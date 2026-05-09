#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../UI/SCIColorPickerSheet.h"
#import <objc/runtime.h>

// Long-press the color wheel on a music or lyric sticker → action sheet [Solid / Gradient] →
// bottom sheet with SCIColorPickerSheet (shared with Notes customization).

#pragma mark - Helpers

static UIColor *SCIGradientPatternColor(UIColor *start, UIColor *end, CGSize size) {
    if (size.width < 1 || size.height < 1) size = CGSizeMake(300, 60);
    UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(__bridge id)start.CGColor, (__bridge id)end.CGColor];
    CGFloat locations[2] = {0.0, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(ctx, gradient, CGPointZero, CGPointMake(size.width, 0), 0);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGGradientRelease(gradient);
    CGColorSpaceRelease(cs);
    return [UIColor colorWithPatternImage:img];
}

static void SCISetStickerColor(UIView *sticker, UIColor *color) {
    if (!sticker || !color) return;
    if ([sticker respondsToSelector:@selector(setColor:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(sticker, @selector(setColor:), color);
    }
}

static UIView *SCIFindDynamicRevealView(UIView *root) {
    if (!root) return nil;
    if ([NSStringFromClass([root class]) isEqualToString:@"IGDynamicRevealDynamicTextView"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *hit = SCIFindDynamicRevealView(sub);
        if (hit) return hit;
    }
    return nil;
}

// Dual-label "dynamic reveal" lyric variant: setColor:patternImage breaks textColor rendering.
// Apply per-label gradient to the x=0 fill labels and leave the x=8 white highlights alone.
static BOOL SCIApplyDynamicRevealGradient(UIView *sticker, UIColor *start, UIColor *end) {
    UIView *dynView = SCIFindDynamicRevealView(sticker);
    if (!dynView) return NO;
    for (UIView *sub in dynView.subviews) {
        if (![sub isKindOfClass:[UILabel class]]) continue;
        UILabel *label = (UILabel *)sub;
        if (label.frame.origin.x > 0.5) continue;
        CGSize size = label.bounds.size;
        if (size.width < 1 || size.height < 1) continue;
        label.textColor = SCIGradientPatternColor(start, end, size);
        [label setNeedsDisplay];
    }
    return YES;
}

static void SCIScanForStickers(UIView *root, NSMutableArray *out) {
    if (!root) return;
    NSString *cls = NSStringFromClass([root class]);
    if (([cls containsString:@"Music"] || [cls containsString:@"Lyric"]) && [root respondsToSelector:@selector(setColor:)]) {
        [out addObject:root];
    }
    for (UIView *sub in root.subviews) SCIScanForStickers(sub, out);
}

static UIView *SCIFindMusicStickerNearWheel(UIView *wheel) {
    NSMutableArray *candidates = [NSMutableArray array];
    NSMutableArray *windows = [NSMutableArray array];
    if (wheel.window) [windows addObject:wheel.window];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (![windows containsObject:w]) [windows addObject:w];
        }
    }
    for (UIWindow *w in windows) SCIScanForStickers(w, candidates);
    for (UIView *v in candidates) {
        if ([NSStringFromClass([v class]) containsString:@"Sticker"]) return v;
    }
    return candidates.firstObject;
}

#pragma mark - Hook

@interface IGStoryColorPaletteWheel (SCIMusicColor)
- (void)sciHandleLongPress:(UILongPressGestureRecognizer *)sender;
- (void)sciPresentSheetWithMode:(SCIColorPickerSheetMode)mode sticker:(UIView *)sticker presenter:(UIViewController *)presenter;
@end

%hook IGStoryColorPaletteWheel

- (void)didMoveToWindow {
    %orig;
    if ([SCIUtils getBoolPref:@"custom_music_sticker_color"]) {
        [self addLongPressGestureRecognizer];
    }
}

%new
- (void)addLongPressGestureRecognizer {
    for (UIGestureRecognizer *g in self.gestureRecognizers) {
        if ([g isKindOfClass:[UILongPressGestureRecognizer class]]) return;
    }
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sciHandleLongPress:)];
    lp.minimumPressDuration = 0.25;
    [self addGestureRecognizer:lp];
}

%new
- (void)sciHandleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    UIView *sticker = SCIFindMusicStickerNearWheel(self);
    if (!sticker) return;
    UIViewController *presenter = [SCIUtils nearestViewControllerForView:self];
    if (!presenter) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Custom music sticker color")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Solid color")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_a) {
        [self sciPresentSheetWithMode:SCIColorPickerSheetModeSolid sticker:sticker presenter:presenter];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Gradient color")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_a) {
        [self sciPresentSheetWithMode:SCIColorPickerSheetModeGradient sticker:sticker presenter:presenter];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self;
        sheet.popoverPresentationController.sourceRect = self.bounds;
    }

    [presenter presentViewController:sheet animated:YES completion:nil];
}

%new
- (void)sciPresentSheetWithMode:(SCIColorPickerSheetMode)mode sticker:(UIView *)sticker presenter:(UIViewController *)presenter {
    __weak UIView *weakSticker = sticker;
    SCIColorPickerSheet *vc = [SCIColorPickerSheet sheetWithMode:mode
                                                      startColor:nil
                                                        endColor:nil
                                                    applyHandler:^(SCIColorPickerSheetMode m, UIColor *primary, UIColor *secondary) {
        UIView *s = weakSticker;
        if (!s) return;
        if (m == SCIColorPickerSheetModeGradient && secondary) {
            if (!SCIApplyDynamicRevealGradient(s, primary, secondary)) {
                UIColor *pattern = SCIGradientPatternColor(primary, secondary, s.bounds.size);
                SCISetStickerColor(s, pattern);
            }
        } else {
            SCISetStickerColor(s, primary);
        }
    }];
    [vc presentFromViewController:presenter];
}

%end
