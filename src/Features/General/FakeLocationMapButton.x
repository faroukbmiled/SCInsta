// Quick fake-location toggle injected into IG's Friends Map (DMs > Maps).

#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../Settings/SCIFakeLocationSettingsVC.h"
#import "../../Settings/SCIFakeLocationPickerVC.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static const NSInteger kSCIMapButtonTag = 0x5C1F4B;
static const NSInteger kSCIMapHitTag = 0x5C1F4C;

static NSString *const kSCIMapPrefShowButton = @"show_fake_location_map_button";
static NSString *const kSCIMapPrefEnabled = @"fake_location_enabled";
static NSString *const kSCIMapPrefLat = @"fake_location_lat";
static NSString *const kSCIMapPrefLon = @"fake_location_lon";
static NSString *const kSCIMapPrefName = @"fake_location_name";
static NSString *const kSCIMapPrefPresets = @"fake_location_presets";

static BOOL SCIMapButtonEnabled(void) {
	return [SCIUtils getBoolPref:kSCIMapPrefShowButton];
}

static BOOL SCIFakeLocationEnabled(void) {
	return [SCIUtils getBoolPref:kSCIMapPrefEnabled];
}

static CLLocationCoordinate2D SCICurrentFakeCoordinate(void) {
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	return CLLocationCoordinate2DMake([[defaults objectForKey:kSCIMapPrefLat] doubleValue], [[defaults objectForKey:kSCIMapPrefLon] doubleValue]);
}

static UIViewController *SCIPresenterFromView(UIView *view) {
	UIResponder *responder = view;

	while (responder) {
		if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
		responder = responder.nextResponder;
	}

	UIWindow *window = view.window ?: UIApplication.sharedApplication.keyWindow;
	UIViewController *controller = window.rootViewController;

	while (controller.presentedViewController) {
		controller = controller.presentedViewController;
	}

	return controller;
}

static NSHashTable<UIView *> *SCIMapViews(void) {
	static NSHashTable *table;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		table = [NSHashTable weakObjectsHashTable];
	});

	return table;
}

static void SCIRegisterMapView(UIView *mapView) {
	if (mapView) [SCIMapViews() addObject:mapView];
}

static void SCIRemoveMapButton(UIView *mapView) {
	[[mapView viewWithTag:kSCIMapButtonTag] removeFromSuperview];
	[[mapView viewWithTag:kSCIMapHitTag] removeFromSuperview];
}

static void SCIRefreshMapButton(UIView *mapView);

static void SCIRefreshKnownMapButtons(void) {
	for (UIView *mapView in SCIMapViews().allObjects) {
		if (!mapView.window) continue;

		if (!SCIMapButtonEnabled()) {
			SCIRemoveMapButton(mapView);
		} else {
			SCIRefreshMapButton(mapView);
		}
	}
}

static void SCIOpenSettings(UIView *sourceView) {
	UIViewController *presenter = SCIPresenterFromView(sourceView);
	if (!presenter) return;

	SCIFakeLocationSettingsVC *controller = [SCIFakeLocationSettingsVC new];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
	nav.modalPresentationStyle = UIModalPresentationFormSheet;

	[presenter presentViewController:nav animated:YES completion:nil];
}

static void SCIOpenPickerForCurrentLocation(UIView *sourceView) {
	UIViewController *presenter = SCIPresenterFromView(sourceView);
	if (!presenter) return;

	SCIFakeLocationPickerVC *controller = [SCIFakeLocationPickerVC new];
	controller.initialCoord = SCICurrentFakeCoordinate();
	controller.titleText = SCILocalized(@"Set location");

	controller.onPick = ^(double lat, double lon, NSString *name) {
		NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
		[defaults setObject:@(lat) forKey:kSCIMapPrefLat];
		[defaults setObject:@(lon) forKey:kSCIMapPrefLon];
		[defaults setObject:(name ?: @"") forKey:kSCIMapPrefName];
		[defaults setBool:YES forKey:kSCIMapPrefEnabled];
		SCIRefreshKnownMapButtons();
	};

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;

	[presenter presentViewController:nav animated:YES completion:nil];
}

static void SCIOpenPickerForNewPreset(UIView *sourceView) {
	UIViewController *presenter = SCIPresenterFromView(sourceView);
	if (!presenter) return;

	SCIFakeLocationPickerVC *controller = [SCIFakeLocationPickerVC new];
	controller.initialCoord = SCICurrentFakeCoordinate();
	controller.titleText = SCILocalized(@"Add preset");

	__weak UIView *weakSource = sourceView;

	controller.onPick = ^(double lat, double lon, NSString *name) {
		UIViewController *top = SCIPresenterFromView(weakSource);
		if (!top) return;

		UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Save preset") message:nil preferredStyle:UIAlertControllerStyleAlert];

		[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
			textField.placeholder = SCILocalized(@"Name");
			textField.text = name;
		}];

		[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

		[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
			NSString *presetName = alert.textFields.firstObject.text.length ? alert.textFields.firstObject.text : name;
			if (!presetName.length) presetName = SCILocalized(@"Preset");

			NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
			NSArray *rawPresets = [defaults objectForKey:kSCIMapPrefPresets];
			NSMutableArray *presets = [rawPresets isKindOfClass:NSArray.class] ? rawPresets.mutableCopy : NSMutableArray.array;

			[presets addObject:@{@"name": presetName, @"lat": @(lat), @"lon": @(lon)}];
			[defaults setObject:presets.copy forKey:kSCIMapPrefPresets];

			SCIRefreshKnownMapButtons();
			SCINotifySuccess(SCI_NOTIF_SETTINGS_ACTION, [NSString stringWithFormat:SCILocalized(@"Saved preset \"%@\""), presetName], nil);
		}]];

		[top presentViewController:alert animated:YES completion:nil];
	};

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;

	[presenter presentViewController:nav animated:YES completion:nil];
}

static UIMenu *SCIBuildMapMenu(UIView *sourceView) {
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

	BOOL enabled = [defaults boolForKey:kSCIMapPrefEnabled];
	NSString *name = [defaults objectForKey:kSCIMapPrefName];
	if (!name.length) name = SCILocalized(@"Unset");

	UIAction *current = [UIAction actionWithTitle:[NSString stringWithFormat:SCILocalized(@"Current: %@"), name] image:[UIImage systemImageNamed:@"mappin.and.ellipse"] identifier:nil handler:^(__unused UIAction *action) {}];
	current.attributes = UIMenuElementAttributesDisabled;

	UIAction *toggle = [UIAction actionWithTitle:enabled ? SCILocalized(@"Disable") : SCILocalized(@"Enable") image:[UIImage systemImageNamed:enabled ? @"location.slash.fill" : @"location.fill"] identifier:nil handler:^(__unused UIAction *action) {
		[defaults setBool:!enabled forKey:kSCIMapPrefEnabled];
		SCIRefreshKnownMapButtons();
	}];

	if (enabled) toggle.attributes = UIMenuElementAttributesDestructive;

	UIAction *change = [UIAction actionWithTitle:SCILocalized(@"Change location") image:[UIImage systemImageNamed:@"map"] identifier:nil handler:^(__unused UIAction *action) {
		SCIOpenPickerForCurrentLocation(sourceView);
	}];

	UIMenu *mainSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[current, toggle, change]];

	NSMutableArray<UIMenuElement *> *presetItems = NSMutableArray.array;
	NSArray *presets = [defaults objectForKey:kSCIMapPrefPresets];

	if ([presets isKindOfClass:NSArray.class]) {
		for (NSDictionary *preset in presets) {
			if (![preset isKindOfClass:NSDictionary.class]) continue;

			NSString *presetName = preset[@"name"];
			if (!presetName.length) presetName = SCILocalized(@"Preset");

			BOOL active = [presetName isEqualToString:name];

			UIAction *presetAction = [UIAction actionWithTitle:presetName image:[UIImage systemImageNamed:@"mappin.circle.fill"] identifier:nil handler:^(__unused UIAction *action) {
				[defaults setObject:preset[@"lat"] forKey:kSCIMapPrefLat];
				[defaults setObject:preset[@"lon"] forKey:kSCIMapPrefLon];
				[defaults setObject:(preset[@"name"] ?: @"") forKey:kSCIMapPrefName];
				[defaults setBool:YES forKey:kSCIMapPrefEnabled];
				SCIRefreshKnownMapButtons();
			}];

			if (active) presetAction.state = UIMenuElementStateOn;
			[presetItems addObject:presetAction];
		}
	}

	[presetItems addObject:[UIAction actionWithTitle:SCILocalized(@"Add location") image:[UIImage systemImageNamed:@"plus.circle.fill"] identifier:nil handler:^(__unused UIAction *action) {
		SCIOpenPickerForNewPreset(sourceView);
	}]];

	UIMenu *presetSection = [UIMenu menuWithTitle:SCILocalized(@"Saved locations") image:nil identifier:nil options:UIMenuOptionsDisplayInline children:presetItems];

	UIAction *settings = [UIAction actionWithTitle:SCILocalized(@"Settings") image:[UIImage systemImageNamed:@"gearshape.fill"] identifier:nil handler:^(__unused UIAction *action) {
		SCIOpenSettings(sourceView);
	}];

	UIMenu *settingsSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[settings]];

	return [UIMenu menuWithTitle:SCILocalized(@"Fake location") image:nil identifier:nil options:0 children:@[mainSection, presetSection, settingsSection]];
}

static void SCIAddMapButton(UIView *mapView) {
	if (!mapView) return;

	SCIRegisterMapView(mapView);

	if (!SCIMapButtonEnabled()) {
		SCIRemoveMapButton(mapView);
		return;
	}

	if ([mapView viewWithTag:kSCIMapButtonTag] && [mapView viewWithTag:kSCIMapHitTag]) return;

	BOOL enabled = SCIFakeLocationEnabled();

	SCIChromeButton *chrome = [[SCIChromeButton alloc] initWithSymbol:enabled ? @"location.fill" : @"location.slash" pointSize:18.0 diameter:48.0];
	chrome.tag = kSCIMapButtonTag;
	chrome.bubbleColor = UIColor.secondarySystemBackgroundColor;
	chrome.iconTint = enabled ? UIColor.systemGreenColor : UIColor.labelColor;
	chrome.layer.shadowColor = UIColor.blackColor.CGColor;
	chrome.layer.shadowOpacity = 0.18;
	chrome.layer.shadowRadius = 5.0;
	chrome.layer.shadowOffset = CGSizeMake(0.0, 2.0);
	chrome.userInteractionEnabled = NO;

	[mapView addSubview:chrome];

	[NSLayoutConstraint activateConstraints:@[
		[chrome.leadingAnchor constraintEqualToAnchor:mapView.leadingAnchor constant:16.0],
		[chrome.topAnchor constraintEqualToAnchor:mapView.safeAreaLayoutGuide.topAnchor constant:78.0],
		[chrome.widthAnchor constraintEqualToConstant:48.0],
		[chrome.heightAnchor constraintEqualToConstant:48.0],
	]];

	UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
	hit.tag = kSCIMapHitTag;
	hit.backgroundColor = UIColor.clearColor;
	hit.translatesAutoresizingMaskIntoConstraints = NO;
	hit.showsMenuAsPrimaryAction = YES;
	hit.menu = SCIBuildMapMenu(hit);

	[hit addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
		UIButton *sender = (UIButton *)[mapView viewWithTag:kSCIMapHitTag];
		if ([sender isKindOfClass:UIButton.class]) sender.menu = SCIBuildMapMenu(sender);
	}] forControlEvents:UIControlEventMenuActionTriggered];

	[mapView addSubview:hit];

	[NSLayoutConstraint activateConstraints:@[
		[hit.leadingAnchor constraintEqualToAnchor:chrome.leadingAnchor],
		[hit.trailingAnchor constraintEqualToAnchor:chrome.trailingAnchor],
		[hit.topAnchor constraintEqualToAnchor:chrome.topAnchor],
		[hit.bottomAnchor constraintEqualToAnchor:chrome.bottomAnchor],
	]];

	[mapView bringSubviewToFront:chrome];
	[mapView bringSubviewToFront:hit];
}

static void SCIRefreshMapButton(UIView *mapView) {
	if (!mapView) return;

	if (!SCIMapButtonEnabled()) {
		SCIRemoveMapButton(mapView);
		return;
	}

	SCIChromeButton *button = (SCIChromeButton *)[mapView viewWithTag:kSCIMapButtonTag];

	if (![button isKindOfClass:SCIChromeButton.class]) {
		SCIAddMapButton(mapView);
		return;
	}

	BOOL enabled = SCIFakeLocationEnabled();

	button.symbolName = enabled ? @"location.fill" : @"location.slash";
	button.iconTint = enabled ? UIColor.systemGreenColor : UIColor.labelColor;

	UIView *hit = [mapView viewWithTag:kSCIMapHitTag];
	if (hit) [mapView bringSubviewToFront:hit];
}

static void (*orig_IGFriendsMapView_layoutSubviews)(UIView *, SEL);

static void hook_IGFriendsMapView_layoutSubviews(UIView *self, SEL _cmd) {
	orig_IGFriendsMapView_layoutSubviews(self, _cmd);

	SCIRegisterMapView(self);

	if (!SCIMapButtonEnabled()) {
		SCIRemoveMapButton(self);
		return;
	}

	SCIAddMapButton(self);
	SCIRefreshMapButton(self);
}

static void SCIInstallFriendsMapHooks(void) {
	static BOOL installed = NO;
	if (installed) return;

	Class mapClass = NSClassFromString(@"IGFriendsMapCoreUI.IGFriendsMapView");
	if (!mapClass) mapClass = NSClassFromString(@"_TtC18IGFriendsMapCoreUI16IGFriendsMapView");
	if (!mapClass) return;

	Method method = class_getInstanceMethod(mapClass, @selector(layoutSubviews));
	if (!method) return;

	installed = YES;

	MSHookMessageEx(mapClass, @selector(layoutSubviews), (IMP)hook_IGFriendsMapView_layoutSubviews, (IMP *)&orig_IGFriendsMapView_layoutSubviews);
}

%ctor {
	SCIInstallFriendsMapHooks();

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		SCIInstallFriendsMapHooks();
	});

	[NSNotificationCenter.defaultCenter addObserverForName:@"SCIFakeLocationMapBtnPrefChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
		SCIRefreshKnownMapButtons();
	}];
}