#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import <objc/runtime.h>

static SCIDownloadDelegate *imageDownloadDelegate;
static SCIDownloadDelegate *videoDownloadDelegate;

static DownloadAction sciGetDownloadAction() {
    NSString *method = [SCIUtils getStringPref:@"dw_save_action"];
    if ([method isEqualToString:@"photos"]) return saveToPhotos;
    return share;
}

static void initDownloaders () {
    // Re-init each time to pick up the current save action preference
    DownloadAction action = sciGetDownloadAction();
    DownloadAction imgAction = (action == saveToPhotos) ? saveToPhotos : quickLook;
    imageDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:imgAction showProgress:NO];
    videoDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:YES];
}

// Helper: run a download block with optional confirmation dialog
static void sciConfirmAndDownload(NSString *title, void(^downloadBlock)(void)) {
    if ([SCIUtils getBoolPref:@"dw_confirm"]) {
        [SCIUtils showConfirmation:downloadBlock title:title];
    } else {
        downloadBlock();
    }
}

// Helper: recursively search within a view tree for downloadable media (bounded to one post)
static BOOL sciFindAndDownloadMediaInView(UIView *root) {
    if (!root) return NO;

    // Check for video media via mediaCellFeedItem
    if ([root respondsToSelector:@selector(mediaCellFeedItem)]) {
        IGMedia *media = [root performSelector:@selector(mediaCellFeedItem)];
        if (media) {
            NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:media];
            if (videoUrl) {
                initDownloaders();
                [videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:[[videoUrl lastPathComponent] pathExtension] hudLabel:nil];
                return YES;
            }
            NSURL *photoUrl = [SCIUtils getPhotoUrlForMedia:media];
            if (photoUrl) {
                initDownloaders();
                [imageDownloadDelegate downloadFileWithURL:photoUrl fileExtension:[[photoUrl lastPathComponent] pathExtension] hudLabel:nil];
                return YES;
            }
        }
    }

    // Check for IGFeedPhotoView with delegate chain
    if ([root isKindOfClass:NSClassFromString(@"IGFeedPhotoView")] && [root respondsToSelector:@selector(delegate)]) {
        id delegate = [root performSelector:@selector(delegate)];
        if ([delegate isKindOfClass:NSClassFromString(@"IGFeedItemPhotoCell")]) {
            @try {
                Ivar cfgIvar = class_getInstanceVariable([delegate class], "_configuration");
                if (cfgIvar) {
                    id cfg = object_getIvar(delegate, cfgIvar);
                    if (cfg) {
                        Ivar photoIvar = class_getInstanceVariable([cfg class], "_photo");
                        if (photoIvar) {
                            IGPhoto *photo = object_getIvar(cfg, photoIvar);
                            NSURL *photoUrl = [SCIUtils getPhotoUrl:photo];
                            if (photoUrl) {
                                initDownloaders();
                                [imageDownloadDelegate downloadFileWithURL:photoUrl fileExtension:[[photoUrl lastPathComponent] pathExtension] hudLabel:nil];
                                return YES;
                            }
                        }
                    }
                }
            } @catch (NSException *e) {}
        }
        if ([delegate isKindOfClass:NSClassFromString(@"IGFeedItemPagePhotoCell")]) {
            @try {
                if ([delegate respondsToSelector:@selector(pagePhotoPost)]) {
                    id pagePhotoPost = [delegate performSelector:@selector(pagePhotoPost)];
                    if (pagePhotoPost && [pagePhotoPost respondsToSelector:@selector(photo)]) {
                        IGPhoto *photo = [pagePhotoPost performSelector:@selector(photo)];
                        NSURL *photoUrl = [SCIUtils getPhotoUrl:photo];
                        if (photoUrl) {
                            initDownloaders();
                            [imageDownloadDelegate downloadFileWithURL:photoUrl fileExtension:[[photoUrl lastPathComponent] pathExtension] hudLabel:nil];
                            return YES;
                        }
                    }
                }
            } @catch (NSException *e) {}
        }
    }

    // Recurse into subviews
    for (UIView *sub in root.subviews) {
        if (sciFindAndDownloadMediaInView(sub)) return YES;
    }
    return NO;
}

// Helper: find IGMedia from a cell using runtime ivar scanning
// Avoids property getters which can cause EXC_BAD_ACCESS on certain IG versions
static IGMedia * _Nullable sciGetMediaFromView(UIView *view) {
    if (!view) return nil;

    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList([view class], &ivarCount);
    if (!ivars) return nil;

    IGMedia *found = nil;
    Class mediaClass = NSClassFromString(@"IGMedia");

    for (unsigned int i = 0; i < ivarCount; i++) {
        const char *name = ivar_getName(ivars[i]);
        if (!name) continue;

        NSString *ivarName = [NSString stringWithUTF8String:name];
        NSString *lower = [ivarName lowercaseString];

        if ([lower containsString:@"video"] || [lower containsString:@"media"] || [lower containsString:@"item"]) {
            id value = object_getIvar(view, ivars[i]);
            if (value && mediaClass && [value isKindOfClass:mediaClass]) {
                found = (IGMedia *)value;
                NSLog(@"[SCInsta] Found IGMedia in ivar '%@' of %@", ivarName, NSStringFromClass([view class]));
                break;
            }
        }
    }

    free(ivars);
    return found;
}

// Helper: walk superview chain to find a view of a given class
static UIView * _Nullable sciFindSuperviewOfClass(UIView *view, NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return nil;
    UIView *current = view.superview;
    int depth = 0;
    while (current && depth < 15) {
        if ([current isKindOfClass:cls]) return current;
        current = current.superview;
        depth++;
    }
    return nil;
}

// Helper: show debug ivar dump when media extraction fails (survives IG updates)
static void sciShowDebugIvarDump(UIView *cell) {
    NSMutableString *debug = [NSMutableString stringWithFormat:@"No IGMedia found in %@\n\nIvars:\n", NSStringFromClass([cell class])];
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList([cell class], &count);
    for (unsigned int i = 0; i < count && i < 50; i++) {
        const char *name = ivar_getName(ivars[i]);
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (name) [debug appendFormat:@"%s (%s)\n", name, type ? type : "?"];
    }
    if (ivars) free(ivars);

    NSLog(@"[SCInsta] Debug: %@", debug);

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"RyukGram Debug"
                                                                      message:debug
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Copy & Close" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [[UIPasteboard generalPasteboard] setString:debug];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *topVC = topMostController();
        if (topVC) [topVC presentViewController:alert animated:YES completion:nil];
    });
}

// Whether download buttons (not long-press) are enabled
static BOOL sciUseDownloadButtons() {
    return [[SCIUtils getStringPref:@"dw_method"] isEqualToString:@"button"];
}


/* * Feed * */

// Download feed images
%hook IGFeedPhotoView
- (void)didMoveToSuperview {
    %orig;

    if (![SCIUtils getBoolPref:@"dw_feed_posts"]) return;

    if (sciUseDownloadButtons()) {
        [self sciAddDownloadButton];
    } else {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)sciAddDownloadButton {
    if ([self viewWithTag:1338]) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = 1338;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    [btn setImage:[UIImage systemImageNamed:@"arrow.down.to.line" withConfiguration:config] forState:UIControlStateNormal];
    btn.tintColor = [UIColor whiteColor];
    btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    btn.layer.cornerRadius = 12;
    btn.clipsToBounds = YES;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:@selector(sciDownloadBtnTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:btn];

    [NSLayoutConstraint activateConstraints:@[
        [btn.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [btn.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        [btn.widthAnchor constraintEqualToConstant:24],
        [btn.heightAnchor constraintEqualToConstant:24]
    ]];
}
%new - (void)sciDownloadBtnTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformMakeScale(0.75, 0.75); }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformIdentity; }]; }];

    sciConfirmAndDownload(@"Download photo?", ^{
        [self handleLongPress:nil];
    });
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender && sender.state != UIGestureRecognizerStateBegan) return;

    IGPhoto *photo;

    if ([self.delegate isKindOfClass:%c(IGFeedItemPhotoCell)]) {
        IGFeedItemPhotoCellConfiguration *_configuration = MSHookIvar<IGFeedItemPhotoCellConfiguration *>(self.delegate, "_configuration");
        if (!_configuration) return;
        photo = MSHookIvar<IGPhoto *>(_configuration, "_photo");
    }
    else if ([self.delegate isKindOfClass:%c(IGFeedItemPagePhotoCell)]) {
        IGFeedItemPagePhotoCell *pagePhotoCell = self.delegate;
        photo = pagePhotoCell.pagePhotoPost.photo;
    }

    NSURL *photoUrl = [SCIUtils getPhotoUrl:photo];
    if (!photoUrl) {
        [SCIUtils showErrorHUDWithDescription:@"Could not extract photo url from post"];
        return;
    }

    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:photoUrl
                                 fileExtension:[[photoUrl lastPathComponent]pathExtension]
                                      hudLabel:nil];
}
%end

// Download feed videos
%hook IGModernFeedVideoCell.IGModernFeedVideoCell
- (void)didMoveToSuperview {
    %orig;

    if (![SCIUtils getBoolPref:@"dw_feed_posts"]) return;

    if (sciUseDownloadButtons()) {
        [self sciAddDownloadButton];
    } else {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)sciAddDownloadButton {
    UIView *selfView = (UIView *)self;
    if ([selfView viewWithTag:1338]) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = 1338;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    [btn setImage:[UIImage systemImageNamed:@"arrow.down.to.line" withConfiguration:config] forState:UIControlStateNormal];
    btn.tintColor = [UIColor whiteColor];
    btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    btn.layer.cornerRadius = 12;
    btn.clipsToBounds = YES;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:@selector(sciDownloadBtnTapped:) forControlEvents:UIControlEventTouchUpInside];
    [selfView addSubview:btn];

    [NSLayoutConstraint activateConstraints:@[
        [btn.leadingAnchor constraintEqualToAnchor:selfView.leadingAnchor constant:10],
        [btn.bottomAnchor constraintEqualToAnchor:selfView.bottomAnchor constant:-10],
        [btn.widthAnchor constraintEqualToConstant:24],
        [btn.heightAnchor constraintEqualToConstant:24]
    ]];
}
%new - (void)sciDownloadBtnTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformMakeScale(0.75, 0.75); }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformIdentity; }]; }];

    sciConfirmAndDownload(@"Download video?", ^{
        [self handleLongPress:nil];
    });
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender && sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:[self mediaCellFeedItem]];
    if (!videoUrl) {
        [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from post"];
        return;
    }

    initDownloaders();
    [videoDownloadDelegate downloadFileWithURL:videoUrl
                                 fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end



/* * Reels * */

// Download reels (photos) — long press only when gesture mode selected
%hook IGSundialViewerPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_reels"] && !sciUseDownloadButtons()) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        IGPhoto *_photo = nil;
        @try {
            _photo = MSHookIvar<IGPhoto *>(self, "_photo");
        } @catch (NSException *e) {}

        if (!_photo) {
            [SCIUtils showErrorHUDWithDescription:@"Could not access reel photo"];
            return;
        }

        NSURL *photoUrl = [SCIUtils getPhotoUrl:_photo];
        if (!photoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract photo url from reel"];
            return;
        }

        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:photoUrl
                                     fileExtension:[[photoUrl lastPathComponent]pathExtension]
                                          hudLabel:nil];
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Reel photo download error: %@", exception);
        [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:@"Reel photo download failed: %@", exception.reason]];
    }
}
%end

// Download reels (videos) — long press only when gesture mode selected
%hook IGSundialViewerVideoCell
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_reels"] && !sciUseDownloadButtons()) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        IGMedia *media = sciGetMediaFromView(self);
        if (!media) {
            [SCIUtils showErrorHUDWithDescription:@"Could not access reel media"];
            return;
        }

        NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:media];
        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from reel"];
            return;
        }

        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Reel download error: %@", exception);
        [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:@"Reel download failed: %@", exception.reason]];
    }
}
%end

// Download button on reels vertical UFI (like/comment/share sidebar)
%hook IGSundialViewerVerticalUFI
- (void)didMoveToSuperview {
    %orig;

    if (![SCIUtils getBoolPref:@"dw_reels"]) return;
    if (!sciUseDownloadButtons()) return;
    if (!self.superview) return;

    // Add to superview so we're not clipped by the narrow 29pt UFI
    UIView *parent = self.superview;
    if ([parent viewWithTag:1337]) return;

    UIButton *downloadBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    downloadBtn.tag = 1337;

    // Match IG reel sidebar style: outline icon, semi-transparent white
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
    UIImage *icon = [UIImage systemImageNamed:@"arrow.down" withConfiguration:config];
    [downloadBtn setImage:icon forState:UIControlStateNormal];
    downloadBtn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.9];

    downloadBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    downloadBtn.layer.shadowOffset = CGSizeMake(0, 1);
    downloadBtn.layer.shadowOpacity = 0.5;
    downloadBtn.layer.shadowRadius = 3;

    downloadBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [downloadBtn addTarget:self action:@selector(sciDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
    [parent addSubview:downloadBtn];

    [NSLayoutConstraint activateConstraints:@[
        [downloadBtn.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [downloadBtn.bottomAnchor constraintEqualToAnchor:self.topAnchor constant:-10],
        [downloadBtn.widthAnchor constraintEqualToConstant:40],
        [downloadBtn.heightAnchor constraintEqualToConstant:40]
    ]];
}

%new - (void)sciDownloadTapped:(UIButton *)sender {
    NSLog(@"[SCInsta] Reel download button tapped");

    // Haptic + visual feedback
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [UIView animateWithDuration:0.1 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.75, 0.75);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            sender.transform = CGAffineTransformIdentity;
        }];
    }];

    sciConfirmAndDownload(@"Download reel?", ^{
        // Find IGSundialViewerVideoCell in superview chain
        UIView *videoCell = sciFindSuperviewOfClass(self, @"IGSundialViewerVideoCell");

        if (videoCell) {
            IGMedia *media = sciGetMediaFromView(videoCell);
            if (media) {
                NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:media];
                if (videoUrl) {
                    initDownloaders();
                    [videoDownloadDelegate downloadFileWithURL:videoUrl
                                                 fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                                      hudLabel:nil];
                    return;
                }
                [SCIUtils showErrorHUDWithDescription:@"Could not extract video URL from reel"];
                return;
            }
            sciShowDebugIvarDump(videoCell);
            return;
        }

        // Try photo reel
        UIView *photoView = sciFindSuperviewOfClass(self, @"IGSundialViewerPhotoView");
        if (photoView) {
            unsigned int count = 0;
            Ivar *ivars = class_copyIvarList([photoView class], &count);
            Class photoClass = NSClassFromString(@"IGPhoto");
            for (unsigned int i = 0; i < count; i++) {
                const char *name = ivar_getName(ivars[i]);
                if (!name) continue;
                NSString *ivarName = [NSString stringWithUTF8String:name];
                if ([[ivarName lowercaseString] containsString:@"photo"]) {
                    id value = object_getIvar(photoView, ivars[i]);
                    if (value && photoClass && [value isKindOfClass:photoClass]) {
                        NSURL *photoUrl = [SCIUtils getPhotoUrl:(IGPhoto *)value];
                        if (photoUrl) {
                            free(ivars);
                            initDownloaders();
                            [imageDownloadDelegate downloadFileWithURL:photoUrl
                                                         fileExtension:[[photoUrl lastPathComponent] pathExtension]
                                                              hudLabel:nil];
                            return;
                        }
                    }
                }
            }
            if (ivars) free(ivars);
            sciShowDebugIvarDump(photoView);
            return;
        }

        [SCIUtils showErrorHUDWithDescription:@"Could not find reel cell in view hierarchy"];
    });
}
%end


/* * Stories * */

// Download story (images)
%hook IGStoryPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *photoUrl = [SCIUtils getPhotoUrlForMedia:[self item]];
    if (!photoUrl) {
        [SCIUtils showErrorHUDWithDescription:@"Could not extract photo url from story"];

        return;
    }

    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:photoUrl
                                 fileExtension:[[photoUrl lastPathComponent]pathExtension]
                                      hudLabel:nil];
}
%end

// Download story (videos)
%hook IGStoryModernVideoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:self.item];

    if (!videoUrl) {
        [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from story"];

        return;
    }

    initDownloaders();
    [videoDownloadDelegate downloadFileWithURL:videoUrl
                                 fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end

// Download story (videos, legacy)
%hook IGStoryVideoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *videoUrl;

    IGStoryFullscreenSectionController *captionDelegate = self.captionDelegate;
    if (captionDelegate) {
        videoUrl = [SCIUtils getVideoUrlForMedia:captionDelegate.currentStoryItem];
    }
    else {
        // Direct messages video player
        id parentVC = [SCIUtils nearestViewControllerForView:self];
        if (!parentVC || ![parentVC isKindOfClass:%c(IGDirectVisualMessageViewerController)]) return;

        IGDirectVisualMessageViewerViewModeAwareDataSource *_dataSource = MSHookIvar<IGDirectVisualMessageViewerViewModeAwareDataSource *>(parentVC, "_dataSource");
        if (!_dataSource) return;

        IGDirectVisualMessage *_currentMessage = MSHookIvar<IGDirectVisualMessage *>(_dataSource, "_currentMessage");
        if (!_currentMessage) return;

        IGVideo *rawVideo = _currentMessage.rawVideo;
        if (!rawVideo) return;

        videoUrl = [SCIUtils getVideoUrl:rawVideo];
    }

    if (!videoUrl) {
        [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from story"];

        return;
    }

    initDownloaders();
    [videoDownloadDelegate downloadFileWithURL:videoUrl
                                 fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end


/* * Profile pictures * */

%hook IGProfilePictureImageView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"save_profile"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    IGImageView *_imageView = MSHookIvar<IGImageView *>(self, "_imageView");
    if (!_imageView) return;

    IGImageSpecifier *imageSpecifier = _imageView.imageSpecifier;
    if (!imageSpecifier) return;

    NSURL *imageUrl = imageSpecifier.url;
    if (!imageUrl) return;

    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:imageUrl
                                 fileExtension:[[imageUrl lastPathComponent] pathExtension]
                                      hudLabel:@"Loading"];
}
%end
