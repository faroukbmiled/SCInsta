#import "SCIMediaActions.h"
#import "SCIMediaViewer.h"
#import "SCIRepostSheet.h"
#import "../SCIDashParser.h"
#import "../SCIFFmpeg.h"
#import "../SCIQualityPicker.h"
#import "../Utils.h"
#import "../Downloader/Download.h"
#import "../PhotoAlbum.h"
#import "../Features/StoriesAndMessages/SCIExcludedStoryUsers.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

// Retain the active download delegate so ARC doesn't kill it mid-download.
// Replaced on each new download — one active download at a time.
static SCIDownloadDelegate *sciActiveDownloadDelegate = nil;

// Story audio toggle — defined in StoryAudioToggle.xm (extern "C")
extern void sciToggleStoryAudio(void);
extern BOOL sciIsStoryAudioEnabled(void);

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
    if (!obj || !key) return nil;
    static Ivar fcIvar = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"IGAPIStorableObject");
        if (c) fcIvar = class_getInstanceVariable(c, "_fieldCache");
    });
    if (!fcIvar) return nil;
    id fc = nil;
    @try { fc = object_getIvar(obj, fcIvar); } @catch (__unused id e) { return nil; }
    if (![fc isKindOfClass:[NSDictionary class]]) return nil;
    id val = ((NSDictionary *)fc)[key];
    if (!val || [val isKindOfClass:[NSNull class]]) return nil;
    return val;
}

// Fresh download delegate (one active download at a time).
static SCIDownloadDelegate *sciMakeDownloader(DownloadAction action, BOOL progress) {
    return [[SCIDownloadDelegate alloc] initWithAction:action showProgress:progress];
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

        // saveToPhotos finishes the ticket after the PH completion fires.
        if (action != saveToPhotos) {
            [pill finishTicket:ticket successMessage:SCILocalized(@"HD download complete")];
        }

        switch (action) {
            case share:
                [SCIUtils showShareVC:outputURL];
                break;
            case quickLook:
                [SCIUtils showQuickLookVC:@[outputURL]];
                break;
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
    sciConfirmThen(SCILocalized(@"Download and share?"), ^{
        [self downloadHDMedia:media action:share fromView:sourceView];
    });
}

+ (void)downloadAndSaveMedia:(id)media {
    [self downloadAndSaveMedia:media fromView:nil];
}

+ (void)downloadAndSaveMedia:(id)media fromView:(UIView *)sourceView {
    sciConfirmThen(SCILocalized(@"Save to Photos?"), ^{
        [self downloadHDMedia:media action:saveToPhotos fromView:sourceView];
    });
}

+ (void)copyURLForMedia:(id)media {
    NSURL *url = [self bestURLForMedia:media];
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract media URL")]; return; }
    [[UIPasteboard generalPasteboard] setString:url.absoluteString];
    [SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Copied download URL")];
}

+ (void)copyCaptionForMedia:(id)media {
    NSString *caption = [self captionForMedia:media];
    if (!caption.length) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No caption on this post")]; return; }
    [[UIPasteboard generalPasteboard] setString:caption];
    [SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Copied caption")];
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

        for (NSURL *url in urls) {
            if (cancelled) break;
            dispatch_group_enter(group);
            NSString *ext = [[url lastPathComponent] pathExtension];
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@.%@", [[NSUUID UUID] UUIDString],
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
                        progressTitle:@"Download all and share?"
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
        if ([SCIUtils getBoolPref:@"save_to_ryukgram_album"]) {
            [SCIPhotoAlbum watchForNextSavedAsset];
        }
        [top presentViewController:vc animated:YES completion:nil];
    }];
}

+ (void)downloadAllAndSaveMedia:(id)carouselMedia {
    [self downloadAllChildrenOfMedia:carouselMedia
                        progressTitle:@"Save all to Photos?"
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
                        [SCIUtils showToastForDuration:2.0
                                                 title:[NSString stringWithFormat:SCILocalized(@"Saved %lu items"), (unsigned long)saved]];
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
    [SCIUtils showToastForDuration:1.5 title:[NSString stringWithFormat:SCILocalized(@"Copied %lu URLs"), (unsigned long)urls.count]];
}


// MARK: - Menu builder

+ (NSArray<SCIAction *> *)actionsForContext:(SCIActionContext)ctx
                                      media:(id)media
                                   fromView:(UIView *)sourceView {
    NSMutableArray<SCIAction *> *out = [NSMutableArray array];

    // Resolve parent media for carousel detection + bulk actions.
    id parentMedia = media;
    if (media && ![self isCarouselMedia:media]) {
        // Path 1: _mediaPassthrough ivar (reels)
        UIView *v = sourceView;
        while (v) {
            Ivar mpi = class_getInstanceVariable([v class], "_mediaPassthrough");
            if (mpi) {
                id pm = object_getIvar(v, mpi);
                if (pm && [self isCarouselMedia:pm]) { parentMedia = pm; break; }
            }
            v = v.superview;
        }

        // Path 2: sibling IGFeedItemPageCell in the collection view (feed)
        if (parentMedia == media) {
            v = sourceView;
            UICollectionViewCell *ufiCell = nil;
            UICollectionView *cv = nil;
            while (v) {
                if (!ufiCell && [v isKindOfClass:[UICollectionViewCell class]])
                    ufiCell = (UICollectionViewCell *)v;
                if ([v isKindOfClass:[UICollectionView class]]) { cv = (UICollectionView *)v; break; }
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
                            if (pm && mc && [pm isKindOfClass:mc] && [self isCarouselMedia:pm]) {
                                parentMedia = pm;
                                break;
                            }
                        } @catch (__unused id e) {}
                    }
                }
            }
        }
    }

    NSString *caption = parentMedia ? [self captionForMedia:parentMedia] : nil;
    BOOL isCarousel = parentMedia ? [self isCarouselMedia:parentMedia] : NO;
    __weak UIView *weakSource = sourceView;

    // --- Section 1: navigation ---
    [out addObject:[SCIAction actionWithTitle:SCILocalized(@"Expand")
                                         icon:@"arrow.up.left.and.arrow.down.right"
                                      handler:^{
        if (isCarousel) {
            NSArray *children = [SCIMediaActions carouselChildrenForMedia:parentMedia];
            NSMutableArray *items = [NSMutableArray array];
            for (id child in children) {
                NSURL *v = [SCIUtils getVideoUrlForMedia:(IGMedia *)child];
                NSURL *p = [SCIUtils getPhotoUrlForMedia:(IGMedia *)child];
                if (!v && !p) p = [SCIMediaActions bestURLForMedia:child];
                if (v || p) {
                    [items addObject:[SCIMediaViewerItem itemWithVideoURL:v photoURL:p caption:caption]];
                }
            }
            // Find current page index to start there
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
    }]];

    if (ctx == SCIActionContextReels || (ctx == SCIActionContextFeed && [SCIUtils getVideoUrlForMedia:(IGMedia *)media])) {
        [out addObject:[SCIAction actionWithTitle:SCILocalized(@"View cover")
                                             icon:@"photo"
                                          handler:^{
            NSURL *cover = [SCIMediaActions coverURLForMedia:media];
            if (!cover) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No cover image")]; return; }
            [SCIMediaViewer showWithVideoURL:nil photoURL:cover caption:nil];
        }]];
    }

    // Repost = save to Photos → open IG's native creation flow
    [out addObject:[SCIAction actionWithTitle:SCILocalized(@"Repost")
                                         icon:@"arrow.2.squarepath"
                                      handler:^{
        NSURL *vidURL = [SCIUtils getVideoUrlForMedia:(IGMedia *)media];
        NSURL *imgURL = [SCIUtils getPhotoUrlForMedia:(IGMedia *)media];
        [SCIRepostSheet repostWithVideoURL:vidURL photoURL:imgURL];
    }]];

    if (ctx == SCIActionContextStories) {
        if ([SCIUtils getBoolPref:@"view_story_mentions"]) {
            [out addObject:[SCIAction actionWithTitle:SCILocalized(@"View mentions")
                                                 icon:@"at"
                                              handler:^{
                UIView *v = weakSource;
                UIViewController *host = [SCIUtils nearestViewControllerForView:v];
                extern void sciShowStoryMentions(UIViewController *, UIView *);
                if (!host) return;
                sciShowStoryMentions(host, v);
            }]];
        }

        // Mute / unmute story audio
        if ([SCIUtils getBoolPref:@"story_audio_toggle"]) {
            BOOL audioOn = sciIsStoryAudioEnabled();
            NSString *audioTitle = audioOn ? SCILocalized(@"Mute audio") : SCILocalized(@"Unmute audio");
            NSString *audioIcon = audioOn ? @"speaker.wave.2" : @"speaker.slash";
            [out addObject:[SCIAction actionWithTitle:audioTitle
                                                 icon:audioIcon
                                              handler:^{ sciToggleStoryAudio(); }]];
        }
    }

    // Story user list management (add/remove from exclusion list).
    if (ctx == SCIActionContextStories && [SCIUtils getBoolPref:@"enable_story_user_exclusions"]) {
        extern NSDictionary *sciOwnerInfoForView(UIView *);
        extern void sciRefreshAllVisibleOverlays(UIViewController *);
        extern __weak UIViewController *sciActiveStoryViewerVC;
        NSDictionary *ownerInfo = sourceView ? sciOwnerInfoForView(sourceView) : nil;
        NSString *ownerPK = ownerInfo[@"pk"];
        if (ownerPK.length) {
            BOOL inList = [SCIExcludedStoryUsers isInList:ownerPK];
            BOOL bs = [SCIExcludedStoryUsers isBlockSelectedMode];
            NSString *addLabel = bs ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude from seen");
            NSString *removeLabel = bs ? SCILocalized(@"Remove from block list") : SCILocalized(@"Remove from exclude list");
            NSString *title = inList ? removeLabel : addLabel;
            NSString *icon = inList ? @"eye.fill" : @"eye.slash";
            NSString *capturedPK = [ownerPK copy];
            NSString *capturedUser = [ownerInfo[@"username"] ?: @"" copy];
            NSString *capturedName = [ownerInfo[@"fullName"] ?: @"" copy];
            [out addObject:[SCIAction actionWithTitle:title icon:icon handler:^{
                if (inList) {
                    [SCIExcludedStoryUsers removePK:capturedPK];
                    [SCIUtils showToastForDuration:2.0 title:bs ? SCILocalized(@"Unblocked") : SCILocalized(@"Removed from list")];
                } else {
                    [SCIExcludedStoryUsers addOrUpdateEntry:@{@"pk": capturedPK, @"username": capturedUser, @"fullName": capturedName}];
                    [SCIUtils showToastForDuration:2.0 title:bs ? SCILocalized(@"Added to block list") : SCILocalized(@"Added to exclude list")];
                }
                sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
            }]];
        }
    }

    if (ctx != SCIActionContextStories) {
        // Caption lives on the parent media (not on carousel children).
        [out addObject:[SCIAction actionWithTitle:SCILocalized(@"Copy caption")
                                             icon:@"text.quote"
                                          handler:^{
            [SCIMediaActions copyCaptionForMedia:parentMedia];
        }]];
    }

    NSString *settingsTitle = [NSString stringWithFormat:SCILocalized(@"%@ settings"),
                               sciSettingsTitleForContext(ctx)];
    [out addObject:[SCIAction actionWithTitle:settingsTitle
                                         icon:@"gearshape"
                                      handler:^{
        [SCIMediaActions openSettingsForContext:ctx fromView:weakSource];
    }]];

    // Section 2 — bulk download (carousels or multi-story reels)
    if (isCarousel) {
        // Bulk actions use the PARENT media (all children), not the current page
        id bulkMedia = parentMedia;
        [out addObject:[SCIAction separator]];
        NSArray<SCIAction *> *bulkChildren = @[
            [SCIAction actionWithTitle:SCILocalized(@"Copy all URLs") icon:@"doc.on.doc" handler:^{
                [SCIMediaActions copyAllURLsForMedia:bulkMedia];
            }],
            [SCIAction actionWithTitle:SCILocalized(@"Download and share all") icon:@"square.and.arrow.up.on.square" handler:^{
                [SCIMediaActions downloadAllAndShareMedia:bulkMedia];
            }],
            [SCIAction actionWithTitle:SCILocalized(@"Download all to Photos") icon:@"square.and.arrow.down.on.square" handler:^{
                [SCIMediaActions downloadAllAndSaveMedia:bulkMedia];
            }],
        ];
        NSUInteger childCount = [self carouselChildrenForMedia:bulkMedia].count;
        NSString *bulkTitle = childCount > 0
            ? [NSString stringWithFormat:SCILocalized(@"Download all (%lu)"), (unsigned long)childCount]
            : @"Download all";
        [out addObject:[SCIAction actionWithTitle:bulkTitle
                                             icon:@"square.stack.3d.down.right"
                                         children:bulkChildren]];
    }

    // Multi-story reel bulk actions
    if (ctx == SCIActionContextStories && !isCarousel) {
        // Read reel items from the story VC
        NSArray *reelItems = nil;
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
        if (storyVC) {
            // Walk to IGStoryViewerViewController
            UIResponder *r = storyVC;
            Class svCls = NSClassFromString(@"IGStoryViewerViewController");
            while (r && !(svCls && [r isKindOfClass:svCls])) r = [r nextResponder];
            if (!r) r = (UIResponder *)storyVC;

            id vm = nil;
            if ([r respondsToSelector:@selector(currentViewModel)])
                vm = ((id(*)(id,SEL))objc_msgSend)(r, @selector(currentViewModel));

            if (vm) {
                // Try selectors
                for (NSString *sel in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
                    if ([vm respondsToSelector:NSSelectorFromString(sel)]) {
                        @try {
                            id val = ((id(*)(id,SEL))objc_msgSend)(vm, NSSelectorFromString(sel));
                            if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count] > 1) {
                                reelItems = val;
                                break;
                            }
                        } @catch (__unused id e) {}
                    }
                }

                // Scan vm ivars for arrays
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
                                    reelItems = val;
                                    break;
                                }
                            }
                        } @catch (__unused id e) {}
                    }
                    if (ivs) free(ivs);
                }
            }
        }

        if (reelItems.count > 1) {
            // Extract IGMedia from each item (may be wrapped)
            NSMutableArray *storyMedias = [NSMutableArray array];
            Class mc = NSClassFromString(@"IGMedia");
            for (id item in reelItems) {
                if (mc && [item isKindOfClass:mc]) {
                    [storyMedias addObject:item];
                } else {
                    // Try to extract
                    for (NSString *sel in @[@"media", @"storyItem", @"item", @"mediaItem"]) {
                        if ([item respondsToSelector:NSSelectorFromString(sel)]) {
                            @try {
                                id m = ((id(*)(id,SEL))objc_msgSend)(item, NSSelectorFromString(sel));
                                if (m && mc && [m isKindOfClass:mc]) { [storyMedias addObject:m]; break; }
                            } @catch (__unused id e) {}
                        }
                    }
                }
            }

            if (storyMedias.count > 1) {
                [out addObject:[SCIAction separator]];

                NSArray *capturedMedias = [storyMedias copy];
                NSArray<SCIAction *> *storyBulk = @[
                    [SCIAction actionWithTitle:SCILocalized(@"Copy all URLs") icon:@"doc.on.doc" handler:^{
                        NSMutableArray *urls = [NSMutableArray array];
                        for (id m in capturedMedias) {
                            NSURL *u = [SCIMediaActions bestURLForMedia:m];
                            if (u) [urls addObject:u.absoluteString];
                        }
                        if (urls.count) {
                            [[UIPasteboard generalPasteboard] setString:[urls componentsJoinedByString:@"\n"]];
                            [SCIUtils showToastForDuration:1.5 title:[NSString stringWithFormat:SCILocalized(@"Copied %lu URLs"), (unsigned long)urls.count]];
                        }
                    }],
                    [SCIAction actionWithTitle:SCILocalized(@"Download and share all") icon:@"square.and.arrow.up.on.square" handler:^{
                        NSMutableArray *urls = [NSMutableArray array];
                        for (id m in capturedMedias) {
                            NSURL *u = [SCIMediaActions bestURLForMedia:m];
                            if (u) [urls addObject:u];
                        }
                        if (!urls.count) return;
                        [SCIMediaActions bulkDownloadURLs:urls title:SCILocalized(@"Download all stories and share?") done:^(NSArray<NSURL *> *files) {
                            if (!files.count) return;
                            UIViewController *top = topMostController();
                            UIActivityViewController *vc = [[UIActivityViewController alloc]
                                initWithActivityItems:files applicationActivities:nil];
                            [top presentViewController:vc animated:YES completion:nil];
                        }];
                    }],
                    [SCIAction actionWithTitle:SCILocalized(@"Download all to Photos") icon:@"square.and.arrow.down.on.square" handler:^{
                        NSMutableArray *urls = [NSMutableArray array];
                        for (id m in capturedMedias) {
                            NSURL *u = [SCIMediaActions bestURLForMedia:m];
                            if (u) [urls addObject:u];
                        }
                        if (!urls.count) return;
                        [SCIMediaActions bulkDownloadURLs:urls title:SCILocalized(@"Save all stories to Photos?") done:^(NSArray<NSURL *> *files) {
                            [SCIMediaActions bulkSaveFiles:files];
                        }];
                    }],
                ];
                [out addObject:[SCIAction actionWithTitle:[NSString stringWithFormat:SCILocalized(@"Download all (%lu)"), (unsigned long)storyMedias.count]
                                                     icon:@"square.stack.3d.down.right"
                                                 children:storyBulk]];
            }
        }
    }

    // --- Section 3: current media actions ---
    [out addObject:[SCIAction separator]];
    [out addObject:[SCIAction actionWithTitle:SCILocalized(@"Copy download URL")
                                         icon:@"link"
                                      handler:^{
        [SCIMediaActions copyURLForMedia:media];
    }]];
    [out addObject:[SCIAction actionWithTitle:SCILocalized(@"Download and share")
                                         icon:@"square.and.arrow.up"
                                      handler:^{
        [SCIMediaActions downloadAndShareMedia:media];
    }]];
    [out addObject:[SCIAction actionWithTitle:SCILocalized(@"Download to Photos")
                                         icon:@"square.and.arrow.down"
                                      handler:^{
        [SCIMediaActions downloadAndSaveMedia:media];
    }]];

    return [out copy];
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

        for (NSURL *url in urls) {
            if (cancelled) break;
            dispatch_group_enter(group);
            NSString *ext = [[url lastPathComponent] pathExtension];
            NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@.%@", [[NSUUID UUID] UUIDString],
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
                    [SCIUtils showToastForDuration:2.0
                                             title:[NSString stringWithFormat:SCILocalized(@"Saved %lu items"), (unsigned long)saved]];
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
