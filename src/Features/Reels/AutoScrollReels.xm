// Auto-scroll reels. Modes:
//   * ig     — flip IG's own auto-scroll gates; covers video + photo reels
//   * custom — same flag flip (photos) + per-cell loopCount trigger calling
//     WantsScrollToNextItem each loop (videos keep advancing after back-swipe)

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kSCILoopCountKey = &kSCILoopCountKey;
static BOOL sciAdvanceInFlight = NO;

static inline NSString *sciMode(void) {
    NSString *m = [SCIUtils getStringPref:@"auto_scroll_reels_mode"];
    return m.length ? m : @"off";
}
static inline BOOL sciModeOn(void) { return ![sciMode() isEqualToString:@"off"]; }
static inline BOOL sciModeCustom(void) { return [sciMode() isEqualToString:@"custom"]; }

static UIViewController *sciFindFeedVCFromView(UIView *view) {
    UIResponder *r = view;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]] &&
            [NSStringFromClass([r class]) isEqualToString:@"IGSundialFeedViewController"])
            return (UIViewController *)r;
        r = [r nextResponder];
    }
    return nil;
}

%hook IGSundialFeedViewController
- (BOOL)shouldForceEnableAutoScroll {
    if (sciModeOn()) return YES;
    return %orig;
}
- (BOOL)autoAdvanceToNextItem {
    if (sciModeOn()) return YES;
    return %orig;
}
%end

%hook IGSundialViewerVideoCell
- (void)videoView:(id)v didUpdatePlaybackStatus:(id)status {
    %orig;
    if (!sciModeCustom() || !status) return;
    SEL loopSel = @selector(loopCount);
    if (![status respondsToSelector:loopSel]) return;

    long long cur = ((long long(*)(id, SEL))objc_msgSend)(status, loopSel);
    NSNumber *prev = objc_getAssociatedObject(self, kSCILoopCountKey);
    objc_setAssociatedObject(self, kSCILoopCountKey, @(cur), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!prev || cur <= prev.longLongValue || sciAdvanceInFlight) return;

    UIViewController *feedVC = sciFindFeedVCFromView((UIView *)self);
    if (!feedVC || !feedVC.viewIfLoaded.window) return;

    sciAdvanceInFlight = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        SEL wants = @selector(sundialViewerInteractionCoordinatorWantsScrollToNextItemAnimated:);
        if ([feedVC respondsToSelector:wants])
            ((void(*)(id, SEL, BOOL))objc_msgSend)(feedVC, wants, YES);
        sciAdvanceInFlight = NO;
    });
}

- (void)prepareForReuse {
    objc_setAssociatedObject(self, kSCILoopCountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end
