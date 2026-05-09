#import "SCIHomeShortcutCatalog.h"
#import "../../Utils.h"
#import "../../Gallery/SCIGalleryViewController.h"
#import "../General/SCIChangelog.h"
#import "../ProfileAnalyzer/SCIProfileAnalyzerViewController.h"
#import "../DeletedMessages/SCIDeletedMessagesViewController.h"
#import "../../UI/SCIPopupChrome.h"

NSString *const kSCIHomeShortcutActionsPrefKey = @"home_shortcut_actions";
NSString *const kSCIHomeShortcutEnabledPrefKey = @"home_shortcut_enabled";
NSString *const kSCIHomeShortcutIconPrefKey    = @"home_shortcut_icon";

NSNotificationName const SCIHomeShortcutConfigDidChangeNotification = @"SCIHomeShortcutConfigDidChangeNotification";

@interface SCIHomeShortcutAction ()
- (instancetype)initWithID:(NSString *)aid title:(NSString *)title symbol:(NSString *)sym;
@end

@implementation SCIHomeShortcutAction
- (instancetype)initWithID:(NSString *)aid title:(NSString *)title symbol:(NSString *)sym {
    if ((self = [super init])) {
        _actionID = aid.copy;
        _title = title.copy;
        _symbol = sym.copy;
    }
    return self;
}
@end

@implementation SCIHomeShortcutCatalog

+ (NSArray<SCIHomeShortcutAction *> *)allActions {
    static NSArray<SCIHomeShortcutAction *> *cat = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SCIHomeShortcutAction *(^make)(NSString *, NSString *, NSString *) = ^(NSString *aid, NSString *t, NSString *s) {
            return [[SCIHomeShortcutAction alloc] initWithID:aid title:t symbol:s];
        };
        cat = @[
            make(@"gallery",          SCILocalized(@"Gallery"),          @"photo.on.rectangle.angled"),
            make(@"settings",         SCILocalized(@"Settings"),         @"gearshape"),
            make(@"profile_analyzer", SCILocalized(@"Profile Analyzer"), @"person.fill.viewfinder"),
            make(@"deleted_messages", SCILocalized(@"Deleted messages"), @"tray.full"),
            make(@"changelog",        SCILocalized(@"Changelog"),        @"doc.text"),
        ];
    });
    return cat;
}

+ (SCIHomeShortcutAction *)actionForID:(NSString *)actionID {
    for (SCIHomeShortcutAction *a in [self allActions]) {
        if ([a.actionID isEqualToString:actionID]) return a;
    }
    return nil;
}

+ (NSArray<NSString *> *)availableIcons {
    static NSArray<NSString *> *names = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[
            @"bolt", @"bolt.fill", @"bolt.circle", @"bolt.circle.fill",
            @"bolt.shield", @"bolt.shield.fill",
            @"sparkle", @"sparkles", @"wand.and.stars", @"wand.and.stars.inverse",
            @"square.grid.2x2", @"square.grid.2x2.fill",
            @"square.grid.3x3", @"square.grid.3x3.fill",
            @"circle.grid.2x2", @"circle.grid.2x2.fill",
            @"circle.grid.3x3", @"circle.grid.3x3.fill",
            @"apps.iphone", @"app.badge", @"app.badge.fill",
            @"square.stack", @"square.stack.fill", @"square.stack.3d.up", @"square.stack.3d.up.fill",
            @"ellipsis", @"ellipsis.circle", @"ellipsis.circle.fill", @"ellipsis.rectangle", @"ellipsis.rectangle.fill",
            @"line.3.horizontal", @"line.3.horizontal.circle", @"line.3.horizontal.circle.fill",
            @"gear", @"gearshape", @"gearshape.fill", @"gearshape.2", @"gearshape.2.fill",
            @"slider.horizontal.3", @"slider.vertical.3",
            @"wrench", @"wrench.fill",
            @"wrench.adjustable", @"wrench.adjustable.fill",
            @"wrench.and.screwdriver", @"wrench.and.screwdriver.fill",
            @"hammer", @"hammer.fill", @"hammer.circle", @"hammer.circle.fill",
            @"command", @"command.circle", @"command.circle.fill", @"command.square", @"command.square.fill",
            @"star", @"star.fill", @"star.circle", @"star.circle.fill",
            @"crown", @"crown.fill",
            @"flame", @"flame.fill",
            @"sun.max", @"sun.max.fill", @"moon", @"moon.fill",
            @"heart", @"heart.fill", @"heart.circle", @"heart.circle.fill",
            @"plus.circle", @"plus.circle.fill", @"plus.app", @"plus.app.fill",
            @"plus.square", @"plus.square.fill",
            @"power", @"power.circle", @"power.circle.fill",
            @"hare", @"hare.fill",
            @"globe", @"globe.americas", @"globe.americas.fill",
            @"safari", @"safari.fill",
            @"arrow.up.right.square", @"arrow.up.right.square.fill",
            @"arrow.up.forward.app", @"arrow.up.forward.app.fill",
            @"link", @"link.circle", @"link.circle.fill",
            @"chevron.right.circle", @"chevron.right.circle.fill",
            @"house", @"house.fill", @"house.circle", @"house.circle.fill",
            @"cube", @"cube.fill", @"shippingbox", @"shippingbox.fill",
            @"gift", @"gift.fill", @"gift.circle", @"gift.circle.fill",
            @"leaf", @"leaf.fill",
        ];
    });
    return names;
}

+ (NSArray<NSString *> *)enabledActionIDs {
    if (![SCIUtils getBoolPref:kSCIHomeShortcutEnabledPrefKey]) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSDictionary *row in [SCIUtils getArrayPref:kSCIHomeShortcutActionsPrefKey]) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        NSString *aid = row[@"id"];
        if (![aid isKindOfClass:[NSString class]] || !aid.length) continue;
        if (![row[@"enabled"] boolValue]) continue;
        if (![self actionForID:aid]) continue; // drop stale entries
        [out addObject:aid];
    }
    return out;
}

+ (void)fireActionID:(NSString *)actionID contextView:(UIView *)contextView {
    if ([actionID isEqualToString:@"gallery"]) {
        [SCIGalleryViewController presentGallery];
        return;
    }
    if ([actionID isEqualToString:@"settings"]) {
        UIWindow *w = contextView.window ?: UIApplication.sharedApplication.keyWindow;
        if (w) [SCIUtils showSettingsVC:w];
        return;
    }
    if ([actionID isEqualToString:@"profile_analyzer"]) {
        UIViewController *top = [SCIUtils nearestViewControllerForView:contextView];
        [SCIPopupChrome presentVC:[SCIProfileAnalyzerViewController new] from:top];
        return;
    }
    if ([actionID isEqualToString:@"deleted_messages"]) {
        UIViewController *top = [SCIUtils nearestViewControllerForView:contextView];
        [SCIDeletedMessagesViewController presentFromViewController:top];
        return;
    }
    if ([actionID isEqualToString:@"changelog"]) {
        UIViewController *top = [SCIUtils nearestViewControllerForView:contextView];
        if (top) [SCIChangelog presentAllFromViewController:top];
    }
}

@end
