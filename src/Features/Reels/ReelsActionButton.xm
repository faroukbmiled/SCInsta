// Reels action button — injects a RyukGram action button above the reel's
// vertical like/comment/share sidebar (IGSundialViewerVerticalUFI).

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../ActionButton/SCIActionButton.h"
#import "../../ActionButton/SCIActionIcon.h"
#import "../../ActionButton/SCIMediaActions.h"

static const NSInteger kReelActionBtnTag = 1337;
static const NSInteger kReelActionHitTag = 1338;

static char kReelActionDefaultKey;
static char kReelContextInteractionKey;
static char kReelVisibleButtonKey;
static char kSCIIGUFIButtonEDRKey;

@interface SCIReelHitButton : UIButton
@end

@implementation SCIReelHitButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
	return CGRectContainsPoint(CGRectInset(self.bounds, -24.0, -24.0), point);
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:NO];
	self.backgroundColor = UIColor.clearColor;
	self.layer.backgroundColor = UIColor.clearColor.CGColor;
}

- (void)setSelected:(BOOL)selected {
	[super setSelected:NO];
	self.backgroundColor = UIColor.clearColor;
	self.layer.backgroundColor = UIColor.clearColor.CGColor;
}

@end

static inline BOOL SCIReelsActionEnabled(void) {
	return [SCIUtils getBoolPref:@"reels_action_button"];
}

static inline NSString *SCIReelDefaultAction(void) {
	return [SCIUtils getStringPref:@"reels_action_default"];
}

static inline NSString *SCIReelActionOrMenu(void) {
	NSString *action = SCIReelDefaultAction();
	return action.length ? action : @"menu";
}

static UIColor *sciReelIconColor(BOOL edr) {
	if (!edr) return UIColor.whiteColor;

	static UIColor *color;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
		CGFloat c[] = { 2.0, 2.0, 2.0, 1.0 };
		CGColorRef cg = CGColorCreate(cs, c);
		color = [UIColor colorWithCGColor:cg];
		CGColorRelease(cg);
		CGColorSpaceRelease(cs);
	});

	return color;
}

static BOOL sciNativeReelEDR(id ufi) {
	id button = [ufi respondsToSelector:@selector(ufiLikeButton)]
		? ((id (*)(id, SEL))objc_msgSend)(ufi, @selector(ufiLikeButton))
		: nil;

	NSNumber *value = objc_getAssociatedObject(button, &kSCIIGUFIButtonEDRKey);
	if (value) return value.boolValue;

	return [button respondsToSelector:@selector(edr)]
		? ((BOOL (*)(id, SEL))objc_msgSend)(button, @selector(edr))
		: NO;
}

static void sciApplyReelIconBrightness(SCIChromeButton *button, BOOL edr) {
	if (!button) return;

	UIColor *color = sciReelIconColor(edr);

	button.hidden = NO;
	button.alpha = 1.0;
	button.userInteractionEnabled = NO;
	button.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;
	button.iconTint = color;
	button.bubbleColor = UIColor.clearColor;

	button.iconView.hidden = NO;
	button.iconView.alpha = 1.0;
	button.iconView.tintColor = color;
	button.iconView.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;
	button.iconView.highlighted = NO;

	if (button.iconView.image) {
		button.iconView.image = [button.iconView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	}
}

static UIView *sciFindSuperviewOfClass(UIView *view, NSString *className) {
	Class cls = NSClassFromString(className);
	if (!view || !cls) return nil;

	for (UIView *current = view.superview; current; current = current.superview) {
		if ([current isKindOfClass:cls]) return current;
	}

	return nil;
}

static id sciFindMediaIvar(UIView *view) {
	Class mediaClass = NSClassFromString(@"IGMedia");
	if (!view || !mediaClass) return nil;

	unsigned int count = 0;
	Ivar *ivars = class_copyIvarList(view.class, &count);
	id found = nil;

	for (unsigned int i = 0; i < count && !found; i++) {
		const char *type = ivar_getTypeEncoding(ivars[i]);
		if (!type || type[0] != '@') continue;

		@try {
			id value = object_getIvar(view, ivars[i]);
			if ([value isKindOfClass:mediaClass]) found = value;
		} @catch (__unused id e) {}
	}

	if (ivars) free(ivars);
	return found;
}

static NSInteger sciCarouselIndex(UIView *cell) {
	NSInteger index = 0;

	Ivar ivar = class_getInstanceVariable(cell.class, "_currentIndex");
	if (ivar) index = *(NSInteger *)((char *)(__bridge void *)cell + ivar_getOffset(ivar));

	ivar = class_getInstanceVariable(cell.class, "_currentFractionalIndex");
	if (ivar) {
		NSInteger rounded = (NSInteger)round(*(double *)((char *)(__bridge void *)cell + ivar_getOffset(ivar)));
		if (rounded > index) index = rounded;
	}

	ivar = class_getInstanceVariable(cell.class, "_collectionView");
	if (ivar) {
		UICollectionView *collectionView = object_getIvar(cell, ivar);
		CGFloat width = collectionView.bounds.size.width;

		if (collectionView && width > 0.0) {
			NSInteger cvIndex = (NSInteger)round(collectionView.contentOffset.x / width);
			if (cvIndex > index) index = cvIndex;
		}
	}

	return index;
}

static id sciReelsMediaProvider(UIView *sourceView) {
	UIView *cell = sciFindSuperviewOfClass(sourceView, @"IGSundialViewerVideoCell") ?: sciFindSuperviewOfClass(sourceView, @"IGSundialViewerPhotoCell");

	if (cell) {
		id media = sciFindMediaIvar(cell);
		if (media) return media;
	}

	UIView *carousel = sciFindSuperviewOfClass(sourceView, @"IGSundialViewerCarouselCell");
	id parent = sciFindMediaIvar(carousel);
	if (!parent) return nil;

	NSArray *children = [SCIMediaActions carouselChildrenForMedia:parent];
	NSInteger index = sciCarouselIndex(carousel);

	return (index >= 0 && (NSUInteger)index < children.count) ? children[index] : parent;
}

static void sciClearHit(UIButton *hit) {
	if (!hit) return;

	hit.highlighted = NO;
	hit.selected = NO;
	hit.opaque = NO;
	hit.alpha = 1.0;
	hit.backgroundColor = UIColor.clearColor;
	hit.layer.backgroundColor = UIColor.clearColor.CGColor;
	hit.adjustsImageWhenHighlighted = NO;
}

static void sciBounceVisibleButton(UIButton *hit) {
	UIView *button = objc_getAssociatedObject(hit, &kReelVisibleButtonKey);
	if (button) [SCIActionButton bounceButton:button];
}

@interface SCIReelMenuTarget : NSObject <UIContextMenuInteractionDelegate>
+ (instancetype)shared;
- (void)touchDown:(UIButton *)sender;
- (void)tapped:(UIButton *)sender;
@end

@implementation SCIReelMenuTarget

+ (instancetype)shared {
	static SCIReelMenuTarget *target;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		target = [SCIReelMenuTarget new];
	});
	return target;
}

- (void)touchDown:(UIButton *)sender {
	sciBounceVisibleButton(sender);
}

- (void)tapped:(UIButton *)sender {
	UIContextMenuInteraction *interaction = objc_getAssociatedObject(sender, &kReelContextInteractionKey);
	if (!interaction) return;

	CGPoint point = CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds));
	SEL selector = NSSelectorFromString(@"_presentMenuAtLocation:");

	if ([interaction respondsToSelector:selector]) {
		((void (*)(id, SEL, CGPoint))objc_msgSend)(interaction, selector, point);
		return;
	}

	selector = NSSelectorFromString(@"presentMenuAtLocation:");

	if ([interaction respondsToSelector:selector]) {
		((void (*)(id, SEL, CGPoint))objc_msgSend)(interaction, selector, point);
	}
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
						configurationForMenuAtLocation:(CGPoint)location {
	UIView *view = interaction.view;
	if (!view) return nil;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil
												   previewProvider:nil
													actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggested) {
		return [SCIActionButton deferredMenuForContext:SCIActionContextReels
											  fromView:view
										 mediaProvider:^id (UIView *sourceView) {
			return sciReelsMediaProvider(sourceView);
		}];
	}];
}

@end

static void sciConfigureMenuHit(UIButton *hit, SCIChromeButton *button) {
	if (!hit || !button) return;

	objc_setAssociatedObject(hit, &kReelVisibleButtonKey, button, OBJC_ASSOCIATION_ASSIGN);

	[hit addTarget:SCIReelMenuTarget.shared action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown];
	[hit addTarget:SCIReelMenuTarget.shared action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];

	UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:SCIReelMenuTarget.shared];
	[hit addInteraction:interaction];

	objc_setAssociatedObject(hit, &kReelContextInteractionKey, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(hit, &kReelActionDefaultKey, SCIReelDefaultAction() ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);

	sciClearHit(hit);
}

static void sciConfigureActionHit(UIButton *hit, SCIChromeButton *button) {
	if (!hit || !button) return;

	objc_setAssociatedObject(hit, &kReelVisibleButtonKey, button, OBJC_ASSOCIATION_ASSIGN);

	[SCIActionButton configureButton:hit
							 context:SCIActionContextReels
							 prefKey:@"reels_action_default"
					   mediaProvider:^id (UIView *sourceView) {
		return sciReelsMediaProvider(sourceView);
	}];

	[hit addTarget:SCIReelMenuTarget.shared action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown];

	objc_setAssociatedObject(hit, &kReelActionDefaultKey, SCIReelDefaultAction() ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);

	sciClearHit(hit);
}

static void sciConfigureHit(UIButton *hit, SCIChromeButton *button) {
	if ([SCIReelActionOrMenu() isEqualToString:@"menu"]) {
		sciConfigureMenuHit(hit, button);
	} else {
		sciConfigureActionHit(hit, button);
	}
}

static void sciRemoveReelButton(UIView *root) {
	[[root viewWithTag:kReelActionHitTag] removeFromSuperview];
	[[root viewWithTag:kReelActionBtnTag] removeFromSuperview];
}

%hook IGUFIButton
- (void)setEDR:(BOOL)edr {
	objc_setAssociatedObject(self, &kSCIIGUFIButtonEDRKey, @(edr), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	%orig;
}
%end

%hook IGSundialViewerVerticalUFI

- (void)didMoveToSuperview {
	%orig;
	((void(*)(id, SEL))objc_msgSend)(self, @selector(sciReloadReelActionButton));
}

- (void)layoutSubviews {
	%orig;
	((void(*)(id, SEL))objc_msgSend)(self, @selector(sciReloadReelActionButton));
}

%new
- (void)sciReloadReelActionButton {
	if (!self.superview) return;

	SCIChromeButton *button = (SCIChromeButton *)[self viewWithTag:kReelActionBtnTag];
	UIButton *hit = (UIButton *)[self viewWithTag:kReelActionHitTag];

	if (![button isKindOfClass:SCIChromeButton.class]) button = nil;
	if (![hit isKindOfClass:UIButton.class]) hit = nil;

	if (!SCIReelsActionEnabled()) {
		sciRemoveReelButton(self);
		return;
	}

	NSString *currentAction = SCIReelDefaultAction() ?: @"";
	NSString *configuredAction = objc_getAssociatedObject(hit, &kReelActionDefaultKey);

	if (hit && configuredAction && ![configuredAction isEqualToString:currentAction]) {
		[hit removeFromSuperview];
		hit = nil;
	}

	if (!button) {
		button = [[SCIChromeButton alloc] initWithSymbol:@"" pointSize:0 diameter:40];
		button.tag = kReelActionBtnTag;
		button.bubbleColor = UIColor.clearColor;
		button.adjustsImageWhenHighlighted = NO;
		button.userInteractionEnabled = NO;
		button.menu = nil;
		button.showsMenuAsPrimaryAction = NO;

		self.clipsToBounds = NO;
		[self addSubview:button];

		[NSLayoutConstraint activateConstraints:@[
			[button.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
			[button.bottomAnchor constraintEqualToAnchor:self.topAnchor constant:-10.0],
			[button.widthAnchor constraintEqualToConstant:40.0],
			[button.heightAnchor constraintEqualToConstant:40.0]
		]];

		[SCIActionIcon attachAutoUpdate:button pointSize:24 style:SCIActionIconStyleShadowBaked];
	}

	if (!hit) {
		hit = [SCIReelHitButton buttonWithType:UIButtonTypeCustom];
		hit.tag = kReelActionHitTag;
		hit.translatesAutoresizingMaskIntoConstraints = NO;
		sciClearHit(hit);

		[self addSubview:hit];

		[NSLayoutConstraint activateConstraints:@[
			[hit.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
			[hit.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
			[hit.widthAnchor constraintEqualToConstant:1.0],
			[hit.heightAnchor constraintEqualToConstant:1.0]
		]];

		sciConfigureHit(hit, button);
	}

	button.transform = CGAffineTransformIdentity;
	sciApplyReelIconBrightness(button, sciNativeReelEDR(self));

	hit.hidden = NO;
	sciClearHit(hit);

	[self bringSubviewToFront:button];
	[self bringSubviewToFront:hit];
}

%end