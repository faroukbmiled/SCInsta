#import "SCIMediaActions.h"
#import "SCIMediaViewer.h"
#import "SCIRepostSheet.h"
#import "SCIActionMenuConfig.h"
#import "SCIActionCatalog.h"
#import "../SCIDashParser.h"
#import "../SCIFFmpeg.h"
#import "../SCIQualityPicker.h"
#import "../Utils.h"
#import "../Downloader/Download.h"
#import "../PhotoAlbum.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../Gallery/SCIGalleryOriginController.h"
#import "../Features/StoriesAndMessages/SCIExcludedStoryUsers.h"
#import "../Features/StoriesAndMessages/OverlayHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

// One-shot metadata stamped before a download fires; sciMakeDownloader picks
// it up + clears. Lets callers tag a download for gallery logging without
// threading metadata through every overload.
static SCIGallerySaveMetadata *sciPendingGalleryMetadata = nil;

static SCIGallerySource sciGallerySourceFromContext(SCIActionContext ctx) {
    switch (ctx) {
        case SCIActionContextFeed:    return SCIGallerySourceFeed;
        case SCIActionContextReels:   return SCIGallerySourceReels;
        case SCIActionContextStories: return SCIGallerySourceStories;
    }
    return SCIGallerySourceOther;
}

static void sciStampGalleryMetadataForMedia(id media, SCIActionContext ctx) {
    SCIGallerySaveMetadata *m = [[SCIGallerySaveMetadata alloc] init];
    m.source = (int16_t)sciGallerySourceFromContext(ctx);
    @try { [SCIGalleryOriginController populateMetadata:m fromMedia:media]; }
    @catch (__unused id e) {}
    sciPendingGalleryMetadata = m;
}

static SCIActionSource sciSourceFromContext(SCIActionContext ctx) {
    switch (ctx) {
        case SCIActionContextFeed:    return SCIActionSourceFeed;
        case SCIActionContextReels:   return SCIActionSourceReels;
        case SCIActionContextStories: return SCIActionSourceStories;
    }
    return SCIActionSourceFeed;
}

// Retain the active download delegate so ARC doesn't kill it mid-download.
// Replaced on each new download — one active download at a time.
static SCIDownloadDelegate *sciActiveDownloadDelegate = nil;

// Story audio toggle — defined in StoryAudioToggle.xm (extern "C")
extern void sciToggleStoryAudio(void);
extern BOOL sciIsStoryAudioEnabled(void);

// MARK: - Date header

// Auto-detects microseconds (>1e15) and milliseconds (>1e12).
static NSTimeInterval sciCoerceTimestamp(id v) {
    double d = 0;
    if ([v isKindOfClass:[NSNumber class]])      d = [v doubleValue];
    else if ([v isKindOfClass:[NSString class]]) d = [(NSString *)v doubleValue];
    if (d <= 0) return 0;
    if (d > 1e15) d /= 1e6;
    else if (d > 1e12) d /= 1e3;
    return d;
}

static NSDate *sciExtractDateFromMedia(id media) {
    if (!media) return nil;
    Ivar iv = NULL;
    for (Class c = [media class]; c && !iv; c = class_getSuperclass(c))
        iv = class_getInstanceVariable(c, "_fieldCache");
    if (!iv) return nil;
    NSDictionary *dict = nil;
    @try {
        id v = object_getIvar(media, iv);
        if ([v isKindOfClass:[NSDictionary class]]) dict = v;
    } @catch (__unused id e) { return nil; }
    if (!dict) return nil;

    for (NSString *k in @[@"taken_at", @"device_timestamp",
                          @"created_at", @"upload_time", @"published_time"]) {
        NSTimeInterval t = sciCoerceTimestamp(dict[k]);
        if (t > 0) return [NSDate dateWithTimeIntervalSince1970:t];
    }
    return nil;
}

// "Apr 24, 2026 at 5:30pm" — lowercase am/pm, 12-hour, local timezone.
static NSString *sciFormatDateHeader(NSDate *date) {
    if (!date) return nil;
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"MMM d, yyyy 'at' h:mma";
        fmt.AMSymbol = @"am";
        fmt.PMSymbol = @"pm";
    });
    fmt.timeZone = [NSTimeZone localTimeZone];
    return [fmt stringFromDate:date];
}

static NSString *sciDatePrefKeyForContext(SCIActionContext ctx) {
    switch (ctx) {
        case SCIActionContextFeed:    return @"menu_date_feed";
        case SCIActionContextReels:   return @"menu_date_reels";
        case SCIActionContextStories: return @"menu_date_stories";
    }
    return nil;
}

// MARK: - Filename naming

static NSString *sciCurrentFilenameStem = nil;

static NSString *sciSanitizeFilenameComponent(NSString *s) {
    if (!s.length) return @"";
    NSMutableCharacterSet *bad = [NSMutableCharacterSet alphanumericCharacterSet];
    [bad addCharactersInString:@"._-"];
    NSCharacterSet *drop = bad.invertedSet;
    NSArray *parts = [s componentsSeparatedByCharactersInSet:drop];
    NSString *out = [parts componentsJoinedByString:@""];
    if (out.length > 30) out = [out substringToIndex:30];
    return out;
}

// IGAPIStorableObject's backing dict.
static NSDictionary *sciMediaFieldCache(id obj) {
	if (!obj) return nil;

	if ([obj isKindOfClass:NSDictionary.class]) {
		return (NSDictionary *)obj;
	}

	Class storableClass = NSClassFromString(@"IGAPIStorableObject");
	if (storableClass && ![obj isKindOfClass:storableClass]) {
		return nil;
	}

	Ivar ivar = class_getInstanceVariable(object_getClass(obj), "_fieldCache");
	if (!ivar) ivar = class_getInstanceVariable([obj class], "_fieldCache");
	if (!ivar) return nil;

	@try {
		id value = object_getIvar(obj, ivar);
		return [value isKindOfClass:NSDictionary.class] ? value : nil;
	} @catch (__unused id e) {
		return nil;
	}
}

static NSString *sciUsernameForMedia(id media) {
    if (!media) return nil;
    @try {
        id user = nil;
        @try { user = [media valueForKey:@"user"]; } @catch (__unused id e) {}
        if (!user) {
            NSDictionary *fc = sciMediaFieldCache(media);
            user = fc[@"user"];
        }
        if (!user) return nil;
        NSString *u = nil;
        @try { u = [user valueForKey:@"username"]; } @catch (__unused id e) {}
        if (![u isKindOfClass:[NSString class]] || !u.length) {
            NSDictionary *ufc = sciMediaFieldCache(user);
            id v = ufc[@"username"];
            if ([v isKindOfClass:[NSString class]]) u = v;
            else if ([user isKindOfClass:[NSDictionary class]]) u = ((NSDictionary *)user)[@"username"];
        }
        return [u isKindOfClass:[NSString class]] ? u : nil;
    } @catch (__unused id e) { return nil; }
}

// Match keys used in the settings-entry title map for openSettingsForContext:
static NSString *sciSettingsTitleForContext(SCIActionContext ctx) {
    switch (ctx) {
        case SCIActionContextFeed: return SCILocalized(@"Feed");
        case SCIActionContextReels: return SCILocalized(@"Reels");
        case SCIActionContextStories: return SCILocalized(@"Stories");
    }
    return @"General";
}

// Pull an ivar by name. Returns nil on miss. Safe for any class.
static id sciIvar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Ivar i = class_getInstanceVariable(object_getClass(obj), name);
    if (!i) return nil;
    @try { return object_getIvar(obj, i); } @catch (__unused id e) { return nil; }
}

// Read from IGAPIStorableObject._fieldCache (KVC returns NSNull for many keys).
static id sciFieldCache(id obj, NSString *key) {
	if (!obj || !key.length) return nil;

	NSDictionary *dict = nil;

	if ([obj isKindOfClass:NSDictionary.class]) {
		dict = (NSDictionary *)obj;
	} else {
		Class storableClass = NSClassFromString(@"IGAPIStorableObject");

		if (storableClass && ![obj isKindOfClass:storableClass]) {
			return nil;
		}

		Ivar ivar = class_getInstanceVariable(object_getClass(obj), "_fieldCache");
		if (!ivar) ivar = class_getInstanceVariable([obj class], "_fieldCache");
		if (!ivar) return nil;

		@try {
			id value = object_getIvar(obj, ivar);
			if ([value isKindOfClass:NSDictionary.class]) dict = value;
		} @catch (__unused id e) {
			return nil;
		}
	}

	id value = dict[key];
	if (!value || [value isKindOfClass:NSNull.class]) return nil;
	return value;
}

// Fresh download delegate (one active download at a time). Consumes any
// metadata stamped via sciStampGalleryMetadataForMedia before the call so the
// download routes through Download.m's gallery logic.
static SCIDownloadDelegate *sciMakeDownloader(DownloadAction action, BOOL progress) {
    SCIDownloadDelegate *d = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:progress];
    if (sciPendingGalleryMetadata) {
        d.pendingGallerySaveMetadata = sciPendingGalleryMetadata;
        sciPendingGalleryMetadata = nil;
    }
    return d;
}

// Route a download through the confirm dialog if the pref is on.
static void sciConfirmThen(NSString *title, void(^block)(void)) {
    if ([SCIUtils getBoolPref:@"dw_confirm"]) {
        [SCIUtils showConfirmation:block title:title];
    } else {
        block();
    }
}


@implementation SCIMediaActions

+ (NSString *)contextLabelForContext:(SCIActionContext)ctx {
    switch (ctx) {
        case SCIActionContextFeed:    return @"feed";
        case SCIActionContextReels:   return @"reels";
        case SCIActionContextStories: return @"stories";
    }
    return @"media";
}

+ (NSString *)filenameStemForMedia:(id)media contextLabel:(NSString *)ctxLabel {
    return [self filenameStemForUsername:sciUsernameForMedia(media) contextLabel:ctxLabel];
}

+ (NSString *)filenameStemForUsername:(NSString *)username contextLabel:(NSString *)ctxLabel {
    @try {
        NSString *user = sciSanitizeFilenameComponent(username);
        NSString *userPart = user.length ? [@"@" stringByAppendingString:user] : @"media";
        NSString *ctxPart = sciSanitizeFilenameComponent(ctxLabel);
        if (!ctxPart.length) ctxPart = @"media";
        static NSDateFormatter *fmt = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            fmt = [NSDateFormatter new];
            fmt.dateFormat = @"yyyyMMdd_HHmmss";
            fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        });
        NSString *ts = [fmt stringFromDate:[NSDate date]];
        return [NSString stringWithFormat:@"%@_%@_%@", userPart, ctxPart, ts];
    } @catch (__unused id e) {
        return [[NSUUID UUID] UUIDString];
    }
}

+ (NSString *)currentFilenameStem { return sciCurrentFilenameStem; }
+ (void)setCurrentFilenameStem:(NSString *)stem { sciCurrentFilenameStem = [stem copy]; }

// MARK: - Media extraction

+ (NSString *)captionForMedia:(id)media {
    if (!media) return nil;

    // Try known selectors
    for (NSString *sel in @[@"fullCaptionString", @"captionString", @"caption",
                             @"captionText", @"text"]) {
        SEL s = NSSelectorFromString(sel);
        if ([media respondsToSelector:s]) {
            @try {
                id result = ((id(*)(id, SEL))objc_msgSend)(media, s);
                if ([result isKindOfClass:[NSString class]] && [(NSString *)result length]) {
                    return result;
                }
                // Wrapper objects (IGAPICommentDict, etc.) — try all text accessors
                if (result && ![result isKindOfClass:[NSString class]]) {
                    for (NSString *textSel in @[@"text", @"string", @"commentText",
                                                 @"attributedString", @"rawText"]) {
                        if ([result respondsToSelector:NSSelectorFromString(textSel)]) {
                            @try {
                                id text = ((id(*)(id,SEL))objc_msgSend)(result, NSSelectorFromString(textSel));
                                // NSAttributedString → .string
                                if ([text respondsToSelector:@selector(string)] && ![text isKindOfClass:[NSString class]])
                                    text = ((id(*)(id,SEL))objc_msgSend)(text, @selector(string));
                                if ([text isKindOfClass:[NSString class]] && [(NSString *)text length])
                                    return text;
                            } @catch (__unused id e) {}
                        }
                    }
                    // Also try reading fieldCache on the wrapper (Pando dict)
                    id fcText = sciFieldCache(result, @"text");
                    if ([fcText isKindOfClass:[NSString class]] && [(NSString *)fcText length])
                        return fcText;
                }
            } @catch (__unused id e) {}
        }
    }

    // Fieldcache: `caption` → dict with `text`, or direct string
    id capObj = sciFieldCache(media, @"caption");
    if ([capObj isKindOfClass:[NSDictionary class]]) {
        id text = ((NSDictionary *)capObj)[@"text"];
        if ([text isKindOfClass:[NSString class]] && [(NSString *)text length]) return text;
    } else if ([capObj isKindOfClass:[NSString class]] && [(NSString *)capObj length]) {
        return capObj;
    }

    // Fieldcache: try the caption wrapper object's text
    if (capObj && [capObj respondsToSelector:@selector(text)]) {
        @try {
            id text = ((id(*)(id, SEL))objc_msgSend)(capObj, @selector(text));
            if ([text isKindOfClass:[NSString class]] && [(NSString *)text length]) return text;
        } @catch (__unused id e) {}
    }

    // Deep scan: check ivars named _caption* on the media object
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(object_getClass(media), &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *name = ivar_getName(ivars[i]);
        if (!name) continue;
        NSString *ivarName = [[NSString stringWithUTF8String:name] lowercaseString];
        if (![ivarName containsString:@"caption"]) continue;
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') continue;
        @try {
            id val = object_getIvar(media, ivars[i]);
            if ([val isKindOfClass:[NSString class]] && [(NSString *)val length]) {
                free(ivars); return val;
            }
            if (val && [val respondsToSelector:@selector(text)]) {
                id text = ((id(*)(id, SEL))objc_msgSend)(val, @selector(text));
                if ([text isKindOfClass:[NSString class]] && [(NSString *)text length]) {
                    free(ivars); return text;
                }
            }
            if (val && [val respondsToSelector:@selector(string)]) {
                id str = ((id(*)(id, SEL))objc_msgSend)(val, @selector(string));
                if ([str isKindOfClass:[NSString class]] && [(NSString *)str length]) {
                    free(ivars); return str;
                }
            }
        } @catch (__unused id e) {}
    }
    if (ivars) free(ivars);

    return nil;
}

+ (BOOL)isCarouselMedia:(id)media {
    if (!media) return NO;

    if ([media respondsToSelector:@selector(isCarousel)]) {
        @try {
            BOOL r = ((BOOL(*)(id, SEL))objc_msgSend)(media, @selector(isCarousel));
            if (r) return YES;
        } @catch (__unused id e) {}
    }

    if ([media respondsToSelector:@selector(mediaType)]) {
        @try {
            NSInteger t = ((NSInteger(*)(id, SEL))objc_msgSend)(media, @selector(mediaType));
            if (t == 8) return YES;
        } @catch (__unused id e) {}
    }

    return [self carouselChildrenForMedia:media].count > 0;
}

+ (NSArray *)carouselChildrenForMedia:(id)media {
    if (!media) return @[];

    for (NSString *sel in @[@"carouselMedia", @"carouselChildren", @"children"]) {
        SEL s = NSSelectorFromString(sel);
        if ([media respondsToSelector:s]) {
            @try {
                id val = ((id(*)(id, SEL))objc_msgSend)(media, s);
                if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count]) return val;
            } @catch (__unused id e) {}
        }
    }

    static const char * const kCarouselIvars[] = { "_carouselMedia", "_carouselChildren" };
    for (size_t i = 0; i < sizeof(kCarouselIvars)/sizeof(kCarouselIvars[0]); i++) {
        id val = sciIvar(media, kCarouselIvars[i]);
        if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count]) return val;
    }

    id fc = sciFieldCache(media, @"carousel_media");
    if ([fc isKindOfClass:[NSArray class]]) return fc;

    return @[];
}

+ (BOOL)mediaHasAudio:(id)media {
    if (!media) return NO;
    // fieldCache on media (old IG path).
    id v = sciFieldCache(media, @"has_audio");
    if ([v respondsToSelector:@selector(boolValue)] && [v boolValue]) return YES;

    // IGVideo.isAudioDetected — positive signal only; NO often means "IG
    // hasn't decoded the manifest yet" for stories, not actually silent.
    @try {
        id video = nil;
        if ([media respondsToSelector:@selector(video)])
            video = ((id(*)(id, SEL))objc_msgSend)(media, @selector(video));
        if (video && [video respondsToSelector:@selector(isAudioDetected)]) {
            if (((BOOL(*)(id, SEL))objc_msgSend)(video, @selector(isAudioDetected))) return YES;
        }
    } @catch (__unused id e) {}

    // Stories often carry audio but don't surface it in fieldCache. If any
    // of these music/audio hints are present, treat as audio-bearing.
    for (NSString *key in @[@"music_metadata", @"story_music_stickers",
                            @"is_story_image_with_music", @"story_sound_on",
                            @"spotify_stickers", @"story_music_lyric_stickers"]) {
        id val = sciFieldCache(media, key);
        if (val && ![val isKindOfClass:[NSNull class]]) {
            if ([val respondsToSelector:@selector(boolValue)] && [val boolValue]) return YES;
            if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count]) return YES;
            if ([val isKindOfClass:[NSDictionary class]] && [(NSDictionary *)val count]) return YES;
        }
    }

    // Last resort: if a DASH manifest exists, assume audio is present.
    return [SCIDashParser dashManifestForMedia:media].length > 0;
}

+ (void)downloadPhotoOnlyForMedia:(id)media action:(DownloadAction)action {
    NSURL *url = [self hdPhotoURLForMedia:media];
    if (!url) url = [SCIUtils getPhotoUrlForMedia:(IGMedia *)media];
    if (!url) url = [self fieldCachePhotoURLForMedia:media];
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract photo URL")]; return; }
    NSString *ext = [[url lastPathComponent] pathExtension];
    if (!ext.length) ext = @"jpg";
    sciActiveDownloadDelegate = sciMakeDownloader(action, NO);
    [sciActiveDownloadDelegate downloadFileWithURL:url fileExtension:ext hudLabel:nil];
}

// Photos library can't hold audio — save action falls back to share sheet.
+ (void)downloadAudioOnlyForMedia:(id)media action:(DownloadAction)action {
    NSString *manifest = [SCIDashParser dashManifestForMedia:media];
    if (!manifest.length) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No audio stream available")];
        return;
    }
    NSArray *reps = [SCIDashParser parseManifest:manifest];
    SCIDashRepresentation *audio = [SCIDashParser bestAudioFromRepresentations:reps];
    if (!audio.url) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No audio track found")];
        return;
    }
    if (![SCIFFmpeg isAvailable]) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"FFmpeg not available")];
        return;
    }

    SCIDownloadPillView *pill = [SCIDownloadPillView shared];
    NSString *ticket = [pill beginTicketWithTitle:SCILocalized(@"Downloading audio...")
                                         onCancel:^{ [SCIFFmpeg cancelAll]; }];

    NSString *audioStem = [self currentFilenameStem] ?: [[NSUUID UUID] UUIDString];
    NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@.m4a", audioStem]];
    NSString *cmd = [NSString stringWithFormat:@"-i \"%@\" -vn -c:a copy -y \"%@\"",
                     audio.url.absoluteString, outPath];
    [SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) {
                [pill finishTicket:ticket errorMessage:SCILocalized(@"Audio extract failed")];
                return;
            }
            NSURL *fileURL = [NSURL fileURLWithPath:outPath];
            if (action == saveToGallery) {
                NSError *err = nil;
                SCIGallerySaveMetadata *m = sciPendingGalleryMetadata;
                sciPendingGalleryMetadata = nil;
                SCIGallerySource src = m ? (SCIGallerySource)m.source : SCIGallerySourceOther;
                SCIGalleryFile *f = [SCIGalleryFile saveFileToGallery:fileURL
                                                                source:src
                                                             mediaType:SCIGalleryMediaTypeAudio
                                                            folderPath:nil
                                                              metadata:m
                                                                 error:&err];
                if (f && !err) {
                    [pill finishTicket:ticket successMessage:SCILocalized(@"Saved to Gallery")];
                } else {
                    [pill finishTicket:ticket errorMessage:err.localizedDescription ?: SCILocalized(@"Failed to save")];
                }
                return;
            }
            [pill finishTicket:ticket successMessage:SCILocalized(@"Audio ready")];
            switch (action) {
                case quickLook: [SCIUtils showQuickLookVC:@[fileURL]]; break;
                case share:
                case saveToPhotos:
                default: [SCIUtils showShareVC:fileURL]; break;
            }
        });
    }];
}

+ (NSURL *)bestURLForMedia:(id)media {
    if (!media) return nil;

    NSURL *v = [SCIUtils getVideoUrlForMedia:(IGMedia *)media];
    if (v) return v;

    BOOL hdPhotos = [[SCIUtils getStringPref:@"default_photo_quality"] isEqualToString:@"high"];
    if (hdPhotos) {
        NSURL *hd = [self hdPhotoURLForMedia:media];
        if (hd) return hd;
    }

    NSURL *p = [SCIUtils getPhotoUrlForMedia:(IGMedia *)media];
    if (p) return p;

    // Carousel children: fieldCache fallback
    return [self fieldCachePhotoURLForMedia:media];
}

+ (NSURL *)hdPhotoURLForMedia:(id)media {
    // fieldCache image_versions2.candidates has multiple sizes — pick largest
    id candidates = nil;
    id iv2 = sciFieldCache(media, @"image_versions2");
    if ([iv2 isKindOfClass:[NSDictionary class]])
        candidates = ((NSDictionary *)iv2)[@"candidates"];
    if (!candidates)
        candidates = sciFieldCache(media, @"candidates");

    if ([candidates isKindOfClass:[NSArray class]] && [(NSArray *)candidates count]) {
        NSDictionary *best = nil;
        NSInteger bestW = 0;
        for (id c in (NSArray *)candidates) {
            if (![c isKindOfClass:[NSDictionary class]]) continue;
            NSInteger w = [((NSDictionary *)c)[@"width"] integerValue];
            if (w > bestW) { bestW = w; best = c; }
        }
        NSString *urlStr = best[@"url"];
        if (urlStr.length) return [NSURL URLWithString:urlStr];
    }

    // Try .photo sub-object imageVersions
    id photo = nil;
    if ([media respondsToSelector:@selector(photo)])
        photo = ((id(*)(id, SEL))objc_msgSend)(media, @selector(photo));

    // _originalImageVersions on IGPhoto — array of IGImageURL objects
    if (photo) {
        Ivar oivIvar = class_getInstanceVariable([photo class], "_originalImageVersions");
        if (oivIvar) {
            id oiv = object_getIvar(photo, oivIvar);
            if ([oiv isKindOfClass:[NSArray class]] && [(NSArray *)oiv count]) {
                NSURL *best = nil;
                NSInteger bestW = 0;
                for (id item in (NSArray *)oiv) {
                    NSURL *u = nil;
                    NSInteger w = 0;
                    if ([item isKindOfClass:[NSDictionary class]]) {
                        NSString *s = ((NSDictionary *)item)[@"url"];
                        if (s.length) u = [NSURL URLWithString:s];
                        w = [((NSDictionary *)item)[@"width"] integerValue];
                    } else {
                        if ([item respondsToSelector:@selector(url)])
                            u = [item valueForKey:@"url"];
                        if ([item respondsToSelector:@selector(width)])
                            w = [[item valueForKey:@"width"] integerValue];
                    }
                    if (u && w > bestW) { bestW = w; best = u; }
                }
                if (best) return best;
            }
        }
    }

    return nil;
}

+ (NSURL *)fieldCachePhotoURLForMedia:(id)media {
    id candidates = nil;
    id iv2 = sciFieldCache(media, @"image_versions2");
    if ([iv2 isKindOfClass:[NSDictionary class]])
        candidates = ((NSDictionary *)iv2)[@"candidates"];
    if (!candidates)
        candidates = sciFieldCache(media, @"candidates");

    if ([candidates isKindOfClass:[NSArray class]] && [(NSArray *)candidates count]) {
        NSDictionary *best = nil;
        NSInteger bestW = 0;
        for (id c in (NSArray *)candidates) {
            if (![c isKindOfClass:[NSDictionary class]]) continue;
            NSInteger w = [((NSDictionary *)c)[@"width"] integerValue];
            if (w > bestW) { bestW = w; best = c; }
        }
        NSString *urlStr = best[@"url"];
        if (urlStr.length) return [NSURL URLWithString:urlStr];
    }
    return nil;
}

// MARK: - Enhanced HD download

+ (void)downloadHDMedia:(id)media action:(DownloadAction)action fromView:(UIView *)sourceView {
    if (!media) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No media")]; return; }

    BOOL isVideo = ([SCIUtils getVideoUrlForMedia:(IGMedia *)media] != nil);

    // Photos: always use best candidates URL (no FFmpeg needed)
    if (!isVideo) {
        NSURL *url = [self bestURLForMedia:media];
        if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract photo URL")]; return; }
        sciActiveDownloadDelegate = sciMakeDownloader(action, NO);
        [sciActiveDownloadDelegate downloadFileWithURL:url
                                         fileExtension:[[url lastPathComponent] pathExtension]
                                              hudLabel:nil];
        return;
    }

    // Try enhanced HD path via reusable quality picker
    BOOL handled = [SCIQualityPicker pickQualityForMedia:media
        fromView:sourceView
        action:action
        picked:^(SCIDashRepresentation *video, SCIDashRepresentation *audio) {
            [self downloadDASHVideo:video audio:audio action:action];
        }
        fallback:^{
            // No DASH or FFmpeg unavailable — use progressive URL
            NSURL *url = [self bestURLForMedia:media];
            if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract video URL")]; return; }
            sciActiveDownloadDelegate = sciMakeDownloader(action, YES);
            [sciActiveDownloadDelegate downloadFileWithURL:url
                                             fileExtension:[[url lastPathComponent] pathExtension]
                                                  hudLabel:nil];
        }];

    if (!handled) {
        // pickQualityForMedia returned NO and already called fallback
    }
}

+ (void)downloadDASHVideo:(SCIDashRepresentation *)videoRep
                    audio:(SCIDashRepresentation *)audioRep
                   action:(DownloadAction)action {
    if (!videoRep.url) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No video URL")];
        return;
    }

    SCIDownloadPillView *pill = [SCIDownloadPillView shared];
    __block void (^muxCancel)(void) = nil;
    NSString *ticket = [pill beginTicketWithTitle:[NSString stringWithFormat:SCILocalized(@"Downloading %@..."), videoRep.qualityLabel ?: @"HD"]
                                         onCancel:^{ if (muxCancel) muxCancel(); }];

    NSString *encPreset = [SCIUtils getStringPref:@"ffmpeg_encoding_speed"];
    if (!encPreset.length) encPreset = @"ultrafast";

    [SCIFFmpeg muxVideoURL:videoRep.url audioURL:audioRep.url preset:encPreset
                  progress:^(float progress, NSString *stage) {
        [pill updateTicket:ticket progress:progress];
        [pill updateTicket:ticket text:stage];
    } completion:^(NSURL *outputURL, NSError *error) {
        if (error && error.code == NSUserCancelledError) {
            [pill finishTicket:ticket cancelled:@"Cancelled"];
            if (outputURL) [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
            return;
        }
        if (error || !outputURL) {
            [pill finishTicket:ticket errorMessage:error.localizedDescription ?: @"Mux failed"];
            return;
        }

        // saveToPhotos / saveToGallery finish the ticket after their
        // completion fires.
        if (action != saveToPhotos && action != saveToGallery) {
            [pill finishTicket:ticket successMessage:SCILocalized(@"HD download complete")];
        }

        switch (action) {
            case share:
                [SCIUtils showShareVC:outputURL];
                break;
            case quickLook:
                [SCIUtils showQuickLookVC:@[outputURL]];
                break;
            case saveToGallery: {
                NSError *err = nil;
                SCIGallerySaveMetadata *m = sciPendingGalleryMetadata;
                sciPendingGalleryMetadata = nil;
                SCIGallerySource src = m ? (SCIGallerySource)m.source : SCIGallerySourceOther;
                SCIGalleryFile *f = [SCIGalleryFile saveFileToGallery:outputURL
                                                                source:src
                                                             mediaType:SCIGalleryMediaTypeVideo
                                                            folderPath:nil
                                                              metadata:m
                                                                 error:&err];
                if (f && !err) {
                    [pill finishTicket:ticket successMessage:SCILocalized(@"Saved to Gallery")];
                } else {
                    [pill finishTicket:ticket errorMessage:err.localizedDescription ?: @"Failed to save"];
                }
                break;
            }
            case saveToPhotos: {
                [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                    if (status != PHAuthorizationStatusAuthorized) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
                        });
                        return;
                    }

                    BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];
                    void (^onDone)(BOOL, NSError *) = ^(BOOL ok, NSError *e) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (ok) [pill finishTicket:ticket successMessage:useAlbum ? SCILocalized(@"Saved to RyukGram") : SCILocalized(@"Saved to Photos")];
                            else [pill finishTicket:ticket errorMessage:e.localizedDescription ?: @"Failed to save"];
                        });
                    };

                    if (useAlbum) {
                        [SCIPhotoAlbum saveFileToAlbum:outputURL completion:^(BOOL ok, NSError *e) {
                            [[NSFileManager defaultManager] removeItemAtPath:outputURL.path error:nil];
                            onDone(ok, e);
                        }];
                    } else {
                        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                            PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
                            PHAssetResourceCreationOptions *opts = [PHAssetResourceCreationOptions new];
                            opts.shouldMoveFile = YES;
                            [req addResourceWithType:PHAssetResourceTypeVideo
                                fileURL:outputURL options:opts];
                        } completionHandler:onDone];
                    }
                }];
                break;
            }
        }
    } cancelOut:^(void (^cb)(void)) {
        muxCancel = cb;
    }];
}

+ (NSURL *)coverURLForMedia:(id)media {
    if (!media) return nil;
    // For a reel/video, `media.photo` exposes the poster frame URL.
    return [SCIUtils getPhotoUrlForMedia:(IGMedia *)media];
}


// MARK: - Primary actions

+ (void)expandMedia:(id)media fromView:(UIView *)sourceView caption:(NSString *)caption {
    if (!media) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No media to expand")]; return; }

    NSString *cap = caption ?: [self captionForMedia:media];

    // Check if this is a carousel — show all items with swiping
    if ([self isCarouselMedia:media]) {
        NSArray *children = [self carouselChildrenForMedia:media];
        NSMutableArray<SCIMediaViewerItem *> *items = [NSMutableArray array];
        for (id child in children) {
            NSURL *v = [SCIUtils getVideoUrlForMedia:(IGMedia *)child];
            NSURL *p = [SCIUtils getPhotoUrlForMedia:(IGMedia *)child];
            if (v || p) {
                [items addObject:[SCIMediaViewerItem itemWithVideoURL:v photoURL:p caption:cap]];
            }
        }
        if (items.count) {
            [SCIMediaViewer showItems:items startIndex:0];
            return;
        }
    }

    // Single item
    NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:(IGMedia *)media];
    NSURL *photoUrl = [SCIUtils getPhotoUrlForMedia:(IGMedia *)media];
    if (!videoUrl && !photoUrl) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract media URL")]; return; }

    [SCIMediaViewer showWithVideoURL:videoUrl photoURL:photoUrl caption:cap];
}

+ (void)downloadAndShareMedia:(id)media {
    [self downloadAndShareMedia:media fromView:nil];
}

+ (void)downloadAndShareMedia:(id)media fromView:(UIView *)sourceView {
    sciConfirmThen(SCILocalized(@"Download and share"), ^{
        [self downloadHDMedia:media action:share fromView:sourceView];
    });
}

+ (void)downloadAndSaveMedia:(id)media {
    [self downloadAndSaveMedia:media fromView:nil];
}

+ (void)downloadAndSaveMedia:(id)media fromView:(UIView *)sourceView {
    sciConfirmThen(SCILocalized(@"Save to Photos"), ^{
        [self downloadHDMedia:media action:saveToPhotos fromView:sourceView];
    });
}

+ (void)downloadAndSaveMediaToGallery:(id)media fromView:(UIView *)sourceView {
    sciConfirmThen(SCILocalized(@"Save to Gallery?"), ^{
        [self downloadHDMedia:media action:saveToGallery fromView:sourceView];
    });
}

+ (void)downloadAllAndSaveMediaToGallery:(id)carouselMedia context:(SCIActionContext)ctx {
    [self downloadAllChildrenOfMedia:carouselMedia
                        progressTitle:SCILocalized(@"Save all to Gallery?")
                                 done:^(NSArray<NSURL *> *files) {
        if (!files.count) {
            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to save")];
            return;
        }

        SCIGallerySaveMetadata *metadata = [[SCIGallerySaveMetadata alloc] init];
        metadata.source = (int16_t)sciGallerySourceFromContext(ctx);
        metadata.skipDedup = YES;
        @try { [SCIGalleryOriginController populateMetadata:metadata fromMedia:carouselMedia]; }
        @catch (__unused id e) {}

        NSArray<SCIGallerySaveMetadata *> *perFile = nil;
        [self bulkSaveFilesToGallery:files perFileMetadata:perFile defaultMetadata:metadata];
    }];
}

// Save files into the gallery one at a time, yielding to the runloop between
// iterations so the pill stays smooth. Per-file metadata array (when given)
// MUST match files.count; otherwise defaultMetadata is used for every file.
+ (void)bulkSaveFilesToGallery:(NSArray<NSURL *> *)files
                  perFileMetadata:(NSArray<SCIGallerySaveMetadata *> *)perFile
                  defaultMetadata:(SCIGallerySaveMetadata *)defaultMetadata {
    if (!files.count) return;
    SCIDownloadPillView *pill = [SCIDownloadPillView shared];
    [pill resetState];
    UIView *host = [UIApplication sharedApplication].keyWindow ?: topMostController().view;
    if (host) [pill showInView:host];
    [pill setText:SCILocalized(@"Saving to Gallery...")];
    [pill showBulkProgress:0 total:files.count];

    [self _bulkGallerySaveStep:files
                          index:0
                        success:0
                  perFileMetadata:perFile
                  defaultMetadata:defaultMetadata
                            pill:pill];
}

+ (void)_bulkGallerySaveStep:(NSArray<NSURL *> *)files
                         index:(NSUInteger)idx
                       success:(NSUInteger)success
                 perFileMetadata:(NSArray<SCIGallerySaveMetadata *> *)perFile
                 defaultMetadata:(SCIGallerySaveMetadata *)defaultMetadata
                           pill:(SCIDownloadPillView *)pill {
    if (idx >= files.count) {
        [pill showSuccess:[NSString stringWithFormat:SCILocalized(@"Saved %lu items to Gallery"),
                                                     (unsigned long)success]];
        [pill dismissAfterDelay:1.5];
        return;
    }

    [pill showBulkProgress:idx total:files.count];

    NSURL *fileURL = files[idx];
    SCIGallerySaveMetadata *m = (perFile && idx < perFile.count) ? perFile[idx] : defaultMetadata;
    NSString *ext = [fileURL.pathExtension lowercaseString];
    BOOL isVideo = [@[@"mp4", @"mov", @"m4v", @"webm"] containsObject:ext];
    NSError *err = nil;
    SCIGalleryFile *f = [SCIGalleryFile saveFileToGallery:fileURL
                                                    source:(SCIGallerySource)m.source
                                                 mediaType:(isVideo ? SCIGalleryMediaTypeVideo : SCIGalleryMediaTypeImage)
                                                folderPath:nil
                                                  metadata:m
                                                     error:&err];
    NSUInteger nextSuccess = success + ((f && !err) ? 1 : 0);
    if (err) NSLog(@"[RyukGram][Gallery] Bulk save error: %@", err);

    // Yield to the runloop so progress updates render before the next file.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _bulkGallerySaveStep:files
                              index:idx + 1
                            success:nextSuccess
                      perFileMetadata:perFile
                      defaultMetadata:defaultMetadata
                                pill:pill];
    });
}

+ (void)copyURLForMedia:(id)media {
    NSURL *url = [self bestURLForMedia:media];
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract media URL")]; return; }
    [[UIPasteboard generalPasteboard] setString:url.absoluteString];
    SCINotifySuccess(SCI_NOTIF_COPY_URL, SCILocalized(@"Copied download URL"), nil);
}

+ (void)copyCaptionForMedia:(id)media {
    NSString *caption = [self captionForMedia:media];
    if (!caption.length) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No caption on this post")]; return; }
    [[UIPasteboard generalPasteboard] setString:caption];
    SCINotifySuccess(SCI_NOTIF_COPY_CAPTION, SCILocalized(@"Copied caption"), nil);
}

// BFS search for a view of a given class within a subtree (bounded depth).
static UIView *sciFindSubviewOfClass(UIView *root, NSString *className, int maxDepth) {
    Class cls = NSClassFromString(className);
    if (!cls || !root) return nil;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    int processed = 0;
    while (queue.count && processed < 200) {
        UIView *v = queue.firstObject; [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:cls]) return v;
        if (processed < maxDepth * 50) {
            for (UIView *sub in v.subviews) [queue addObject:sub];
        }
        processed++;
    }
    return nil;
}

+ (void)triggerRepostForContext:(SCIActionContext)ctx sourceView:(UIView *)sourceView {
    if (ctx == SCIActionContextReels) {
        // Walk up to video cell, then BFS for the UFI bar.
        Class cellCls = NSClassFromString(@"IGSundialViewerVideoCell");
        if (!cellCls) cellCls = NSClassFromString(@"IGSundialViewerPhotoView");
        UIView *v = sourceView;
        while (v && cellCls && ![v isKindOfClass:cellCls]) v = v.superview;
        UIView *ufi = v ? sciFindSubviewOfClass(v, @"IGSundialViewerVerticalUFI", 8) : nil;
        if (ufi) {
            SEL noArg = NSSelectorFromString(@"_didTapRepostButton");
            if ([ufi respondsToSelector:noArg]) {
                ((void(*)(id, SEL))objc_msgSend)(ufi, noArg);
                return;
            }
            // Fallback: try the 1-arg variant (older IG?)
            SEL oneArg = @selector(_didTapRepostButton:);
            if ([ufi respondsToSelector:oneArg]) {
                ((void(*)(id, SEL, id))objc_msgSend)(ufi, oneArg, nil);
                return;
            }
        }
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Repost unavailable")];
        return;
    }

    // Feed: walk responder chain for IGFeedItemUFICell.
    UIResponder *r = sourceView;
    Class feedCell = NSClassFromString(@"IGFeedItemUFICell");
    while (r) {
        if (feedCell && [r isKindOfClass:feedCell]) break;
        r = [r nextResponder];
    }
    if (r) {
        @try {
            SEL s = @selector(UFIButtonBarDidTapOnRepost:);
            if ([r respondsToSelector:s]) {
                ((void(*)(id, SEL, id))objc_msgSend)(r, s, nil);
                return;
            }
        } @catch (__unused id e) {}
    }
    [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Repost unavailable")];
}

+ (void)openSettingsForContext:(SCIActionContext)ctx fromView:(UIView *)sourceView {
    UIWindow *win = sourceView.window;
    if (!win) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { win = w; break; }
        }
    }
    if (!win) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) { win = w; break; }
            }
            if (win) break;
        }
    }
    if (!win) return;
    [SCIUtils showSettingsVC:win atTopLevelEntry:sciSettingsTitleForContext(ctx)];
}


// MARK: - Carousel bulk actions

// Download all carousel children in parallel, call `done` when finished.
+ (void)downloadAllChildrenOfMedia:(id)media
                     progressTitle:(NSString *)title
                              done:(void(^)(NSArray<NSURL *> *fileURLs))done {
    NSArray *children = [self carouselChildrenForMedia:media];
    if (!children.count) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No carousel children")];
        return;
    }

    // Collect URLs first
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (id child in children) {
        NSURL *u = [self bestURLForMedia:child];
        if (u) [urls addObject:u];
    }
    if (!urls.count) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract any URLs")];
        return;
    }

    sciConfirmThen(title, ^{
        // Show the shared pill with bulk progress
        SCIDownloadPillView *pill = [SCIDownloadPillView shared];
        [pill resetState];
        [pill showBulkProgress:0 total:urls.count];
        UIView *hostView = [UIApplication sharedApplication].keyWindow ?: topMostController().view;
        if (hostView) [pill showInView:hostView];

        __block BOOL cancelled = NO;
        pill.onCancel = ^{ cancelled = YES; };

        dispatch_group_t group = dispatch_group_create();
        NSMutableArray<NSURL *> *files = [NSMutableArray array];
        NSLock *lock = [NSLock new];
        __block NSUInteger completed = 0;
        NSString *bulkStem = [self currentFilenameStem];

        NSUInteger __idx = 0;
        for (NSURL *url in urls) {
            if (cancelled) break;
            dispatch_group_enter(group);
            NSString *ext = [[url lastPathComponent] pathExtension];
            NSString *name = bulkStem
                ? [NSString stringWithFormat:@"%@_%lu", bulkStem, (unsigned long)(++__idx)]
                : [[NSUUID UUID] UUIDString];
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@.%@", name,
                              ext.length ? ext : @"jpg"]];
            NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
                downloadTaskWithURL:url completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
                if (!err && loc && !cancelled) {
                    NSError *mv = nil;
                    [[NSFileManager defaultManager] moveItemAtURL:loc
                                                           toURL:[NSURL fileURLWithPath:tmp]
                                                           error:&mv];
                    if (!mv) {
                        [lock lock];
                        [files addObject:[NSURL fileURLWithPath:tmp]];
                        [lock unlock];
                    }
                }
                [lock lock];
                completed++;
                NSUInteger c = completed;
                NSUInteger t = urls.count;
                [lock unlock];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [pill showBulkProgress:c total:t];
                });
                dispatch_group_leave(group);
            }];
            [task resume];
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (cancelled) {
                [pill showError:SCILocalized(@"Cancelled")];
                [pill dismissAfterDelay:1.0];
            } else if (files.count) {
                [pill showSuccess:[NSString stringWithFormat:SCILocalized(@"Downloaded %lu items"), (unsigned long)files.count]];
                [pill dismissAfterDelay:1.5];
                if (done) done([files copy]);
            } else {
                [pill showError:SCILocalized(@"No files downloaded")];
                [pill dismissAfterDelay:2.0];
            }
        });
    });
}

+ (void)downloadAllAndShareMedia:(id)carouselMedia {
    [self downloadAllChildrenOfMedia:carouselMedia
                        progressTitle:SCILocalized(@"Download all and share?")
                                 done:^(NSArray<NSURL *> *files) {
        if (!files.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to share")]; return; }
        UIViewController *top = topMostController();
        UIActivityViewController *vc = [[UIActivityViewController alloc]
                                         initWithActivityItems:files applicationActivities:nil];
        if (is_iPad()) {
            vc.popoverPresentationController.sourceView = top.view;
            vc.popoverPresentationController.sourceRect =
                CGRectMake(top.view.bounds.size.width/2.0, top.view.bounds.size.height/2.0, 1, 1);
        }
        [SCIPhotoAlbum armWatcherIfEnabled];
        [top presentViewController:vc animated:YES completion:nil];
    }];
}

+ (void)downloadAllAndSaveMedia:(id)carouselMedia {
    [self downloadAllChildrenOfMedia:carouselMedia
                        progressTitle:SCILocalized(@"Save all to Photos?")
                                 done:^(NSArray<NSURL *> *files) {
        if (!files.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to save")]; return; }
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status != PHAuthorizationStatusAuthorized) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
                });
                return;
            }
            BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];
            __block NSUInteger saved = 0;
            __block NSUInteger idx = 0;

            // Save sequentially (Photos API doesn't like parallel writes)
            __block void (^saveNext)(void) = ^{
                if (idx >= files.count) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        SCINotifySuccess(SCI_NOTIF_GALLERY_SAVE,
                                         [NSString stringWithFormat:SCILocalized(@"Saved %lu items"), (unsigned long)saved], nil);
                    });
                    saveNext = nil; // break retain cycle
                    return;
                }
                NSURL *f = files[idx];
                idx++;
                void (^step)(BOOL, NSError *) = ^(BOOL ok, NSError *e) {
                    if (ok) saved++;
                    if (saveNext) saveNext();
                };
                if (useAlbum) {
                    [SCIPhotoAlbum saveFileToAlbum:f completion:step];
                } else {
                    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                        NSString *ext = [[f pathExtension] lowercaseString];
                        BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];
                        PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
                        PHAssetResourceCreationOptions *opts = [[PHAssetResourceCreationOptions alloc] init];
                        opts.shouldMoveFile = YES;
                        [req addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto)
                                         fileURL:f options:opts];
                    } completionHandler:step];
                }
            };
            saveNext();
        }];
    }];
}

+ (void)copyAllURLsForMedia:(id)carouselMedia {
    NSArray *children = [self carouselChildrenForMedia:carouselMedia];
    if (!children.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Not a carousel")]; return; }
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    for (id child in children) {
        NSURL *u = [self bestURLForMedia:child];
        if (u) [urls addObject:u.absoluteString];
    }
    if (!urls.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No URLs found")]; return; }
    [[UIPasteboard generalPasteboard] setString:[urls componentsJoinedByString:@"\n"]];
    SCINotifySuccess(SCI_NOTIF_COPY_URL, [NSString stringWithFormat:SCILocalized(@"Copied %lu URLs"), (unsigned long)urls.count], nil);
}


// MARK: - Menu builder

// MARK: - Story-reel sibling discovery

// For multi-item story reels, gather every IGMedia in the current viewer's
// queue. Returns an empty array if the source view isn't inside a story viewer
// or there's only one item in the reel.
static NSArray *sciStoryReelMedias(UIView *sourceView) {
    if (!sourceView) return @[];

    UIViewController *storyVC = [SCIUtils nearestViewControllerForView:sourceView];
    if (!storyVC) {
        UIResponder *r = sourceView;
        while (r) {
            if ([NSStringFromClass([r class]) containsString:@"StoryViewer"]) {
                storyVC = (UIViewController *)r; break;
            }
            r = [r nextResponder];
        }
    }
    if (!storyVC) return @[];

    UIResponder *r = storyVC;
    Class svCls = NSClassFromString(@"IGStoryViewerViewController");
    while (r && !(svCls && [r isKindOfClass:svCls])) r = [r nextResponder];
    if (!r) r = (UIResponder *)storyVC;

    id vm = nil;
    if ([r respondsToSelector:@selector(currentViewModel)]) {
        vm = ((id(*)(id,SEL))objc_msgSend)(r, @selector(currentViewModel));
    }
    if (!vm) return @[];

    NSArray *reelItems = nil;
    for (NSString *sel in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
        if ([vm respondsToSelector:NSSelectorFromString(sel)]) {
            @try {
                id val = ((id(*)(id,SEL))objc_msgSend)(vm, NSSelectorFromString(sel));
                if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count] > 1) {
                    reelItems = val; break;
                }
            } @catch (__unused id e) {}
        }
    }

    if (!reelItems) {
        Class mc = NSClassFromString(@"IGMedia");
        unsigned int cnt = 0;
        Ivar *ivs = class_copyIvarList(object_getClass(vm), &cnt);
        for (unsigned int i = 0; i < cnt; i++) {
            const char *type = ivar_getTypeEncoding(ivs[i]);
            if (!type || type[0] != '@') continue;
            @try {
                id val = object_getIvar(vm, ivs[i]);
                if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count] > 1) {
                    id first = [(NSArray *)val firstObject];
                    if ((mc && [first isKindOfClass:mc]) ||
                        (first && [first respondsToSelector:@selector(media)])) {
                        reelItems = val; break;
                    }
                }
            } @catch (__unused id e) {}
        }
        if (ivs) free(ivs);
    }

    if (reelItems.count <= 1) return @[];

    NSMutableArray *medias = [NSMutableArray array];
    Class mc = NSClassFromString(@"IGMedia");
    for (id item in reelItems) {
        if (mc && [item isKindOfClass:mc]) {
            [medias addObject:item];
            continue;
        }
        for (NSString *sel in @[@"media", @"storyItem", @"item", @"mediaItem"]) {
            if ([item respondsToSelector:NSSelectorFromString(sel)]) {
                @try {
                    id m = ((id(*)(id,SEL))objc_msgSend)(item, NSSelectorFromString(sel));
                    if (m && mc && [m isKindOfClass:mc]) { [medias addObject:m]; break; }
                } @catch (__unused id e) {}
            }
        }
    }
    return medias.count > 1 ? medias : @[];
}

// Resolve carousel parent media: walks up sourceView's superviews looking for
// an `_mediaPassthrough` ivar (reels) or sibling cells holding the carousel
// parent (feed). Returns `media` itself when no parent is found.
static id sciCarouselParentMedia(id media, UIView *sourceView) {
    if (!media || [SCIMediaActions isCarouselMedia:media]) return media;

    // Path 1: _mediaPassthrough ivar (reels).
    UIView *v = sourceView;
    while (v) {
        Ivar mpi = class_getInstanceVariable([v class], "_mediaPassthrough");
        if (mpi) {
            id pm = object_getIvar(v, mpi);
            if (pm && [SCIMediaActions isCarouselMedia:pm]) return pm;
        }
        v = v.superview;
    }

    // Path 2: sibling IGFeedItemPageCell in the collection view (feed).
    v = sourceView;
    UICollectionViewCell *ufiCell = nil;
    UICollectionView *cv = nil;
    while (v) {
        if (!ufiCell && [v isKindOfClass:[UICollectionViewCell class]])
            ufiCell = (UICollectionViewCell *)v;
        if ([v isKindOfClass:[UICollectionView class]]) {
            cv = (UICollectionView *)v; break;
        }
        v = v.superview;
    }
    if (ufiCell && cv) {
        NSIndexPath *ufiPath = [cv indexPathForCell:ufiCell];
        if (ufiPath) {
            Class mc = NSClassFromString(@"IGMedia");
            for (UICollectionViewCell *cell in cv.visibleCells) {
                NSIndexPath *p = [cv indexPathForCell:cell];
                if (!p || p.section != ufiPath.section || cell == ufiCell) continue;
                if (![NSStringFromClass([cell class]) containsString:@"Page"]) continue;
                Ivar mi = class_getInstanceVariable(object_getClass(cell), "_media");
                if (!mi) continue;
                @try {
                    id pm = object_getIvar(cell, mi);
                    if (pm && mc && [pm isKindOfClass:mc] && [SCIMediaActions isCarouselMedia:pm]) {
                        return pm;
                    }
                } @catch (__unused id e) {}
            }
        }
    }

    return media;
}


// MARK: - Menu builder

+ (NSArray<SCIAction *> *)actionsForContext:(SCIActionContext)ctx
                                      media:(id)media
                                   fromView:(UIView *)sourceView {
    SCIActionSource source = sciSourceFromContext(ctx);
    SCIActionMenuConfig *config = [SCIActionMenuConfig configForSource:source];

    NSString *dateHeader = nil;
    if (config.showDate) {
        dateHeader = sciFormatDateHeader(sciExtractDateFromMedia(media));
    }

    NSString *ctxLabel = [self contextLabelForContext:ctx];
    void (^stampStemForMedia)(id) = ^(id m) {
        [SCIMediaActions setCurrentFilenameStem:[SCIMediaActions filenameStemForMedia:m contextLabel:ctxLabel]];
    };

    id parentMedia = sciCarouselParentMedia(media, sourceView);
    BOOL isCarousel = parentMedia ? [self isCarouselMedia:parentMedia] : NO;
    NSString *caption = parentMedia ? [self captionForMedia:parentMedia] : nil;

    NSArray *storyMedias = (ctx == SCIActionContextStories && !isCarousel)
        ? sciStoryReelMedias(sourceView)
        : @[];
    BOOL hasBulk = isCarousel || storyMedias.count > 1;

    __weak UIView *weakSource = sourceView;

    SCIAction *(^resolve)(NSString *) = ^SCIAction *(NSString *aid) {
        if ([aid isEqualToString:SCIAID_Expand]) {
            return [SCIAction actionWithTitle:SCILocalized(@"Expand")
                                         icon:@"arrow.up.left.and.arrow.down.right"
                                      handler:^{
                if (isCarousel) {
                    NSArray *children = [SCIMediaActions carouselChildrenForMedia:parentMedia];
                    NSMutableArray *items = [NSMutableArray array];
                    for (id child in children) {
                        NSURL *vURL = [SCIUtils getVideoUrlForMedia:(IGMedia *)child];
                        NSURL *p = [SCIUtils getPhotoUrlForMedia:(IGMedia *)child];
                        if (!vURL && !p) p = [SCIMediaActions bestURLForMedia:child];
                        if (vURL || p) [items addObject:[SCIMediaViewerItem itemWithVideoURL:vURL photoURL:p caption:caption]];
                    }
                    NSUInteger startIdx = 0;
                    if (media != parentMedia) {
                        NSUInteger idx = [children indexOfObjectIdenticalTo:media];
                        if (idx != NSNotFound) startIdx = idx;
                    }
                    if (items.count) {
                        [SCIMediaViewer showItems:items startIndex:startIdx];
                    } else {
                        [SCIMediaActions expandMedia:media fromView:weakSource caption:caption];
                    }
                } else {
                    [SCIMediaActions expandMedia:media fromView:weakSource caption:caption];
                }
            }];
        }

        if ([aid isEqualToString:SCIAID_ViewCover]) {
            BOOL hasCover = (ctx == SCIActionContextReels) ||
                            (ctx == SCIActionContextFeed && [SCIUtils getVideoUrlForMedia:(IGMedia *)media] != nil);
            if (!hasCover) return nil;
            return [SCIAction actionWithTitle:SCILocalized(@"View cover")
                                         icon:@"photo"
                                      handler:^{
                NSURL *cover = [SCIMediaActions coverURLForMedia:media];
                if (!cover) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No cover image")]; return; }
                [SCIMediaViewer showWithVideoURL:nil photoURL:cover caption:nil];
            }];
        }

        if ([aid isEqualToString:SCIAID_Repost]) {
            return [SCIAction actionWithTitle:SCILocalized(@"Repost")
                                         icon:@"arrow.2.squarepath"
                                      handler:^{
                NSURL *vidURL = [SCIUtils getVideoUrlForMedia:(IGMedia *)media];
                NSURL *imgURL = [SCIUtils getPhotoUrlForMedia:(IGMedia *)media];
                [SCIRepostSheet repostWithVideoURL:vidURL photoURL:imgURL];
            }];
        }

        if ([aid isEqualToString:SCIAID_ViewMentions]) {
            if (ctx != SCIActionContextStories) return nil;
            if (![SCIUtils getBoolPref:@"view_story_mentions"]) return nil;
            return [SCIAction actionWithTitle:SCILocalized(@"View mentions")
                                         icon:@"at"
                                      handler:^{
                UIView *v = weakSource;
                UIViewController *host = [SCIUtils nearestViewControllerForView:v];
                if (host) sciShowStoryMentions(host, v);
            }];
        }

        if ([aid isEqualToString:SCIAID_ToggleAudio]) {
            if (ctx != SCIActionContextStories) return nil;
            if (![SCIUtils getBoolPref:@"story_audio_toggle"]) return nil;
            BOOL audioOn = sciIsStoryAudioEnabled();
            NSString *title = audioOn ? SCILocalized(@"Mute audio") : SCILocalized(@"Unmute audio");
            NSString *icon = audioOn ? @"speaker.wave.2" : @"speaker.slash";
            return [SCIAction actionWithTitle:title icon:icon handler:^{ sciToggleStoryAudio(); }];
        }

        if ([aid isEqualToString:SCIAID_ExcludeUser]) {
            if (ctx != SCIActionContextStories) return nil;
            if (![SCIUtils getBoolPref:@"enable_story_user_exclusions"]) return nil;
            extern NSDictionary *sciOwnerInfoForView(UIView *);
            extern void sciRefreshAllVisibleOverlays(UIViewController *);
            extern __weak UIViewController *sciActiveStoryViewerVC;
            NSDictionary *ownerInfo = weakSource ? sciOwnerInfoForView(weakSource) : nil;
            NSString *ownerPK = ownerInfo[@"pk"];
            if (!ownerPK.length) return nil;
            BOOL inList = [SCIExcludedStoryUsers isInList:ownerPK];
            BOOL bs = [SCIExcludedStoryUsers isBlockSelectedMode];
            NSString *addLabel = bs ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude from seen");
            NSString *removeLabel = bs ? SCILocalized(@"Remove from block list") : SCILocalized(@"Remove from exclude list");
            NSString *title = inList ? removeLabel : addLabel;
            NSString *icon = inList ? @"eye.fill" : @"eye.slash";
            NSString *capturedPK = [ownerPK copy];
            NSString *capturedUser = [ownerInfo[@"username"] ?: @"" copy];
            NSString *capturedName = [ownerInfo[@"fullName"] ?: @"" copy];
            return [SCIAction actionWithTitle:title icon:icon handler:^{
                if (inList) {
                    [SCIExcludedStoryUsers removePK:capturedPK];
                    SCINotifySuccess(bs ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY,
                                     bs ? SCILocalized(@"Unblocked") : SCILocalized(@"Removed from list"), nil);
                } else {
                    [SCIExcludedStoryUsers addOrUpdateEntry:@{@"pk": capturedPK, @"username": capturedUser, @"fullName": capturedName}];
                    SCINotifySuccess(bs ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY,
                                     bs ? SCILocalized(@"Added to block list") : SCILocalized(@"Added to exclude list"), nil);
                }
                sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
            }];
        }

        if ([aid isEqualToString:SCIAID_CopyCaption]) {
            if (ctx == SCIActionContextStories) return nil;
            return [SCIAction actionWithTitle:SCILocalized(@"Copy caption")
                                         icon:@"text.quote"
                                      handler:^{
                [SCIMediaActions copyCaptionForMedia:parentMedia];
            }];
        }

        if ([aid isEqualToString:SCIAID_CopyURL]) {
            return [SCIAction actionWithTitle:SCILocalized(@"Copy media URL")
                                         icon:@"link"
                                      handler:^{
                [SCIMediaActions copyURLForMedia:media];
            }];
        }

        if ([aid isEqualToString:SCIAID_DownloadShare]) {
            return [SCIAction actionWithTitle:SCILocalized(@"Download and share")
                                         icon:@"square.and.arrow.up"
                                      handler:^{
                stampStemForMedia(media);
                sciStampGalleryMetadataForMedia(media, ctx);
                [SCIMediaActions downloadAndShareMedia:media];
            }];
        }

        if ([aid isEqualToString:SCIAID_DownloadSave]) {
            return [SCIAction actionWithTitle:SCILocalized(@"Download to Photos")
                                         icon:@"square.and.arrow.down"
                                      handler:^{
                stampStemForMedia(media);
                sciStampGalleryMetadataForMedia(media, ctx);
                [SCIMediaActions downloadAndSaveMedia:media];
            }];
        }

        if ([aid isEqualToString:SCIAID_DownloadGallery]) {
            if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;
            return [SCIAction actionWithTitle:SCILocalized(@"Download to Gallery")
                                         icon:@"photo.on.rectangle.angled"
                                      handler:^{
                stampStemForMedia(media);
                sciStampGalleryMetadataForMedia(media, ctx);
                [SCIMediaActions downloadAndSaveMediaToGallery:media fromView:weakSource];
            }];
        }

        if ([aid isEqualToString:SCIAID_BulkCopyURLs]) {
            if (!hasBulk) return nil;
            id bulkSource = isCarousel ? parentMedia : nil;
            NSArray *capturedMedias = isCarousel ? nil : storyMedias;
            return [SCIAction actionWithTitle:SCILocalized(@"Copy all URLs")
                                         icon:@"doc.on.doc"
                                      handler:^{
                if (bulkSource) {
                    [SCIMediaActions copyAllURLsForMedia:bulkSource];
                    return;
                }
                NSMutableArray *urls = [NSMutableArray array];
                for (id m in capturedMedias) {
                    NSURL *u = [SCIMediaActions bestURLForMedia:m];
                    if (u) [urls addObject:u.absoluteString];
                }
                if (!urls.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No URLs found")]; return; }
                [[UIPasteboard generalPasteboard] setString:[urls componentsJoinedByString:@"\n"]];
                SCINotifySuccess(SCI_NOTIF_COPY_URL, [NSString stringWithFormat:SCILocalized(@"Copied %lu URLs"), (unsigned long)urls.count], nil);
            }];
        }

        if ([aid isEqualToString:SCIAID_BulkDownloadShare]) {
            if (!hasBulk) return nil;
            if (isCarousel) {
                id bulkSource = parentMedia;
                return [SCIAction actionWithTitle:SCILocalized(@"Download and share all")
                                             icon:@"square.and.arrow.up.on.square"
                                          handler:^{
                    stampStemForMedia(bulkSource);
                    [SCIMediaActions downloadAllAndShareMedia:bulkSource];
                }];
            }
            NSArray *capturedMedias = storyMedias;
            return [SCIAction actionWithTitle:SCILocalized(@"Download and share all")
                                         icon:@"square.and.arrow.up.on.square"
                                      handler:^{
                NSMutableArray *urls = [NSMutableArray array];
                for (id m in capturedMedias) {
                    NSURL *u = [SCIMediaActions bestURLForMedia:m];
                    if (u) [urls addObject:u];
                }
                if (!urls.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to download")]; return; }
                stampStemForMedia(capturedMedias.firstObject);
                [SCIMediaActions bulkDownloadURLs:urls title:SCILocalized(@"Download all stories and share?") done:^(NSArray<NSURL *> *files) {
                    if (!files.count) return;
                    UIViewController *top = topMostController();
                    UIActivityViewController *vc = [[UIActivityViewController alloc]
                                                      initWithActivityItems:files applicationActivities:nil];
                    [SCIPhotoAlbum armWatcherIfEnabled];
                    [top presentViewController:vc animated:YES completion:nil];
                }];
            }];
        }

        if ([aid isEqualToString:SCIAID_BulkDownloadSave]) {
            if (!hasBulk) return nil;
            if (isCarousel) {
                id bulkSource = parentMedia;
                return [SCIAction actionWithTitle:SCILocalized(@"Download all to Photos")
                                             icon:@"square.and.arrow.down.on.square"
                                          handler:^{
                    stampStemForMedia(bulkSource);
                    [SCIMediaActions downloadAllAndSaveMedia:bulkSource];
                }];
            }
            NSArray *capturedMedias = storyMedias;
            return [SCIAction actionWithTitle:SCILocalized(@"Download all to Photos")
                                         icon:@"square.and.arrow.down.on.square"
                                      handler:^{
                NSMutableArray *urls = [NSMutableArray array];
                for (id m in capturedMedias) {
                    NSURL *u = [SCIMediaActions bestURLForMedia:m];
                    if (u) [urls addObject:u];
                }
                if (!urls.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to download")]; return; }
                stampStemForMedia(capturedMedias.firstObject);
                [SCIMediaActions bulkDownloadURLs:urls title:SCILocalized(@"Download all to Photos") done:^(NSArray<NSURL *> *files) {
                    [SCIMediaActions bulkSaveFiles:files];
                }];
            }];
        }

        if ([aid isEqualToString:SCIAID_BulkDownloadGallery]) {
            if (!hasBulk) return nil;
            if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;
            if (isCarousel) {
                id bulkSource = parentMedia;
                return [SCIAction actionWithTitle:SCILocalized(@"Download all to Gallery")
                                             icon:@"square.stack.3d.down.right"
                                          handler:^{
                    stampStemForMedia(bulkSource);
                    [SCIMediaActions downloadAllAndSaveMediaToGallery:bulkSource context:ctx];
                }];
            }
            NSArray *capturedMedias = storyMedias;
            return [SCIAction actionWithTitle:SCILocalized(@"Download all to Gallery")
                                         icon:@"square.stack.3d.down.right"
                                      handler:^{
                NSMutableArray *urls = [NSMutableArray array];
                for (id m in capturedMedias) {
                    NSURL *u = [SCIMediaActions bestURLForMedia:m];
                    if (u) [urls addObject:u];
                }
                if (!urls.count) {
                    [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to download")];
                    return;
                }
                stampStemForMedia(capturedMedias.firstObject);
                [SCIMediaActions bulkDownloadURLs:urls title:SCILocalized(@"Download all to Gallery") done:^(NSArray<NSURL *> *files) {
                    if (!files.count) return;
                    NSMutableArray<SCIGallerySaveMetadata *> *perFile = [NSMutableArray arrayWithCapacity:files.count];
                    for (NSUInteger i = 0; i < files.count; i++) {
                        SCIGallerySaveMetadata *m = [[SCIGallerySaveMetadata alloc] init];
                        m.source = (int16_t)sciGallerySourceFromContext(ctx);
                        m.skipDedup = YES;
                        if (i < capturedMedias.count) {
                            @try { [SCIGalleryOriginController populateMetadata:m fromMedia:capturedMedias[i]]; }
                            @catch (__unused id e) {}
                        }
                        [perFile addObject:m];
                    }
                    [SCIMediaActions bulkSaveFilesToGallery:files
                                            perFileMetadata:perFile
                                            defaultMetadata:perFile.firstObject];
                }];
            }];
        }

        if ([aid isEqualToString:SCIAID_Settings]) {
            NSString *settingsTitle = [NSString stringWithFormat:SCILocalized(@"%@ settings"),
                                       sciSettingsTitleForContext(ctx)];
            return [SCIAction actionWithTitle:settingsTitle
                                         icon:@"gearshape"
                                      handler:^{
                [SCIMediaActions openSettingsForContext:ctx fromView:weakSource];
            }];
        }

        return nil;
    };

    return [SCIActionMenu actionsForConfig:config dateHeader:dateHeader resolver:resolve];
}

static BOOL sciFireActionWithIDInList(NSArray<SCIAction *> *items, NSString *aid) {
    for (SCIAction *a in items) {
        if (a.isSeparator) continue;
        if (a.children.count) {
            if (sciFireActionWithIDInList(a.children, aid)) return YES;
        }
        if (a.actionID.length && [a.actionID isEqualToString:aid] && a.handler) {
            a.handler();
            return YES;
        }
    }
    return NO;
}

+ (BOOL)executeActionForContext:(SCIActionContext)ctx
                       actionID:(NSString *)aid
                          media:(id)media
                       fromView:(UIView *)sourceView {
    if (!aid.length || [aid isEqualToString:@"menu"]) return NO;
    NSArray<SCIAction *> *flat = [self actionsForContext:ctx media:media fromView:sourceView];
    return sciFireActionWithIDInList(flat, aid);
}


// MARK: - Bulk URL download helpers (used by story reel + carousel)

+ (void)bulkDownloadURLs:(NSArray<NSURL *> *)urls
                   title:(NSString *)title
                    done:(void(^)(NSArray<NSURL *> *fileURLs))done {
    if (!urls.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No URLs")]; return; }

    sciConfirmThen(title, ^{
        SCIDownloadPillView *pill = [SCIDownloadPillView shared];
        [pill resetState];
        [pill showBulkProgress:0 total:urls.count];
        UIView *hostView = [UIApplication sharedApplication].keyWindow ?: topMostController().view;
        if (hostView) [pill showInView:hostView];

        __block BOOL cancelled = NO;
        pill.onCancel = ^{ cancelled = YES; };

        dispatch_group_t group = dispatch_group_create();
        NSMutableArray<NSURL *> *files = [NSMutableArray array];
        NSLock *lock = [NSLock new];
        __block NSUInteger completed = 0;
        NSString *bulkStem2 = [self currentFilenameStem];

        NSUInteger __idx2 = 0;
        for (NSURL *url in urls) {
            if (cancelled) break;
            dispatch_group_enter(group);
            NSString *ext = [[url lastPathComponent] pathExtension];
            NSString *name = bulkStem2
                ? [NSString stringWithFormat:@"%@_%lu", bulkStem2, (unsigned long)(++__idx2)]
                : [[NSUUID UUID] UUIDString];
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@.%@", name,
                              ext.length ? ext : @"jpg"]];
            NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
                downloadTaskWithURL:url completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
                if (!err && loc && !cancelled) {
                    NSError *mv = nil;
                    [[NSFileManager defaultManager] moveItemAtURL:loc
                                                           toURL:[NSURL fileURLWithPath:tmp]
                                                           error:&mv];
                    if (!mv) {
                        [lock lock]; [files addObject:[NSURL fileURLWithPath:tmp]]; [lock unlock];
                    }
                }
                [lock lock]; completed++; NSUInteger c = completed; [lock unlock];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [pill showBulkProgress:c total:urls.count];
                });
                dispatch_group_leave(group);
            }];
            [task resume];
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (cancelled) {
                [pill showError:SCILocalized(@"Cancelled")];
                [pill dismissAfterDelay:1.0];
            } else if (files.count) {
                [pill showSuccess:[NSString stringWithFormat:SCILocalized(@"Downloaded %lu items"), (unsigned long)files.count]];
                [pill dismissAfterDelay:1.5];
                if (done) done([files copy]);
            } else {
                [pill showError:SCILocalized(@"No files downloaded")];
                [pill dismissAfterDelay:2.0];
            }
        });
    });
}

+ (void)bulkSaveFiles:(NSArray<NSURL *> *)files {
    if (!files.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to save")]; return; }
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
            });
            return;
        }
        BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];
        __block NSUInteger saved = 0;
        __block NSUInteger idx = 0;
        __block void (^saveNext)(void) = ^{
            if (idx >= files.count) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    SCINotifySuccess(SCI_NOTIF_GALLERY_SAVE,
                                     [NSString stringWithFormat:SCILocalized(@"Saved %lu items"), (unsigned long)saved], nil);
                });
                saveNext = nil;
                return;
            }
            NSURL *f = files[idx]; idx++;
            void (^step)(BOOL, NSError *) = ^(BOOL ok, NSError *e) {
                if (ok) saved++;
                if (saveNext) saveNext();
            };
            if (useAlbum) {
                [SCIPhotoAlbum saveFileToAlbum:f completion:step];
            } else {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    NSString *ext = [[f pathExtension] lowercaseString];
                    BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];
                    PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
                    PHAssetResourceCreationOptions *opts = [PHAssetResourceCreationOptions new];
                    opts.shouldMoveFile = YES;
                    [req addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto)
                                     fileURL:f options:opts];
                } completionHandler:step];
            }
        };
        saveNext();
    }];
}

@end
