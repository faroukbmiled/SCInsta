#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "SCIExcludedThreads.h"
#import "SCIDirectUserResolver.h"
#import "../DeletedMessages/SCIDeletedMessagesCapture.h"
#import <objc/runtime.h>
#import <substrate.h>

// Hooks IGDirectCacheUpdatesApplicator._applyThreadUpdates: and clears
// _removeMessages_messageKeys on remote unsends. Reason 0 = unsend,
// 2 = delete-for-you. Single chokepoint for stock + E2EE A/B paths.

#pragma mark - State

#define SCI_SENDER_MAP_MAX        4000
#define SCI_CONTENT_CLASSES_MAX   4000
#define SCI_PRESERVED_MAX         200
#define SCI_PRESERVED_IDS_KEY     @"SCIPreservedMsgIdsByPk"
#define SCI_PRESERVED_LEGACY_KEY  @"SCIPreservedMsgIds"
#define SCI_PRESERVED_TAG         1399

static BOOL                                                       sciLocalDeleteInProgress = NO;
static NSMutableDictionary<NSString *, NSDate *>                 *sciDeleteForYouKeys      = nil;
static NSMutableDictionary<NSString *, NSMutableSet<NSString *>*>*sciPreservedByPk         = nil;
static NSMutableDictionary<NSString *, NSString *>               *sciMessageContentClasses = nil;
static NSMutableDictionary<NSString *, NSString *>               *sciSenderPkBySid         = nil;
static NSMutableDictionary<NSString *, NSString *>               *sciSenderNameBySid       = nil;
static NSMutableSet<NSString *>                                  *sciPendingLocalSids      = nil;

static void sciUpdateCellIndicator(id cell);

#pragma mark - Helpers

static BOOL sciKeepDeletedEnabled() {
    return [SCIUtils getBoolPref:@"keep_deleted_message"];
}

static BOOL sciDeletedMessagesLogEnabled() {
    return [SCIUtils getBoolPref:@"deleted_messages_log_enabled"];
}

static BOOL sciIndicateUnsentEnabled() {
    return [SCIUtils getBoolPref:@"indicate_unsent_messages"];
}

static NSString *sciCurrentUserPk(void);

// Applicator is per-IGUserSession; its _user ivar identifies the owning account.
static NSString *sciOwningPkFromApplicator(id applicator) {
    if (!applicator) return nil;
    @try {
        Ivar uIvar = class_getInstanceVariable([applicator class], "_user");
        if (!uIvar) return nil;
        return sciDirectUserResolverPKFromUser(object_getIvar(applicator, uIvar));
    } @catch (__unused id e) {}
    return nil;
}

// Lazy-loads per-pk dict from defaults; legacy flat key migrates into current pk's bucket.
static NSMutableDictionary<NSString *, NSMutableSet<NSString *>*> *sciGetPreservedByPk(void) {
    if (sciPreservedByPk) return sciPreservedByPk;
    sciPreservedByPk = [NSMutableDictionary dictionary];
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:SCI_PRESERVED_IDS_KEY];
    if ([saved isKindOfClass:[NSDictionary class]]) {
        for (NSString *pk in saved) {
            id arr = saved[pk];
            if ([arr isKindOfClass:[NSArray class]])
                sciPreservedByPk[pk] = [NSMutableSet setWithArray:arr];
        }
    }
    NSArray *legacy = [[NSUserDefaults standardUserDefaults] arrayForKey:SCI_PRESERVED_LEGACY_KEY];
    if ([legacy isKindOfClass:[NSArray class]] && legacy.count > 0) {
        NSString *pk = sciCurrentUserPk();
        if (pk.length) {
            NSMutableSet *bucket = sciPreservedByPk[pk] ?: [NSMutableSet set];
            [bucket addObjectsFromArray:legacy];
            sciPreservedByPk[pk] = bucket;
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:SCI_PRESERVED_LEGACY_KEY];
        }
    }
    return sciPreservedByPk;
}

static NSMutableSet<NSString *> *sciBucketForPk(NSString *pk) {
    if (!pk.length) return nil;
    NSMutableDictionary *byPk = sciGetPreservedByPk();
    NSMutableSet *bucket = byPk[pk];
    if (!bucket) {
        bucket = [NSMutableSet set];
        byPk[pk] = bucket;
    }
    return bucket;
}

// Foreground-session entry. Apply hook uses sciBucketForPk(owningPk) instead.
NSMutableSet *sciGetPreservedIds(void) {
    NSString *pk = sciCurrentUserPk();
    if (!pk.length) return [NSMutableSet set];
    sciGetPreservedByPk();
    return sciBucketForPk(pk);
}

static void sciSavePreservedIds(void) {
    NSMutableDictionary *byPk = sciGetPreservedByPk();
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in byPk) {
        NSMutableSet *s = byPk[k];
        while (s.count > SCI_PRESERVED_MAX) [s removeObject:[s anyObject]];
        if (s.count > 0) out[k] = [s allObjects];
    }
    if (out.count > 0)
        [[NSUserDefaults standardUserDefaults] setObject:out forKey:SCI_PRESERVED_IDS_KEY];
    else
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SCI_PRESERVED_IDS_KEY];
}

// Clears active account's bucket only.
void sciClearPreservedIds(void) {
    NSMutableDictionary *byPk = sciGetPreservedByPk();
    NSString *pk = sciCurrentUserPk();
    if (!pk.length) return;
    [byPk removeObjectForKey:pk];
    sciSavePreservedIds();
}

static NSMutableSet<NSString *> *sciGetPendingLocalSids() {
    if (!sciPendingLocalSids) sciPendingLocalSids = [NSMutableSet set];
    return sciPendingLocalSids;
}

static NSMutableDictionary<NSString *, NSString *> *sciGetSenderMap() {
    if (!sciSenderPkBySid) sciSenderPkBySid = [NSMutableDictionary dictionary];
    return sciSenderPkBySid;
}

static void sciTrackSenderPk(NSString *sid, NSString *pk) {
    if (!sid.length || !pk.length) return;
    NSMutableDictionary *m = sciGetSenderMap();
    m[sid] = pk;
    if (m.count > SCI_SENDER_MAP_MAX) {
        NSArray *keys = [m allKeys];
        for (NSUInteger i = 0; i < keys.count / 10; i++) [m removeObjectForKey:keys[i]];
    }
}

static NSMutableDictionary<NSString *, NSString *> *sciGetSenderNameMap(void) {
    if (!sciSenderNameBySid) sciSenderNameBySid = [NSMutableDictionary dictionary];
    return sciSenderNameBySid;
}

static void sciTrackSenderName(NSString *sid, NSString *name) {
    if (!sid.length || !name.length) return;
    NSMutableDictionary *m = sciGetSenderNameMap();
    m[sid] = name;
    if (m.count > SCI_SENDER_MAP_MAX) {
        NSArray *keys = [m allKeys];
        for (NSUInteger i = 0; i < keys.count / 10; i++) [m removeObjectForKey:keys[i]];
    }
}

static NSMutableDictionary<NSString *, NSString *> *sciGetContentClasses() {
    if (!sciMessageContentClasses) sciMessageContentClasses = [NSMutableDictionary dictionary];
    return sciMessageContentClasses;
}

static void sciTrackInsertedMessage(NSString *sid, NSString *className) {
    if (!sid.length || !className.length) return;
    NSMutableDictionary *map = sciGetContentClasses();
    map[sid] = className;
    if (map.count > SCI_CONTENT_CLASSES_MAX) {
        NSArray *keys = [map allKeys];
        for (NSUInteger i = 0; i < keys.count / 10; i++) [map removeObjectForKey:keys[i]];
    }
}

static BOOL sciIsReactionRelatedMessage(NSString *sid) {
    if (!sid.length) return NO;
    NSString *className = sciGetContentClasses()[sid];
    if (!className.length) return NO;
    return [className containsString:@"Reaction"] ||
           [className containsString:@"ActionLog"] ||
           [className containsString:@"reaction"] ||
           [className containsString:@"actionLog"];
}

// Walks every connected scene's window for IGUserSession.user. Read fresh —
// caching breaks under account quick-switch.
static NSString *sciCurrentUserPk(void) {
    @try {
        NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) [windows addObject:w];
        }
        if (windows.count == 0) {
            for (UIWindow *w in [UIApplication sharedApplication].windows) [windows addObject:w];
        }
        for (UIWindow *w in windows) {
            id session = nil;
            @try { session = [w valueForKey:@"userSession"]; } @catch (__unused id e) {}
            if (!session) continue;
            id user = nil;
            @try { user = [session valueForKey:@"user"]; } @catch (__unused id e) {}
            NSString *pk = sciDirectUserResolverPKFromUser(user);
            if (pk.length) return pk;
        }
    } @catch (__unused id e) {}
    return nil;
}

static NSString *sciExtractServerId(id key) {
    @try {
        Ivar sidIvar = class_getInstanceVariable([key class], "_messageServerId");
        if (sidIvar) {
            NSString *sid = object_getIvar(key, sidIvar);
            if ([sid isKindOfClass:[NSString class]] && sid.length > 0) return sid;
        }
    } @catch(id e) {}
    return nil;
}

#pragma mark - Remote unsend detection

static void sciPruneStaleDeleteForYouKeys() {
    if (!sciDeleteForYouKeys) return;
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-10.0];
    for (NSString *k in [sciDeleteForYouKeys allKeys]) {
        if ([sciDeleteForYouKeys[k] compare:cutoff] == NSOrderedAscending)
            [sciDeleteForYouKeys removeObjectForKey:k];
    }
}

// Empty the keys ivar — IG's later apply iterates an empty list.
static void sciNeuterRemoveUpdate(id update) {
    @try {
        Ivar ivar = class_getInstanceVariable([update class], "_removeMessages_messageKeys");
        if (ivar) object_setIvar(update, ivar, nil);
    } @catch (__unused id e) {}
}

// sid path varies by metadata variant:
//   IGDirectPublishedMessageMetadata: _serverId on meta
//   IGDirectUIMessageMetadata:        _key._serverId / _messageServerId
static void sciCaptureFromMessage(id m) {
    if (!m) return;
    @try {
        Ivar metaIvar = class_getInstanceVariable([m class], "_metadata");
        id meta = metaIvar ? object_getIvar(m, metaIvar) : nil;
        if (!meta) return;

        NSString *sid = nil;
        static const char *flatNames[] = {"_serverId", "_messageServerId"};
        for (int i = 0; i < 2 && !sid; i++) {
            Ivar siv = class_getInstanceVariable([meta class], flatNames[i]);
            if (siv) {
                id v = object_getIvar(meta, siv);
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) sid = v;
            }
        }
        if (!sid.length) {
            Ivar keyIvar = class_getInstanceVariable([meta class], "_key");
            id key = keyIvar ? object_getIvar(meta, keyIvar) : nil;
            if (key) {
                for (int i = 0; i < 2 && !sid; i++) {
                    Ivar siv = class_getInstanceVariable([key class], flatNames[i]);
                    if (siv) {
                        id v = object_getIvar(key, siv);
                        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) sid = v;
                    }
                }
            }
        }
        if (!sid.length) return;

        Ivar pkIvar = class_getInstanceVariable([meta class], "_senderPk");
        id pk = pkIvar ? object_getIvar(meta, pkIvar) : nil;
        if ([pk isKindOfClass:[NSString class]] && [(NSString *)pk length] > 0) {
            sciTrackSenderPk(sid, pk);
        }
    } @catch (__unused id e) {}
}

// Captures sender info from inserts/replaces so it's ready when a later unsend
// delta lands for the same sid. Also forwards to the deleted-messages log.
static void sciCaptureSendersFromUpdate(id update) {
    @try {
        Ivar insIvar = class_getInstanceVariable([update class], "_insertMessages");
        NSArray *inserts = insIvar ? object_getIvar(update, insIvar) : nil;
        if ([inserts isKindOfClass:[NSArray class]]) {
            for (id m in (NSArray *)inserts) {
                sciCaptureFromMessage(m);
                sciDMCaptureNoteInsert(m);
            }
        }
        Ivar repIvar = class_getInstanceVariable([update class], "_replaceMessages_messages");
        NSArray *replaces = repIvar ? object_getIvar(update, repIvar) : nil;
        if ([replaces isKindOfClass:[NSArray class]]) {
            for (id m in (NSArray *)replaces) {
                sciCaptureFromMessage(m);
                sciDMCaptureNoteInsert(m);
            }
        }
    } @catch (__unused id e) {}
}

static void sciProcessOneUpdate(id update, NSString *owningPk, NSString *threadId, NSMutableSet<NSString *> *preserved, id applicator) {
    @try {
        Ivar removeIvar = class_getInstanceVariable([update class], "_removeMessages_messageKeys");
        if (!removeIvar) return;
        NSArray *keys = object_getIvar(update, removeIvar);
        if (!keys || keys.count == 0) return;

        long long reason = -1;
        Ivar reasonIvar = class_getInstanceVariable([update class], "_removeMessages_reason");
        if (reasonIvar) {
            ptrdiff_t off = ivar_getOffset(reasonIvar);
            reason = *(long long *)((char *)(__bridge void *)update + off);
        }

        // Track DFY keys so the reason=0 follow-up gets recognised.
        if (reason == 2) {
            NSDate *now = [NSDate date];
            for (id key in keys) {
                NSString *sid = sciExtractServerId(key);
                if (sid) sciDeleteForYouKeys[sid] = now;
            }
            return;
        }

        if (reason != 0) return;

        // Per-sid intent — sids just locally removed via a hooked mutation processor.
        {
            NSMutableSet *pending = sciGetPendingLocalSids();
            BOOL anyIntent = NO;
            for (id key in keys) {
                NSString *sid = sciExtractServerId(key);
                if (sid && [pending containsObject:sid]) { anyIntent = YES; break; }
            }
            if (anyIntent) {
                for (id key in keys) {
                    NSString *sid = sciExtractServerId(key);
                    if (sid) [pending removeObject:sid];
                }
                return;
            }
        }

        if (sciLocalDeleteInProgress) return;

        // DFY follow-up — any tracked key, let the batch through.
        BOOL anyMatched = NO;
        for (id key in keys) {
            NSString *sid = sciExtractServerId(key);
            if (sid && sciDeleteForYouKeys[sid]) { anyMatched = YES; break; }
        }
        if (anyMatched) {
            for (id key in keys) {
                NSString *sid = sciExtractServerId(key);
                if (sid) [sciDeleteForYouKeys removeObjectForKey:sid];
            }
            return;
        }

        // Remote unsend → preserve into owner bucket, skipping reactions/action-logs
        // and own messages. Forward the key objects (not just sids) so the capture
        // can fall back to `[applicator._cache messageForKey:]` for aged-out messages.
        NSMutableSet *ownerBucket = sciBucketForPk(owningPk);
        NSMutableArray *unsendKeys = [NSMutableArray array];
        for (id key in keys) {
            NSString *sid = sciExtractServerId(key);
            if (!sid) continue;
            if (sciIsReactionRelatedMessage(sid)) continue;
            NSString *senderPk = sciGetSenderMap()[sid];
            if (senderPk && [senderPk isEqualToString:owningPk]) continue;
            if (ownerBucket) {
                [ownerBucket addObject:sid];
                [preserved addObject:sid];
            }
            [unsendKeys addObject:key];
        }
        if (unsendKeys.count) sciDMCaptureNoteRemoveKeys(unsendKeys, applicator, owningPk, threadId);
    } @catch (__unused id e) {}
}

static NSSet<NSString *> *sciProcessCacheThreadUpdate(id cacheTU, NSString *tid, NSString *owningPk, id applicator) {
    NSMutableSet<NSString *> *preserved = [NSMutableSet set];
    if (!cacheTU || tid.length == 0) return preserved;
    if (!sciDeleteForYouKeys) sciDeleteForYouKeys = [NSMutableDictionary dictionary];
    sciPruneStaleDeleteForYouKeys();

    if ([SCIExcludedThreads shouldKeepDeletedBeBlockedForThreadId:tid]) return preserved;

    NSArray *threadUpdates = nil;
    @try { threadUpdates = [cacheTU valueForKey:@"threadUpdates"]; } @catch (__unused id e) {}
    if (![threadUpdates isKindOfClass:[NSArray class]]) return preserved;

    for (id thru in threadUpdates) {
        id msgUpdate = nil;
        @try { msgUpdate = [thru valueForKey:@"messageUpdate"]; } @catch (__unused id e) {}
        if (!msgUpdate) continue;

        sciCaptureSendersFromUpdate(msgUpdate);

        NSUInteger before = preserved.count;
        sciProcessOneUpdate(msgUpdate, owningPk, tid, preserved, applicator);
        if (preserved.count > before) sciNeuterRemoveUpdate(msgUpdate);
    }

    if (preserved.count > 0) sciSavePreservedIds();
    return preserved;
}

#pragma mark - Cache update hook

// Two-name format wired for hypothetical actor split — IG unsend is always
// sender-removes-own, so deleterName == senderName in practice.
static NSString *sciBuildUnsentText(NSString *senderName, NSString *deleterName) {
    BOOL hasSender  = senderName.length > 0;
    BOOL hasDeleter = deleterName.length > 0;
    if (hasSender && hasDeleter) {
        if ([senderName isEqualToString:deleterName])
            return [NSString stringWithFormat:SCILocalized(@"%@ unsent a message"), senderName];
        return [NSString stringWithFormat:SCILocalized(@"%@ unsent a message from %@"), deleterName, senderName];
    }
    if (hasSender)  return [NSString stringWithFormat:SCILocalized(@"Message from %@ was unsent"), senderName];
    if (hasDeleter) return [NSString stringWithFormat:SCILocalized(@"%@ unsent a message"), deleterName];
    return SCILocalized(@"A message was unsent");
}

static void sciShowUnsentToast(NSString *senderName, NSString *deleterName, NSString *ownerAccount) {
    NSString *body = sciBuildUnsentText(senderName, deleterName);
    SCINotify(SCI_NOTIF_UNSENT_MESSAGE,
              ownerAccount.length > 0 ? ownerAccount : body,
              ownerAccount.length > 0 ? body : nil,
              @"trash.fill",
              SCINotificationToneError);
}

static void sciRefreshVisibleCellIndicators() {
    Class cellClass = NSClassFromString(@"IGDirectMessageCell");
    if (!cellClass) return;
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
    while (stack.count > 0) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:cellClass]) {
            sciUpdateCellIndicator(v);
            continue;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

static void (*orig_applyUpdates)(id self, SEL _cmd, id updates, id completion, id userAccess);
static void new_applyUpdates(id self, SEL _cmd, id updates, id completion, id userAccess) {
    // Stamp unconditionally — the shared user resolver reads from it even when keep-deleted is off.
    sciDirectUserResolverSetActiveApplicator(self);

    BOOL keepOn = sciKeepDeletedEnabled();
    BOOL logOn  = sciDeletedMessagesLogEnabled();
    if (!keepOn && !logOn) {
        orig_applyUpdates(self, _cmd, updates, completion, userAccess);
        return;
    }

    NSString *owningPk = sciOwningPkFromApplicator(self);

    NSMutableSet<NSString *> *preserved = [NSMutableSet set];
    if (owningPk.length && [updates isKindOfClass:[NSArray class]]) {
        for (id tu in (NSArray *)updates) {
            NSString *tid = nil;
            @try { tid = [tu valueForKey:@"threadId"]; } @catch (__unused id e) {}
            if (tid.length == 0) continue;
            NSSet *p = sciProcessCacheThreadUpdate(tu, tid, owningPk, self);
            if (p.count > 0) [preserved unionSet:p];
        }
    }

    orig_applyUpdates(self, _cmd, updates, completion, userAccess);

    if (preserved.count > 0) {
        NSString *repSid = [preserved anyObject];
        NSString *senderName = repSid ? sciGetSenderNameMap()[repSid] : nil;
        NSString *senderPk = repSid ? sciGetSenderMap()[repSid] : nil;
        if (!senderName.length && senderPk.length) {
            senderName = sciDirectUserResolverUsernameForPK(senderPk);
            if (senderName.length && repSid) sciTrackSenderName(repSid, senderName);
        }
        NSString *deleterName = senderName;

        // Cell refresh = foreground only; pill fires for both so backgrounded unsends still surface.
        NSString *currentPk = sciCurrentUserPk();
        BOOL isForeground = currentPk.length && [currentPk isEqualToString:owningPk];

        // Owner-account title row only when unsend is on a backgrounded login.
        // fieldCache is the reliable read for IGUser fields (KVC returns NSNull for many).
        NSString *ownerAccount = nil;
        if (!isForeground) {
            @try {
                Ivar uIvar = class_getInstanceVariable([self class], "_user");
                id user = uIvar ? object_getIvar(self, uIvar) : nil;
                if (user) {
                    Ivar fcIv = NULL;
                    for (Class c = [user class]; c && !fcIv; c = class_getSuperclass(c))
                        fcIv = class_getInstanceVariable(c, "_fieldCache");
                    if (fcIv) {
                        NSDictionary *fc = object_getIvar(user, fcIv);
                        id un = [fc isKindOfClass:[NSDictionary class]] ? fc[@"username"] : nil;
                        if ([un isKindOfClass:[NSString class]] && [(NSString *)un length] > 0)
                            ownerAccount = un;
                    }
                    if (!ownerAccount.length) {
                        id un = [user valueForKey:@"username"];
                        if ([un isKindOfClass:[NSString class]] && [(NSString *)un length] > 0)
                            ownerAccount = un;
                    }
                }
            } @catch (__unused id e) {}
        }

        BOOL toastPrefOn = [SCIUtils getBoolPref:@"unsent_message_toast"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (isForeground) sciRefreshVisibleCellIndicators();
            if (toastPrefOn) sciShowUnsentToast(senderName, deleterName, ownerAccount);
        });
    }
}

#pragma mark - Local delete tracking

// Per-sid intent path reads target sids off _messageKeys; the time-window
// flag is a safety net for any sid extraction may miss.
static void (*orig_removeMutation_execute)(id self, SEL _cmd, id handler, id pkg);
static void new_removeMutation_execute(id self, SEL _cmd, id handler, id pkg) {
    @try {
        Ivar mkIvar = class_getInstanceVariable([self class], "_messageKeys");
        id keys = mkIvar ? object_getIvar(self, mkIvar) : nil;
        if ([keys isKindOfClass:[NSArray class]]) {
            static const char *kSidNames[] = {"_serverId", "_messageServerId"};
            for (id k in (NSArray *)keys) {
                NSString *sid = nil;
                for (int ni = 0; ni < 2; ni++) {
                    Ivar sidIvar = class_getInstanceVariable([k class], kSidNames[ni]);
                    if (sidIvar) {
                        id v = object_getIvar(k, sidIvar);
                        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
                            sid = v; break;
                        }
                    }
                }
                if (sid) [sciGetPendingLocalSids() addObject:sid];
            }
        }
    } @catch (__unused id e) {}

    sciLocalDeleteInProgress = YES;
    orig_removeMutation_execute(self, _cmd, handler, pkg);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciLocalDeleteInProgress = NO;
    });
}

// Wraps removal-shaped IGDirect*Outgoing*MutationProcessor.execute.
// IGDirectGenericOutgoingMutationProcessor is the DFY signal; rest are class-name heuristics.
static void sciHookAllRemovalMutationProcessors(void) {
    unsigned int count = 0;
    Class *all = objc_copyClassList(&count);
    if (!all) return;
    SEL execSel = NSSelectorFromString(@"executeWithResultHandler:accessoryPackage:");
    Class baseUnsend = NSClassFromString(@"IGDirectMessageOutgoingUpdateRemoveMessagesMutationProcessor");
    for (unsigned int i = 0; i < count; i++) {
        Class c = all[i];
        const char *cn = class_getName(c);
        if (!cn) continue;
        if (c == baseUnsend) continue;
        if (strstr(cn, "MutationProcessor") == NULL) continue;
        if (strstr(cn, "IGDirect") == NULL) continue;
        if (strstr(cn, "Outgoing") == NULL) continue;
        Method m = class_getInstanceMethod(c, execSel);
        if (!m) continue;

        BOOL isDfySignal = (strcmp(cn, "IGDirectGenericOutgoingMutationProcessor") == 0);
        BOOL looksLikeRemoval = (strstr(cn, "Remove") != NULL ||
                                 strstr(cn, "Delete") != NULL ||
                                 strstr(cn, "Hide")   != NULL ||
                                 strstr(cn, "Visibility") != NULL);
        if (!isDfySignal && !looksLikeRemoval) continue;

        __block IMP origImp = method_getImplementation(m);
        IMP newImp = imp_implementationWithBlock(^(id self, id handler, id pkg) {
            sciLocalDeleteInProgress = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                sciLocalDeleteInProgress = NO;
            });
            ((void(*)(id, SEL, id, id))origImp)(self, execSel, handler, pkg);
        });
        IMP prev = class_replaceMethod(c, execSel, newImp, method_getTypeEncoding(m));
        if (prev) origImp = prev;
    }
    free(all);
}

#pragma mark - Visual indicator

static NSString * _Nullable sciGetCellServerId(id cell) {
    @try {
        Ivar vmIvar = class_getInstanceVariable([cell class], "_viewModel");
        if (!vmIvar) return nil;
        id vm = object_getIvar(cell, vmIvar);
        if (!vm) return nil;

        SEL metaSel = NSSelectorFromString(@"messageMetadata");
        if (![vm respondsToSelector:metaSel]) return nil;
        id meta = ((id(*)(id,SEL))objc_msgSend)(vm, metaSel);
        if (!meta) return nil;

        Ivar keyIvar = class_getInstanceVariable([meta class], "_key");
        if (!keyIvar) return nil;
        id keyObj = object_getIvar(meta, keyIvar);
        if (!keyObj) return nil;

        Ivar sidIvar = class_getInstanceVariable([keyObj class], "_serverId");
        if (!sidIvar) return nil;
        NSString *serverId = object_getIvar(keyObj, sidIvar);
        return [serverId isKindOfClass:[NSString class]] ? serverId : nil;
    } @catch(id e) {}
    return nil;
}

static BOOL sciCellIsPreserved(id cell) {
    NSString *sid = sciGetCellServerId(cell);
    return sid && [sciGetPreservedIds() containsObject:sid];
}

// Closest squarish ancestor (32-60pt) — the visible button wrapper.
static UIView *sciFindAccessoryWrapper(UIView *view) {
    UIView *cur = view;
    while (cur && cur.superview) {
        CGRect f = cur.frame;
        if (f.size.width >= 32 && f.size.width <= 60 &&
            fabs(f.size.width - f.size.height) < 4) {
            return cur;
        }
        cur = cur.superview;
    }
    return view;
}

// Trailing action buttons on preserved cells don't work and overlap the "Unsent" label.
static void sciSetTrailingButtonsHidden(UIView *cell, BOOL hidden) {
    if (!cell) return;
    Ivar accIvar = class_getInstanceVariable([cell class], "_tappableAccessoryViews");
    if (!accIvar) return;
    id accViews = object_getIvar(cell, accIvar);
    if (![accViews isKindOfClass:[NSArray class]]) return;
    for (UIView *v in (NSArray *)accViews) {
        if (![v isKindOfClass:[UIView class]]) continue;
        UIView *wrapper = sciFindAccessoryWrapper(v);
        wrapper.hidden = hidden;
        if (wrapper != v) v.hidden = hidden;
    }
}

static void (*orig_addTappableAccessoryView)(id self, SEL _cmd, id view);
static void new_addTappableAccessoryView(id self, SEL _cmd, id view) {
    orig_addTappableAccessoryView(self, _cmd, view);
    if (sciIndicateUnsentEnabled() && sciCellIsPreserved(self)) {
        if ([view isKindOfClass:[UIView class]]) {
            UIView *wrapper = sciFindAccessoryWrapper((UIView *)view);
            wrapper.hidden = YES;
            if (wrapper != view) ((UIView *)view).hidden = YES;
        }
    }
}

static void sciUpdateCellIndicator(id cell) {
    UIView *view = (UIView *)cell;
    UIView *oldIndicator = [view viewWithTag:SCI_PRESERVED_TAG];
    Ivar bubbleIvar = class_getInstanceVariable([cell class], "_messageContentContainerView");
    UIView *bubble = bubbleIvar ? object_getIvar(cell, bubbleIvar) : nil;

    if (!sciIndicateUnsentEnabled()) {
        if (oldIndicator) [oldIndicator removeFromSuperview];
        sciSetTrailingButtonsHidden(view, NO);
        return;
    }

    NSString *serverId = sciGetCellServerId(cell);
    BOOL isPreserved = serverId && [sciGetPreservedIds() containsObject:serverId];

    if (!isPreserved) {
        if (oldIndicator) [oldIndicator removeFromSuperview];
        sciSetTrailingButtonsHidden(view, NO);
        return;
    }

    sciSetTrailingButtonsHidden(view, YES);
    if (oldIndicator) return;

    UIView *parent = bubble ?: view;
    UILabel *label = [[UILabel alloc] init];
    label.tag = SCI_PRESERVED_TAG;
    label.text = SCILocalized(@"Unsent");
    label.font = [UIFont italicSystemFontOfSize:10];
    label.textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.9];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:4],
        [label.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],
    ]];
}

static void (*orig_configureCell)(id self, SEL _cmd, id vm, id ringSpec, id launcherSet);
static void new_configureCell(id self, SEL _cmd, id vm, id ringSpec, id launcherSet) {
    orig_configureCell(self, _cmd, vm, ringSpec, launcherSet);
    // Track sid → senderPk so the apply hook can skip own messages.
    @try {
        Ivar vmIvar = class_getInstanceVariable([self class], "_viewModel");
        id vmObj = vmIvar ? object_getIvar(self, vmIvar) : nil;
        SEL metaSel = NSSelectorFromString(@"messageMetadata");
        id meta = (vmObj && [vmObj respondsToSelector:metaSel])
                  ? ((id(*)(id,SEL))objc_msgSend)(vmObj, metaSel) : nil;
        if (meta) {
            Ivar keyIvar = class_getInstanceVariable([meta class], "_key");
            id keyObj = keyIvar ? object_getIvar(meta, keyIvar) : nil;
            Ivar sidIvar = keyObj ? class_getInstanceVariable([keyObj class], "_serverId") : NULL;
            NSString *sid = sidIvar ? object_getIvar(keyObj, sidIvar) : nil;

            Ivar pkIvar = class_getInstanceVariable([meta class], "_senderPk");
            id pk = pkIvar ? object_getIvar(meta, pkIvar) : nil;
            if ([sid isKindOfClass:[NSString class]] && [pk isKindOfClass:[NSString class]]) {
                sciTrackSenderPk(sid, pk);
            }
        }
    } @catch (__unused id e) {}
    sciUpdateCellIndicator(self);
}

static void (*orig_cellLayoutSubviews)(id self, SEL _cmd);
static void new_cellLayoutSubviews(id self, SEL _cmd) {
    orig_cellLayoutSubviews(self, _cmd);
    sciUpdateCellIndicator(self);
}

#pragma mark - Action log tracking

// IGDirectThreadActionLog = the local "X liked a message" row.
// Tracking its message id keeps the unsend path from preserving these.
static id (*orig_actionLogFullInit)(id, SEL, id, id, id, id, id, BOOL, BOOL, id);
static id new_actionLogFullInit(id self, SEL _cmd,
                                 id message, id title, id textAttributes, id textParts,
                                 id actionLogType, BOOL collapsible, BOOL hidden, id genAIMetadata) {
    id result = orig_actionLogFullInit(self, _cmd, message, title, textAttributes, textParts,
                                        actionLogType, collapsible, hidden, genAIMetadata);
    @try {
        SEL midSel = @selector(messageId);
        if ([result respondsToSelector:midSel]) {
            id mid = ((id(*)(id, SEL))objc_msgSend)(result, midSel);
            if ([mid isKindOfClass:[NSString class]]) {
                sciTrackInsertedMessage(mid, @"IGDirectThreadActionLog");
            }
        }
    } @catch(id e) {}
    return result;
}

#pragma mark - Runtime hooks

%ctor {
    Class actionLogCls = NSClassFromString(@"IGDirectThreadActionLog");
    if (actionLogCls) {
        SEL fullInit = NSSelectorFromString(@"initWithMessage:title:textAttributes:textParts:actionLogType:collapsible:hidden:genAIMetadata:");
        if (class_getInstanceMethod(actionLogCls, fullInit))
            MSHookMessageEx(actionLogCls, fullInit, (IMP)new_actionLogFullInit, (IMP *)&orig_actionLogFullInit);
    }

    Class cacheClass = NSClassFromString(@"IGDirectCacheUpdatesApplicator");
    if (cacheClass) {
        SEL sel = NSSelectorFromString(@"_applyThreadUpdates:completion:userAccess:");
        if (class_getInstanceMethod(cacheClass, sel))
            MSHookMessageEx(cacheClass, sel, (IMP)new_applyUpdates, (IMP *)&orig_applyUpdates);
    }

    Class cellClass = NSClassFromString(@"IGDirectMessageCell");
    if (cellClass) {
        SEL configSel = NSSelectorFromString(@"configureWithViewModel:ringViewSpecFactory:launcherSet:");
        if (class_getInstanceMethod(cellClass, configSel))
            MSHookMessageEx(cellClass, configSel,
                            (IMP)new_configureCell, (IMP *)&orig_configureCell);

        SEL layoutSel = @selector(layoutSubviews);
        MSHookMessageEx(cellClass, layoutSel,
                        (IMP)new_cellLayoutSubviews, (IMP *)&orig_cellLayoutSubviews);

        SEL addAccSel = NSSelectorFromString(@"_addTappableAccessoryView:");
        if (class_getInstanceMethod(cellClass, addAccSel))
            MSHookMessageEx(cellClass, addAccSel,
                            (IMP)new_addTappableAccessoryView, (IMP *)&orig_addTappableAccessoryView);
    }

    Class removeMutationClass = NSClassFromString(@"IGDirectMessageOutgoingUpdateRemoveMessagesMutationProcessor");
    if (removeMutationClass) {
        SEL execSel = NSSelectorFromString(@"executeWithResultHandler:accessoryPackage:");
        if (class_getInstanceMethod(removeMutationClass, execSel))
            MSHookMessageEx(removeMutationClass, execSel,
                            (IMP)new_removeMutation_execute, (IMP *)&orig_removeMutation_execute);
    }

    sciHookAllRemovalMutationProcessors();

    if (![SCIUtils getBoolPref:@"indicate_unsent_messages"]) {
        // Wipe storage directly — pk isn't known at %ctor time.
        sciPreservedByPk = [NSMutableDictionary dictionary];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SCI_PRESERVED_IDS_KEY];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SCI_PRESERVED_LEGACY_KEY];
    }
}
