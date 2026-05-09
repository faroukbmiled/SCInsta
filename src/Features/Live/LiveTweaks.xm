// Live-stream tweaks — anonymous viewing + long-press heart to hide comments.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

// MARK: - Anonymous viewing

static void sciDisableViewerCountPuller(id feedbackController) {
    Ivar pullerIvar = class_getInstanceVariable([feedbackController class], "_viewCountPuller");
    if (!pullerIvar) return;
    id puller = object_getIvar(feedbackController, pullerIvar);
    if (!puller) return;

    // Ivars live on the IGLiveIntervalPuller superclass.
    Ivar activeIvar = NULL;
    Ivar timerIvar = NULL;
    for (Class c = [puller class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        if (!activeIvar) activeIvar = class_getInstanceVariable(c, "_isActive");
        if (!timerIvar)  timerIvar  = class_getInstanceVariable(c, "_nextFetchTimer");
        if (activeIvar && timerIvar) break;
    }
    if (activeIvar) {
        ptrdiff_t off = ivar_getOffset(activeIvar);
        *(BOOL *)((char *)(__bridge void *)puller + off) = NO;
    }
    if (timerIvar) {
        id timer = object_getIvar(puller, timerIvar);
        if (timer && [timer respondsToSelector:@selector(invalidate)]) {
            ((void(*)(id, SEL))objc_msgSend)(timer, @selector(invalidate));
        }
    }
}

%hook IGLiveFeedbackController
- (void)start {
    %orig;
    if ([SCIUtils getBoolPref:@"live_anonymous_view"]) {
        sciDisableViewerCountPuller(self);
    }
}
%end

// MARK: - Hide comments (session-only)

// Session-only — state resets on each new comments VC appearance.
static __weak UIViewController *gActiveLiveCommentsVC = nil;
static BOOL gCommentsHidden = NO;
static const void *kSCIHeartAttachedKey = &kSCIHeartAttachedKey;

// Only hide the scrolling collection — keep input + like usable.
static void sciHideCommentCollections(UIView *root, BOOL hide, int depth) {
    if (!root || depth > 8) return;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:[UICollectionView class]]) {
            sub.alpha = hide ? 0.0 : 1.0;
            sub.userInteractionEnabled = !hide;
            continue;
        }
        sciHideCommentCollections(sub, hide, depth + 1);
    }
}

static void sciApplyCommentsStateTo(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return;
    sciHideCommentCollections(vc.view, gCommentsHidden, 0);
}

extern "C" void sciRefreshLiveCommentsHidden(void) {
    sciApplyCommentsStateTo(gActiveLiveCommentsVC);
}

static void sciAttachLongPressToView(UIView *v);

// Heart lives in the footer's _likeButton ivar.
%hook IGLiveFooterButtonsView
- (void)layoutSubviews {
    %orig;
    id obj = (id)self;
    Ivar iv = class_getInstanceVariable([obj class], "_likeButton");
    if (!iv) return;
    UIView *btn = object_getIvar(obj, iv);
    if (btn) sciAttachLongPressToView(btn);
}
%end

%hook IGLiveCommentsContainerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gActiveLiveCommentsVC = self;
    gCommentsHidden = NO;
    sciApplyCommentsStateTo(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (gActiveLiveCommentsVC == self) gActiveLiveCommentsVC = nil;
}
%end

// MARK: - Long-press heart → toggle comments

@interface SCILiveLikeLongPress : NSObject
+ (instancetype)shared;
- (void)fired:(UILongPressGestureRecognizer *)g;
@end

@implementation SCILiveLikeLongPress
+ (instancetype)shared {
    static SCILiveLikeLongPress *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SCILiveLikeLongPress new]; });
    return s;
}
- (void)fired:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (![SCIUtils getBoolPref:@"live_hide_comments"]) return;
    gCommentsHidden = !gCommentsHidden;
    sciRefreshLiveCommentsHidden();
    SCINotifySuccess(SCI_NOTIF_LIVE_TOGGLE,
                     gCommentsHidden ? SCILocalized(@"Comments hidden") : SCILocalized(@"Comments shown"),
                     nil);
}
@end

static void sciAttachLongPressToView(UIView *v) {
    if (!v || objc_getAssociatedObject(v, kSCIHeartAttachedKey)) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[SCILiveLikeLongPress shared] action:@selector(fired:)];
    g.minimumPressDuration = 0.5;
    // Swallow the tap so the reactions sheet doesn't open.
    g.cancelsTouchesInView = YES;
    [v addGestureRecognizer:g];
    objc_setAssociatedObject(v, kSCIHeartAttachedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
