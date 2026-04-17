#import "../../InstagramHeaders.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "SCIExcludedThreads.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// Returns the threadId for an IGDirectThreadViewController, or nil.
static NSString *sciThreadIdForVC(id vc) {
    if (!vc) return nil;
    @try { return [vc valueForKey:@"threadId"]; } @catch (__unused id e) { return nil; }
}


// Seen buttons (in DMs)
// - Enables no seen for messages
// - Enables unlimited views of DM visual messages

BOOL dmSeenToggleEnabled = NO;
static NSInteger sciSeenAutoBypassCount = 0;
__weak IGDirectThreadViewController *sciActiveThreadVC = nil;

static BOOL sciIsSeenToggleMode() {
    return [[SCIUtils getStringPref:@"seen_mode"] isEqualToString:@"toggle"];
}

static BOOL sciAutoInteractEnabled() {
    if ([SCIExcludedThreads isActiveThreadExcluded]) return NO;
    return [SCIUtils getBoolPref:@"remove_lastseen"] && [SCIUtils getBoolPref:@"seen_auto_on_interact"];
}

BOOL sciAutoTypingEnabled() {
    if ([SCIExcludedThreads isActiveThreadExcluded]) return NO;
    return [SCIUtils getBoolPref:@"remove_lastseen"] && [SCIUtils getBoolPref:@"seen_auto_on_typing"];
}

void sciDoAutoSeen(IGDirectThreadViewController *threadVC) {
    sciSeenAutoBypassCount++;
    [threadVC markLastMessageAsSeen];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciSeenAutoBypassCount--;
    });
}

// ============ AUTO SEEN ON SEND ============

static void (*orig_setHasSent)(id self, SEL _cmd, BOOL sent);
static void new_setHasSent(id self, SEL _cmd, BOOL sent) {
    orig_setHasSent(self, _cmd, sent);
    if (!sent || !sciAutoInteractEnabled()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciDoAutoSeen((IGDirectThreadViewController *)self);
    });
}

// ============ AUTO SEEN ON TYPING ============
// Tracks the visible thread VC so the typing-service hook (in
// DisableTypingStatus.x) can mark its messages as seen.

%hook IGDirectThreadViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sciActiveThreadVC = self;
}
- (void)viewWillDisappear:(BOOL)animated {
    if (sciActiveThreadVC == self) sciActiveThreadVC = nil;
    %orig;
}
%end

// ============ NAV BAR BUTTONS ============

// Re-runs setRightBarButtonItems with the live items. The hook tags its own
// buttons so they get stripped and rebuilt against the new exclusion state.
void sciRefreshNavBarItems(UIView *anchor) {
    if (!anchor || ![anchor respondsToSelector:@selector(setRightBarButtonItems:)]) return;
    NSArray *cur = [(id)anchor performSelector:@selector(rightBarButtonItems)];
    [(id)anchor performSelector:@selector(setRightBarButtonItems:) withObject:cur];
}

static NSDictionary *sciEntryFromThreadVC(UIViewController *vc);

// Long-press menu shared by the seen button and the un-exclude button.
static UIMenu *sciBuildThreadActionsMenu(UIView *anchor, NSString *threadId, UIWindow *window) {
    BOOL inList = threadId && [SCIExcludedThreads isInList:threadId];
    BOOL excluded = threadId && [SCIExcludedThreads isThreadIdExcluded:threadId];
    BOOL blockSelected = [SCIExcludedThreads isBlockSelectedMode];
    BOOL seenFeatureOn = [SCIUtils getBoolPref:@"remove_lastseen"];

    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];

    if (seenFeatureOn && !excluded) {
        BOOL toggleMode = sciIsSeenToggleMode();

        // Toggle mode: show toggle action + one-shot mark seen
        if (toggleMode) {
            NSString *toggleTitle = dmSeenToggleEnabled ? SCILocalized(@"Disable read receipts") : SCILocalized(@"Enable read receipts");
            UIImage *toggleImg2 = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
            UIAction *toggleAction = [UIAction actionWithTitle:toggleTitle image:toggleImg2 identifier:nil
                                                       handler:^(__kindof UIAction *_) {
                dmSeenToggleEnabled = !dmSeenToggleEnabled;
                UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:anchor];
                if (dmSeenToggleEnabled && [nearestVC isKindOfClass:%c(IGDirectThreadViewController)])
                    [(IGDirectThreadViewController *)nearestVC markLastMessageAsSeen];
                [SCIUtils showToastForDuration:2.0 title:dmSeenToggleEnabled ? SCILocalized(@"Read receipts enabled") : SCILocalized(@"Read receipts disabled")];
                sciRefreshNavBarItems(anchor);
            }];
            toggleAction.state = dmSeenToggleEnabled ? UIMenuElementStateOn : UIMenuElementStateOff;
            [items addObject:toggleAction];

            UIAction *markSeen = [UIAction actionWithTitle:SCILocalized(@"Mark messages as seen")
                                                     image:[UIImage systemImageNamed:@"checkmark.circle"]
                                                identifier:nil
                                                   handler:^(__kindof UIAction *_) {
                UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:anchor];
                if ([nearestVC isKindOfClass:%c(IGDirectThreadViewController)])
                    [(IGDirectThreadViewController *)nearestVC markLastMessageAsSeen];
                [SCIUtils showToastForDuration:2.0 title:SCILocalized(@"Marked messages as seen")];
            }];
            [items addObject:markSeen];
        } else {
            // Button mode: just mark seen
            UIAction *seenAction = [UIAction actionWithTitle:SCILocalized(@"Mark messages as seen")
                                                       image:[UIImage systemImageNamed:@"checkmark.circle"]
                                                  identifier:nil
                                                     handler:^(__kindof UIAction *_) {
                UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:anchor];
                if ([nearestVC isKindOfClass:%c(IGDirectThreadViewController)])
                    [(IGDirectThreadViewController *)nearestVC markLastMessageAsSeen];
                [SCIUtils showToastForDuration:2.0 title:SCILocalized(@"Marked messages as seen")];
            }];
            [items addObject:seenAction];
        }
    }

    NSString *addLabel = blockSelected ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude chat");
    NSString *removeLabel = blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude chat");
    NSString *toggleTitle = inList ? removeLabel : addLabel;
    UIImage *toggleImg = [UIImage systemImageNamed:inList ? @"eye.fill" : @"eye.slash"];
    __weak UIView *weakAnchor = anchor;
    UIAction *toggle = [UIAction actionWithTitle:toggleTitle image:toggleImg identifier:nil
                                         handler:^(__kindof UIAction *_) {
        if (!threadId) return;
        if (inList) {
            [SCIExcludedThreads removeThreadId:threadId];
            [SCIUtils showToastForDuration:2.0 title:blockSelected ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded")];
            // In block_selected, removing = normal behavior → mark seen
            if (blockSelected) {
                UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:weakAnchor];
                if ([nearestVC isKindOfClass:%c(IGDirectThreadViewController)])
                    [(IGDirectThreadViewController *)nearestVC markLastMessageAsSeen];
            }
        } else {
            UIViewController *anchorVC = [SCIUtils nearestViewControllerForView:anchor];
            NSDictionary *entry = sciEntryFromThreadVC(anchorVC);
            if (!entry) entry = @{ @"threadId": threadId, @"threadName": @"", @"isGroup": @NO, @"users": @[] };
            [SCIExcludedThreads addOrUpdateEntry:entry];
            [SCIUtils showToastForDuration:2.0 title:blockSelected ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded")];
            // In block_all, excluding = normal behavior → mark seen
            if (!blockSelected) {
                UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:weakAnchor];
                if ([nearestVC isKindOfClass:%c(IGDirectThreadViewController)])
                    [(IGDirectThreadViewController *)nearestVC markLastMessageAsSeen];
            }
        }
        sciRefreshNavBarItems(weakAnchor);
    }];
    if (excluded) toggle.attributes = UIMenuElementAttributesDestructive;
    [items addObject:toggle];

    // Unlimited replay toggle
    if ([SCIUtils getBoolPref:@"unlimited_replay"] && !excluded) {
        NSString *replayTitle = dmVisualMsgsViewedButtonEnabled
            ? SCILocalized(@"Visual messages: expiring")
            : SCILocalized(@"Visual messages: unlimited replay");
        UIImage *replayImg = [UIImage systemImageNamed:dmVisualMsgsViewedButtonEnabled
            ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill"];
        UIAction *replayAction = [UIAction actionWithTitle:replayTitle image:replayImg identifier:nil
                                                   handler:^(__kindof UIAction *_) {
            dmVisualMsgsViewedButtonEnabled = !dmVisualMsgsViewedButtonEnabled;
            [SCIUtils showToastForDuration:2.0 title:dmVisualMsgsViewedButtonEnabled
                ? SCILocalized(@"Visual messages will expire") : SCILocalized(@"Unlimited replay enabled")];
            sciRefreshNavBarItems(anchor);
        }];
        replayAction.state = dmVisualMsgsViewedButtonEnabled ? UIMenuElementStateOff : UIMenuElementStateOn;
        [items addObject:replayAction];
    }

    UIAction *openSettings = [UIAction actionWithTitle:SCILocalized(@"Messages settings")
                                                 image:[UIImage systemImageNamed:@"gear"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *_) {
        UIWindow *win = window;
        if (!win) {
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
        }
        [SCIUtils showSettingsVC:win atTopLevelEntry:SCILocalized(@"Messages")];
    }];
    [items addObject:openSettings];

    return [UIMenu menuWithTitle:@"" children:items];
}

// Extract thread info from an IGDirectThreadViewController
static NSDictionary *sciEntryFromThreadVC(UIViewController *vc) {
    if (!vc) return nil;
    NSString *tid = sciThreadIdForVC(vc);
    if (!tid) return nil;
    NSString *name = @"";
    NSMutableArray *users = [NSMutableArray array];
    @try {
        // Try to get thread title from navigation item
        name = vc.navigationItem.title ?: @"";
        // Try to get the thread object for user info
        id thread = [vc valueForKey:@"thread"];
        if (thread) {
            id threadUsers = [thread valueForKey:@"users"];
            if ([threadUsers isKindOfClass:[NSArray class]]) {
                for (id u in (NSArray *)threadUsers) {
                    NSMutableDictionary *d = [NSMutableDictionary dictionary];
                    @try {
                        id pk = [u valueForKey:@"pk"];
                        id un = [u valueForKey:@"username"];
                        id fn = [u valueForKey:@"fullName"];
                        if (pk) d[@"pk"] = [NSString stringWithFormat:@"%@", pk];
                        if (un) d[@"username"] = [NSString stringWithFormat:@"%@", un];
                        if (fn) d[@"fullName"] = [NSString stringWithFormat:@"%@", fn];
                    } @catch (__unused id e) {}
                    if (d.count) [users addObject:d];
                }
            }
        }
    } @catch (__unused id e) {}
    return @{ @"threadId": tid, @"threadName": name, @"isGroup": @NO, @"users": users };
}

%hook IGTallNavigationBarView

%new - (void)sciAddToListHandler:(UIBarButtonItem *)sender {
    UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:self];
    NSDictionary *entry = sciEntryFromThreadVC(nearestVC);
    if (!entry) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"Add to block list?")
                         message:SCILocalized(@"Read receipts will be blocked for this chat.")
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Add") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [SCIExcludedThreads addOrUpdateEntry:entry];
        [SCIUtils showToastForDuration:2.0 title:SCILocalized(@"Added to block list")];
        sciRefreshNavBarItems(weakSelf);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [nearestVC presentViewController:alert animated:YES completion:nil];
}

%new - (void)sciUnexcludeButtonHandler:(UIBarButtonItem *)sender {
    UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:self];
    NSString *tid = sciThreadIdForVC(nearestVC);
    if (!tid) return;

    BOOL bs = [SCIExcludedThreads isBlockSelectedMode];
    NSString *alertTitle = bs ? SCILocalized(@"Remove from block list?") : SCILocalized(@"Un-exclude chat?");
    NSString *alertMsg = bs ? SCILocalized(@"Read receipts will no longer be blocked for this chat.")
                            : SCILocalized(@"This chat will resume normal read-receipt behavior.");
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:alertTitle message:alertMsg preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [SCIExcludedThreads removeThreadId:tid];
        [SCIUtils showToastForDuration:2.0 title:SCILocalized(@"Removed")];
        sciRefreshNavBarItems(weakSelf);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [nearestVC presentViewController:alert animated:YES completion:nil];
}
- (void)setRightBarButtonItems:(NSArray <UIBarButtonItem *> *)items {
    // Strip our own injected buttons (so re-runs don't dupe) and drop
    // IGDirectCallButton-backed items when their hide pref is on — some
    // account variants bundle them into the same platter as our eye btn.
    BOOL hideVoice = [SCIUtils getBoolPref:@"hide_voice_call_button"];
    BOOL hideVideo = [SCIUtils getBoolPref:@"hide_video_call_button"];
    BOOL hideBlend = [SCIUtils getBoolPref:@"hide_reels_blend"];
    NSMutableArray *new_items = [[items filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(UIBarButtonItem *value, NSDictionary *_) {
            NSString *aid = value.accessibilityIdentifier;
            if ([aid isEqualToString:@"sci-seen-btn"] ||
                [aid isEqualToString:@"sci-unex-btn"] ||
                [aid isEqualToString:@"sci-visual-btn"]) return NO;
            if (hideBlend && [aid isEqualToString:@"blend-button"]) return NO;
            UIView *cv = value.customView;
            if (cv && [cv isKindOfClass:NSClassFromString(@"IGDirectCallButton")]) {
                NSString *cvAx = cv.accessibilityIdentifier;
                if (hideVoice && [cvAx isEqualToString:@"audio-call"]) return NO;
                if (hideVideo && [cvAx isEqualToString:@"video-chat"]) return NO;
            }
            return YES;
        }]
    ] mutableCopy];

    // setRightBarButtonItems: runs before viewDidAppear: fires, so the global
    // active thread id isn't reliable here — read it directly from the VC.
    UIViewController *navNearestVC = [SCIUtils nearestViewControllerForView:self];
    NSString *navThreadId = sciThreadIdForVC(navNearestVC);
    BOOL navExcluded = navThreadId && [SCIExcludedThreads isThreadIdExcluded:navThreadId];
    BOOL navInList = navThreadId && [SCIExcludedThreads isInList:navThreadId];

    if ([SCIUtils getBoolPref:@"remove_lastseen"] && !navExcluded) {
        UIBarButtonItem *seenButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"eye"] style:UIBarButtonItemStylePlain target:self action:@selector(seenButtonHandler:)];
        seenButton.accessibilityIdentifier = @"sci-seen-btn";
        if (sciIsSeenToggleMode())
            [seenButton setTintColor:dmSeenToggleEnabled ? SCIUtils.SCIColor_Primary : UIColor.labelColor];
        seenButton.menu = sciBuildThreadActionsMenu(self, navThreadId, self.window);
        [new_items addObject:seenButton];
    }

    // In block_all: show remove button for listed (excluded) chats
    // In block_selected: show remove button for listed chats, or add button for non-listed chats
    BOOL blockSelected = [SCIExcludedThreads isBlockSelectedMode];
    BOOL showListButton = [SCIUtils getBoolPref:@"remove_lastseen"] && [SCIUtils getBoolPref:@"chat_quick_list_button"];
    // block_all + in list: show remove button (no seen button shown for excluded chats)
    // block_selected + NOT in list: show add-to-list button
    // block_selected + in list: DON'T show (seen button already visible with long-press menu)
    BOOL showRemoveBtn = !blockSelected && navInList && navExcluded;
    BOOL showAddBtn = blockSelected && !navInList;
    if (showListButton && (showRemoveBtn || showAddBtn)) {
        SEL action = showRemoveBtn ? @selector(sciUnexcludeButtonHandler:) : @selector(sciAddToListHandler:);
        UIBarButtonItem *listBtn = [[UIBarButtonItem alloc]
            initWithImage:[UIImage systemImageNamed:showRemoveBtn ? @"eye.slash.fill" : @"eye.slash"]
                    style:UIBarButtonItemStylePlain
                   target:self
                   action:action];
        listBtn.accessibilityIdentifier = @"sci-unex-btn";
        listBtn.tintColor = showRemoveBtn ? SCIUtils.SCIColor_Primary : UIColor.labelColor;
        listBtn.menu = sciBuildThreadActionsMenu(self, navThreadId, self.window);
        [new_items addObject:listBtn];
    }

    // Replay toggle: in eye menu when eye button exists, standalone button otherwise
    BOOL eyeButtonOn = [SCIUtils getBoolPref:@"remove_lastseen"];
    if ([SCIUtils getBoolPref:@"unlimited_replay"] && !navExcluded && !eyeButtonOn) {
        UIBarButtonItem *replayBtn = [[UIBarButtonItem alloc]
            initWithImage:[UIImage systemImageNamed:dmVisualMsgsViewedButtonEnabled ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill"]
                    style:UIBarButtonItemStylePlain target:self action:@selector(sciReplayToggleHandler:)];
        replayBtn.accessibilityIdentifier = @"sci-visual-btn";
        replayBtn.tintColor = dmVisualMsgsViewedButtonEnabled ? UIColor.labelColor : SCIUtils.SCIColor_Primary;
        [new_items addObject:replayBtn];
    }

    %orig([new_items copy]);
}

// ============ MESSAGES SEEN BUTTON ============

%new - (void)seenButtonHandler:(UIBarButtonItem *)sender {
    if (sciIsSeenToggleMode()) {
        dmSeenToggleEnabled = !dmSeenToggleEnabled;
        [sender setTintColor:dmSeenToggleEnabled ? SCIUtils.SCIColor_Primary : UIColor.labelColor];
        if (dmSeenToggleEnabled) {
            UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:self];
            if ([nearestVC isKindOfClass:%c(IGDirectThreadViewController)])
                [(IGDirectThreadViewController *)nearestVC markLastMessageAsSeen];
            [SCIUtils showToastForDuration:2.5 title:SCILocalized(@"Read receipts enabled")];
        } else {
            [SCIUtils showToastForDuration:2.5 title:SCILocalized(@"Read receipts disabled")];
        }
    } else {
        UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:self];
        if ([nearestVC isKindOfClass:%c(IGDirectThreadViewController)]) {
            [(IGDirectThreadViewController *)nearestVC markLastMessageAsSeen];
            [SCIUtils showToastForDuration:2.5 title:SCILocalized(@"Marked messages as seen")];
        }
    }
    // Rebuild menu so toggle text updates
    UIViewController *navNearestVC = [SCIUtils nearestViewControllerForView:self];
    NSString *tid = sciThreadIdForVC(navNearestVC);
    sender.menu = sciBuildThreadActionsMenu(self, tid, ((UIView *)self).window);
}

%new - (void)sciReplayToggleHandler:(UIBarButtonItem *)sender {
    dmVisualMsgsViewedButtonEnabled = !dmVisualMsgsViewedButtonEnabled;
    sender.image = [UIImage systemImageNamed:dmVisualMsgsViewedButtonEnabled ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill"];
    sender.tintColor = dmVisualMsgsViewedButtonEnabled ? UIColor.labelColor : SCIUtils.SCIColor_Primary;
    [SCIUtils showToastForDuration:2.0 title:dmVisualMsgsViewedButtonEnabled
        ? SCILocalized(@"Visual messages will expire") : SCILocalized(@"Unlimited replay enabled")];
}

%end

// ============ SEEN BLOCKING LOGIC ============

%hook IGDirectThreadViewListAdapterDataSource
- (BOOL)shouldUpdateLastSeenMessage {
    if ([SCIUtils getBoolPref:@"remove_lastseen"]) {
        if ([SCIExcludedThreads isActiveThreadExcluded]) return %orig; // excluded → behave normally
        if (sciIsSeenToggleMode() && dmSeenToggleEnabled) return %orig;
        if (sciSeenAutoBypassCount > 0) return %orig;
        return false;
    }
    return %orig;
}
%end

// ============ DM VISUAL MESSAGES VIEWED LOGIC ============

%hook IGDirectVisualMessageViewerEventHandler
- (void)visualMessageViewerController:(id)arg1 didBeginPlaybackForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 {
    if ([SCIUtils getBoolPref:@"unlimited_replay"] && !dmVisualMsgsViewedButtonEnabled
        && ![SCIExcludedThreads isActiveThreadExcluded]) return;
    %orig;
}
- (void)visualMessageViewerController:(id)arg1 didEndPlaybackForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 mediaCurrentTime:(CGFloat)arg4 forNavType:(NSInteger)arg5 {
    if ([SCIUtils getBoolPref:@"unlimited_replay"] && !dmVisualMsgsViewedButtonEnabled
        && ![SCIExcludedThreads isActiveThreadExcluded]) return;
    %orig;
}
%end

// ============ RUNTIME HOOKS ============

%ctor {
    Class threadVCClass = NSClassFromString(@"IGDirectThreadViewController");
    if (threadVCClass) {
        SEL sentSel = NSSelectorFromString(@"setHasSentAMessageOrUpdate:");
        if (class_getInstanceMethod(threadVCClass, sentSel)) {
            MSHookMessageEx(threadVCClass, sentSel,
                            (IMP)new_setHasSent, (IMP *)&orig_setHasSent);
        }
    }
}
