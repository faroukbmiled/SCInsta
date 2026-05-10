#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>
#import <os/log.h>
#import <objc/message.h>

#import "InstagramHeaders.h"
#import "QuickLook.h"
#import "Localization/SCILocalization.h"

#import "Settings/SCISettingsViewController.h"

#define SCILog(fmt, ...) \
    do { \
        NSString *tmpStr = [NSString stringWithFormat:(fmt), ##__VA_ARGS__]; \
        os_log(OS_LOG_DEFAULT, "[RyukGram] %{public}s", tmpStr.UTF8String); \
    } while(0)

#define SCILogId(prefix, obj) os_log(OS_LOG_DEFAULT, "[RyukGram] %{public}@: %{public}@", prefix, obj);

@interface SCIUtils : NSObject

+ (BOOL)getBoolPref:(NSString *)key;
+ (double)getDoublePref:(NSString *)key;
+ (NSString *)getStringPref:(NSString *)key;
+ (NSDictionary *)getDictPref:(NSString *)key;
+ (NSArray *)getArrayPref:(NSString *)key;
+ (void)setPref:(id)value forKey:(NSString *)key;

// Registered SCInsta defaults (set once at app launch by Tweak.x). Used by
// the settings backup so any new pref is included automatically.
+ (NSDictionary<NSString *, id> *)sciRegisteredDefaults;
+ (void)setSciRegisteredDefaults:(NSDictionary<NSString *, id> *)defaults;

+ (_Bool)liquidGlassEnabledBool:(_Bool)fallback;

// Displaying View Controllers
+ (void)showQuickLookVC:(NSArray<id> *)items;
+ (void)showShareVC:(id)item;
+ (void)showSettingsVC:(UIWindow *)window;
+ (void)showSettingsVC:(UIWindow *)window atTopLevelEntry:(NSString *)entryTitle;

// Colours
+ (UIColor *)SCIColor_Primary;
+ (UIColor *)SCIColor_InstagramBackground;
+ (UIColor *)SCIColor_InstagramSecondaryBackground;
+ (UIColor *)SCIColor_InstagramTertiaryBackground;
+ (UIColor *)SCIColor_InstagramGroupedBackground;
+ (UIColor *)SCIColor_InstagramPrimaryText;
+ (UIColor *)SCIColor_InstagramSecondaryText;
+ (UIColor *)SCIColor_InstagramTertiaryText;
+ (UIColor *)SCIColor_InstagramSeparator;
+ (UIColor *)SCIColor_InstagramFavorite;
+ (UIColor *)SCIColor_InstagramDestructive;
+ (UIColor *)SCIColor_InstagramPressedBackground;

// Errors
+ (NSError *)errorWithDescription:(NSString *)errorDesc;
+ (NSError *)errorWithDescription:(NSString *)errorDesc code:(NSInteger)errorCode;

+ (void)showErrorHUDWithDescription:(NSString *)errorDesc;
+ (void)showErrorHUDWithDescription:(NSString *)errorDesc dismissAfterDelay:(CGFloat)dismissDelay;

// Media
// IGAPIStorableObject's snake_case Pando _fieldCache dict. Many IG fields
// aren't exposed through KVC (the resolver returns NSNull for absent keys);
// reading the dict directly is the reliable path. Returns nil when obj has
// no _fieldCache ivar or the value is missing.
+ (NSDictionary *)fieldCacheForObject:(id)obj;
+ (id)fieldCacheValue:(id)obj forKey:(NSString *)key;

+ (NSURL *)getPhotoUrl:(IGPhoto *)photo;
+ (NSURL *)getPhotoUrlForMedia:(IGMedia *)media;

+ (NSURL *)getVideoUrl:(IGVideo *)video;
+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media;

// View Controllers
+ (UIViewController *)viewControllerForView:(UIView *)view;
+ (UIViewController *)viewControllerForAncestralView:(UIView *)view;
+ (UIViewController *)nearestViewControllerForView:(UIView *)view;

// Functions
+ (NSString *)IGVersionString;
+ (BOOL)isNotch;

+ (BOOL)existingLongPressGestureRecognizerForView:(UIView *)view;

// Alerts
// Pass the matching Settings toggle title for `title` (reuses localized strings). nil = generic.
+ (BOOL)showConfirmation:(void(^)(void))okHandler title:(NSString *)title;
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler title:(NSString *)title;
+ (BOOL)showConfirmation:(void(^)(void))okHandler;
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler;
+ (void)showRestartConfirmation;

// Toasts
+ (void)showToastForDuration:(double)duration title:(NSString *)title;
+ (void)showToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle;
+ (void)showIGNativeToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle;

// Math
+ (NSUInteger)decimalPlacesInDouble:(double)value;

// Ivars
+ (id)getIvarForObj:(id)obj name:(const char *)name;
+ (void)setIvarForObj:(id)obj name:(const char *)name value:(id)value;

// Active IG user session (walks all connected scenes for the first window
// with a non-nil `userSession`).
+ (id)activeUserSession;
// PK string read from an IGUser object's `_pk` ivar (walks superclass chain).
+ (NSString *)pkFromIGUser:(id)user;
// Current logged-in user's PK via the active session.
+ (NSString *)currentUserPK;

@end