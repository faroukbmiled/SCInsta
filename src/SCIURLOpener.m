#import "SCIURLOpener.h"

@implementation SCIURLOpener

+ (BOOL)isInstagramHost:(NSString *)host {
    if (!host.length) return NO;
    NSString *h = host.lowercaseString;
    return [h isEqualToString:@"instagram.com"]
        || [h hasSuffix:@".instagram.com"]
        || [h isEqualToString:@"instagr.am"]
        || [h isEqualToString:@"ig.me"];
}

// IG / FB outbound redirectors wrap the real destination in `?u=<URL>`.
+ (NSURL *)unwrapRedirector:(NSURL *)url {
    NSString *h = url.host.lowercaseString;
    if (![h isEqualToString:@"l.instagram.com"]
        && ![h isEqualToString:@"l.facebook.com"]
        && ![h isEqualToString:@"lm.facebook.com"]) return url;
    NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *q in comps.queryItems) {
        if ([q.name isEqualToString:@"u"] && q.value.length) {
            NSURL *real = [NSURL URLWithString:q.value];
            if (real) return real;
        }
    }
    return url;
}

+ (BOOL)openURL:(NSURL *)url {
    if (!url) return NO;
    url = [self unwrapRedirector:url];

    UIApplication *app = [UIApplication sharedApplication];
    id<UIApplicationDelegate> delegate = app.delegate;
    NSString *scheme = url.scheme.lowercaseString;

    if ([scheme isEqualToString:@"instagram"]) {
        if ([delegate respondsToSelector:@selector(application:openURL:options:)]) {
            [delegate application:app openURL:url options:@{}];
            return YES;
        }
        [app openURL:url options:@{} completionHandler:nil];
        return YES;
    }

    if (([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        && [self isInstagramHost:url.host]) {
        NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
        activity.webpageURL = url;
        SEL contSel = @selector(application:continueUserActivity:restorationHandler:);
        if ([delegate respondsToSelector:contSel]) {
            BOOL handled = [delegate application:app
                            continueUserActivity:activity
                              restorationHandler:^(NSArray<id<UIUserActivityRestoring>> *_Nullable _) {}];
            if (handled) return YES;
        }
        if ([delegate respondsToSelector:@selector(application:openURL:options:)]) {
            [delegate application:app openURL:url options:@{}];
            return YES;
        }
    }

    [app openURL:url options:@{} completionHandler:nil];
    return YES;
}

+ (BOOL)openURLString:(NSString *)urlString {
    if (!urlString.length) return NO;
    return [self openURL:[NSURL URLWithString:urlString]];
}

+ (BOOL)dismiss:(UIViewController *)presenter thenOpenURL:(NSURL *)url {
    if (!url) return NO;
    UIViewController *root = presenter;
    while (root.presentingViewController) root = root.presentingViewController;
    void (^open)(void) = ^{ [self openURL:url]; };
    if (root && root != presenter) {
        [root dismissViewControllerAnimated:YES completion:open];
        return YES;
    }
    open();
    return YES;
}

+ (NSURL *)profileURLForUsername:(NSString *)username {
    if (!username.length) return nil;
    NSString *enc = [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if (!enc.length) return nil;
    NSURL *appURL = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", enc]];
    if (appURL && [[UIApplication sharedApplication] canOpenURL:appURL]) return appURL;
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/", enc]];
}

+ (BOOL)openInstagramProfileForUsername:(NSString *)username {
    NSURL *url = [self profileURLForUsername:username];
    return url ? [self openURL:url] : NO;
}

+ (BOOL)dismiss:(UIViewController *)presenter thenOpenInstagramProfileForUsername:(NSString *)username {
    NSURL *url = [self profileURLForUsername:username];
    return url ? [self dismiss:presenter thenOpenURL:url] : NO;
}

@end
