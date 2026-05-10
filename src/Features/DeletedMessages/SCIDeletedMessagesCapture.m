#import "SCIDeletedMessagesCapture.h"
#import "SCIDeletedMessagesModels.h"
#import "SCIDeletedMessagesStorage.h"
#import "../StoriesAndMessages/SCIDirectUserResolver.h"
#import "../../Utils.h"
#import "../../SCIDashParser.h"
#import "../../SCIFFmpeg.h"
#import <objc/runtime.h>

#pragma mark - Lazy weak-ref cache

// Stash a weak ref at insert; on unsend, promote to strong and snapshot.
// Aged-out messages fall back to a `_messagesByServerId` read.

static NSMapTable *sciMessageRefs(void) {
    static NSMapTable *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory|NSPointerFunctionsObjectPersonality
                                  valueOptions:NSPointerFunctionsWeakMemory  |NSPointerFunctionsObjectPersonality];
    });
    return t;
}

static NSObject *sciMessageRefsLock(void) {
    static NSObject *o;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ o = [NSObject new]; });
    return o;
}

static dispatch_queue_t sciCaptureQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.ryukgram.deletedmessages.capture", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static dispatch_queue_t sciDownloadQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.ryukgram.deletedmessages.download", DISPATCH_QUEUE_CONCURRENT);
    });
    return q;
}

static NSURLSession *sciSharedSession(void) {
    static NSURLSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 30;
        cfg.timeoutIntervalForResource = 120;
        cfg.HTTPMaximumConnectionsPerHost = 4;
        s = [NSURLSession sessionWithConfiguration:cfg];
    });
    return s;
}

static BOOL sciCaptureEnabled(void) {
    return [SCIUtils getBoolPref:@"deleted_messages_log_enabled"];
}

#pragma mark - Ivar / selector helpers

static NSString *sciStrIvar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Ivar iv = NULL;
    for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, name);
    if (!iv) return nil;
    @try {
        id v = object_getIvar(obj, iv);
        return [v isKindOfClass:[NSString class]] ? v : nil;
    } @catch (__unused id e) { return nil; }
}

static id sciAnyIvar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Ivar iv = NULL;
    for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, name);
    if (!iv) return nil;
    @try { return object_getIvar(obj, iv); } @catch (__unused id e) { return nil; }
}

static double sciDoubleSelector(id obj, NSString *selName) {
    if (!obj) return 0;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return 0;
    @try {
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        const char *rt = sig.methodReturnType;
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.target = obj; inv.selector = sel;
        [inv invoke];
        if (strcmp(rt, "d") == 0) { double r;     [inv getReturnValue:&r]; return r; }
        if (strcmp(rt, "f") == 0) { float  r;     [inv getReturnValue:&r]; return (double)r; }
        if (strcmp(rt, "q") == 0) { long long r;  [inv getReturnValue:&r]; return (double)r; }
        if (strcmp(rt, "i") == 0) { int    r;     [inv getReturnValue:&r]; return (double)r; }
    } @catch (__unused id e) {}
    return 0;
}

// Filter out NSObject's `<ClassName: 0xaddr>` description fallback.
static BOOL sciIsDescriptionFallback(NSString *s) {
    if (!s.length) return NO;
    return [s hasPrefix:@"<"] && [s containsString:@": 0x"] && [s hasSuffix:@">"];
}

static NSString *sciTryStringSelectors(id obj, NSArray<NSString *> *names) {
    if (!obj) return nil;
    for (NSString *n in names) {
        SEL s = NSSelectorFromString(n);
        if (![obj respondsToSelector:s]) continue;
        @try {
            id v = ((id(*)(id, SEL))objc_msgSend)(obj, s);
            NSString *str = nil;
            if ([v isKindOfClass:[NSString class]])           str = v;
            else if ([v isKindOfClass:[NSAttributedString class]]) str = [(NSAttributedString *)v string];
            if (!str.length || sciIsDescriptionFallback(str)) continue;
            return str;
        } @catch (__unused id e) {}
    }
    return nil;
}

static NSString *sciTryURLSelectors(id obj, NSArray<NSString *> *names) {
    if (!obj) return nil;
    for (NSString *n in names) {
        SEL s = NSSelectorFromString(n);
        if (![obj respondsToSelector:s]) continue;
        @try {
            id v = ((id(*)(id, SEL))objc_msgSend)(obj, s);
            if ([v isKindOfClass:[NSURL class]]) {
                NSString *str = [(NSURL *)v absoluteString];
                if (str.length) return str;
            }
            if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
        } @catch (__unused id e) {}
    }
    return nil;
}

#pragma mark - URL scanner (recursive, scored)

static void sciScanForURLsRecursive(id obj, int depth,
                                     NSString **outMedia, int *mediaScore,
                                     NSString **outThumb, int *thumbScore,
                                     NSString *parentName) {
    if (!obj || depth < 0) return;
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)obj;
        BOOL urlShaped = NO;
        for (NSString *p in @[@"http://", @"https://", @"instagram://",
                              @"fb://", @"fbthreads://", @"intent://"]) {
            if ([s hasPrefix:p]) { urlShaped = YES; break; }
        }
        if (!urlShaped) return;

        NSString *n = parentName ?: @"";
        BOOL thumbHint = [n containsString:@"thumb"] || [n containsString:@"preview"]
                       || [n containsString:@"poster"] || [n containsString:@"cover"];
        BOOL mediaHint = [n containsString:@"playable"] || [n containsString:@"video"]
                       || [n containsString:@"audio"]   || [n containsString:@"voice"]
                       || [n containsString:@"asset"]   || [n containsString:@"download"]
                       || [n containsString:@"src"]     || [n containsString:@"url"];
        BOOL imageHint = [n containsString:@"image"] || [n containsString:@"photo"];

        int score = 1;
        if (mediaHint) score = 4;
        if (imageHint) score = thumbHint ? 2 : 3;
        if (thumbHint) {
            if (score > *thumbScore) { *thumbScore = score; *outThumb = s; }
        } else {
            if (score > *mediaScore) { *mediaScore = score; *outMedia = s; }
        }
        return;
    }
    if ([obj isKindOfClass:[NSURL class]]) {
        NSString *s = [(NSURL *)obj absoluteString];
        if (s.length) sciScanForURLsRecursive(s, depth, outMedia, mediaScore, outThumb, thumbScore, parentName);
        return;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) sciScanForURLsRecursive(e, depth - 1, outMedia, mediaScore, outThumb, thumbScore, parentName);
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        for (id k in d) {
            id v = d[k];
            NSString *kn = [k isKindOfClass:[NSString class]] ? (NSString *)k : parentName;
            sciScanForURLsRecursive(v, depth - 1, outMedia, mediaScore, outThumb, thumbScore, kn);
        }
        return;
    }
    Class cls = [obj class];
    NSString *cn = NSStringFromClass(cls);
    if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"]
        || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"]) return;
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Ivar *list = class_copyIvarList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            const char *type = ivar_getTypeEncoding(list[i]);
            if (!type || type[0] != '@') continue;
            const char *name = ivar_getName(list[i]);
            id v = nil;
            @try { v = object_getIvar(obj, list[i]); } @catch (__unused id e) {}
            if (!v) continue;
            NSString *nameStr = name ? @(name) : parentName;
            sciScanForURLsRecursive(v, depth - 1, outMedia, mediaScore, outThumb, thumbScore, nameStr);
        }
        if (list) free(list);
    }
}

#pragma mark - Token-based kind classifier

static void sciCollectIvarNames(id obj, int depth, NSMutableSet *visited, NSMutableSet<NSString *> *out) {
    if (!obj || depth < 0) return;
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) sciCollectIvarNames(e, depth - 1, visited, out);
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        for (id k in d) {
            if ([k isKindOfClass:[NSString class]]) [out addObject:[(NSString *)k lowercaseString]];
            sciCollectIvarNames(d[k], depth - 1, visited, out);
        }
        return;
    }
    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]
        || [obj isKindOfClass:[NSDate class]] || [obj isKindOfClass:[NSURL class]]) return;
    NSValue *box = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:box]) return;
    [visited addObject:box];
    Class cls = [obj class];
    NSString *cn = NSStringFromClass(cls);
    if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"]
        || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"]) return;
    [out addObject:cn.lowercaseString];
    // Only object-typed ivars holding values — IG declares every variant slot up-front, most nil.
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Ivar *list = class_copyIvarList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            const char *name = ivar_getName(list[i]);
            const char *type = ivar_getTypeEncoding(list[i]);
            if (!type || type[0] != '@') continue;
            id v = nil;
            @try { v = object_getIvar(obj, list[i]); } @catch (__unused id e) {}
            if (!v) continue;
            if (name) [out addObject:[@(name) lowercaseString]];
            sciCollectIvarNames(v, depth - 1, visited, out);
        }
        if (list) free(list);
    }
}

static BOOL sciSetContainsAny(NSSet<NSString *> *set, NSArray<NSString *> *needles) {
    for (NSString *n in needles) {
        for (NSString *tok in set) if ([tok containsString:n]) return YES;
    }
    return NO;
}

#pragma mark - Sender / metadata extraction

static NSString *sciSidFromMessage(id m) {
    id meta = sciAnyIvar(m, "_metadata");
    if (!meta) return nil;
    NSString *sid = sciStrIvar(meta, "_serverId") ?: sciStrIvar(meta, "_messageServerId");
    if (!sid.length) {
        id key = sciAnyIvar(meta, "_key");
        if (key) sid = sciStrIvar(key, "_serverId") ?: sciStrIvar(key, "_messageServerId");
    }
    return sid;
}

static NSString *sciSenderPkFromMessage(id m) {
    id meta = sciAnyIvar(m, "_metadata");
    return sciStrIvar(meta, "_senderPk");
}

static NSDate *sciSentAtFromMessage(id m) {
    id meta = sciAnyIvar(m, "_metadata");
    if (!meta) return nil;
    static const char *names[] = {"_serverTimestamp", "_clientTimestamp", "_timestamp"};
    for (int i = 0; i < 3; i++) {
        id v = sciAnyIvar(meta, names[i]);
        if ([v isKindOfClass:[NSDate class]]) return v;
        if ([v isKindOfClass:[NSNumber class]]) {
            double d = [(NSNumber *)v doubleValue];
            if (d > 1.0e12) d /= 1.0e9;
            else if (d > 1.0e10) d /= 1.0e3;
            if (d > 0) return [NSDate dateWithTimeIntervalSince1970:d];
        }
    }
    return nil;
}

// fieldCache (snake_case Pando dict) — KVC returns NSNull for many IGUser fields.
static void sciResolveSenderInfo(NSString *pk, NSString **outUser, NSString **outName, NSString **outPic) {
    if (!pk.length) return;
    NSString *u = sciDirectUserResolverUsernameForPK(pk);
    NSString *p = sciDirectUserResolverProfilePicURLStringForPK(pk);
    NSString *fn = nil;
    id user = sciDirectUserResolverUserForPK(pk);
    if (user) {
        Ivar fcIv = NULL;
        for (Class c = [user class]; c && !fcIv; c = class_getSuperclass(c))
            fcIv = class_getInstanceVariable(c, "_fieldCache");
        NSDictionary *fc = nil;
        if (fcIv) {
            id raw = object_getIvar(user, fcIv);
            if ([raw isKindOfClass:[NSDictionary class]]) fc = raw;
        }
        id (^fcStr)(NSString *) = ^id(NSString *k) {
            id v = fc[k];
            return [v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0 ? v : nil;
        };
        if (!u.length) u  = fcStr(@"username");
        if (!p.length) p  = fcStr(@"profile_pic_url");
        fn = fcStr(@"full_name");
        if (!fn.length) {
            @try {
                id kvc = [user valueForKey:@"fullName"];
                if ([kvc isKindOfClass:[NSString class]]) fn = kvc;
            } @catch (__unused id e) {}
        }
    }
    if (outUser) *outUser = u;
    if (outName) *outName = fn;
    if (outPic)  *outPic  = p;
}

#pragma mark - Share/link title fallback

// Walks string ivars by name (title/caption/headline/…). First non-empty wins; longer wins ties.
static NSString *sciExtractShareTitle(id obj) {
    if (!obj) return nil;
    NSMutableSet *visited = [NSMutableSet set];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:obj];
    NSString *best = nil;
    NSArray<NSString *> *keys = @[@"title", @"caption", @"text", @"name",
                                   @"description", @"summary", @"label",
                                   @"username", @"headline"];
    int hops = 0;
    while (stack.count && hops++ < 64) {
        id cur = stack.lastObject;
        [stack removeLastObject];
        if (!cur) continue;
        if ([cur isKindOfClass:[NSArray class]]) {
            for (id e in (NSArray *)cur) [stack addObject:e];
            continue;
        }
        if ([cur isKindOfClass:[NSString class]] || [cur isKindOfClass:[NSNumber class]]
            || [cur isKindOfClass:[NSDate class]] || [cur isKindOfClass:[NSURL class]]) continue;
        NSValue *box = [NSValue valueWithNonretainedObject:cur];
        if ([visited containsObject:box]) continue;
        [visited addObject:box];
        NSString *cn = NSStringFromClass([cur class]);
        if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"]
            || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"]) continue;
        for (Class c = [cur class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
            unsigned int n = 0;
            Ivar *list = class_copyIvarList(c, &n);
            for (unsigned int i = 0; i < n; i++) {
                const char *type = ivar_getTypeEncoding(list[i]);
                if (!type || type[0] != '@') continue;
                const char *name = ivar_getName(list[i]);
                id v = nil;
                @try { v = object_getIvar(cur, list[i]); } @catch (__unused id e) {}
                if (!v) continue;
                NSString *nameStr = name ? [@(name) lowercaseString] : @"";
                if ([v isKindOfClass:[NSString class]]) {
                    for (NSString *needle in keys) {
                        if (![nameStr containsString:needle]) continue;
                        NSString *s = v;
                        if (s.length && (!best || s.length > best.length)) best = s;
                    }
                } else {
                    [stack addObject:v];
                }
            }
            if (list) free(list);
        }
    }
    return best;
}

#pragma mark - Voice metadata sniffer

static void sciScanVoiceMetadata(id media, double *outDuration, NSArray **outWaveform) {
    NSMutableSet *visited = [NSMutableSet set];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:media];
    while (stack.count) {
        id cur = stack.lastObject;
        [stack removeLastObject];
        if (!cur) continue;
        if ([cur isKindOfClass:[NSArray class]]) {
            for (id e in cur) [stack addObject:e];
            continue;
        }
        if ([cur isKindOfClass:[NSString class]] || [cur isKindOfClass:[NSNumber class]]
            || [cur isKindOfClass:[NSDate class]] || [cur isKindOfClass:[NSURL class]]) continue;
        NSValue *box = [NSValue valueWithNonretainedObject:cur];
        if ([visited containsObject:box]) continue;
        [visited addObject:box];
        NSString *cn = NSStringFromClass([cur class]);
        if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"_NS"]
            || [cn hasPrefix:@"OS"] || [cn hasPrefix:@"__"]) continue;

        if (!*outDuration) {
            double cand = sciDoubleSelector(cur, @"durationInSeconds");
            if (cand <= 0) cand = sciDoubleSelector(cur, @"duration");
            if (cand <= 0) {
                for (Class c = [cur class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
                    Ivar iv = class_getInstanceVariable(c, "_durationMs");
                    if (!iv) iv = class_getInstanceVariable(c, "_instamadillo_durationMs");
                    if (!iv) continue;
                    const char *t = ivar_getTypeEncoding(iv);
                    ptrdiff_t off = ivar_getOffset(iv);
                    if (t[0] == 'Q' || t[0] == 'q') {
                        long long ms = *(long long *)((char *)(__bridge void *)cur + off);
                        if (ms > 0) cand = (double)ms / 1000.0;
                    }
                    break;
                }
            }
            if (cand > 0) *outDuration = cand;
        }
        if (!*outWaveform) {
            id cand = sciAnyIvar(cur, "_averageVolume")
                   ?: sciAnyIvar(cur, "_waveformData")
                   ?: sciAnyIvar(cur, "_waveform")
                   ?: sciAnyIvar(cur, "_amplitudes");
            if ([cand isKindOfClass:[NSArray class]]) *outWaveform = cand;
        }
        for (Class c = [cur class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
            unsigned int n = 0;
            Ivar *list = class_copyIvarList(c, &n);
            for (unsigned int i = 0; i < n; i++) {
                const char *type = ivar_getTypeEncoding(list[i]);
                if (!type || type[0] != '@') continue;
                id v = nil;
                @try { v = object_getIvar(cur, list[i]); } @catch (__unused id e) {}
                if (v) [stack addObject:v];
            }
            if (list) free(list);
        }
    }
}

#pragma mark - Snapshot builder

// Returns nil for system / placeholder / non-user rows.
static NSDictionary *sciBuildSnapshot(id message, NSString *ownerHint) {
    NSString *sid = sciSidFromMessage(message);
    if (!sid.length) return nil;

    NSMutableDictionary *snap = [NSMutableDictionary dictionary];
    snap[@"sid"] = sid;
    if (ownerHint.length) snap[@"owner_pk"] = ownerHint;

    NSString *threadId = nil;
    @try { threadId = [message valueForKey:@"threadId"]; } @catch (__unused id e) {}
    if (![threadId isKindOfClass:[NSString class]] || !threadId.length) {
        id meta = sciAnyIvar(message, "_metadata");
        threadId = sciStrIvar(meta, "_threadId") ?: sciStrIvar(meta, "_threadID");
    }
    if (threadId.length) snap[@"thread_id"] = threadId;

    NSString *senderPk = sciSenderPkFromMessage(message);
    if (senderPk.length) {
        snap[@"sender_pk"] = senderPk;
        NSString *u = nil, *fn = nil, *pic = nil;
        sciResolveSenderInfo(senderPk, &u, &fn, &pic);
        if (u.length)  snap[@"sender_username"]        = u;
        if (fn.length) snap[@"sender_full_name"]       = fn;
        if (pic.length)snap[@"sender_profile_pic_url"] = pic;
    }
    NSDate *sentAt = sciSentAtFromMessage(message);
    if (sentAt) snap[@"sent_at"] = sentAt;

    // Reply id can sit on metadata, on the message, or as a Pando-resolved value-key.
    @try {
        id meta = sciAnyIvar(message, "_metadata");
        NSString *replyId = nil;
        for (NSString *k in @[@"_replyToMessageId", @"_replyMessageId",
                              @"_quotedMessageId", @"_repliedToMessageId",
                              @"_parentMessageId"]) {
            NSString *v = sciStrIvar(meta, k.UTF8String) ?: sciStrIvar(message, k.UTF8String);
            if (v.length) { replyId = v; break; }
        }
        if (!replyId.length) {
            for (NSString *k in @[@"replyToMessageId", @"replyMessageId",
                                  @"quotedMessageId", @"repliedToMessageId",
                                  @"reply_message_id"]) {
                @try {
                    id v = [message valueForKey:k];
                    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
                        replyId = v; break;
                    }
                } @catch (__unused id e) {}
            }
        }
        if (replyId.length) snap[@"reply_to_id"] = replyId;
    } @catch (__unused id e) {}

    id content = sciAnyIvar(message, "_content")
              ?: sciAnyIvar(message, "_messageContent")
              ?: sciAnyIvar(message, "_payload");
    if (!content) {
        @try { content = [message valueForKey:@"content"]; } @catch (__unused id e) {}
    }
    if (!content) {
        snap[@"kind"] = @(SCIDeletedMessageKindUnknown);
        return snap;
    }

    if (sciAnyIvar(content, "_threadActivity")
        || sciAnyIvar(content, "_messageTypeNotLocallyAvailable_placeholderTitle")
        || sciAnyIvar(content, "_messageTypeNotLocallyAvailable_placeholderMessage")
        || sciAnyIvar(content, "_expiredPlaceholder_messageContent")) {
        return nil;
    }

    SCIDeletedMessageKind kind = SCIDeletedMessageKindUnknown;
    NSString *text = nil, *mediaURL = nil, *thumbURL = nil;
    int mediaScore = 0, thumbScore = 0;

    NSString *txt = sciStrIvar(content, "_text_string");
    if (txt.length) {
        kind = SCIDeletedMessageKindText;
        text = txt;
    }

    // Media branch — photo / video / voice / gif / sticker.
    id media = sciAnyIvar(content, "_media");
    if (media) {
        NSMutableSet *vis = [NSMutableSet set];
        NSMutableSet<NSString *> *tokens = [NSMutableSet set];
        sciCollectIvarNames(media, 5, vis, tokens);

        if (sciSetContainsAny(tokens, @[@"voice", @"audio"]))      kind = SCIDeletedMessageKindVoice;
        else if (sciSetContainsAny(tokens, @[@"sticker"]))         kind = SCIDeletedMessageKindSticker;
        else if (sciSetContainsAny(tokens, @[@"giphy", @"gif", @"animated"])) kind = SCIDeletedMessageKindGif;
        else if (sciSetContainsAny(tokens, @[@"video", @"dashmanifest", @"playableurl"])) kind = SCIDeletedMessageKindVideo;
        else                                                       kind = SCIDeletedMessageKindPhoto;

        if (kind == SCIDeletedMessageKindVoice) {
            double dur = 0; NSArray *wf = nil;
            sciScanVoiceMetadata(media, &dur, &wf);
            if (dur > 0)  snap[@"duration"] = @(dur);
            if (wf.count) snap[@"waveform"] = wf;
        }

        // IGVideo sits under _permanentMedia_permanentMedia, not on media.
        if (kind == SCIDeletedMessageKindVideo) {
            id permanent = sciAnyIvar(media, "_permanentMedia_permanentMedia");
            id video = nil;
            id overlayPhoto = nil;
            if (permanent) {
                video = sciAnyIvar(permanent, "_video_video")
                     ?: sciAnyIvar(permanent, "_videoMemo_memoVideo");
                overlayPhoto = sciAnyIvar(permanent, "_video_overlayPhoto")
                            ?: sciAnyIvar(permanent, "_videoMemo_videoMemoPhoto");
            }
            // visualMedia fallback — view-once flows.
            if (!video) {
                id visual = sciAnyIvar(media, "_visualMedia");
                if (visual) {
                    video = sciAnyIvar(visual, "_video_video")
                         ?: sciAnyIvar(visual, "_video");
                    if (!overlayPhoto) overlayPhoto = sciAnyIvar(visual, "_video_overlayPhoto")
                                                  ?: sciAnyIvar(visual, "_overlayPhoto");
                }
            }

            if (video) {
                NSData *manifestData = sciAnyIvar(video, "_dashManifestData");
                if ([manifestData isKindOfClass:[NSData class]] && manifestData.length) {
                    NSString *xml = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
                    NSArray<SCIDashRepresentation *> *reps = [SCIDashParser parseManifest:xml];
                    SCIDashRepresentation *bestV = [SCIDashParser bestVideoFromRepresentations:reps];
                    SCIDashRepresentation *bestA = [SCIDashParser bestAudioFromRepresentations:reps];
                    if (bestV.url.absoluteString.length) {
                        mediaURL = bestV.url.absoluteString;
                        mediaScore = 100;
                    }
                    // DASH video + audio are separate reps; muxed via SCIFFmpeg later.
                    if (bestA.url.absoluteString.length) snap[@"audio_url"] = bestA.url.absoluteString;
                }
                if (!mediaURL.length) {
                    for (NSString *ivName in @[@"_broadcastURL", @"_subtitleURL"]) {
                        id v = sciAnyIvar(video, ivName.UTF8String);
                        if ([v isKindOfClass:[NSURL class]]) {
                            mediaURL = [(NSURL *)v absoluteString];
                            mediaScore = 90;
                            break;
                        }
                    }
                }
            }
            if (overlayPhoto) {
                NSString *t = nil; int ts = 0;
                NSString *m = nil; int ms = 0;
                sciScanForURLsRecursive(overlayPhoto, 4, &m, &ms, &t, &ts, @"thumbnail");
                NSString *picked = t.length ? t : m;
                if (picked.length) { thumbURL = picked; thumbScore = MAX(ts, ms); }
            }
        }

        sciScanForURLsRecursive(media, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, @"media");
    }

    // Reshare branch.
    id reshare = sciAnyIvar(content, "_reshare_attachment");
    if (reshare && kind == SCIDeletedMessageKindUnknown) {
        kind = SCIDeletedMessageKindShare;
        sciScanForURLsRecursive(reshare, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, @"reshare");
        text = sciStrIvar(content, "_reshare_comment");
        if (!text.length) text = sciExtractShareTitle(reshare);
        if (!text.length) text = sciTryStringSelectors(reshare,
            @[@"caption", @"captionText", @"title", @"headline", @"summary",
              @"name", @"username", @"text"]);
        if (!mediaURL.length) {
            NSString *u = sciTryURLSelectors(reshare,
                @[@"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL", @"playableURL"]);
            if (u.length) mediaURL = u;
        }
    }

    // Link branch — IGDirectLinkContext has direct ivars.
    id link = sciAnyIvar(content, "_link_linkContext");
    if (link && kind == SCIDeletedMessageKindUnknown) {
        kind = SCIDeletedMessageKindLink;
        id u    = sciAnyIvar(link, "_url");
        id imgU = sciAnyIvar(link, "_imageURL");
        if ([u    isKindOfClass:[NSURL class]]) mediaURL = [(NSURL *)u    absoluteString];
        if ([imgU isKindOfClass:[NSURL class]]) thumbURL = [(NSURL *)imgU absoluteString];
        NSString *title   = sciStrIvar(link, "_title");
        NSString *summary = sciStrIvar(link, "_summary");
        NSString *comment = sciStrIvar(content, "_link_commentText");
        NSMutableArray *parts = [NSMutableArray array];
        if (comment.length) [parts addObject:comment];
        if (title.length)   [parts addObject:title];
        if (summary.length) [parts addObject:summary];
        if (!parts.count && mediaURL.length) [parts addObject:mediaURL];
        if (parts.count) text = [parts componentsJoinedByString:@"\n"];
    }

    // XMA — Pando-backed wrapper. IGDirectXMA has zero ivars; data comes
    // via valueForKey on names mirroring IGDirectXMABuilder / IGDirectXMAShareBuilder.
    if (kind == SCIDeletedMessageKindUnknown) {
        id xmaLike = sciAnyIvar(content, "_xma")
                  ?: sciAnyIvar(content, "_bloksXMA")
                  ?: sciAnyIvar(content, "_pollMessage")
                  ?: sciAnyIvar(content, "_progressiveImage");
        if (xmaLike) {
            NSString *xmaContentType = nil;
            @try {
                id v = [xmaLike valueForKey:@"contentType"];
                if ([v isKindOfClass:[NSString class]]) xmaContentType = [(NSString *)v lowercaseString];
            } @catch (__unused id e) {}

            // Audio share heuristic — generic_xma with playableAudioURL or /reels_audio_page targetURL.
            BOOL isAudio = NO;
            @try {
                id items = [xmaLike valueForKey:@"xmaItems"];
                id first = ([items isKindOfClass:[NSArray class]] && [items count] > 0) ? [items firstObject] : nil;
                if (first) {
                    id pa = [first valueForKey:@"playableAudioURL"];
                    if ([pa isKindOfClass:[NSURL class]] && [(NSURL *)pa absoluteString].length) isAudio = YES;
                    if (!isAudio) {
                        id tgt = [first valueForKey:@"targetURL"];
                        NSString *tgtStr = [tgt isKindOfClass:[NSURL class]] ? [(NSURL *)tgt absoluteString]
                                           : ([tgt isKindOfClass:[NSString class]] ? tgt : nil);
                        if ([tgtStr.lowercaseString containsString:@"reels_audio_page"]
                            || [tgtStr.lowercaseString containsString:@"audio_page"]) isAudio = YES;
                    }
                }
            } @catch (__unused id e) {}

            if (isAudio)                                           kind = SCIDeletedMessageKindAudioShare;
            else if ([xmaContentType isEqualToString:@"xma_link"]) kind = SCIDeletedMessageKindLink;
            else                                                   kind = SCIDeletedMessageKindShare;

            // Real share payload sits on xmaItems[0] (IGDirectXMAShare).
            NSMutableArray *probeTargets = [NSMutableArray arrayWithObject:xmaLike];
            @try {
                id items = [xmaLike valueForKey:@"xmaItems"];
                if ([items isKindOfClass:[NSArray class]]) {
                    for (id it in (NSArray *)items) if (it) [probeTargets addObject:it];
                }
            } @catch (__unused id e) {}
            @try {
                id meta = [xmaLike valueForKey:@"metadata"];
                if (meta && meta != [NSNull null]) [probeTargets addObject:meta];
            } @catch (__unused id e) {}

            NSString *(^pickStr)(id, NSArray<NSString *> *) = ^NSString *(id obj, NSArray<NSString *> *keys) {
                for (NSString *k in keys) {
                    @try {
                        id v = [obj valueForKey:k];
                        if (!v || v == [NSNull null]) continue;
                        if ([v isKindOfClass:[NSAttributedString class]]) v = [(NSAttributedString *)v string];
                        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0
                            && !sciIsDescriptionFallback(v)) return v;
                    } @catch (__unused id e) {}
                }
                return nil;
            };
            NSString *(^pickURL)(id, NSArray<NSString *> *) = ^NSString *(id obj, NSArray<NSString *> *keys) {
                for (NSString *k in keys) {
                    @try {
                        id v = [obj valueForKey:k];
                        if (!v || v == [NSNull null]) continue;
                        if ([v isKindOfClass:[NSURL class]]) {
                            NSString *s = [(NSURL *)v absoluteString];
                            if (s.length) return s;
                        }
                        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
                    } @catch (__unused id e) {}
                }
                return nil;
            };

            // IGDirectXMAShareBuilder mirror keys — priority order.
            NSArray<NSString *> *titleKeys = @[
                @"headerTitleText", @"titleText", @"headerSubtitleText",
                @"subtitleText", @"captionBodyText", @"footerBodyText",
                @"overlayTitle", @"overlayDescription", @"overlayText",
                @"quotedTitleText", @"quotedAttributionText", @"quotedCaptionBodyText",
                @"groupName", @"targetURLTitle",
                @"title", @"caption", @"text", @"summary", @"description"
            ];
            // Audio: prefer .mp4 (download/play); others: targetURL (in-app open).
            NSArray<NSString *> *mediaKeys = (kind == SCIDeletedMessageKindAudioShare)
                ? @[@"playableAudioURL", @"playableURL", @"accessoryPlayableURL",
                    @"fullSizeURL", @"targetURL",
                    @"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL"]
                : @[@"targetURL",
                    @"playableURL", @"playableAudioURL",
                    @"accessoryPlayableURL", @"fullSizeURL",
                    @"webURL", @"shareURL", @"deepLink", @"url", @"mediaURL"];
            NSArray<NSString *> *thumbKeys = @[
                @"previewURL", @"accessoryPreviewURL", @"previewMaskURL",
                @"previewIgImageURL",
                @"thumbnailURL", @"posterURL", @"imageURL"
            ];

            NSMutableArray *titleParts = [NSMutableArray array];
            for (id obj in probeTargets) {
                NSString *t = pickStr(obj, titleKeys);
                if (t.length && ![titleParts containsObject:t]) [titleParts addObject:t];
                if (titleParts.count >= 3) break;
            }
            if (!text.length && titleParts.count) text = [titleParts componentsJoinedByString:@"\n"];

            for (id obj in probeTargets) {
                if (!mediaURL.length) {
                    NSString *u = pickURL(obj, mediaKeys);
                    if (u.length) { mediaURL = u; mediaScore = 70; }
                }
                if (!thumbURL.length) {
                    NSString *u = pickURL(obj, thumbKeys);
                    if (u.length) { thumbURL = u; thumbScore = 70; }
                }
                if (mediaURL.length && thumbURL.length) break;
            }

            sciScanForURLsRecursive(xmaLike, 5, &mediaURL, &mediaScore, &thumbURL, &thumbScore, @"xma");

            // Unwrap IG/FB outbound redirector — `l.instagram.com/?u=<real>`.
            if (kind == SCIDeletedMessageKindLink && mediaURL.length) {
                NSURL *u = [NSURL URLWithString:mediaURL];
                NSString *host = u.host.lowercaseString;
                if ([host isEqualToString:@"l.instagram.com"]
                    || [host isEqualToString:@"l.facebook.com"]
                    || [host isEqualToString:@"lm.facebook.com"]) {
                    NSURLComponents *comps = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
                    for (NSURLQueryItem *q in comps.queryItems) {
                        if ([q.name isEqualToString:@"u"] && q.value.length) {
                            mediaURL = q.value;
                            break;
                        }
                    }
                }
            }
        }
    }

    if (kind == SCIDeletedMessageKindUnknown && text.length) kind = SCIDeletedMessageKindText;

    snap[@"kind"]  = @(kind);
    if (text.length)     snap[@"text"]      = text;
    if (mediaURL.length) snap[@"media_url"] = mediaURL;
    if (thumbURL.length) snap[@"thumb_url"] = thumbURL;
    return snap;
}

#pragma mark - Media download

// Tiny helper: download a URL into a temp file synchronously on the
// download queue. Used during video+audio mux. Completion is dispatched on
// the same queue that called us so we can chain steps.
static void sciDownloadToTempFile(NSURL *url, void (^done)(NSURL *file, NSError *err)) {
    if (!url) { done(nil, [NSError errorWithDomain:@"SCIDM" code:0 userInfo:nil]); return; }
    [[sciSharedSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data.length) { done(nil, err); return; }
        NSString *ext = url.pathExtension.length ? url.pathExtension : @"bin";
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"sci_dm_%@.%@", [NSUUID UUID].UUIDString, ext]];
        if (![data writeToFile:tmp atomically:YES]) {
            done(nil, [NSError errorWithDomain:@"SCIDM" code:1 userInfo:nil]);
            return;
        }
        done([NSURL fileURLWithPath:tmp], nil);
    }] resume];
}

// DASH video reps are silent — download video + audio reps and mux to mp4.
static void sciDownloadAndMuxVideo(NSString *videoURL, NSString *audioURL,
                                    NSString *messageId, NSString *ownerPk) {
    if (!videoURL.length || !messageId.length) return;
    if (!audioURL.length || ![SCIFFmpeg isAvailable]) return;
    NSURL *vURL = [NSURL URLWithString:videoURL];
    NSURL *aURL = [NSURL URLWithString:audioURL];
    if (!vURL || !aURL) return;

    dispatch_async(sciDownloadQueue(), ^{
        __block NSURL *vFile = nil, *aFile = nil;
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        sciDownloadToTempFile(vURL, ^(NSURL *f, NSError *e) { if (!e) vFile = f; dispatch_semaphore_signal(sema); });
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        sciDownloadToTempFile(aURL, ^(NSURL *f, NSError *e) { if (!e) aFile = f; dispatch_semaphore_signal(sema); });
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        if (!vFile || !aFile) {
            if (vFile) [[NSFileManager defaultManager] removeItemAtURL:vFile error:nil];
            if (aFile) [[NSFileManager defaultManager] removeItemAtURL:aFile error:nil];
            return;
        }
        [SCIFFmpeg muxVideoURL:vFile audioURL:aFile preset:nil progress:nil
                    completion:^(NSURL *outURL, NSError *err) {
            [[NSFileManager defaultManager] removeItemAtURL:vFile error:nil];
            [[NSFileManager defaultManager] removeItemAtURL:aFile error:nil];
            if (err || !outURL) return;
            NSString *fname = [SCIDeletedMessagesStorage reserveRelativeMediaPathForMessageId:messageId
                                                                                    extension:@"mp4"
                                                                                      ownerPK:ownerPk];
            NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:fname ownerPK:ownerPk];
            if (!abs.length) return;
            [[NSFileManager defaultManager] removeItemAtPath:abs error:nil];
            if (![[NSFileManager defaultManager] moveItemAtURL:outURL toURL:[NSURL fileURLWithPath:abs] error:nil]) return;
            for (SCIDeletedMessage *m in [SCIDeletedMessagesStorage allMessagesForOwnerPK:ownerPk]) {
                if (![m.messageId isEqualToString:messageId]) continue;
                m.mediaPath = fname;
                [SCIDeletedMessagesStorage saveMessage:m forOwnerPK:ownerPk];
                break;
            }
        }];
    });
}

static void sciDownloadMedia(NSString *urlString, NSString *messageId,
                             NSString *ownerPk, BOOL isThumbnail) {
    if (!urlString.length || !messageId.length) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    NSString *ext = url.pathExtension.length ? url.pathExtension : (isThumbnail ? @"jpg" : @"bin");
    NSString *fname = isThumbnail
        ? [NSString stringWithFormat:@"thumb_%@.%@", messageId, ext]
        : [SCIDeletedMessagesStorage reserveRelativeMediaPathForMessageId:messageId
                                                                extension:ext
                                                                  ownerPK:ownerPk];
    NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:fname ownerPK:ownerPk];
    if (!abs.length) return;

    dispatch_async(sciDownloadQueue(), ^{
        NSURLSessionDataTask *task = [sciSharedSession() dataTaskWithURL:url
                                                       completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err || !data.length) return;
            if (![data writeToFile:abs atomically:YES]) return;
            for (SCIDeletedMessage *m in [SCIDeletedMessagesStorage allMessagesForOwnerPK:ownerPk]) {
                if (![m.messageId isEqualToString:messageId]) continue;
                if (isThumbnail) m.thumbnailPath = fname;
                else             m.mediaPath     = fname;
                [SCIDeletedMessagesStorage saveMessage:m forOwnerPK:ownerPk];
                break;
            }
        }];
        [task resume];
    });
}

#pragma mark - Per-thread fallback (covers foreground threads in IG's _cache)

// `applicator._cache.threadClientStateForThreadId:tid` returns an
// IGDirectThreadClientState whose `_messagesByServerId` ivar is a dict
// keyed by sid → IGDirectMessage. Direct ivar read skips method dispatch.
static id sciFallbackLookupMessage(id applicator, NSString *sid, NSString *threadId) {
    if (!applicator || !sid.length || !threadId.length) return nil;
    @try {
        Ivar iv = class_getInstanceVariable([applicator class], "_cache");
        id cache = iv ? object_getIvar(applicator, iv) : nil;
        SEL sel = NSSelectorFromString(@"threadClientStateForThreadId:");
        if (!cache || ![cache respondsToSelector:sel]) return nil;
        id state = ((id(*)(id, SEL, id))objc_msgSend)(cache, sel, threadId);
        if (!state) return nil;
        for (Class c = [state class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
            Ivar di = class_getInstanceVariable(c, "_messagesByServerId");
            if (!di) continue;
            id dict = object_getIvar(state, di);
            if ([dict isKindOfClass:[NSDictionary class]]) return ((NSDictionary *)dict)[sid];
            break;
        }
    } @catch (__unused id e) {}
    return nil;
}

#pragma mark - Public hooks

void sciDMCaptureNoteInsert(id message) {
    if (!sciCaptureEnabled() || !message) return;
    @try {
        NSString *sid = sciSidFromMessage(message);
        if (!sid.length) return;
        @synchronized (sciMessageRefsLock()) {
            [sciMessageRefs() setObject:message forKey:sid];
        }
    } @catch (__unused id e) {}
}

static NSString *sciExtractKeySid(id key) {
    if (!key) return nil;
    @try {
        for (Class c = [key class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
            Ivar iv = class_getInstanceVariable(c, "_serverId");
            if (!iv) iv = class_getInstanceVariable(c, "_messageServerId");
            if (!iv) continue;
            id v = object_getIvar(key, iv);
            if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
            break;
        }
    } @catch (__unused id e) {}
    return nil;
}

void sciDMCaptureNoteRemoveKeys(NSArray *keys, id applicator,
                                 NSString *ownerPk, NSString *threadId) {
    if (!sciCaptureEnabled() || !keys.count) return;
    NSString *owner  = ownerPk.length  ? [ownerPk copy]  : @"";
    NSString *thread = threadId.length ? [threadId copy] : nil;

    NSMutableDictionary<NSString *, id> *strongRefs = [NSMutableDictionary dictionary];

    // Layer 1: weak ref → strong promotion.
    @synchronized (sciMessageRefsLock()) {
        NSMapTable *t = sciMessageRefs();
        for (id key in keys) {
            NSString *sid = sciExtractKeySid(key);
            if (!sid.length) continue;
            id m = [t objectForKey:sid];
            if (m) { strongRefs[sid] = m; [t removeObjectForKey:sid]; }
        }
    }

    // Layer 2: per-thread state lookup for sids no longer in the weak cache.
    for (id key in keys) {
        NSString *sid = sciExtractKeySid(key);
        if (!sid.length || strongRefs[sid]) continue;
        id m = sciFallbackLookupMessage(applicator, sid, thread);
        if (m) strongRefs[sid] = m;
    }

    if (!strongRefs.count) return;

    dispatch_async(sciCaptureQueue(), ^{
        NSDate *now = [NSDate date];
        for (NSString *sid in strongRefs) {
            id message = strongRefs[sid];
            NSDictionary *snap = sciBuildSnapshot(message, owner);
            if (!snap) continue;
            NSString *senderPk = snap[@"sender_pk"];
            if (senderPk.length && [senderPk isEqualToString:owner]) continue;

            SCIDeletedMessageKind kind = (SCIDeletedMessageKind)[snap[@"kind"] integerValue];
            NSString *txt = snap[@"text"];
            NSString *mu  = snap[@"media_url"];
            NSString *tu  = snap[@"thumb_url"];
            if ((kind == SCIDeletedMessageKindUnknown || kind == SCIDeletedMessageKindOther)
                && !txt.length && !mu.length && !tu.length) continue;

            SCIDeletedMessage *m = [SCIDeletedMessage new];
            m.messageId           = sid;
            m.threadId            = snap[@"thread_id"] ?: thread;
            m.senderPk            = senderPk ?: @"";
            m.senderUsername      = snap[@"sender_username"];
            m.senderFullName      = snap[@"sender_full_name"];
            m.senderProfilePicURL = snap[@"sender_profile_pic_url"];
            m.sentAt              = snap[@"sent_at"];
            m.capturedAt          = now;
            m.deletedAt           = now;
            m.kind                = kind;
            m.text                = txt;
            m.previewText         = txt;
            m.mediaURL            = mu;
            m.thumbnailURL        = tu;
            m.durationSeconds     = [snap[@"duration"] doubleValue];
            id wf = snap[@"waveform"];
            if ([wf isKindOfClass:[NSArray class]]) m.waveform = wf;
            m.replyToMessageId    = snap[@"reply_to_id"];

            [SCIDeletedMessagesStorage saveMessage:m forOwnerPK:owner];

            // Video → mux path. Share/Link mediaURL is a deeplink, skip body fetch (thumb only).
            // AudioShare's mediaURL is a downloadable .mp4.
            NSString *audioURL = snap[@"audio_url"];
            BOOL isDeeplinkOnly = (m.kind == SCIDeletedMessageKindShare ||
                                   m.kind == SCIDeletedMessageKindLink);
            if (m.kind == SCIDeletedMessageKindVideo && audioURL.length && m.mediaURL.length) {
                sciDownloadAndMuxVideo(m.mediaURL, audioURL, sid, owner);
            } else if (!isDeeplinkOnly && m.mediaURL.length) {
                sciDownloadMedia(m.mediaURL, sid, owner, NO);
            }
            if (m.thumbnailURL.length) sciDownloadMedia(m.thumbnailURL, sid, owner, YES);
        }
    });
}
