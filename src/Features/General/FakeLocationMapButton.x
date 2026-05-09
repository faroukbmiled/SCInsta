// Quick fake-location toggle injected into IG's Friends Map (DMs > Maps).

#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../Settings/SCIFakeLocationSettingsVC.h"
#import "../../Settings/SCIFakeLocationPickerVC.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static const NSInteger kSciMapBtnTag    = 0x5C1F4B;
static const NSInteger kSciMapHitBtnTag = 0x5C1F4C;

static UIViewController *sciTopMost(void) {
    UIWindow *win = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) if (w.isKeyWindow) { win = w; break; }
        if (win) break;
    }
    UIViewController *v = win.rootViewController;
    while (v.presentedViewController) v = v.presentedViewController;
    return v;
}

static void sciRefreshMapButton(UIView *mapView);
static void sciAddMapButton(UIView *mapView);
static void sciRemoveMapButton(UIView *mapView);
static UIMenu *sciBuildMapMenu(void);

static void sciWalkMapViews(UIView *root, Class mapCls, void (^block)(UIView *)) {
    if (!root) return;
    if (mapCls && [root isKindOfClass:mapCls]) block(root);
    for (UIView *s in root.subviews) sciWalkMapViews(s, mapCls, block);
}

static void sciRefreshActiveMapButton(void) {
    Class mapCls = NSClassFromString(@"IGFriendsMapCoreUI.IGFriendsMapView");
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) {
            sciWalkMapViews(w, mapCls, ^(UIView *mv) {
                if (![SCIUtils getBoolPref:@"show_fake_location_map_button"]) {
                    sciRemoveMapButton(mv);
                } else {
                    sciAddMapButton(mv);
                    sciRefreshMapButton(mv);
                }
            });
        }
    }
}

static void sciOpenPickerForCurrent(void) {
    UIViewController *top = sciTopMost();
    if (!top) return;
    SCIFakeLocationPickerVC *vc = [SCIFakeLocationPickerVC new];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    vc.initialCoord = CLLocationCoordinate2DMake([[d objectForKey:@"fake_location_lat"] doubleValue],
                                                 [[d objectForKey:@"fake_location_lon"] doubleValue]);
    vc.titleText = SCILocalized(@"Set location");
    vc.onPick = ^(double lat, double lon, NSString *name) {
        NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
        [u setObject:@(lat) forKey:@"fake_location_lat"];
        [u setObject:@(lon) forKey:@"fake_location_lon"];
        [u setObject:(name ?: @"") forKey:@"fake_location_name"];
        if (![u boolForKey:@"fake_location_enabled"]) [u setBool:YES forKey:@"fake_location_enabled"];
        sciRefreshActiveMapButton();
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [top presentViewController:nav animated:YES completion:nil];
}

static void sciOpenPickerForNewPreset(void) {
    UIViewController *top = sciTopMost();
    if (!top) return;
    SCIFakeLocationPickerVC *vc = [SCIFakeLocationPickerVC new];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    vc.initialCoord = CLLocationCoordinate2DMake([[d objectForKey:@"fake_location_lat"] doubleValue],
                                                 [[d objectForKey:@"fake_location_lon"] doubleValue]);
    vc.titleText = SCILocalized(@"Add preset");
    vc.onPick = ^(double lat, double lon, NSString *name) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Save preset")
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = SCILocalized(@"Name"); tf.text = name; }];
        [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            NSString *n = alert.textFields.firstObject.text.length ? alert.textFields.firstObject.text : name;
            NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
            NSArray *raw = [u objectForKey:@"fake_location_presets"];
            NSMutableArray *presets = [raw isKindOfClass:[NSArray class]] ? [raw mutableCopy] : [NSMutableArray array];
            [presets addObject:@{@"name": n ?: @"", @"lat": @(lat), @"lon": @(lon)}];
            [u setObject:presets forKey:@"fake_location_presets"];
            sciRefreshActiveMapButton();
            SCINotifySuccess(SCI_NOTIF_SETTINGS_ACTION,
                             [NSString stringWithFormat:SCILocalized(@"Saved preset \"%@\""), n ?: @""],
                             nil);
        }]];
        [sciTopMost() presentViewController:alert animated:YES completion:nil];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [top presentViewController:nav animated:YES completion:nil];
}

static UIMenu *sciBuildMapMenu(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [d boolForKey:@"fake_location_enabled"];
    NSString *name = [d objectForKey:@"fake_location_name"] ?: @"(unset)";

    // Header section: current location (disabled), enable/disable, change location
    UIAction *header = [UIAction actionWithTitle:[NSString stringWithFormat:SCILocalized(@"Current: %@"), name]
                                           image:[UIImage systemImageNamed:@"mappin.and.ellipse"]
                                      identifier:nil handler:^(__unused UIAction *a) {}];
    header.attributes = UIMenuElementAttributesDisabled;

    UIAction *toggle = [UIAction actionWithTitle:enabled ? SCILocalized(@"Disable") : SCILocalized(@"Enable")
                                           image:[UIImage systemImageNamed:enabled ? @"location.slash.fill" : @"location.fill"]
                                      identifier:nil
                                         handler:^(__unused UIAction *a) {
        [d setBool:!enabled forKey:@"fake_location_enabled"];
        sciRefreshActiveMapButton();
    }];
    if (enabled) toggle.attributes = UIMenuElementAttributesDestructive;

    UIAction *change = [UIAction actionWithTitle:SCILocalized(@"Change location")
                                           image:[UIImage systemImageNamed:@"map"]
                                      identifier:nil
                                         handler:^(__unused UIAction *a) { sciOpenPickerForCurrent(); }];

    UIMenu *headerSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil
                                          options:UIMenuOptionsDisplayInline children:@[header, toggle, change]];

    // Presets + Add
    NSMutableArray<UIMenuElement *> *presetItems = [NSMutableArray array];
    NSArray *presets = [d objectForKey:@"fake_location_presets"];
    if ([presets isKindOfClass:[NSArray class]]) {
        for (NSDictionary *p in presets) {
            if (![p isKindOfClass:[NSDictionary class]]) continue;
            NSString *pname = p[@"name"] ?: @"Preset";
            BOOL active = [p[@"name"] isEqualToString:name];
            UIAction *act = [UIAction actionWithTitle:pname
                                                image:[UIImage systemImageNamed:@"mappin.circle.fill"]
                                           identifier:nil
                                              handler:^(__unused UIAction *x) {
                [d setObject:p[@"lat"] forKey:@"fake_location_lat"];
                [d setObject:p[@"lon"] forKey:@"fake_location_lon"];
                [d setObject:p[@"name"] ?: @"" forKey:@"fake_location_name"];
                if (![d boolForKey:@"fake_location_enabled"]) [d setBool:YES forKey:@"fake_location_enabled"];
                sciRefreshActiveMapButton();
            }];
            if (active) act.state = UIMenuElementStateOn;
            [presetItems addObject:act];
        }
    }
    [presetItems addObject:[UIAction actionWithTitle:SCILocalized(@"Add location")
                                               image:[UIImage systemImageNamed:@"plus.circle.fill"]
                                          identifier:nil
                                             handler:^(__unused UIAction *x) { sciOpenPickerForNewPreset(); }]];
    UIMenu *presetSection = [UIMenu menuWithTitle:SCILocalized(@"Saved locations") image:nil identifier:nil
                                          options:UIMenuOptionsDisplayInline children:presetItems];

    // Settings
    UIAction *openSettings = [UIAction actionWithTitle:SCILocalized(@"Settings")
                                                 image:[UIImage systemImageNamed:@"gearshape.fill"]
                                            identifier:nil
                                               handler:^(__unused UIAction *x) {
        UIViewController *top = sciTopMost();
        if (!top) return;
        SCIFakeLocationSettingsVC *vc = [SCIFakeLocationSettingsVC new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [top presentViewController:nav animated:YES completion:nil];
    }];
    UIMenu *settingsSection = [UIMenu menuWithTitle:@"" image:nil identifier:nil
                                            options:UIMenuOptionsDisplayInline children:@[openSettings]];

    return [UIMenu menuWithTitle:SCILocalized(@"Fake location") image:nil identifier:nil options:0
                        children:@[headerSection, presetSection, settingsSection]];
}

static void sciRemoveMapButton(UIView *mapView) {
    UIView *btn = [mapView viewWithTag:kSciMapBtnTag];
    if (btn) [btn removeFromSuperview];
    UIView *hit = [mapView viewWithTag:kSciMapHitBtnTag];
    if (hit) [hit removeFromSuperview];
}

static void sciAddMapButton(UIView *mapView) {
    if (!mapView) return;
    if (![SCIUtils getBoolPref:@"show_fake_location_map_button"]) { sciRemoveMapButton(mapView); return; }
    if ([mapView viewWithTag:kSciMapBtnTag]) return;

    // Visible chrome — static, never absorbed into the menu platter animation.
    BOOL on = [SCIUtils getBoolPref:@"fake_location_enabled"];
    SCIChromeButton *chrome = [[SCIChromeButton alloc] initWithSymbol:on ? @"location.fill" : @"location.slash"
                                                            pointSize:18
                                                             diameter:48];
    chrome.tag = kSciMapBtnTag;
    chrome.bubbleColor = [UIColor secondarySystemBackgroundColor];
    chrome.iconTint = on ? [UIColor systemGreenColor] : [UIColor labelColor];
    chrome.layer.shadowColor = [UIColor blackColor].CGColor;
    chrome.layer.shadowOpacity = 0.18;
    chrome.layer.shadowRadius = 5;
    chrome.layer.shadowOffset = CGSizeMake(0, 2);
    chrome.userInteractionEnabled = NO;
    [mapView addSubview:chrome];
    [NSLayoutConstraint activateConstraints:@[
        [chrome.leadingAnchor constraintEqualToAnchor:mapView.leadingAnchor constant:16],
        [chrome.topAnchor constraintEqualToAnchor:mapView.safeAreaLayoutGuide.topAnchor constant:78],
        [chrome.widthAnchor constraintEqualToConstant:48],
        [chrome.heightAnchor constraintEqualToConstant:48],
    ]];

    // Invisible hit target owns the menu; visible chrome below stays put
    // when UIKit absorbs the hit into the menu platter on dismiss.
    UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
    hit.tag = kSciMapHitBtnTag;
    hit.backgroundColor = [UIColor clearColor];
    hit.translatesAutoresizingMaskIntoConstraints = NO;
    hit.showsMenuAsPrimaryAction = YES;
    hit.menu = sciBuildMapMenu();
    [hit addAction:[UIAction actionWithHandler:^(__unused UIAction *a) {
        hit.menu = sciBuildMapMenu();
    }] forControlEvents:UIControlEventMenuActionTriggered];
    [mapView addSubview:hit];
    [NSLayoutConstraint activateConstraints:@[
        [hit.leadingAnchor  constraintEqualToAnchor:chrome.leadingAnchor],
        [hit.trailingAnchor constraintEqualToAnchor:chrome.trailingAnchor],
        [hit.topAnchor      constraintEqualToAnchor:chrome.topAnchor],
        [hit.bottomAnchor   constraintEqualToAnchor:chrome.bottomAnchor],
    ]];
}

static void sciRefreshMapButton(UIView *mapView) {
    SCIChromeButton *btn = (SCIChromeButton *)[mapView viewWithTag:kSciMapBtnTag];
    if (![btn isKindOfClass:[SCIChromeButton class]]) return;
    BOOL on = [SCIUtils getBoolPref:@"fake_location_enabled"];
    btn.symbolName = on ? @"location.fill" : @"location.slash";
    btn.iconTint = on ? [UIColor systemGreenColor] : [UIColor labelColor];
    // Don't touch btn.menu here — reassigning mid-dismiss flickers the button.
    // UIControlEventMenuActionTriggered rebuilds on next open.
}

static void (*orig_mapLayout)(UIView *, SEL);
static void new_mapLayout(UIView *self, SEL _cmd) {
    orig_mapLayout(self, _cmd);
    if (![SCIUtils getBoolPref:@"show_fake_location_map_button"]) {
        sciRemoveMapButton(self);
        return;
    }
    sciAddMapButton(self);
    sciRefreshMapButton(self);
    UIView *btn = [self viewWithTag:kSciMapBtnTag];
    if (btn) [self bringSubviewToFront:btn];
}

static void sciInstallMapHooks(void) {
    static BOOL installed = NO;
    if (installed) return;
    Class c = NSClassFromString(@"IGFriendsMapCoreUI.IGFriendsMapView");
    if (!c) return;
    installed = YES;
    SEL sel = @selector(layoutSubviews);
    if (class_getInstanceMethod(c, sel))
        MSHookMessageEx(c, sel, (IMP)new_mapLayout, (IMP *)&orig_mapLayout);
}

%ctor {
    sciInstallMapHooks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciInstallMapHooks();
    });
    [[NSNotificationCenter defaultCenter] addObserverForName:@"SCIFakeLocationMapBtnPrefChanged"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *n) {
        sciRefreshActiveMapButton();
    }];
}
