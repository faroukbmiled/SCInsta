// Long-press the Explore/search tab to open an IG link from the clipboard.

#import "../../Utils.h"
#import "../../SCIURLOpener.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>

static const void *kPasteGestureKey = &kPasteGestureKey;

// Parse the clipboard string into a URL IG will recognize. Accepts bare
// hostnames, canonical IG hosts, and fix-embed mirrors (any host with
// "instagram" in it — ddinstagram, eeinstagram, vxinstagram, etc.) which
// get rewritten to www.instagram.com.
static NSURL *sciNormalizeIGURL(NSString *raw) {
    if (!raw.length) return nil;
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![raw containsString:@"://"]) raw = [@"https://" stringByAppendingString:raw];

    NSURL *url = [NSURL URLWithString:raw];
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"instagram"]) return url;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return nil;

    NSString *host = url.host.lowercaseString;
    if (!host.length) return nil;

    if ([host isEqualToString:@"instagram.com"]
        || [host hasSuffix:@".instagram.com"]
        || [host isEqualToString:@"instagr.am"]
        || [host isEqualToString:@"ig.me"]) {
        return url;
    }

    if ([host containsString:@"instagram"]) {
        NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        comps.scheme = @"https";
        comps.host = @"www.instagram.com";
        return comps.URL;
    }

    return nil;
}

@interface SCIPasteLinkHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)longPressed:(UILongPressGestureRecognizer *)g;
@end

@implementation SCIPasteLinkHandler
+ (instancetype)shared {
    static SCIPasteLinkHandler *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SCIPasteLinkHandler new]; });
    return s;
}

// Gate the gesture on the pref. When off, IG's default long-press falls through.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    return [SCIUtils getBoolPref:@"paste_link_from_search"];
}

- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;

    NSURL *url = sciNormalizeIGURL([[UIPasteboard generalPasteboard] string]);
    if (!url) {
        SCINotifyWarning(SCI_NOTIF_PASTE_LINK_INVALID, SCILocalized(@"Clipboard is not an Instagram URL"), nil);
        return;
    }
    [SCIURLOpener openURL:url];
}
@end

static void sciAttachPasteGesture(UIButton *btn) {
    if (!btn || objc_getAssociatedObject(btn, kPasteGestureKey)) return;
    SCIPasteLinkHandler *handler = [SCIPasteLinkHandler shared];
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc]
        initWithTarget:handler action:@selector(longPressed:)];
    g.minimumPressDuration = 0.5;
    g.delegate = handler;
    // Cancel the tap so IG's tab-tap doesn't fire after and clobber our nav.
    g.cancelsTouchesInView = YES;
    [btn addGestureRecognizer:g];
    objc_setAssociatedObject(btn, kPasteGestureKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook IGTabBarController
- (void)viewDidLayoutSubviews {
    %orig;
    Ivar iv = class_getInstanceVariable([self class], "_exploreButton");
    if (!iv) return;
    id btn = object_getIvar(self, iv);
    if ([btn isKindOfClass:[UIButton class]]) sciAttachPasteGesture(btn);
}
%end
