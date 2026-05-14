// Liquid glass tab bar — Default / Fixed / Hide on scroll.
// IG drives the shrink via -setScaleProgress: on IGLiquidGlassInteractiveTabBar
// (0 = normal, ~0.2 = fully shrunk). We clamp it or hide+translate the bar.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

typedef NS_ENUM(NSInteger, SCITabBarMode) {
    SCITabBarModeDefault = 0,
    SCITabBarModeFixed   = 1,
    SCITabBarModeHide    = 2,
};

static SCITabBarMode sciTabBarMode(void) {
    NSString *v = [SCIUtils getStringPref:@"liquid_glass_tabbar_mode"];
    if ([v isEqualToString:@"fixed"]) return SCITabBarModeFixed;
    if ([v isEqualToString:@"hide"])  return SCITabBarModeHide;
    return SCITabBarModeDefault;
}

static const void *kSCITabBarHiddenKey = &kSCITabBarHiddenKey;

static void sciApplyTabBarHideState(UIView *bar, BOOL hide) {
    NSNumber *cur = objc_getAssociatedObject(bar, kSCITabBarHiddenKey);
    if (cur && cur.boolValue == hide) return;
    objc_setAssociatedObject(bar, kSCITabBarHiddenKey, @(hide), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGFloat dropY = CGRectGetHeight(bar.bounds) + 40.0;
    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:0.9
          initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        bar.transform = hide ? CGAffineTransformMakeTranslation(0, dropY) : CGAffineTransformIdentity;
        bar.alpha     = hide ? 0.0 : 1.0;
    } completion:nil];
}

static void (*orig_setScaleProgress)(id, SEL, double) = NULL;
static void hook_setScaleProgress(id self, SEL _cmd, double progress) {
    SCITabBarMode mode = sciTabBarMode();
    if (mode == SCITabBarModeFixed) {
        progress = 0.0;
    } else if (mode == SCITabBarModeHide) {
        sciApplyTabBarHideState((UIView *)self, progress > 0.05);
        progress = 0.0;
    }
    if (orig_setScaleProgress) orig_setScaleProgress(self, _cmd, progress);
}

static void (*orig_scaleDownWithInteraction)(id, SEL, id) = NULL;
static void hook_scaleDownWithInteraction(id self, SEL _cmd, id interaction) {
    if (sciTabBarMode() != SCITabBarModeDefault) return;
    if (orig_scaleDownWithInteraction) orig_scaleDownWithInteraction(self, _cmd, interaction);
}

%ctor {
    if (sciTabBarMode() == SCITabBarModeDefault) return;

    Class ltb = objc_getClass("IGLiquidGlassInteractiveTabBar");
    if (!ltb) return;
    MSHookMessageEx(ltb, @selector(setScaleProgress:),         (IMP)hook_setScaleProgress,         (IMP *)&orig_setScaleProgress);
    MSHookMessageEx(ltb, @selector(scaleDownWithInteraction:), (IMP)hook_scaleDownWithInteraction, (IMP *)&orig_scaleDownWithInteraction);
}
