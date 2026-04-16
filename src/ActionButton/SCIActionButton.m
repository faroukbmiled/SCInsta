#import "SCIActionButton.h"
#import "SCIActionMenu.h"
#import "SCIRepostSheet.h"
#import "../Utils.h"
#import <objc/runtime.h>

// Associated-object keys for per-button config.
static const void *kSCICtxKey       = &kSCICtxKey;
static const void *kSCIProviderKey  = &kSCIProviderKey;
static const void *kSCIPrefKey      = &kSCIPrefKey;
const void *kSCIDismissKey   = &kSCIDismissKey;


@interface SCIActionButton () <UIContextMenuInteractionDelegate>
@end

@implementation SCIActionButton

// Singleton delegate for UIContextMenuInteraction.
+ (instancetype)shared {
    static SCIActionButton *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SCIActionButton new]; });
    return s;
}

+ (UIMenu *)deferredMenuForContext:(SCIActionContext)ctx
                          fromView:(UIView *)sourceView
                     mediaProvider:(SCIActionMediaProvider)provider {
    __weak UIView *weakSource = sourceView;
    SCIActionMediaProvider capturedProvider = [provider copy];

    UIDeferredMenuElement *deferred = [UIDeferredMenuElement
        elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> * _Nonnull)) {
        UIView *view = weakSource;
        id media = (view && capturedProvider) ? capturedProvider(view) : nil;
        NSArray *actions = [SCIMediaActions actionsForContext:ctx
                                                        media:media
                                                     fromView:view];
        UIMenu *built = [SCIActionMenu buildMenuWithActions:actions];
        completion(built.children);
    }];

    return [UIMenu menuWithTitle:@""
                           image:nil
                      identifier:nil
                         options:0
                        children:@[deferred]];
}

+ (void)configureButton:(UIButton *)button
                context:(SCIActionContext)ctx
                prefKey:(NSString *)prefKey
          mediaProvider:(SCIActionMediaProvider)provider {
    if (!button) return;

    // Stash config on the button.
    objc_setAssociatedObject(button, kSCICtxKey, @(ctx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, kSCIProviderKey, [provider copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(button, kSCIPrefKey, [prefKey copy], OBJC_ASSOCIATION_COPY_NONATOMIC);

    // Read default tap mode fresh.
    NSString *defaultTap = [SCIUtils getStringPref:prefKey];
    if (!defaultTap.length) defaultTap = @"menu";

    // Remove previous wiring to stay idempotent.
    [button removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    for (id<UIInteraction> it in [button.interactions copy]) {
        if ([(id)it isKindOfClass:[UIContextMenuInteraction class]]) {
            [button removeInteraction:it];
        }
    }

    if ([defaultTap isEqualToString:@"menu"]) {
        // Tap opens menu natively.
        button.menu = [self deferredMenuForContext:ctx fromView:button mediaProvider:provider];
        button.showsMenuAsPrimaryAction = YES;
        return;
    }

    // Tap fires dedicated action; long-press opens menu.
    button.showsMenuAsPrimaryAction = NO;
    button.menu = nil;
    [button addTarget:[self shared]
               action:@selector(sciTapHandler:)
     forControlEvents:UIControlEventTouchUpInside];

    UIContextMenuInteraction *interaction =
        [[UIContextMenuInteraction alloc] initWithDelegate:[self shared]];
    [button addInteraction:interaction];
}

// Haptic + scale-bounce feedback.
+ (void)bounceButton:(UIView *)view {
    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [UIView animateWithDuration:0.1
                     animations:^{ view.transform = CGAffineTransformMakeScale(0.82, 0.82); }
                     completion:^(BOOL _) {
        [UIView animateWithDuration:0.1 animations:^{
            view.transform = CGAffineTransformIdentity;
        }];
    }];
}

// Default-tap handler.
- (void)sciTapHandler:(UIButton *)sender {
    [SCIActionButton bounceButton:sender];

    NSNumber *ctxNum = objc_getAssociatedObject(sender, kSCICtxKey);
    SCIActionMediaProvider provider = objc_getAssociatedObject(sender, kSCIProviderKey);
    NSString *prefKey = objc_getAssociatedObject(sender, kSCIPrefKey);
    if (!ctxNum || !provider) return;

    NSString *tap = [SCIUtils getStringPref:prefKey];
    if (!tap.length) tap = @"menu";
    id media = provider(sender);
    if (media == (id)kCFNull) return;

    if ([tap isEqualToString:@"expand"]) {
        [SCIMediaActions expandMedia:media fromView:sender caption:nil];
    } else if ([tap isEqualToString:@"download_share"]) {
        [SCIMediaActions downloadAndShareMedia:media];
    } else if ([tap isEqualToString:@"download_photos"]) {
        [SCIMediaActions downloadAndSaveMedia:media];
    } else if ([tap isEqualToString:@"copy_link"]) {
        [SCIMediaActions copyURLForMedia:media];
    } else if ([tap isEqualToString:@"repost"]) {
        NSURL *vidURL = [SCIUtils getVideoUrlForMedia:(id)media];
        NSURL *imgURL = [SCIUtils getPhotoUrlForMedia:(id)media];
        [SCIRepostSheet repostWithVideoURL:vidURL photoURL:imgURL];
    } else if ([tap isEqualToString:@"view_mentions"]) {
        UIViewController *host = [SCIUtils nearestViewControllerForView:sender];
        if (host) {
            extern void sciShowStoryMentions(UIViewController *, UIView *);
            sciShowStoryMentions(host, sender);
        }
    }
}

// MARK: - UIContextMenuInteractionDelegate

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    UIView *view = interaction.view;
    NSNumber *ctxNum = objc_getAssociatedObject(view, kSCICtxKey);
    SCIActionMediaProvider provider = objc_getAssociatedObject(view, kSCIProviderKey);
    if (!ctxNum || !provider) return nil;
    SCIActionContext ctx = (SCIActionContext)ctxNum.integerValue;

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggested) {
        return [SCIActionButton deferredMenuForContext:ctx
                                              fromView:view
                                         mediaProvider:provider];
    }];
}

- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
    willEndForConfiguration:(UIContextMenuConfiguration *)configuration
                   animator:(id<UIContextMenuInteractionAnimating>)animator {
    UIView *view = interaction.view;
    void (^dismiss)(void) = objc_getAssociatedObject(view, kSCIDismissKey);
    if (dismiss) {
        if (animator) {
            [animator addCompletion:^{ dismiss(); }];
        } else {
            dismiss();
        }
    }
}

@end
