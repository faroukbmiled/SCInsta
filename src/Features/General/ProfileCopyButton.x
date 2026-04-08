#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../../modules/JGProgressHUD/JGProgressHUD.h"
#import <objc/runtime.h>
#import <substrate.h>

// Profile page copy button: hooks IG's native nav header builder to insert
// a copy button alongside IG's own buttons, then opens a menu to copy
// username/name/bio.

@interface IGProfileViewController : UIViewController
@end

static id sci_safeValueForKey(id obj, NSString *key) {
    @try { return [obj valueForKey:key]; }
    @catch (__unused NSException *e) { return nil; }
}

static id sci_valueForAnyKey(id obj, NSArray<NSString *> *keys) {
    for (NSString *k in keys) {
        id v = sci_safeValueForKey(obj, k);
        if (v && v != [NSNull null]) return v;
    }
    return nil;
}

static id sci_findUserOnVC(UIViewController *vc) {
    id user = sci_valueForAnyKey(vc, @[@"user", @"userGQL", @"profileUser", @"loggedInUser", @"currentUser"]);
    if (user) return user;

    Class userCls = NSClassFromString(@"IGUser");
    Class c = [vc class];
    while (c && c != [NSObject class]) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(c, &count);
        for (unsigned int i = 0; i < count; i++) {
            id v = object_getIvar(vc, ivars[i]);
            if (userCls && [v isKindOfClass:userCls]) {
                free(ivars);
                return v;
            }
        }
        if (ivars) free(ivars);
        c = class_getSuperclass(c);
    }
    return nil;
}

static UIViewController *sci_findProfileVC(UIView *view) {
    Class profileCls = NSClassFromString(@"IGProfileViewController");
    UIResponder *r = view;
    while (r) {
        if (profileCls && [r isKindOfClass:profileCls]) return (UIViewController *)r;
        r = [r nextResponder];
    }
    return nil;
}

static void sci_copyAndToast(NSString *value, NSString *label) {
    if (value.length == 0) return;
    [UIPasteboard generalPasteboard].string = value;

    JGProgressHUD *HUD = [[JGProgressHUD alloc] init];
    HUD.textLabel.text = [NSString stringWithFormat:@"Copied %@", label];
    HUD.indicatorView = [[JGProgressHUDSuccessIndicatorView alloc] init];
    UIView *host = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { host = w; break; }
    }
    if (host) {
        [HUD showInView:host];
        [HUD dismissAfterDelay:1.5];
    }
}

// Singleton target for the copy button so we don't have to track lifetime.
@interface SCIProfileCopyTarget : NSObject
+ (instancetype)shared;
- (void)handleTap:(UIButton *)sender;
@end

@implementation SCIProfileCopyTarget
+ (instancetype)shared {
    static SCIProfileCopyTarget *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SCIProfileCopyTarget alloc] init]; });
    return s;
}

- (void)handleTap:(UIButton *)sender {
    UIViewController *vc = sci_findProfileVC(sender);
    if (!vc) {
        NSLog(@"[SCInsta] copy button: no IGProfileViewController in responder chain");
        return;
    }

    id user = sci_findUserOnVC(vc);
    if (!user) {
        NSLog(@"[SCInsta] copy button: no IGUser found on %@", vc.class);
        return;
    }

    NSString *username = [sci_valueForAnyKey(user, @[@"username"]) description];
    NSString *fullName = [sci_valueForAnyKey(user, @[@"fullName", @"fullname", @"name"]) description];
    NSString *biography = [sci_valueForAnyKey(user, @[@"biography", @"bio", @"profileBiography"]) description];

    NSLog(@"[SCInsta] copy button user=%@ name=%@ bioLen=%lu",
          username, fullName, (unsigned long)biography.length);

    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Copy from profile"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    if (username.length) {
        [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Copy username (@%@)", username]
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *_) { sci_copyAndToast(username, @"username"); }]];
    }
    if (fullName.length) {
        [menu addAction:[UIAlertAction actionWithTitle:@"Copy name"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *_) { sci_copyAndToast(fullName, @"name"); }]];
    }
    if (biography.length) {
        [menu addAction:[UIAlertAction actionWithTitle:@"Copy bio"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *_) { sci_copyAndToast(biography, @"bio"); }]];
    }

    NSMutableArray *parts = [NSMutableArray array];
    if (username.length)  [parts addObject:[NSString stringWithFormat:@"Username: @%@", username]];
    if (fullName.length)  [parts addObject:[NSString stringWithFormat:@"Name: %@", fullName]];
    if (biography.length) [parts addObject:[NSString stringWithFormat:@"Bio:\n%@", biography]];

    if (parts.count >= 2) {
        NSString *combined = [parts componentsJoinedByString:@"\n\n"];
        [menu addAction:[UIAlertAction actionWithTitle:@"Copy all"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *_) { sci_copyAndToast(combined, @"all"); }]];
    }

    if (menu.actions.count == 0) {
        [menu addAction:[UIAlertAction actionWithTitle:@"Nothing to copy" style:UIAlertActionStyleDefault handler:nil]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sender) {
        menu.popoverPresentationController.sourceView = sender;
        menu.popoverPresentationController.sourceRect = sender.bounds;
    }

    [vc presentViewController:menu animated:YES completion:nil];
}
@end

static UIView *sci_buildCopyButton(void) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.accessibilityIdentifier = @"sci-profile-copy-button";
    btn.accessibilityLabel = @"Copy profile info";
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:16
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *icon = [[UIImage systemImageNamed:@"doc.on.doc"] imageByApplyingSymbolConfiguration:cfg];
    [btn setImage:icon forState:UIControlStateNormal];
    btn.tintColor = [UIColor labelColor];
    btn.frame = CGRectMake(0, 0, 24, 44);
    [btn addTarget:[SCIProfileCopyTarget shared]
            action:@selector(handleTap:)
  forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

static void (*orig_configureHeaderView)(id, SEL, id, id, id, BOOL);

static void hooked_configureHeaderView(id self, SEL _cmd,
                                       id titleView,
                                       id leftButtons,
                                       id rightButtons,
                                       BOOL titleIsCentered) {
    if (![SCIUtils getBoolPref:@"profile_copy_button"]) {
        orig_configureHeaderView(self, _cmd, titleView, leftButtons, rightButtons, titleIsCentered);
        return;
    }

    // Own profile (centered title) → inject on the left to avoid crowding the
    // plus/notifications/burger cluster. Other profiles → inject on the right.
    NSArray *lb = [leftButtons isKindOfClass:[NSArray class]] ? (NSArray *)leftButtons : nil;
    NSArray *rb = [rightButtons isKindOfClass:[NSArray class]] ? (NSArray *)rightButtons : nil;
    BOOL isOwnProfile = titleIsCentered;

    BOOL alreadyHas = NO;
    for (id wrapper in (isOwnProfile ? lb : rb)) {
        UIView *v = sci_safeValueForKey(wrapper, @"view");
        if ([v isKindOfClass:[UIView class]] &&
            [v.accessibilityIdentifier isEqualToString:@"sci-profile-copy-button"]) {
            alreadyHas = YES;
            break;
        }
    }

    NSArray *patchedLeft = leftButtons;
    NSArray *patchedRight = rightButtons;

    if (!alreadyHas) {
        Class wrapperCls = NSClassFromString(@"IGProfileNavigationHeaderViewButtonSwift.IGProfileNavigationHeaderViewButton");
        // Mirror an existing button's type so IG lays ours out the same way
        id sample = rb.firstObject ?: lb.firstObject;
        NSInteger type = 0;
        id typeVal = sci_safeValueForKey(sample, @"type");
        if ([typeVal respondsToSelector:@selector(integerValue)]) {
            type = [typeVal integerValue];
        }

        UIView *btn = sci_buildCopyButton();
        id wrapper = nil;
        if (wrapperCls) {
            wrapper = [wrapperCls alloc];
            SEL initSel = @selector(initWithType:view:);
            if ([wrapper respondsToSelector:initSel]) {
                id (*ctor)(id, SEL, NSInteger, id) =
                    (id (*)(id, SEL, NSInteger, id))objc_msgSend;
                wrapper = ctor(wrapper, initSel, type, btn);
            }
        }

        if (wrapper) {
            if (isOwnProfile) {
                NSMutableArray *m = lb ? [lb mutableCopy] : [NSMutableArray array];
                [m addObject:wrapper];
                patchedLeft = m;
            } else if (rb) {
                NSMutableArray *m = [rb mutableCopy];
                [m insertObject:wrapper atIndex:0];
                patchedRight = m;
            }
        }
    }

    orig_configureHeaderView(self, _cmd, titleView, patchedLeft, patchedRight, titleIsCentered);
}

%ctor {
    Class cls = objc_getClass("IGProfileNavigationSwift.IGProfileNavigationHeaderView");
    if (!cls) return;
    SEL sel = @selector(configureWithTitleView:leftButtons:rightButtons:titleIsCentered:);
    if (![cls instancesRespondToSelector:sel]) return;
    MSHookMessageEx(cls, sel,
                    (IMP)hooked_configureHeaderView,
                    (IMP *)&orig_configureHeaderView);
}
