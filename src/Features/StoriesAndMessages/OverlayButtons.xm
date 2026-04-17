// Action + mark-seen buttons on story/DM visual message overlay
// Tags: [1339] eye  [1340] action  [1341] audio

#import "StoryHelpers.h"
#import "SCIExcludedThreads.h"
#import "SCIExcludedStoryUsers.h"
#import "../../ActionButton/SCIActionButton.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../Downloader/Download.h"

extern "C" BOOL sciSeenBypassActive;
extern "C" BOOL sciAdvanceBypassActive;
extern "C" NSMutableSet *sciAllowedSeenPKs;
extern "C" void sciAllowSeenForPK(id);
extern "C" BOOL sciIsCurrentStoryOwnerExcluded(void);
extern "C" NSDictionary *sciCurrentStoryOwnerInfo(void);
extern "C" NSDictionary *sciOwnerInfoForView(UIView *view);
extern "C" BOOL sciStorySeenToggleEnabled;
extern "C" void sciRefreshAllVisibleOverlays(UIViewController *storyVC);
extern "C" void sciTriggerStoryMarkSeen(UIViewController *storyVC);
extern "C" __weak UIViewController *sciActiveStoryViewerVC;
extern "C" void sciToggleStoryAudio(void);
extern "C" BOOL sciIsStoryAudioEnabled(void);
extern "C" void sciInitStoryAudioState(void);
extern "C" void sciResetStoryAudioState(void);
extern "C" void sciShowStoryMentions(UIViewController *, UIView *);

// ── Disappearing DM media ──
static NSURL *sciDisappearingMediaURL(UIViewController *dmVC, BOOL *outIsVideo) {
    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    if (!msg) return nil;

    Ivar vmiIvar = class_getInstanceVariable([msg class], "_visualMediaInfo");
    id vmi = vmiIvar ? object_getIvar(msg, vmiIvar) : nil;
    Ivar mIvar = vmi ? class_getInstanceVariable([vmi class], "_media") : nil;
    id visMedia = mIvar ? object_getIvar(vmi, mIvar) : nil;
    if (!visMedia) return nil;

    // Video
    @try {
        id rawVideo = [msg valueForKey:@"rawVideo"];
        if (rawVideo) {
            NSURL *url = [SCIUtils getVideoUrl:rawVideo];
            if (url) { if (outIsVideo) *outIsVideo = YES; return url; }
        }
    } @catch (NSException *e) {}

    // Photo
    Ivar pi = class_getInstanceVariable([visMedia class], "_photo_photo");
    id photo = pi ? object_getIvar(visMedia, pi) : nil;
    if (photo) {
        if (outIsVideo) *outIsVideo = NO;
        return [SCIUtils getPhotoUrl:photo];
    }
    return nil;
}

static SCIDownloadDelegate *sciDMDownloadDelegate = nil;
static void sciDownloadDisappearingMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDisappearingMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }

    sciDMDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:saveToPhotos showProgress:YES];
    [sciDMDownloadDelegate downloadFileWithURL:url fileExtension:(isVideo ? @"mp4" : @"jpg") hudLabel:nil];
}

static SCIDownloadDelegate *sciDMShareDelegate = nil;
static void sciShareDisappearingMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDisappearingMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }

    sciDMShareDelegate = [[SCIDownloadDelegate alloc] initWithAction:share showProgress:YES];
    [sciDMShareDelegate downloadFileWithURL:url fileExtension:(isVideo ? @"mp4" : @"jpg") hudLabel:nil];
}

static void sciExpandDisappearingMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDisappearingMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }

    if (isVideo) {
        [SCIMediaViewer showWithVideoURL:url photoURL:nil caption:nil];
    } else {
        [SCIMediaViewer showWithVideoURL:nil photoURL:url caption:nil];
    }
}

// ── Story playback control ──

static void sciPauseStoryPlayback(UIView *sourceView) {
    UIViewController *storyVC = sciFindVC(sourceView, @"IGStoryViewerViewController");
    if (!storyVC) return;
    id sc = sciFindSectionController(storyVC);

    SEL pauseSel = NSSelectorFromString(@"pauseWithReason:");
    if (sc && [sc respondsToSelector:pauseSel]) {
        ((void(*)(id, SEL, NSInteger))objc_msgSend)(sc, pauseSel, 10);
        return;
    }
    if ([storyVC respondsToSelector:pauseSel]) {
        ((void(*)(id, SEL, NSInteger))objc_msgSend)(storyVC, pauseSel, 10);
        return;
    }
}

static void sciResumeStoryPlayback(UIView *sourceView) {
    UIViewController *storyVC = sciFindVC(sourceView, @"IGStoryViewerViewController");
    if (!storyVC) return;
    id sc = sciFindSectionController(storyVC);

    SEL resumeSel1 = NSSelectorFromString(@"tryResumePlaybackWithReason:");
    SEL resumeSel2 = NSSelectorFromString(@"tryResumePlayback");
    if (sc && [sc respondsToSelector:resumeSel1]) {
        ((void(*)(id, SEL, NSInteger))objc_msgSend)(sc, resumeSel1, 0);
        return;
    }
    if ([storyVC respondsToSelector:resumeSel2]) {
        ((void(*)(id, SEL))objc_msgSend)(storyVC, resumeSel2);
        return;
    }
    if ([storyVC respondsToSelector:resumeSel1]) {
        ((void(*)(id, SEL, NSInteger))objc_msgSend)(storyVC, resumeSel1, 0);
        return;
    }
}

%hook IGStoryFullscreenOverlayView

// ============ Button injection ============

- (void)didMoveToSuperview {
    %orig;
    if (!self.superview) return;

    // Action button
    if ([SCIUtils getBoolPref:@"stories_action_button"] && ![self viewWithTag:1340]) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = 1340;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
        [btn setImage:[UIImage systemImageNamed:@"ellipsis.circle" withConfiguration:cfg] forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
        btn.layer.cornerRadius = 18;
        btn.clipsToBounds = YES;
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100],
            [btn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [btn.widthAnchor constraintEqualToConstant:36],
            [btn.heightAnchor constraintEqualToConstant:36]
        ]];

        SCIActionMediaProvider storyProvider = ^id (UIView *sourceView) {
            // DM disappearing message — handle directly for tap actions
            UIViewController *dmVC = sciFindVC(sourceView, @"IGDirectVisualMessageViewerController");
            if (dmVC) {
                sciDownloadDisappearingMedia(dmVC);
                return (id)kCFNull;
            }

            // Story path
            sciPauseStoryPlayback(sourceView);
            id item = sciGetCurrentStoryItem(sourceView);
            if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) return item;
            return sciExtractMediaFromItem(item);
        };

        [SCIActionButton configureButton:btn
                                 context:SCIActionContextStories
                                 prefKey:@"stories_action_default"
                           mediaProvider:storyProvider];

        // When configureButton chose "menu" mode, override with our custom
        // deferred menu that handles both DM and story contexts.
        if (btn.showsMenuAsPrimaryAction) {
            btn.menu = [UIMenu menuWithChildren:@[
                [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
                    UIViewController *dmVC = sciFindVC(btn, @"IGDirectVisualMessageViewerController");
                    if (dmVC) {
                        completion(@[
                            [UIAction actionWithTitle:SCILocalized(@"Expand") image:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"]
                                identifier:nil handler:^(UIAction *a) { sciExpandDisappearingMedia(dmVC); }],
                            [UIAction actionWithTitle:SCILocalized(@"Share") image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                identifier:nil handler:^(UIAction *a) { sciShareDisappearingMedia(dmVC); }],
                            [UIAction actionWithTitle:SCILocalized(@"Save to Photos") image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                identifier:nil handler:^(UIAction *a) { sciDownloadDisappearingMedia(dmVC); }],
                        ]);
                    } else {
                        id media = nil;
                        sciPauseStoryPlayback(btn);
                        id item = sciGetCurrentStoryItem(btn);
                        media = [item isKindOfClass:NSClassFromString(@"IGMedia")] ? item : sciExtractMediaFromItem(item);
                        NSArray *actions = [SCIMediaActions actionsForContext:SCIActionContextStories media:media fromView:btn];
                        UIMenu *built = [SCIActionMenu buildMenuWithActions:actions];
                        completion(built.children);
                    }
                }]
            ]];
        }

        // KVO highlighted → resume playback when menu dismisses.
        [btn addObserver:self forKeyPath:@"highlighted"
                 options:NSKeyValueObservingOptionNew context:NULL];


        // Story reel items provider for "download all" detection.
        static const void *kStoryReelItemsProvider = &kStoryReelItemsProvider;
        objc_setAssociatedObject(btn, kStoryReelItemsProvider, ^NSArray *(UIView *src) {
            UIViewController *storyVC = sciFindVC(src, @"IGStoryViewerViewController");
            if (!storyVC) return nil;
            id vm = sciCall(storyVC, @selector(currentViewModel));
            if (!vm) return nil;

            // Try known selectors
            for (NSString *sel in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
                if ([vm respondsToSelector:NSSelectorFromString(sel)]) {
                    @try {
                        id val = ((id(*)(id,SEL))objc_msgSend)(vm, NSSelectorFromString(sel));
                        if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count] > 1) {
                            return val;
                        }
                    } @catch (__unused id e) {}
                }
            }

            // Scan vm ivars for arrays of IGMedia
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
                        if (mc && [first isKindOfClass:mc]) {
                            free(ivs);
                            return val;
                        }
                        // Items might be wrapped — try extracting media from first
                        IGMedia *extracted = sciExtractMediaFromItem(first);
                        if (extracted) {
                            free(ivs);
                            return val;
                        }
                    }
                } @catch (__unused id e) {}
            }
            if (ivs) free(ivs);

            return nil;
        }, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }

    // Audio toggle button
    sciInitStoryAudioState();
    if ([SCIUtils getBoolPref:@"story_audio_toggle"] && ![self viewWithTag:1341]) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = 1341;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
        NSString *icon = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
        [btn setImage:[UIImage systemImageNamed:icon withConfiguration:cfg] forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
        btn.layer.cornerRadius = 14;
        btn.clipsToBounds = YES;
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [btn addTarget:self action:@selector(sciAudioToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100],
            [btn.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [btn.widthAnchor constraintEqualToConstant:28],
            [btn.heightAnchor constraintEqualToConstant:28]
        ]];
    }

    // Seen button — deferred so the responder chain is wired up
    __weak UIView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *s = weakSelf;
        if (s && s.superview) ((void(*)(id, SEL))objc_msgSend)(s, @selector(sciRefreshSeenButton));
    });
}

// ============ Seen button lifecycle ============

// KVO: action button highlighted → NO means UIMenu dismissed → resume.
%new - (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                              change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"highlighted"]) {
        BOOL highlighted = [change[NSKeyValueChangeNewKey] boolValue];
        if (!highlighted) {
            sciResumeStoryPlayback(self);
        }
    }
}

// Refresh the audio toggle icon (tag 1341) to match current state.
%new - (void)sciRefreshAudioButton {
    UIButton *btn = (UIButton *)[self viewWithTag:1341];
    if (!btn) return;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    NSString *icon = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
    [btn setImage:[UIImage systemImageNamed:icon withConfiguration:cfg] forState:UIControlStateNormal];
}

// Rebuilds the eye button (tag 1339). Visible only when the story is
// actively blocked for this owner. List management lives in the hold menu
// and the ellipsis action menu.
%new - (void)sciRefreshSeenButton {
    BOOL seenBlockingOn = [SCIUtils getBoolPref:@"no_seen_receipt"];
    if (!seenBlockingOn) return;

    NSDictionary *ownerInfo = sciOwnerInfoForView(self);
    NSString *ownerPK = ownerInfo[@"pk"] ?: @"";
    BOOL excluded = ownerPK.length && [SCIExcludedStoryUsers isUserPKExcluded:ownerPK];
    UIButton *existing = (UIButton *)[self viewWithTag:1339];

    // Not blocked → no eye button.
    if (excluded) { [existing removeFromSuperview]; return; }

    BOOL toggleMode = [[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"];
    NSString *symName;
    UIColor *tint;
    if (toggleMode) {
        symName = sciStorySeenToggleEnabled ? @"eye.fill" : @"eye";
        tint = sciStorySeenToggleEnabled ? SCIUtils.SCIColor_Primary : [UIColor whiteColor];
    } else {
        symName = @"eye"; tint = [UIColor whiteColor];
    }

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];

    if (existing) {
        [existing setImage:[UIImage systemImageNamed:symName withConfiguration:cfg] forState:UIControlStateNormal];
        existing.tintColor = tint;
        return;
    }

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = 1339;
    [btn setImage:[UIImage systemImageNamed:symName withConfiguration:cfg] forState:UIControlStateNormal];
    btn.tintColor = tint;
    btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    btn.layer.cornerRadius = 18;
    btn.clipsToBounds = YES;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:@selector(sciSeenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(sciSeenButtonLongPressed:)];
    lp.minimumPressDuration = 0.4;
    [btn addGestureRecognizer:lp];
    [self addSubview:btn];
    UIView *anchor = [self viewWithTag:1340];
    if (anchor) {
        [NSLayoutConstraint activateConstraints:@[
            [btn.centerYAnchor constraintEqualToAnchor:anchor.centerYAnchor],
            [btn.trailingAnchor constraintEqualToAnchor:anchor.leadingAnchor constant:-10],
            [btn.widthAnchor constraintEqualToConstant:36],
            [btn.heightAnchor constraintEqualToConstant:36]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100],
            [btn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [btn.widthAnchor constraintEqualToConstant:36],
            [btn.heightAnchor constraintEqualToConstant:36]
        ]];
    }
}

// Refresh when story owner changes or audio state changes
- (void)layoutSubviews {
    %orig;
    static char kLastPKKey;
    static char kLastExclKey;
    static char kLastAudioKey;

    // Audio button: check if state changed
    UIButton *audioBtn = (UIButton *)[self viewWithTag:1341];
    if (audioBtn) {
        BOOL audioOn = sciIsStoryAudioEnabled();
        NSNumber *prevAudio = objc_getAssociatedObject(self, &kLastAudioKey);
        if (!prevAudio || [prevAudio boolValue] != audioOn) {
            objc_setAssociatedObject(self, &kLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshAudioButton));
        }
    }

    // Seen button: check if owner/exclusion changed
    if (![SCIUtils getBoolPref:@"no_seen_receipt"]) return;
    NSDictionary *info = sciOwnerInfoForView(self);
    NSString *pk = info[@"pk"] ?: @"";
    BOOL excluded = pk.length && [SCIExcludedStoryUsers isUserPKExcluded:pk];
    NSString *prev = objc_getAssociatedObject(self, &kLastPKKey);
    NSNumber *prevExcl = objc_getAssociatedObject(self, &kLastExclKey);
    BOOL changed = ![pk isEqualToString:prev ?: @""] || (prevExcl && [prevExcl boolValue] != excluded);
    if (!changed) return;
    objc_setAssociatedObject(self, &kLastPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(self, &kLastExclKey, @(excluded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));
}

// ============ Audio toggle handler ============

%new - (void)sciAudioToggleTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    sciToggleStoryAudio();
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    NSString *icon = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
    [sender setImage:[UIImage systemImageNamed:icon withConfiguration:cfg] forState:UIControlStateNormal];
}

// ============ Seen button tap ============

%new - (void)sciSeenButtonTapped:(UIButton *)sender {
    // Toggle mode
    if ([[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"]) {
        sciStorySeenToggleEnabled = !sciStorySeenToggleEnabled;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
        [sender setImage:[UIImage systemImageNamed:(sciStorySeenToggleEnabled ? @"eye.fill" : @"eye") withConfiguration:cfg] forState:UIControlStateNormal];
        sender.tintColor = sciStorySeenToggleEnabled ? SCIUtils.SCIColor_Primary : [UIColor whiteColor];
        [SCIUtils showToastForDuration:2.0 title:sciStorySeenToggleEnabled ? SCILocalized(@"Story read receipts enabled") : SCILocalized(@"Story read receipts disabled")];
        return;
    }

    // Button mode: mark seen once
    ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciMarkSeenTapped:), sender);
}

// ============ Seen button long-press menu ============

%new - (void)sciSeenButtonLongPressed:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    UIView *btn = gr.view;
    UIViewController *host = [SCIUtils nearestViewControllerForView:self];
    if (!host) return;

    // Pause story while the sheet is open
    sciPauseStoryPlayback(self);
    UIWindow *capturedWin = btn.window ?: self.window;
    if (!capturedWin) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) { if (w.isKeyWindow) { capturedWin = w; break; } }
    }
    NSDictionary *ownerInfo = sciOwnerInfoForView(self);
    NSString *pk = ownerInfo[@"pk"];
    NSString *username = ownerInfo[@"username"] ?: @"";
    NSString *fullName = ownerInfo[@"fullName"] ?: @"";
    BOOL inList = pk && [SCIExcludedStoryUsers isInList:pk];
    BOOL blockSelected = [SCIExcludedStoryUsers isBlockSelectedMode];

    __weak UIView *weakSelf = self;
    void (^resume)(void) = ^{ if (weakSelf) sciResumeStoryPlayback(weakSelf); };

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Mark seen") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciMarkSeenTapped:), btn);
        resume();
    }]];
    if (pk) {
        NSString *addLabel = blockSelected ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude story seen");
        NSString *removeLabel = blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude story seen");
        NSString *t = inList ? removeLabel : addLabel;
        [sheet addAction:[UIAlertAction actionWithTitle:t style:inList ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            if (inList) {
                [SCIExcludedStoryUsers removePK:pk];
                [SCIUtils showToastForDuration:2.0 title:blockSelected ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded")];
                if (blockSelected) sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
            } else {
                [SCIExcludedStoryUsers addOrUpdateEntry:@{ @"pk": pk, @"username": username, @"fullName": fullName }];
                [SCIUtils showToastForDuration:2.0 title:blockSelected ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded")];
                if (!blockSelected) sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
            }
            sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
            resume();
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *_) {
        resume();
    }]];
    sheet.popoverPresentationController.sourceView = btn;
    sheet.popoverPresentationController.sourceRect = btn.bounds;
    [host presentViewController:sheet animated:YES completion:nil];
}

// ============ Mark seen handler ============

%new - (void)sciMarkSeenTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    if (sender) {
        [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformMakeScale(0.8, 0.8); sender.alpha = 0.6; }
                         completion:^(BOOL f) { [UIView animateWithDuration:0.15 animations:^{ sender.transform = CGAffineTransformIdentity; sender.alpha = 1.0; }]; }];
    }

    @try {
        // Story path
        UIViewController *storyVC = sciFindVC(self, @"IGStoryViewerViewController");
        if (storyVC) {
            id sectionCtrl = sciFindSectionController(storyVC);
            id storyItem = sectionCtrl ? sciCall(sectionCtrl, NSSelectorFromString(@"currentStoryItem")) : nil;
            if (!storyItem) storyItem = sciGetCurrentStoryItem(self);
            IGMedia *media = (storyItem && [storyItem isKindOfClass:NSClassFromString(@"IGMedia")]) ? storyItem : sciExtractMediaFromItem(storyItem);

            if (!media) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find story media")]; return; }

            sciAllowSeenForPK(media);
            sciSeenBypassActive = YES;

            SEL delegateSel = @selector(fullscreenSectionController:didMarkItemAsSeen:);
            if ([storyVC respondsToSelector:delegateSel]) {
                typedef void (*Func)(id, SEL, id, id);
                ((Func)objc_msgSend)(storyVC, delegateSel, sectionCtrl, media);
            }
            if (sectionCtrl) {
                SEL markSel = NSSelectorFromString(@"markItemAsSeen:");
                if ([sectionCtrl respondsToSelector:markSel])
                    ((SCIMsgSend1)objc_msgSend)(sectionCtrl, markSel, media);
            }
            id seenManager = sciCall(storyVC, @selector(viewingSessionSeenStateManager));
            id vm = sciCall(storyVC, @selector(currentViewModel));
            if (seenManager && vm) {
                SEL setSel = NSSelectorFromString(@"setSeenMediaId:forReelPK:");
                if ([seenManager respondsToSelector:setSel]) {
                    id mediaPK = sciCall(media, @selector(pk));
                    id reelPK = sciCall(vm, NSSelectorFromString(@"reelPK"));
                    if (!reelPK) reelPK = sciCall(vm, @selector(pk));
                    if (mediaPK && reelPK) {
                        typedef void (*SetFunc)(id, SEL, id, id);
                        ((SetFunc)objc_msgSend)(seenManager, setSel, mediaPK, reelPK);
                    }
                }
            }
            sciSeenBypassActive = NO;
            [SCIUtils showToastForDuration:2.0 title:SCILocalized(@"Marked as seen") subtitle:SCILocalized(@"Will sync when leaving stories")];

            // Advance to next story if enabled (skip when triggered programmatically via exclude)
            if (sender && [SCIUtils getBoolPref:@"advance_on_mark_seen"] && sectionCtrl) {
                __block id secCtrl = sectionCtrl;
                __weak __typeof(self) weakSelf = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    sciAdvanceBypassActive = YES;
                    SEL advSel = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
                    if ([secCtrl respondsToSelector:advSel])
                        ((void(*)(id, SEL, NSInteger))objc_msgSend)(secCtrl, advSel, 1);

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        __strong __typeof(weakSelf) strongSelf = weakSelf;
                        UIViewController *vc2 = strongSelf ? sciFindVC(strongSelf, @"IGStoryViewerViewController") : nil;
                        id sc2 = vc2 ? sciFindSectionController(vc2) : nil;
                        if (sc2) {
                            SEL resumeSel = NSSelectorFromString(@"tryResumePlaybackWithReason:");
                            if ([sc2 respondsToSelector:resumeSel])
                                ((void(*)(id, SEL, NSInteger))objc_msgSend)(sc2, resumeSel, 0);
                        }
                        sciAdvanceBypassActive = NO;
                    });
                });
            }
            return;
        }

        // DM visual message path
        UIViewController *dmVC = sciFindVC(self, @"IGDirectVisualMessageViewerController");
        if (dmVC) {
            extern BOOL dmVisualMsgsViewedButtonEnabled;
            BOOL wasEnabled = dmVisualMsgsViewedButtonEnabled;
            dmVisualMsgsViewedButtonEnabled = YES;

            Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
            id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
            Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
            id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
            Ivar erIvar = class_getInstanceVariable([dmVC class], "_eventResponders");
            NSArray *responders = erIvar ? object_getIvar(dmVC, erIvar) : nil;

            if (responders && msg) {
                for (id resp in responders) {
                    SEL beginSel = @selector(visualMessageViewerController:didBeginPlaybackForVisualMessage:atIndex:);
                    if ([resp respondsToSelector:beginSel]) {
                        typedef void (*Fn)(id, SEL, id, id, NSInteger);
                        ((Fn)objc_msgSend)(resp, beginSel, dmVC, msg, 0);
                    }
                    SEL endSel = @selector(visualMessageViewerController:didEndPlaybackForVisualMessage:atIndex:mediaCurrentTime:forNavType:);
                    if ([resp respondsToSelector:endSel]) {
                        typedef void (*Fn)(id, SEL, id, id, NSInteger, CGFloat, NSInteger);
                        ((Fn)objc_msgSend)(resp, endSel, dmVC, msg, 0, 0.0, 0);
                    }
                }
            }

            SEL dismissSel = NSSelectorFromString(@"_didTapHeaderViewDismissButton:");
            if ([dmVC respondsToSelector:dismissSel])
                ((void(*)(id,SEL,id))objc_msgSend)(dmVC, dismissSel, nil);

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                dmVisualMsgsViewedButtonEnabled = wasEnabled;
            });

            [SCIUtils showToastForDuration:1.5 title:SCILocalized(@"Marked as viewed")];
            return;
        }

        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"VC not found")];
    } @catch (NSException *e) {
        [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"Error: %@"), e.reason]];
    }
}

%end

// ============ Chrome alpha sync ============

static void sciSyncStoryButtonsAlpha(UIView *self_, CGFloat alpha) {
    Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayCls) return;
    UIView *cur = self_;
    while (cur) {
        for (UIView *sib in cur.superview.subviews) {
            if (![sib isKindOfClass:overlayCls]) continue;
            UIView *seen  = [sib viewWithTag:1339];
            UIView *dl    = [sib viewWithTag:1340];
            UIView *audio = [sib viewWithTag:1341];
            if (seen)  seen.alpha  = alpha;
            if (dl)    dl.alpha    = alpha;
            if (audio) audio.alpha = alpha;
            return;
        }
        cur = cur.superview;
    }
}

%hook IGStoryFullscreenHeaderView
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    sciSyncStoryButtonsAlpha((UIView *)self, alpha);
}
%end
