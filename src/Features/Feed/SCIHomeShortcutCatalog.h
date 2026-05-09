// Single source of truth for the home top-bar shortcut button: pref keys,
// catalog (id ↔ title ↔ symbol), and the firing logic.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kSCIHomeShortcutActionsPrefKey;
extern NSString *const kSCIHomeShortcutEnabledPrefKey;
extern NSString *const kSCIHomeShortcutIconPrefKey;

// Posted whenever the user reorders/toggles entries or changes the icon —
// the home top-bar hook listens and rebuilds the injected button live so
// changes don't require a relaunch.
extern NSNotificationName const SCIHomeShortcutConfigDidChangeNotification;

@interface SCIHomeShortcutAction : NSObject
@property (nonatomic, copy, readonly) NSString *actionID;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *symbol;
@end

@interface SCIHomeShortcutCatalog : NSObject
+ (NSArray<SCIHomeShortcutAction *> *)allActions;
+ (nullable SCIHomeShortcutAction *)actionForID:(NSString *)actionID;
+ (NSArray<NSString *> *)availableIcons;
/// Enabled action IDs in user order. Empty when master toggle is off.
+ (NSArray<NSString *> *)enabledActionIDs;
/// `contextView` resolves the window / nearest VC for presenting.
+ (void)fireActionID:(NSString *)actionID contextView:(UIView *)contextView;
@end

NS_ASSUME_NONNULL_END
