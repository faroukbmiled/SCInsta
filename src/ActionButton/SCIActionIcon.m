#import "SCIActionIcon.h"
#import "../Utils.h"
#import "../SCIPrefObserver.h"
#import <objc/runtime.h>

NSString *const SCIActionIconPrefKey = @"action_button_icon";
NSString *const SCIActionIconDefaultName = @"ellipsis.circle";
NSString *const SCIActionIconDidChangeNote = @"SCIActionIconDidChange";

static const void *kSCIActionIconConfigKey = &kSCIActionIconConfigKey;

@interface SCIActionIconConfig : NSObject
@property (nonatomic, assign) CGFloat pointSize;
@property (nonatomic, assign) SCIActionIconStyle style;
@end

@implementation SCIActionIconConfig
@end

@implementation SCIActionIcon

+ (NSHashTable<SCIChromeButton *> *)attached {
	static NSHashTable *table;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ table = NSHashTable.weakObjectsHashTable; });
	return table;
}

+ (void)ensureObserver {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		[SCIPrefObserver observeKey:SCIActionIconPrefKey handler:^{
			[self broadcastChange];
		}];
	});
}

+ (void)broadcastChange {
	for (SCIChromeButton *button in self.attached.allObjects) {
		SCIActionIconConfig *config = objc_getAssociatedObject(button, kSCIActionIconConfigKey);
		if (config) [self applyToButton:button pointSize:config.pointSize style:config.style];
	}

	[NSNotificationCenter.defaultCenter postNotificationName:SCIActionIconDidChangeNote object:nil];
}

+ (NSString *)symbolName {
	NSString *raw = [SCIUtils getStringPref:SCIActionIconPrefKey];
	return (raw.length && [UIImage systemImageNamed:raw]) ? raw : SCIActionIconDefaultName;
}

+ (void)setSymbolName:(NSString *)name {
	if (!name.length || ![UIImage systemImageNamed:name]) return;

	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	NSString *current = [defaults stringForKey:SCIActionIconPrefKey];

	if (![current isEqualToString:name]) {
		[defaults setObject:name forKey:SCIActionIconPrefKey];
	}
}

+ (NSArray<NSString *> *)availableSystemIcons {
	// Curated to "more / open menu / take action" reads.
	return @[
		@"ellipsis.circle", @"ellipsis.circle.fill", @"ellipsis", @"ellipsis.rectangle",
		@"circle.grid.2x2", @"circle.grid.2x2.fill", @"circle.grid.3x3", @"square.grid.2x2",
		@"line.3.horizontal", @"line.3.horizontal.circle", @"line.3.horizontal.circle.fill",

		@"plus.circle", @"plus.circle.fill", @"plus.app", @"plus.app.fill",
		@"xmark.circle", @"xmark.circle.fill",

		@"arrow.down.circle", @"arrow.down.circle.fill",
		@"arrow.up.circle", @"arrow.up.circle.fill",
		@"arrow.up.right.circle", @"arrow.up.right.circle.fill",
		@"square.and.arrow.down", @"square.and.arrow.down.fill",
		@"square.and.arrow.up", @"square.and.arrow.up.fill",
		@"arrow.triangle.2.circlepath", @"arrow.triangle.2.circlepath.circle",
		@"arrow.down", @"arrow.down.to.line", @"arrow.down.to.line.compact",
		@"arrow.down.app", @"arrow.down.app.fill",
		@"arrow.down.square", @"arrow.down.square.fill",
		@"tray.and.arrow.down", @"tray.and.arrow.down.fill",
		@"icloud.and.arrow.down", @"icloud.and.arrow.down.fill",

		@"gear", @"gearshape", @"gearshape.fill", @"gearshape.2", @"gearshape.2.fill",
		@"slider.horizontal.3", @"slider.vertical.3",
		@"wrench", @"wrench.fill", @"wrench.and.screwdriver", @"wrench.and.screwdriver.fill",
		@"hammer", @"hammer.fill", @"hammer.circle", @"hammer.circle.fill",
		@"command", @"command.circle", @"command.circle.fill", @"command.square", @"command.square.fill",

		@"sparkle", @"sparkles", @"wand.and.stars", @"wand.and.stars.inverse",
		@"star", @"star.fill", @"star.circle", @"star.circle.fill",
		@"bolt", @"bolt.fill", @"bolt.circle", @"bolt.circle.fill",
		@"flame", @"flame.fill",

		@"heart", @"heart.fill", @"heart.circle", @"heart.circle.fill",
		@"crown", @"crown.fill", @"leaf", @"leaf.fill", @"hare", @"hare.fill",
		@"moon", @"moon.fill", @"sun.max", @"sun.max.fill",
		@"gift", @"gift.fill", @"gift.circle", @"gift.circle.fill"
	];
}

+ (void)clearIconImageState:(SCIChromeButton *)button {
	button.iconView.image = nil;
	button.iconView.layer.shadowOpacity = 0.0;
	button.iconView.layer.shadowRadius = 0.0;
	button.iconView.layer.shadowOffset = CGSizeZero;
	button.iconView.layer.shadowColor = nil;
}

+ (void)applyToButton:(SCIChromeButton *)button pointSize:(CGFloat)pointSize style:(SCIActionIconStyle)style {
	if (!button) return;

	// ShadowBaked is intentionally treated as plain now.
	// This keeps old callers working without generating baked shadows.
	[self clearIconImageState:button];

	button.symbolPointSize = pointSize;
	button.symbolName = self.symbolName;
}

+ (void)attachAutoUpdate:(SCIChromeButton *)button pointSize:(CGFloat)pointSize style:(SCIActionIconStyle)style {
	if (!button) return;

	[self ensureObserver];

	SCIActionIconConfig *config = SCIActionIconConfig.new;
	config.pointSize = pointSize;
	config.style = style;

	objc_setAssociatedObject(button, kSCIActionIconConfigKey, config, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[self.attached addObject:button];
	[self applyToButton:button pointSize:pointSize style:style];
}

@end