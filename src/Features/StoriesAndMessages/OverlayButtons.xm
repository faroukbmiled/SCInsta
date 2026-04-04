// Download + mark seen buttons on story/DM visual message overlay
#import "StoryHelpers.h"

extern "C" BOOL sciSeenBypassActive;
extern "C" NSMutableSet *sciAllowedSeenPKs;
extern "C" void sciAllowSeenForPK(id);

static SCIDownloadDelegate *sciStoryVideoDl = nil;
static SCIDownloadDelegate *sciStoryImageDl = nil;

static void sciInitStoryDownloaders() {
    NSString *method = [SCIUtils getStringPref:@"dw_save_action"];
    DownloadAction action = [method isEqualToString:@"photos"] ? saveToPhotos : share;
    DownloadAction imgAction = [method isEqualToString:@"photos"] ? saveToPhotos : quickLook;
    sciStoryVideoDl = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:YES];
    sciStoryImageDl = [[SCIDownloadDelegate alloc] initWithAction:imgAction showProgress:NO];
}

static void sciDownloadMedia(IGMedia *media) {
    sciInitStoryDownloaders();
    NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:media];
    if (videoUrl) {
        [sciStoryVideoDl downloadFileWithURL:videoUrl fileExtension:[[videoUrl lastPathComponent] pathExtension] hudLabel:nil];
        return;
    }
    NSURL *photoUrl = [SCIUtils getPhotoUrlForMedia:media];
    if (photoUrl) {
        [sciStoryImageDl downloadFileWithURL:photoUrl fileExtension:[[photoUrl lastPathComponent] pathExtension] hudLabel:nil];
        return;
    }
    [SCIUtils showErrorHUDWithDescription:@"Could not extract URL"];
}

static void sciDownloadWithConfirm(void(^block)(void)) {
    if ([SCIUtils getBoolPref:@"dw_confirm"]) {
        [SCIUtils showConfirmation:block title:@"Download?"];
    } else {
        block();
    }
}

// get media from DM visual message VC
static void sciDownloadDMVisualMessage(UIViewController *dmVC) {
    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    if (!ds) return;
    Ivar msgIvar = class_getInstanceVariable([ds class], "_currentMessage");
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    if (!msg) return;

    // video
    id rawVideo = sciCall(msg, @selector(rawVideo));
    if (rawVideo) {
        NSURL *url = [SCIUtils getVideoUrl:rawVideo];
        if (url) {
            sciInitStoryDownloaders();
            sciDownloadWithConfirm(^{ [sciStoryVideoDl downloadFileWithURL:url fileExtension:[[url lastPathComponent] pathExtension] hudLabel:nil]; });
            return;
        }
    }

    // photo via rawPhoto
    id rawPhoto = sciCall(msg, @selector(rawPhoto));
    if (rawPhoto) {
        NSURL *url = [SCIUtils getPhotoUrl:rawPhoto];
        if (url) {
            sciInitStoryDownloaders();
            sciDownloadWithConfirm(^{ [sciStoryImageDl downloadFileWithURL:url fileExtension:[[url lastPathComponent] pathExtension] hudLabel:nil]; });
            return;
        }
    }

    // photo via imageSpecifier
    id imgSpec = sciCall(msg, NSSelectorFromString(@"imageSpecifier"));
    if (imgSpec) {
        NSURL *url = sciCall(imgSpec, @selector(url));
        if (url) {
            sciInitStoryDownloaders();
            sciDownloadWithConfirm(^{ [sciStoryImageDl downloadFileWithURL:url fileExtension:[[url lastPathComponent] pathExtension] hudLabel:nil]; });
            return;
        }
    }

    // photo via _visualMediaInfo._media
    Ivar vmiIvar = class_getInstanceVariable([msg class], "_visualMediaInfo");
    id vmi = vmiIvar ? object_getIvar(msg, vmiIvar) : nil;
    if (vmi) {
        Ivar mediaIvar = class_getInstanceVariable([vmi class], "_media");
        id mediaObj = mediaIvar ? object_getIvar(vmi, mediaIvar) : nil;
        if (mediaObj) {
            IGMedia *media = sciExtractMediaFromItem(mediaObj);
            if (!media && [mediaObj isKindOfClass:NSClassFromString(@"IGMedia")]) media = (IGMedia *)mediaObj;
            if (media) { sciDownloadWithConfirm(^{ sciDownloadMedia(media); }); return; }
        }
    }

    [SCIUtils showErrorHUDWithDescription:@"Could not find media"];
}

%hook IGStoryFullscreenOverlayView
- (void)didMoveToSuperview {
    %orig;
    if (!self.superview) return;

    // download button
    if ([SCIUtils getBoolPref:@"dw_story"] && ![self viewWithTag:1340]) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = 1340;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
        [btn setImage:[UIImage systemImageNamed:@"arrow.down" withConfiguration:cfg] forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
        btn.layer.cornerRadius = 18;
        btn.clipsToBounds = YES;
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [btn addTarget:self action:@selector(sciDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100],
            [btn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [btn.widthAnchor constraintEqualToConstant:36],
            [btn.heightAnchor constraintEqualToConstant:36]
        ]];
    }

    // mark seen button (stories: mark as seen, DMs: mark as viewed + dismiss)
    if ([SCIUtils getBoolPref:@"no_seen_receipt"] && ![self viewWithTag:1339]) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = 1339;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
        [btn setImage:[UIImage systemImageNamed:@"eye" withConfiguration:cfg] forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
        btn.layer.cornerRadius = 18;
        btn.clipsToBounds = YES;
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [btn addTarget:self action:@selector(sciMarkSeenTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
        UIView *dlBtn = [self viewWithTag:1340];
        if (dlBtn) {
            [NSLayoutConstraint activateConstraints:@[
                [btn.centerYAnchor constraintEqualToAnchor:dlBtn.centerYAnchor],
                [btn.trailingAnchor constraintEqualToAnchor:dlBtn.leadingAnchor constant:-10],
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
}

// download handler — works for both stories and DM visual messages
%new - (void)sciDownloadTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformMakeScale(0.8, 0.8); }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformIdentity; }]; }];
    @try {
        // story path
        id item = sciGetCurrentStoryItem(self);
        IGMedia *media = sciExtractMediaFromItem(item);
        if (media) {
            sciDownloadWithConfirm(^{ sciDownloadMedia(media); });
            return;
        }

        // DM visual message path
        UIViewController *dmVC = sciFindVC(self, @"IGDirectVisualMessageViewerController");
        if (dmVC) {
            sciDownloadDMVisualMessage(dmVC);
            return;
        }

        [SCIUtils showErrorHUDWithDescription:@"Could not find media"];
    } @catch (NSException *e) {
        [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:@"Error: %@", e.reason]];
    }
}

// mark seen handler — stories: allow-list approach, DMs: trigger viewed + dismiss
%new - (void)sciMarkSeenTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [UIView animateWithDuration:0.1 animations:^{ sender.transform = CGAffineTransformMakeScale(0.8, 0.8); sender.alpha = 0.6; }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.15 animations:^{ sender.transform = CGAffineTransformIdentity; sender.alpha = 1.0; }]; }];

    @try {
        // story path
        UIViewController *storyVC = sciFindVC(self, @"IGStoryViewerViewController");
        if (storyVC) {
            // allow-list the current media PK for deferred upload
            id sectionCtrl = sciFindSectionController(storyVC);
            id storyItem = sectionCtrl ? sciCall(sectionCtrl, NSSelectorFromString(@"currentStoryItem")) : nil;
            if (!storyItem) storyItem = sciGetCurrentStoryItem(self);
            IGMedia *media = (storyItem && [storyItem isKindOfClass:NSClassFromString(@"IGMedia")]) ? storyItem : sciExtractMediaFromItem(storyItem);

            if (!media) { [SCIUtils showErrorHUDWithDescription:@"Could not find story media"]; return; }

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
            [SCIUtils showToastForDuration:2.0 title:@"Marked as seen" subtitle:@"Will sync when leaving stories"];
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

            [SCIUtils showToastForDuration:1.5 title:@"Marked as viewed"];
            return;
        }

        [SCIUtils showErrorHUDWithDescription:@"VC not found"];
    } @catch (NSException *e) {
        [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:@"Error: %@", e.reason]];
    }
}
%end
