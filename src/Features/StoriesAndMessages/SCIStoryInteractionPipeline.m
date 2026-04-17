#import "SCIStoryInteractionPipeline.h"
#import "StoryHelpers.h"
#import "../../Utils.h"
#import <objc/message.h>
#import <mach/mach_time.h>

extern __weak UIViewController *sciActiveStoryVC;
extern BOOL sciAdvanceBypassActive;

#pragma mark - Policy table

typedef struct {
    NSString *confirmPref;
    NSString *seenPref;
    NSString *advancePref;
    NSTimeInterval advanceDelay;
} SCIStoryPolicy;

static SCIStoryPolicy sciPolicyForType(SCIStoryInteraction type) {
    switch (type) {
        case SCIStoryInteractionLike:
            return (SCIStoryPolicy){
                @"story_like_confirm",
                @"seen_on_story_like",
                @"advance_on_story_like",
                0.3
            };
        case SCIStoryInteractionEmojiReaction:
            return (SCIStoryPolicy){
                @"emoji_reaction_confirm",
                @"seen_on_story_reply",
                @"advance_on_story_reply",
                0.4
            };
        case SCIStoryInteractionTextReply:
            return (SCIStoryPolicy){
                nil,
                @"seen_on_story_reply",
                @"advance_on_story_reply",
                0.4
            };
    }
    return (SCIStoryPolicy){ nil, nil, nil, 0.3 };
}

#pragma mark - Side effects

static UIView *sciFindOverlay(UIViewController *vc) {
    if (!vc) return nil;
    Class cls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!cls) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:cls]) return v;
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return nil;
}

static void sciMarkSeen(NSString *prefKey) {
    if (!prefKey || ![SCIUtils getBoolPref:prefKey]) return;
    UIView *overlay = sciFindOverlay(sciActiveStoryVC);
    if (!overlay) return;
    SEL sel = NSSelectorFromString(@"sciMarkSeenTapped:");
    if ([overlay respondsToSelector:sel])
        ((void(*)(id, SEL, id))objc_msgSend)(overlay, sel, nil);
}

static uint64_t sciLastAdvanceTime = 0;

static void sciAdvance(NSString *prefKey, NSTimeInterval delay) {
    if (!prefKey || ![SCIUtils getBoolPref:prefKey]) return;
    UIViewController *vc = sciActiveStoryVC;
    if (!vc) return;
    id ctrl = sciFindSectionController(vc);
    if (!ctrl) return;

    uint64_t now = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    if (now - sciLastAdvanceTime < 500000000ULL) return;
    sciLastAdvanceTime = now;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciAdvanceBypassActive = YES;
        SEL advSel = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
        if ([ctrl respondsToSelector:advSel])
            ((void(*)(id, SEL, NSInteger))objc_msgSend)(ctrl, advSel, 1);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id c2 = vc ? sciFindSectionController(vc) : nil;
            if (c2) {
                SEL resumeSel = NSSelectorFromString(@"tryResumePlaybackWithReason:");
                if ([c2 respondsToSelector:resumeSel])
                    ((void(*)(id, SEL, NSInteger))objc_msgSend)(c2, resumeSel, 0);
            }
            sciAdvanceBypassActive = NO;
        });
    });
}

static void sciFireSideEffects(SCIStoryPolicy policy) {
    sciMarkSeen(policy.seenPref);
    sciAdvance(policy.advancePref, policy.advanceDelay);
}

#pragma mark - Pipeline

void sciStoryInteraction(SCIStoryInteraction type,
                         void (^action)(void),
                         void (^_Nullable uiRevert)(void),
                         void (^_Nullable uiReapply)(void)) {
    SCIStoryPolicy policy = sciPolicyForType(type);

    if (policy.confirmPref && [SCIUtils getBoolPref:policy.confirmPref]) {
        if (uiRevert) uiRevert();
        [SCIUtils showConfirmation:^{
            if (uiReapply) uiReapply();
            if (action) action();
            sciFireSideEffects(policy);
        }];
        return;
    }

    if (action) action();
    sciFireSideEffects(policy);
}

void sciStoryInteractionSideEffects(SCIStoryInteraction type) {
    sciFireSideEffects(sciPolicyForType(type));
}
