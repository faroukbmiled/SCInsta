// Profile page copy button: hooks IG's native nav header builder to insert
// a copy button alongside IG's own buttons, then opens a menu to copy
// username/name/bio.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import "../../../modules/JGProgressHUD/JGProgressHUD.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static id sci_safeValueForKey(id obj, NSString *key) {
	@try {
		return [obj valueForKey:key];
	} @catch (__unused NSException *e) {
		return nil;
	}
}

static id sci_valueForAnyKey(id obj, NSArray<NSString *> *keys) {
	for (NSString *key in keys) {
		id value = sci_safeValueForKey(obj, key);
		if (value && value != [NSNull null]) return value;
	}
	return nil;
}

static id sci_findUserOnVC(UIViewController *vc) {
	id user = sci_valueForAnyKey(vc, @[@"user", @"userGQL", @"profileUser", @"loggedInUser", @"currentUser"]);
	if (user) return user;

	Class userCls = NSClassFromString(@"IGUser");
	for (Class cls = [vc class]; cls && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
		unsigned int count = 0;
		Ivar *ivars = class_copyIvarList(cls, &count);
		if (!ivars) continue;

		for (unsigned int i = 0; i < count; i++) {
			id value = nil;
			@try {
				value = object_getIvar(vc, ivars[i]);
			} @catch (__unused NSException *e) {}

			if (userCls && [value isKindOfClass:userCls]) {
				free(ivars);
				return value;
			}
		}

		free(ivars);
	}

	return nil;
}

static UIViewController *sci_findProfileVC(UIView *view) {
	Class profileCls = NSClassFromString(@"IGProfileViewController");
	UIResponder *responder = view;

	while (responder) {
		if (profileCls && [responder isKindOfClass:profileCls]) {
			return (UIViewController *)responder;
		}

		responder = responder.nextResponder;
	}

	return nil;
}

static UIView *sci_keyWindow(void) {
	for (UIWindow *window in UIApplication.sharedApplication.windows) {
		if (window.isKeyWindow) return window;
	}

	return UIApplication.sharedApplication.windows.firstObject;
}

static void sci_copyAndToast(NSString *value, NSString *label) {
	if (!value.length) return;

	UIPasteboard.generalPasteboard.string = value;

	JGProgressHUD *hud = [[JGProgressHUD alloc] init];
	hud.textLabel.text = [NSString stringWithFormat:@"Copied %@", label];
	hud.indicatorView = [[JGProgressHUDSuccessIndicatorView alloc] init];

	UIView *host = sci_keyWindow();
	if (!host) return;

	[hud showInView:host];
	[hud dismissAfterDelay:1.5];
}

@interface SCIProfileCopyTarget : NSObject
+ (instancetype)shared;
- (void)handleTap:(UIButton *)sender;
@end

@implementation SCIProfileCopyTarget

+ (instancetype)shared {
	static SCIProfileCopyTarget *sharedTarget;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedTarget = [[SCIProfileCopyTarget alloc] init];
	});
	return sharedTarget;
}

- (void)handleTap:(UIButton *)sender {
	if (![SCIUtils getBoolPref:@"profile_copy_button"]) return;

	UIViewController *vc = sci_findProfileVC(sender);
	if (!vc || vc.presentedViewController) return;

	id user = sci_findUserOnVC(vc);
	if (!user) return;

	NSString *username = [sci_valueForAnyKey(user, @[@"username"]) description];
	NSString *fullName = [sci_valueForAnyKey(user, @[@"fullName", @"fullname", @"name"]) description];
	NSString *biography = [sci_valueForAnyKey(user, @[@"biography", @"bio", @"profileBiography"]) description];

	UIAlertController *menu = [UIAlertController alertControllerWithTitle:SCILocalized(@"Copy from profile")
																  message:nil
														   preferredStyle:UIAlertControllerStyleActionSheet];

	if (username.length) {
		[menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Copy username (@%@)", username]
												 style:UIAlertActionStyleDefault
											   handler:^(__unused UIAlertAction *action) {
			sci_copyAndToast(username, @"username");
		}]];
	}

	if (fullName.length) {
		[menu addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy name")
												 style:UIAlertActionStyleDefault
											   handler:^(__unused UIAlertAction *action) {
			sci_copyAndToast(fullName, @"name");
		}]];
	}

	if (biography.length) {
		[menu addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy bio")
												 style:UIAlertActionStyleDefault
											   handler:^(__unused UIAlertAction *action) {
			sci_copyAndToast(biography, @"bio");
		}]];
	}

	NSMutableArray *parts = [NSMutableArray array];

	if (username.length) [parts addObject:[NSString stringWithFormat:@"Username: @%@", username]];
	if (fullName.length) [parts addObject:[NSString stringWithFormat:@"Name: %@", fullName]];
	if (biography.length) [parts addObject:[NSString stringWithFormat:@"Bio:\n%@", biography]];

	if (parts.count >= 2) {
		NSString *combined = [parts componentsJoinedByString:@"\n\n"];
		[menu addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy all")
												 style:UIAlertActionStyleDefault
											   handler:^(__unused UIAlertAction *action) {
			sci_copyAndToast(combined, @"all");
		}]];
	}

	if (!menu.actions.count) {
		[menu addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Nothing to copy")
												 style:UIAlertActionStyleDefault
											   handler:nil]];
	}

	[menu addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
											 style:UIAlertActionStyleCancel
										   handler:nil]];

	menu.popoverPresentationController.sourceView = sender;
	menu.popoverPresentationController.sourceRect = sender.bounds;

	[vc presentViewController:menu animated:YES completion:nil];
}

@end

static UIView *sci_buildCopyButton(void) {
	SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:@"doc.on.doc"
															pointSize:16
															 diameter:24];

	button.accessibilityIdentifier = @"sci-profile-copy-button";
	button.accessibilityLabel = @"Copy profile info";
	button.iconTint = UIColor.labelColor;
	button.bubbleColor = UIColor.clearColor;
	button.translatesAutoresizingMaskIntoConstraints = YES;
	button.frame = CGRectMake(0, 0, 24, 44);

	[button addTarget:[SCIProfileCopyTarget shared]
			   action:@selector(handleTap:)
	 forControlEvents:UIControlEventTouchUpInside];

	return button;
}

static void (*orig_configureHeaderView)(id, SEL, id, id, id, BOOL);

static void hooked_configureHeaderView(id self, SEL _cmd, id titleView, id leftButtons, id rightButtons, BOOL titleIsCentered) {
	if (![SCIUtils getBoolPref:@"profile_copy_button"]) {
		if (orig_configureHeaderView) {
			orig_configureHeaderView(self, _cmd, titleView, leftButtons, rightButtons, titleIsCentered);
		}
		return;
	}

	NSArray *leftArray = [leftButtons isKindOfClass:[NSArray class]] ? leftButtons : @[];
	NSArray *rightArray = [rightButtons isKindOfClass:[NSArray class]] ? rightButtons : @[];
	BOOL isOwnProfile = titleIsCentered;
	NSArray *targetArray = isOwnProfile ? leftArray : rightArray;
	BOOL alreadyHas = NO;

	for (id wrapper in targetArray) {
		UIView *view = sci_safeValueForKey(wrapper, @"view");

		if ([view isKindOfClass:[UIView class]] &&
			[view.accessibilityIdentifier isEqualToString:@"sci-profile-copy-button"]) {
			alreadyHas = YES;
			break;
		}
	}

	id patchedLeft = leftButtons;
	id patchedRight = rightButtons;

	if (!alreadyHas) {
		Class wrapperCls = NSClassFromString(@"IGProfileNavigationHeaderViewButtonSwift.IGProfileNavigationHeaderViewButton");
		id sample = rightArray.firstObject ?: leftArray.firstObject;
		NSInteger type = 0;
		id typeValue = sci_safeValueForKey(sample, @"type");

		if ([typeValue respondsToSelector:@selector(integerValue)]) {
			type = [typeValue integerValue];
		}

		UIView *button = sci_buildCopyButton();
		id wrapper = nil;

		if (wrapperCls) {
			SEL initSel = @selector(initWithType:view:);
			id allocatedWrapper = [wrapperCls alloc];

			if ([allocatedWrapper respondsToSelector:initSel]) {
				id (*constructor)(id, SEL, NSInteger, id) = (id (*)(id, SEL, NSInteger, id))objc_msgSend;
				wrapper = constructor(allocatedWrapper, initSel, type, button);
			}
		}

		if (wrapper) {
			if (isOwnProfile) {
				NSMutableArray *mutableLeft = [leftArray mutableCopy];
				[mutableLeft addObject:wrapper];
				patchedLeft = mutableLeft;
			} else {
				NSMutableArray *mutableRight = [rightArray mutableCopy];
				[mutableRight insertObject:wrapper atIndex:0];
				patchedRight = mutableRight;
			}
		}
	}

	if (orig_configureHeaderView) {
		orig_configureHeaderView(self, _cmd, titleView, patchedLeft, patchedRight, titleIsCentered);
	}
}

%ctor {
	Class cls = objc_getClass("IGProfileNavigationSwift.IGProfileNavigationHeaderView");
	if (!cls) return;

	SEL sel = @selector(configureWithTitleView:leftButtons:rightButtons:titleIsCentered:);
	if (![cls instancesRespondToSelector:sel]) return;

	MSHookMessageEx(cls,
					sel,
					(IMP)hooked_configureHeaderView,
					(IMP *)&orig_configureHeaderView);
}