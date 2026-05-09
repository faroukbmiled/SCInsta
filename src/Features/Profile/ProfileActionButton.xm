// Profile action button — replaces the legacy ProfileCopyButton.x. Hooks
// IGProfileNavigationHeaderView's button-config callback to inject our own
// SCIChromeButton wrapped in IG's native button-wrapper class. The button
// reads SCIActionMenuConfig (source = Profile) for default-tap action +
// menu layout. Hidden via SCIChromeCanvas redaction when `hide_ui_on_capture`
// is on.
//
// User resolution + picture URL fetch + share/save pipelines all live in
// SCIProfileHelpers. This file is just the button + menu wiring.

#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIIcon.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../ActionButton/SCIActionMenuConfig.h"
#import "../../ActionButton/SCIActionCatalog.h"
#import "../../ActionButton/SCIActionIcon.h"
#import "SCIProfileHelpers.h"

static NSString * const kSCIProfileActionButtonAccessibilityID = @"sci-profile-action-button";
static CGFloat   const kSCIProfileActionButtonDiameter = 32.0;
static CGFloat   const kSCIProfileActionButtonIconSize = 18.0;

static id sciSafeValue(id obj, NSString *key) {
    if (!obj || !key.length) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused id e) { return nil; }
}

// MARK: - Copy actions

static void sciCopyAndToast(NSString *value, NSString *kind) {
    if (!value.length) {
        SCINotifyWarning(SCI_NOTIF_VALIDATION_ERROR, SCILocalized(@"Nothing to copy"), nil);
        return;
    }
    UIPasteboard.generalPasteboard.string = value;
    SCINotifySuccess(SCI_NOTIF_COPY_PROFILE, [NSString stringWithFormat:SCILocalized(@"Copied %@"), kind], nil);
}

// Build a multi-line "Username: …\nName: …\n…" payload for SCIAID_CopyAll.
// Skips fields whose value is empty so the result reads cleanly for users
// with sparse profiles.
static NSString *sciBuildAllInfoPayload(id user) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    void (^add)(NSString *, NSString *) = ^(NSString *label, NSString *value) {
        if (value.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", label, value]];
    };
    add(SCILocalized(@"Username"), [SCIProfileHelpers usernameForUser:user]);
    add(SCILocalized(@"Name"),     [SCIProfileHelpers fullNameForUser:user]);
    add(SCILocalized(@"Bio"),      [SCIProfileHelpers biographyForUser:user]);
    NSURL *link = [SCIProfileHelpers profileLinkForUser:user];
    add(SCILocalized(@"Profile link"), link.absoluteString);
    add(SCILocalized(@"ID"),       [SCIProfileHelpers pkForUser:user]);
    return [lines componentsJoinedByString:@"\n"];
}

static void sciExecuteCopyInfoAction(id user, NSString *aid) {
    if ([aid isEqualToString:SCIAID_CopyID]) {
        sciCopyAndToast([SCIProfileHelpers pkForUser:user], SCILocalized(@"ID"));
    } else if ([aid isEqualToString:SCIAID_CopyUsername]) {
        sciCopyAndToast([SCIProfileHelpers usernameForUser:user], SCILocalized(@"Username"));
    } else if ([aid isEqualToString:SCIAID_CopyName]) {
        sciCopyAndToast([SCIProfileHelpers fullNameForUser:user], SCILocalized(@"Name"));
    } else if ([aid isEqualToString:SCIAID_CopyBio]) {
        sciCopyAndToast([SCIProfileHelpers biographyForUser:user], SCILocalized(@"Bio"));
    } else if ([aid isEqualToString:SCIAID_CopyLink]) {
        sciCopyAndToast([SCIProfileHelpers profileLinkForUser:user].absoluteString, SCILocalized(@"Profile link"));
    } else if ([aid isEqualToString:SCIAID_CopyAll]) {
        sciCopyAndToast(sciBuildAllInfoPayload(user), SCILocalized(@"Profile info"));
    }
}

// MARK: - Settings nav

static void sciOpenProfileSettings(void) {
    UIWindow *win = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
            if (win) break;
        }
    }
    if (!win) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { win = w; break; }
        }
    }
    if (!win) return;
    [SCIUtils showSettingsVC:win atTopLevelEntry:SCILocalized(@"Profile")];
}

// MARK: - Menu builder

// Lightweight per-action resolver for copy IDs. The Copy Info section in the
// profile catalog now lists each copy variant as a first-class action — the
// section's `collapsible` flag (default YES) renders them under one
// "Copy Info" submenu entry, and the user can disable/reorder/promote any of
// them like every other action.
static SCIAction *sciCopyLeaf(NSString *aid, id user) {
    SCIActionDescriptor *d = [SCIActionCatalog descriptorForActionID:aid source:SCIActionSourceProfile];
    if (!d) return nil;
    return [SCIAction actionWithTitle:d.title icon:d.iconSF handler:^{
        sciExecuteCopyInfoAction(user, aid);
    }];
}

// Read-only info rows that show profile data (privacy, follower/following
// counts) — greyed out + non-tappable since they aren't actions.
static SCIAction *sciInfoLeaf(NSString *title, NSString *icon) {
    return [SCIAction infoRowWithTitle:title icon:icon];
}

static UIMenu *sciProfileBuildMenu(id user) {
    if (!user) {
        SCIAction *empty = [SCIAction actionWithTitle:SCILocalized(@"Profile unavailable") icon:nil handler:^{}];
        return [SCIActionMenu buildMenuWithActions:@[empty]];
    }

    SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceProfile];

    SCIAction *(^resolve)(NSString *) = ^SCIAction *(NSString *aid) {
        // Copy variants — each is its own first-class action under the
        // "Copy Info" config section (collapsible by default).
        if ([aid isEqualToString:SCIAID_CopyUsername]) return sciCopyLeaf(aid, user);
        if ([aid isEqualToString:SCIAID_CopyName])     return sciCopyLeaf(aid, user);
        if ([aid isEqualToString:SCIAID_CopyBio])      return sciCopyLeaf(aid, user);
        if ([aid isEqualToString:SCIAID_CopyLink])     return sciCopyLeaf(aid, user);
        if ([aid isEqualToString:SCIAID_CopyID])       return sciCopyLeaf(aid, user);
        if ([aid isEqualToString:SCIAID_CopyAll])      return sciCopyLeaf(aid, user);
        if ([aid isEqualToString:SCIAID_ViewPicture])        return [SCIAction actionWithTitle:SCILocalized(@"View picture") icon:@"photo" handler:^{ [SCIProfileHelpers viewPictureForUser:user]; }];
        if ([aid isEqualToString:SCIAID_SharePicture])       return [SCIAction actionWithTitle:SCILocalized(@"Share picture") icon:@"square.and.arrow.up" handler:^{ [SCIProfileHelpers sharePictureForUser:user]; }];
        if ([aid isEqualToString:SCIAID_SavePictureGallery]) {
            if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;
            return [SCIAction actionWithTitle:SCILocalized(@"Save picture to Gallery")
                                         icon:@"photo.on.rectangle.angled"
                                      handler:^{ [SCIProfileHelpers savePictureToGalleryForUser:user]; }];
        }
        if ([aid isEqualToString:SCIAID_ProfileSettings])    return [SCIAction actionWithTitle:SCILocalized(@"Profile settings") icon:@"gearshape" handler:^{ sciOpenProfileSettings(); }];

        if ([aid isEqualToString:SCIAID_ProfileInfoPrivacy]) {
            NSNumber *p = [SCIProfileHelpers privacyStatusForUser:user];
            if (!p) return nil;
            BOOL priv = p.integerValue == 2;
            return sciInfoLeaf(priv ? SCILocalized(@"Private profile") : SCILocalized(@"Public profile"),
                                priv ? @"lock" : @"lock.open");
        }
        if ([aid isEqualToString:SCIAID_ProfileInfoFollowers]) {
            NSNumber *n = [SCIProfileHelpers followerCountForUser:user];
            if (!n) return nil;
            NSNumberFormatter *f = [NSNumberFormatter new]; f.numberStyle = NSNumberFormatterDecimalStyle;
            return sciInfoLeaf([NSString stringWithFormat:SCILocalized(@"Followers: %@"), [f stringFromNumber:n]], @"person.2");
        }
        if ([aid isEqualToString:SCIAID_ProfileInfoFollowing]) {
            NSNumber *n = [SCIProfileHelpers followingCountForUser:user];
            if (!n) return nil;
            NSNumberFormatter *f = [NSNumberFormatter new]; f.numberStyle = NSNumberFormatterDecimalStyle;
            return sciInfoLeaf([NSString stringWithFormat:SCILocalized(@"Following: %@"), [f stringFromNumber:n]], @"person.crop.circle.badge.plus");
        }

        return nil;
    };

    NSArray<SCIAction *> *flat = [SCIActionMenu actionsForConfig:cfg dateHeader:nil resolver:resolve];
    return [SCIActionMenu buildMenuWithActions:flat];
}

static void sciProfileExecuteDefaultTap(id user, SCIActionMenuConfig *cfg) {
    NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
    if ([tap isEqualToString:SCIAID_ViewPicture]) {
        [SCIProfileHelpers viewPictureForUser:user];
    } else if ([tap isEqualToString:SCIAID_SharePicture]) {
        [SCIProfileHelpers sharePictureForUser:user];
    } else if ([tap isEqualToString:SCIAID_SavePictureGallery]) {
        [SCIProfileHelpers savePictureToGalleryForUser:user];
    } else if ([tap isEqualToString:SCIAID_ProfileSettings]) {
        sciOpenProfileSettings();
    } else if ([tap isEqualToString:SCIAID_CopyID])       { sciExecuteCopyInfoAction(user, SCIAID_CopyID); }
    else if ([tap isEqualToString:SCIAID_CopyUsername])   { sciExecuteCopyInfoAction(user, SCIAID_CopyUsername); }
    else if ([tap isEqualToString:SCIAID_CopyName])       { sciExecuteCopyInfoAction(user, SCIAID_CopyName); }
    else if ([tap isEqualToString:SCIAID_CopyBio])        { sciExecuteCopyInfoAction(user, SCIAID_CopyBio); }
    else if ([tap isEqualToString:SCIAID_CopyLink])       { sciExecuteCopyInfoAction(user, SCIAID_CopyLink); }
    else if ([tap isEqualToString:SCIAID_CopyAll])        { sciExecuteCopyInfoAction(user, SCIAID_CopyAll); }
}

// MARK: - Button + delegate

@interface SCIProfileActionTarget : NSObject
+ (instancetype)shared;
@end

@implementation SCIProfileActionTarget

+ (instancetype)shared {
    static SCIProfileActionTarget *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SCIProfileActionTarget new]; });
    return s;
}

- (void)tap:(UIButton *)sender {
    SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceProfile];
    NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
    if ([tap isEqualToString:@"menu"]) return;

    id user = [SCIProfileHelpers userForView:sender];
    if (!user) return;
    sciProfileExecuteDefaultTap(user, cfg);
}

@end

// Idempotence guard — repeat configure calls during a menu interaction
// must not reassign `button.menu`, which collapses any open submenu.
static const void *kSCIProfileActionWireKey = &kSCIProfileActionWireKey;
static NSInteger sciProfileActionConfigVersion = 0;

static void sciConfigureProfileActionButton(SCIChromeButton *button) {
    if (!button) return;
    id user = [SCIProfileHelpers userForView:button];
    if (!user) {
        button.hidden = YES;
        return;
    }
    button.hidden = NO;

    SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceProfile];
    NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
    NSString *wireKey = [NSString stringWithFormat:@"%p|%@|%ld",
                                                     user, tap, (long)sciProfileActionConfigVersion];
    NSString *prevWire = objc_getAssociatedObject(button, kSCIProfileActionWireKey);
    if ([prevWire isEqualToString:wireKey]) return;

    [button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    button.menu = sciProfileBuildMenu(user);

    if ([tap isEqualToString:@"menu"]) {
        button.showsMenuAsPrimaryAction = YES;
    } else {
        button.showsMenuAsPrimaryAction = NO;
        [button addTarget:[SCIProfileActionTarget shared]
                   action:@selector(tap:)
         forControlEvents:UIControlEventTouchUpInside];
    }

    objc_setAssociatedObject(button, kSCIProfileActionWireKey, wireKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static SCIChromeButton *sciBuildProfileActionButton(void) {
    // Symbol is overridden by SCIActionIcon below; pick a safe default.
    SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:@"ellipsis"
                                                            pointSize:kSCIProfileActionButtonIconSize
                                                             diameter:kSCIProfileActionButtonDiameter];
    button.accessibilityIdentifier = kSCIProfileActionButtonAccessibilityID;
    button.accessibilityLabel = SCILocalized(@"RyukGram profile actions");
    button.iconTint = UIColor.labelColor;
    button.bubbleColor = UIColor.clearColor;
    button.translatesAutoresizingMaskIntoConstraints = YES;
    button.frame = CGRectMake(0.0, 0.0, kSCIProfileActionButtonDiameter, 44.0);

    // Track the global icon picker.
    [SCIActionIcon attachAutoUpdate:button
                          pointSize:kSCIProfileActionButtonIconSize
                              style:SCIActionIconStylePlain];
    return button;
}

// MARK: - Hook

static void (*orig_configureHeaderView)(id, SEL, id, id, id, BOOL);

static BOOL sciButtonsAlreadyHaveActionButton(NSArray *buttons) {
    for (id wrapper in buttons) {
        UIView *v = sciSafeValue(wrapper, @"view");
        if ([v isKindOfClass:[UIView class]] &&
            [v.accessibilityIdentifier isEqualToString:kSCIProfileActionButtonAccessibilityID]) {
            return YES;
        }
    }
    return NO;
}

static id sciBuildButtonWrapper(UIView *button, id sample) {
    Class wrapperCls = NSClassFromString(@"IGProfileNavigationHeaderViewButtonSwift.IGProfileNavigationHeaderViewButton");
    if (!wrapperCls) return nil;

    NSInteger type = 0;
    id typeValue = sciSafeValue(sample, @"type");
    if ([typeValue respondsToSelector:@selector(integerValue)]) type = [typeValue integerValue];

    SEL initSel = @selector(initWithType:view:);
    id w = [wrapperCls alloc];
    if (![w respondsToSelector:initSel]) return nil;
    return ((id (*)(id, SEL, NSInteger, id))objc_msgSend)(w, initSel, type, button);
}

static void hooked_configureHeaderView(id self, SEL _cmd, id titleView, id leftButtons, id rightButtons, BOOL titleIsCentered) {
    if (![SCIUtils getBoolPref:@"action_button_profile_enabled"]) {
        if (orig_configureHeaderView) orig_configureHeaderView(self, _cmd, titleView, leftButtons, rightButtons, titleIsCentered);
        return;
    }

    NSArray *leftArray = [leftButtons isKindOfClass:[NSArray class]] ? leftButtons : @[];
    NSArray *rightArray = [rightButtons isKindOfClass:[NSArray class]] ? rightButtons : @[];

    BOOL isOwnProfile = titleIsCentered;
    NSArray *target = isOwnProfile ? leftArray : rightArray;
    if (sciButtonsAlreadyHaveActionButton(target)) {
        if (orig_configureHeaderView) orig_configureHeaderView(self, _cmd, titleView, leftButtons, rightButtons, titleIsCentered);
        return;
    }

    SCIChromeButton *button = sciBuildProfileActionButton();
    id sample = rightArray.firstObject ?: leftArray.firstObject;
    id wrapper = sciBuildButtonWrapper(button, sample);
    if (!wrapper) {
        if (orig_configureHeaderView) orig_configureHeaderView(self, _cmd, titleView, leftButtons, rightButtons, titleIsCentered);
        return;
    }

    id patchedLeft = leftButtons;
    id patchedRight = rightButtons;
    if (isOwnProfile) {
        NSMutableArray *m = [leftArray mutableCopy];
        [m addObject:wrapper];
        patchedLeft = m;
    } else {
        NSMutableArray *m = [rightArray mutableCopy];
        [m insertObject:wrapper atIndex:0];
        patchedRight = m;
    }

    if (orig_configureHeaderView) orig_configureHeaderView(self, _cmd, titleView, patchedLeft, patchedRight, titleIsCentered);

    __weak SCIChromeButton *weakButton = button;
    dispatch_async(dispatch_get_main_queue(), ^{
        sciConfigureProfileActionButton(weakButton);
    });
}

%ctor {
    Class cls = objc_getClass("IGProfileNavigationSwift.IGProfileNavigationHeaderView");
    if (!cls) cls = objc_getClass("IGProfileNavigationHeaderView");
    if (!cls) return;

    SEL sel = @selector(configureWithTitleView:leftButtons:rightButtons:titleIsCentered:);
    if (![cls instancesRespondToSelector:sel]) return;
    MSHookMessageEx(cls, sel, (IMP)hooked_configureHeaderView, (IMP *)&orig_configureHeaderView);

    [[NSNotificationCenter defaultCenter] addObserverForName:SCIActionMenuConfigDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) {
        NSNumber *src = n.userInfo[@"source"];
        if (src.integerValue == SCIActionSourceProfile) sciProfileActionConfigVersion++;
    }];
}
