#import "Utils.h"
#import "PhotoAlbum.h"
#import "Settings/TweakSettings.h"
#import "UI/SCIPopupChrome.h"

@implementation SCIUtils

static NSDictionary *sciRegisteredDefaultsRef = nil;

+ (BOOL)getBoolPref:(NSString *)key {
    if (![key length]) return false;
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (v == nil) v = sciRegisteredDefaultsRef[key];
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v boolValue];
    if ([v isKindOfClass:[NSString class]]) return [(NSString *)v boolValue];
    return false;
}
+ (double)getDoublePref:(NSString *)key {
    if (![key length]) return 0;
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (v == nil) v = sciRegisteredDefaultsRef[key];
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v doubleValue];
    if ([v isKindOfClass:[NSString class]]) return [(NSString *)v doubleValue];
    return 0;
}
+ (NSString *)getStringPref:(NSString *)key {
    if (![key length]) return @"";
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (v == nil) v = sciRegisteredDefaultsRef[key];
    if (![v isKindOfClass:[NSString class]]) return @"";
    return v;
}
+ (NSDictionary *)getDictPref:(NSString *)key {
    if (![key length]) return @{};
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (v == nil) v = sciRegisteredDefaultsRef[key];
    if (![v isKindOfClass:[NSDictionary class]]) return @{};
    return v;
}
+ (NSArray *)getArrayPref:(NSString *)key {
    if (![key length]) return @[];
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (v == nil) v = sciRegisteredDefaultsRef[key];
    if (![v isKindOfClass:[NSArray class]]) return @[];
    return v;
}
+ (void)setPref:(id)value forKey:(NSString *)key {
    if (![key length]) return;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if (value == nil) {
        [defs removeObjectForKey:key];
    } else {
        [defs setObject:value forKey:key];
    }
}

+ (NSDictionary<NSString *, id> *)sciRegisteredDefaults { return sciRegisteredDefaultsRef ?: @{}; }
+ (void)setSciRegisteredDefaults:(NSDictionary<NSString *, id> *)defaults {
    sciRegisteredDefaultsRef = [defaults copy];
}

+ (_Bool)liquidGlassEnabledBool:(_Bool)fallback {
    BOOL setting = [SCIUtils getBoolPref:@"liquid_glass_surfaces"];
    return setting ? true : fallback;
}

// Displaying View Controllers
+ (void)showQuickLookVC:(NSArray<id> *)items {
    UIViewController *topVC = topMostController();
    if (!topVC) {
        NSLog(@"[RyukGram] No view controller available to present QuickLook");
        return;
    }

    QLPreviewController *previewController = [[QLPreviewController alloc] init];
    QuickLookDelegate *quickLookDelegate = [[QuickLookDelegate alloc] initWithPreviewItemURLs:items];

    previewController.dataSource = quickLookDelegate;

    [topVC presentViewController:previewController animated:true completion:nil];
}
+ (void)showShareVC:(id)item {
    UIViewController *topVC = topMostController();
    if (!topVC) {
        NSLog(@"[RyukGram] No view controller available to present share sheet");
        return;
    }

    UIActivityViewController *acVC = [[UIActivityViewController alloc] initWithActivityItems:@[item] applicationActivities:nil];
    if (is_iPad()) {
        acVC.popoverPresentationController.sourceView = topVC.view;
        acVC.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width / 2.0, topVC.view.bounds.size.height / 2.0, 1.0, 1.0);
    }

    [SCIPhotoAlbum armWatcherIfEnabled];

    [topVC presentViewController:acVC animated:true completion:nil];
}
+ (void)showSettingsVC:(UIWindow *)window {
    [SCIPopupChrome presentVC:[SCISettingsViewController new]
                          from:[window rootViewController]];
}

// Open settings at a named top-level entry. Entry becomes the nav root with
// Close — no settings-root underneath. Falls back to full root when missing.
+ (void)showSettingsVC:(UIWindow *)window atTopLevelEntry:(NSString *)entryTitle {
    UIViewController *rootController = [window rootViewController];
    while (rootController.presentedViewController) rootController = rootController.presentedViewController;

    NSArray *targetNavSections = nil;
    for (NSDictionary *section in [SCITweakSettings sections]) {
        for (SCISetting *row in section[@"rows"]) {
            if (row.type == SCITableCellNavigation && [row.title isEqualToString:entryTitle]) {
                targetNavSections = row.navSections;
                break;
            }
        }
        if (targetNavSections) break;
    }

    UIViewController *navRoot;
    if (targetNavSections) {
        SCISettingsViewController *child = [[SCISettingsViewController alloc]
            initWithTitle:entryTitle sections:targetNavSections reduceMargin:NO];
        child.title = entryTitle;
        child.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                 target:child action:@selector(sciDismissSettings)];
        navRoot = child;
    } else {
        navRoot = [SCISettingsViewController new];
    }

    [SCIPopupChrome presentVC:navRoot from:rootController];
}

// Colours
+ (UIColor *)SCIColor_Primary {
    return [UIColor colorWithRed:0/255.0 green:152/255.0 blue:254/255.0 alpha:1];
};

static UIColor *SCIDynIGColor(CGFloat lr, CGFloat lg, CGFloat lb, CGFloat dr, CGFloat dg, CGFloat db) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        BOOL dark = tc.userInterfaceStyle == UIUserInterfaceStyleDark;
        return [UIColor colorWithRed:(dark ? dr : lr)/255.0 green:(dark ? dg : lg)/255.0 blue:(dark ? db : lb)/255.0 alpha:1.0];
    }];
}

+ (UIColor *)SCIColor_InstagramBackground { return SCIDynIGColor(255,255,255, 11,16,20); }
+ (UIColor *)SCIColor_InstagramSecondaryBackground { return SCIDynIGColor(240,241,245, 42,48,55); }
+ (UIColor *)SCIColor_InstagramTertiaryBackground { return SCIDynIGColor(232,234,238, 58,64,72); }
+ (UIColor *)SCIColor_InstagramGroupedBackground { return [self SCIColor_InstagramBackground]; }
+ (UIColor *)SCIColor_InstagramPrimaryText { return SCIDynIGColor(15,20,25, 244,247,251); }
+ (UIColor *)SCIColor_InstagramSecondaryText { return SCIDynIGColor(99,108,118, 177,185,194); }
+ (UIColor *)SCIColor_InstagramTertiaryText { return SCIDynIGColor(130,138,147, 130,138,147); }
+ (UIColor *)SCIColor_InstagramSeparator { return SCIDynIGColor(220,223,228, 52,59,67); }
+ (UIColor *)SCIColor_InstagramFavorite { return [UIColor colorWithRed:255/255.0 green:48/255.0 blue:64/255.0 alpha:1.0]; }
+ (UIColor *)SCIColor_InstagramDestructive { return [UIColor colorWithRed:237/255.0 green:73/255.0 blue:86/255.0 alpha:1.0]; }
+ (UIColor *)SCIColor_InstagramPressedBackground { return SCIDynIGColor(232,233,238, 51,60,69); }

// Instagram deep-link openers — try the in-app URL handler first, fall back
// to UIApplication openURL: + the web URL.
+ (BOOL)openInstagramProfileForUsername:(NSString *)username {
    if (!username.length) return NO;
    NSString *enc = [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if (!enc.length) return NO;
    NSURL *appURL = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", enc]];
    UIApplication *app = [UIApplication sharedApplication];
    if (appURL && [app canOpenURL:appURL]) {
        id<UIApplicationDelegate> d = app.delegate;
        if ([d respondsToSelector:@selector(application:openURL:options:)]) {
            [d application:app openURL:appURL options:@{}];
            return YES;
        }
        [app openURL:appURL options:@{} completionHandler:nil];
        return YES;
    }
    NSURL *web = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/", enc]];
    return [self openInstagramMediaURL:web];
}

+ (BOOL)openInstagramMediaURL:(NSURL *)url {
    // Always route through IG's own URL handler. We never call
    // [UIApplication openURL:] for https/http URLs because that bounces them
    // to Safari instead of into IG's deep-link stack.
    if (!url) return NO;
    UIApplication *app = [UIApplication sharedApplication];
    id<UIApplicationDelegate> d = app.delegate;
    NSString *scheme = url.scheme.lowercaseString ?: @"";

    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        NSUserActivity *act = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
        act.webpageURL = url;
        if ([d respondsToSelector:@selector(application:continueUserActivity:restorationHandler:)]) {
            BOOL h = [d application:app continueUserActivity:act restorationHandler:^(__unused NSArray<id<UIUserActivityRestoring>> *r) {}];
            if (h) return YES;
        }
        // Fall back to the IG app delegate's openURL: (still in-app, never Safari).
        if ([d respondsToSelector:@selector(application:openURL:options:)]) {
            [d application:app openURL:url options:@{}];
            return YES;
        }
        return NO;
    }

    if ([scheme isEqualToString:@"instagram"]) {
        if ([d respondsToSelector:@selector(application:openURL:options:)]) {
            [d application:app openURL:url options:@{}];
            return YES;
        }
        return NO;
    }

    return NO;
}

// Errors
+ (NSError *)errorWithDescription:(NSString *)errorDesc {
    return [self errorWithDescription:errorDesc code:1];
}
+ (NSError *)errorWithDescription:(NSString *)errorDesc code:(NSInteger)errorCode {
    NSError *error = [ NSError errorWithDomain:@"com.socuul.scinsta" code:errorCode userInfo:@{ NSLocalizedDescriptionKey: errorDesc } ];
    return error;
}

+ (void)showErrorHUDWithDescription:(NSString *)errorDesc {
    [self showErrorHUDWithDescription:errorDesc dismissAfterDelay:4.0];
}
+ (void)showErrorHUDWithDescription:(NSString *)errorDesc dismissAfterDelay:(CGFloat)dismissDelay {
    (void)dismissDelay;
    [[SCINotificationCenter shared] notifyError:SCI_NOTIF_ACTION_ERROR title:errorDesc message:nil];
}

// Media

+ (NSDictionary *)fieldCacheForObject:(id)obj {
    if (!obj) return nil;
    if ([obj isKindOfClass:[NSDictionary class]]) return obj;
    Ivar iv = NULL;
    for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c))
        iv = class_getInstanceVariable(c, "_fieldCache");
    if (!iv) return nil;
    @try {
        id v = object_getIvar(obj, iv);
        return [v isKindOfClass:[NSDictionary class]] ? v : nil;
    } @catch (__unused id e) { return nil; }
}

+ (id)fieldCacheValue:(id)obj forKey:(NSString *)key {
    if (!key.length) return nil;
    NSDictionary *fc = [self fieldCacheForObject:obj];
    id v = fc[key];
    return [v isKindOfClass:[NSNull class]] ? nil : v;
}

// Local alias used by older callers in this file.
static id sciFieldCacheValue(id obj, NSString *key) {
    return [SCIUtils fieldCacheValue:obj forKey:key];
}

+ (NSURL *)getPhotoUrl:(IGPhoto *)photo {
    if (!photo) return nil;
    @try {
        if ([photo respondsToSelector:@selector(imageURLForWidth:)]) {
            NSURL *url = [photo imageURLForWidth:100000.00];
            if (url) return url;
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

+ (NSURL *)getPhotoUrlForMedia:(IGMedia *)media {
    if (!media) return nil;

    // fieldCache first — IGPhoto selectors crash on newer IG builds.
    @try {
        NSDictionary *imageVersions = sciFieldCacheValue(media, @"image_versions2");
        NSArray *candidates = [imageVersions isKindOfClass:[NSDictionary class]] ? imageVersions[@"candidates"] : nil;
        if ([candidates isKindOfClass:[NSArray class]] && candidates.count) {
            NSDictionary *best = nil;
            NSInteger bestW = -1;
            for (id c in candidates) {
                if (![c isKindOfClass:[NSDictionary class]]) continue;
                NSInteger w = [[c objectForKey:@"width"] integerValue];
                if (w > bestW) { bestW = w; best = c; }
            }
            NSString *urlStr = best[@"url"] ?: [[candidates firstObject] objectForKey:@"url"];
            if ([urlStr isKindOfClass:[NSString class]] && urlStr.length) {
                return [NSURL URLWithString:urlStr];
            }
        }
    } @catch (__unused NSException *e) {}

    IGPhoto *photo = nil;
    @try {
        if ([media respondsToSelector:@selector(photo)]) photo = media.photo;
    } @catch (__unused NSException *e) {}
    if (photo) return [SCIUtils getPhotoUrl:photo];
    return nil;
}

+ (NSURL *)getVideoUrl:(IGVideo *)video {
    if (!video) return nil;

    @try {
        if ([video respondsToSelector:@selector(sortedVideoURLsBySize)]) {
            NSArray<NSDictionary *> *sorted = [video sortedVideoURLsBySize];
            NSString *urlString = [sorted.firstObject isKindOfClass:[NSDictionary class]] ? sorted.firstObject[@"url"] : nil;
            if ([urlString isKindOfClass:[NSString class]] && urlString.length) return [NSURL URLWithString:urlString];
        }
    } @catch (__unused NSException *e) {}

    @try {
        if ([video respondsToSelector:@selector(allVideoURLs)]) {
            id set = [video allVideoURLs];
            if ([set respondsToSelector:@selector(anyObject)]) {
                id obj = [set anyObject];
                if ([obj isKindOfClass:[NSURL class]]) {
                    NSString *abs = nil;
                    @try { abs = [(NSURL *)obj absoluteString]; } @catch (__unused NSException *e) {}
                    if (abs.length && ([abs hasPrefix:@"http"] || [abs hasPrefix:@"file:"])) {
                        return [NSURL URLWithString:abs];
                    }
                } else if ([obj isKindOfClass:[NSString class]]) {
                    NSString *s = (NSString *)obj;
                    if (s.length && ([s hasPrefix:@"http"] || [s hasPrefix:@"file:"])) return [NSURL URLWithString:s];
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media {
    if (!media) return nil;

    // fieldCache first — IGVideo selectors crash on newer IG builds.
    @try {
        NSArray *versions = sciFieldCacheValue(media, @"video_versions");
        if ([versions isKindOfClass:[NSArray class]] && versions.count) {
            NSDictionary *best = nil;
            NSInteger bestType = -1;
            for (id v in versions) {
                if (![v isKindOfClass:[NSDictionary class]]) continue;
                NSInteger type = [[v objectForKey:@"type"] integerValue];
                if (type > bestType) { bestType = type; best = v; }
            }
            NSString *urlStr = best[@"url"] ?: [[versions firstObject] objectForKey:@"url"];
            if ([urlStr isKindOfClass:[NSString class]] && urlStr.length) {
                return [NSURL URLWithString:urlStr];
            }
        }
    } @catch (__unused NSException *e) {}

    IGVideo *video = nil;
    @try {
        if ([media respondsToSelector:@selector(video)]) video = media.video;
    } @catch (__unused NSException *e) {}
    if (video) return [SCIUtils getVideoUrl:video];
    return nil;
}

// View Controllers
+ (UIViewController *)viewControllerForView:(UIView *)view {
    NSString *viewDelegate = @"viewDelegate";
    if ([view respondsToSelector:NSSelectorFromString(viewDelegate)]) {
        return [view valueForKey:viewDelegate];
    }

    return nil;
}

+ (UIViewController *)viewControllerForAncestralView:(UIView *)view {
    NSString *_viewControllerForAncestor = @"_viewControllerForAncestor";
    if ([view respondsToSelector:NSSelectorFromString(_viewControllerForAncestor)]) {
        return [view valueForKey:_viewControllerForAncestor];
    }

    return nil;
}

+ (UIViewController *)nearestViewControllerForView:(UIView *)view {
    return [self viewControllerForView:view] ?: [self viewControllerForAncestralView:view];
}

// Functions
+ (NSString *)IGVersionString {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
};
+ (BOOL)isNotch {
    return [[[UIApplication sharedApplication] keyWindow] safeAreaInsets].bottom > 0;
};

+ (BOOL)existingLongPressGestureRecognizerForView:(UIView *)view {
    NSArray *allRecognizers = view.gestureRecognizers;

    for (UIGestureRecognizer *recognizer in allRecognizers) {
        if ([[recognizer class] isSubclassOfClass:[UILongPressGestureRecognizer class]]) {
            return YES;
        }
    }

    return NO;
}

// Alerts
+ (BOOL)showConfirmation:(void(^)(void))okHandler title:(NSString *)title {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:SCILocalized(@"Are you sure?") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Yes") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        okHandler();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"No!") style:UIAlertActionStyleCancel handler:nil]];

    [topMostController() presentViewController:alert animated:YES completion:nil];

    return nil;
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler title:(NSString *)title {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:SCILocalized(@"Are you sure?") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Yes") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        okHandler();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"No!") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        if (cancelHandler != nil) {
            cancelHandler();
        }
    }]];

    [topMostController() presentViewController:alert animated:YES completion:nil];

    return nil;
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler {
    return [self showConfirmation:okHandler title:nil];
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler {
    return [self showConfirmation:okHandler cancelHandler:cancelHandler title:nil];
}
+ (void)showRestartConfirmation {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Restart required") message:SCILocalized(@"You must restart the app to apply this change") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Restart") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        exit(0);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Later") style:UIAlertActionStyleCancel handler:nil]];

    [topMostController() presentViewController:alert animated:YES completion:nil];
};

// Toasts — routes through SCINotificationCenter; IG-native presenter still
// reachable via showIGNativeToastForDuration: for ig_native overrides.
+ (void)showToastForDuration:(double)duration title:(NSString *)title {
    [SCIUtils showToastForDuration:duration title:title subtitle:nil];
}
+ (void)showToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle {
    [[SCINotificationCenter shared] notifyAction:SCI_NOTIF_GENERIC
                                            title:title
                                         subtitle:subtitle
                                             icon:nil
                                             tone:SCINotificationToneInfo
                                         duration:duration];
}

// Find IGRootViewController in any connected window. Topmost VC is rarely
// IGRoot itself (it's usually a child / presented VC), so we walk down.
static IGRootViewController *sciFindIGRootVC(void) {
    Class rootCls = NSClassFromString(@"IGRootViewController");
    if (!rootCls) return nil;
    NSMutableArray<UIViewController *> *queue = [NSMutableArray new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.rootViewController) [queue addObject:w.rootViewController];
        }
    }
    while (queue.count) {
        UIViewController *vc = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([vc isKindOfClass:rootCls]) return (IGRootViewController *)vc;
        if (vc.presentedViewController) [queue addObject:vc.presentedViewController];
        for (UIViewController *child in vc.childViewControllers) [queue addObject:child];
    }
    return nil;
}

+ (void)showIGNativeToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle {
    IGRootViewController *rootVC = sciFindIGRootVC();
    if (!rootVC) return;

    IGActionableConfirmationToastPresenter *toastPresenter = [rootVC toastPresenter];
    if (toastPresenter == nil) return;

    Class modelClass = NSClassFromString(@"IGActionableConfirmationToastViewModel");
    if (!modelClass) return;
    IGActionableConfirmationToastViewModel *model = [modelClass new];
    [model setValue:title forKey:@"text_annotatedTitleText"];
    [model setValue:subtitle forKey:@"text_annotatedSubtitleText"];

    [toastPresenter hideAlert];
    [toastPresenter showAlertWithViewModel:model isAnimated:true animationDuration:duration presentationPriority:0 tapActionBlock:nil presentedHandler:nil dismissedHandler:nil];
}

// Math
+ (NSUInteger)decimalPlacesInDouble:(double)value {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setMaximumFractionDigits:15]; // Allow enough digits for double precision
    [formatter setMinimumFractionDigits:0];
    [formatter setDecimalSeparator:@"."]; // Force dot for internal logic, then respect locale for final display if needed

    NSString *stringValue = [formatter stringFromNumber:@(value)];

    // Find decimal separator
    NSRange decimalRange = [stringValue rangeOfString:formatter.decimalSeparator];

    if (decimalRange.location == NSNotFound) {
        return 0;
    } else {
        return stringValue.length - (decimalRange.location + decimalRange.length);
    }
}

// Ivars
+ (id)getIvarForObj:(id)obj name:(const char *)name {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) return nil;

    return object_getIvar(obj, ivar);
}
+ (void)setIvarForObj:(id)obj name:(const char *)name value:(id)value {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) return;

    object_setIvarWithStrongDefault(obj, ivar, value);
}

+ (id)activeUserSession {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            @try {
                id s = [w valueForKey:@"userSession"];
                if (s) return s;
            } @catch (__unused id e) {}
        }
    }
    return nil;
}

+ (NSString *)pkFromIGUser:(id)user {
    if (!user) return nil;
    Ivar pkIvar = NULL;
    for (Class c = [user class]; c && !pkIvar; c = class_getSuperclass(c)) {
        pkIvar = class_getInstanceVariable(c, "_pk");
    }
    if (!pkIvar) return nil;
    id pk = object_getIvar(user, pkIvar);
    return pk ? [pk description] : nil;
}

+ (NSString *)currentUserPK {
    id session = [self activeUserSession];
    if (!session) return nil;
    @try {
        id user = [session valueForKey:@"user"];
        return [self pkFromIGUser:user];
    } @catch (__unused id e) { return nil; }
}

@end