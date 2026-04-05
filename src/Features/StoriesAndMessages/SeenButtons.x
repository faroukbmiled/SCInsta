#import "../../InstagramHeaders.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>


// Seen buttons (in DMs)
// - Enables no seen for messages
// - Enables unlimited views of DM visual messages

BOOL dmSeenToggleEnabled = NO;
static BOOL sciSeenAutoBypass = NO;

static BOOL sciIsSeenToggleMode() {
    return [[SCIUtils getStringPref:@"seen_mode"] isEqualToString:@"toggle"];
}

static BOOL sciAutoInteractEnabled() {
    return [SCIUtils getBoolPref:@"remove_lastseen"] && [SCIUtils getBoolPref:@"seen_auto_on_interact"];
}

static void sciDoAutoSeen(IGDirectThreadViewController *threadVC) {
    sciSeenAutoBypass = YES;
    [threadVC markLastMessageAsSeen];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciSeenAutoBypass = NO;
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

// ============ NAV BAR BUTTONS ============

%hook IGTallNavigationBarView
- (void)setRightBarButtonItems:(NSArray <UIBarButtonItem *> *)items {
    NSMutableArray *new_items = [[items filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(UIView *value, NSDictionary *_) {
            if ([SCIUtils getBoolPref:@"hide_reels_blend"])
                return ![value.accessibilityIdentifier isEqualToString:@"blend-button"];
            return true;
        }]
    ] mutableCopy];

    if ([SCIUtils getBoolPref:@"remove_lastseen"]) {
        UIBarButtonItem *seenButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.message"] style:UIBarButtonItemStylePlain target:self action:@selector(seenButtonHandler:)];
        if (sciIsSeenToggleMode())
            [seenButton setTintColor:dmSeenToggleEnabled ? SCIUtils.SCIColor_Primary : UIColor.labelColor];
        [new_items addObject:seenButton];
    }

    if ([SCIUtils getBoolPref:@"unlimited_replay"]) {
        UIBarButtonItem *dmVisualMsgsViewedButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"photo.badge.checkmark"] style:UIBarButtonItemStylePlain target:self action:@selector(dmVisualMsgsViewedButtonHandler:)];
        [new_items addObject:dmVisualMsgsViewedButton];
        [dmVisualMsgsViewedButton setTintColor:dmVisualMsgsViewedButtonEnabled ? SCIUtils.SCIColor_Primary : UIColor.labelColor];
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
            [SCIUtils showToastForDuration:2.5 title:@"Read receipts enabled"];
        } else {
            [SCIUtils showToastForDuration:2.5 title:@"Read receipts disabled"];
        }
    } else {
        UIViewController *nearestVC = [SCIUtils nearestViewControllerForView:self];
        if ([nearestVC isKindOfClass:%c(IGDirectThreadViewController)]) {
            [(IGDirectThreadViewController *)nearestVC markLastMessageAsSeen];
            [SCIUtils showToastForDuration:2.5 title:@"Marked messages as seen"];
        }
    }
}

// ============ DM VISUAL MESSAGES VIEWED BUTTON ============

%new - (void)dmVisualMsgsViewedButtonHandler:(UIBarButtonItem *)sender {
    if (dmVisualMsgsViewedButtonEnabled) {
        dmVisualMsgsViewedButtonEnabled = false;
        [sender setTintColor:UIColor.labelColor];
        [SCIUtils showToastForDuration:4.5 title:@"Visual messages can be replayed without expiring"];
    } else {
        dmVisualMsgsViewedButtonEnabled = true;
        [sender setTintColor:SCIUtils.SCIColor_Primary];
        [SCIUtils showToastForDuration:4.5 title:@"Visual messages will now expire after viewing"];
    }
}
%end

// ============ SEEN BLOCKING LOGIC ============

%hook IGDirectThreadViewListAdapterDataSource
- (BOOL)shouldUpdateLastSeenMessage {
    if ([SCIUtils getBoolPref:@"remove_lastseen"]) {
        if (sciIsSeenToggleMode() && dmSeenToggleEnabled) return %orig;
        if (sciSeenAutoBypass) return %orig;
        return false;
    }
    return %orig;
}
%end

// ============ DM VISUAL MESSAGES VIEWED LOGIC ============

%hook IGDirectVisualMessageViewerEventHandler
- (void)visualMessageViewerController:(id)arg1 didBeginPlaybackForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 {
    if ([SCIUtils getBoolPref:@"unlimited_replay"] && !dmVisualMsgsViewedButtonEnabled) return;
    %orig;
}
- (void)visualMessageViewerController:(id)arg1 didEndPlaybackForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 mediaCurrentTime:(CGFloat)arg4 forNavType:(NSInteger)arg5 {
    if ([SCIUtils getBoolPref:@"unlimited_replay"] && !dmVisualMsgsViewedButtonEnabled) return;
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
