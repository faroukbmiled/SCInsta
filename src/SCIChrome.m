#import "SCIChrome.h"
#import "Utils.h"
#import "SCIPrefObserver.h"

static void sciPinEdges(UIView *view, UIView *host) {
	[NSLayoutConstraint activateConstraints:@[
		[view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
		[view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
		[view.topAnchor constraintEqualToAnchor:host.topAnchor],
		[view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
	]];
}

static UIView *sciFindCanvasDeep(UIView *root, NSInteger depth) {
	if (!root || depth > 4) return nil;

	for (UIView *subview in root.subviews) {
		if ([NSStringFromClass(subview.class) containsString:@"CanvasView"]) return subview;

		UIView *found = sciFindCanvasDeep(subview, depth + 1);
		if (found) return found;
	}

	return nil;
}

@interface SCIChromeCanvas ()
@property (nonatomic, strong) UITextField *secureField;
@property (nonatomic, strong, nullable) UIView *canvas;
@end

@implementation SCIChromeCanvas

+ (NSHashTable<SCIChromeCanvas *> *)instances {
	static NSHashTable *table;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		table = [NSHashTable weakObjectsHashTable];
	});
	return table;
}

+ (void)ensureObserverInstalled {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		[SCIPrefObserver observeKey:@"hide_ui_on_capture" handler:^{
			for (SCIChromeCanvas *canvas in [SCIChromeCanvas instances]) {
				[canvas applyPref];
			}
		}];
	});
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];

	if (self) {
		[SCIChromeCanvas ensureObserverInstalled];

		self.translatesAutoresizingMaskIntoConstraints = NO;

		_secureField = [UITextField new];
		_secureField.userInteractionEnabled = NO;
		_secureField.autocorrectionType = UITextAutocorrectionTypeNo;
		_secureField.spellCheckingType = UITextSpellCheckingTypeNo;
		_secureField.smartDashesType = UITextSmartDashesTypeNo;
		_secureField.smartQuotesType = UITextSmartQuotesTypeNo;
		_secureField.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
		_secureField.autocapitalizationType = UITextAutocapitalizationTypeNone;

		[self applyPref];
		[[SCIChromeCanvas instances] addObject:self];
		[self attachCanvasIfPossible];
	}

	return self;
}

- (UIView *)contentContainer {
	return self.canvas ?: self;
}

- (void)applyPref {
	BOOL enabled = [SCIUtils getBoolPref:@"hide_ui_on_capture"];
	if (_secureField.secureTextEntry != enabled) _secureField.secureTextEntry = enabled;
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	[self attachCanvasIfPossible];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[self attachCanvasIfPossible];
}

- (void)attachCanvasIfPossible {
	if (_canvas.superview == self) return;

	[_secureField layoutIfNeeded];

	UIView *canvas = sciFindCanvasDeep(_secureField, 0);
	if (!canvas) return;

	NSMutableArray<UIView *> *stashedViews = [NSMutableArray array];
	for (UIView *subview in self.subviews) {
		if (subview != canvas) [stashedViews addObject:subview];
	}

	[canvas removeFromSuperview];
	canvas.translatesAutoresizingMaskIntoConstraints = NO;
	[self insertSubview:canvas atIndex:0];
	sciPinEdges(canvas, self);

	_canvas = canvas;

	for (UIView *view in stashedViews) {
		[view removeFromSuperview];
		[canvas addSubview:view];
	}
}

@end

@interface SCIChromeButton ()
@property (nonatomic, strong) SCIChromeCanvas *chromeCanvas;
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong, readwrite) UIImageView *iconView;
@end

@implementation SCIChromeButton

- (instancetype)initWithSymbol:(NSString *)symbol pointSize:(CGFloat)pointSize diameter:(CGFloat)diameter {
	self = [super initWithFrame:CGRectMake(0.0, 0.0, diameter, diameter)];

	if (self) {
		_diameter = diameter;
		_symbolName = symbol.copy;
		_symbolPointSize = pointSize;
		_iconTint = UIColor.whiteColor;
		_bubbleColor = [UIColor colorWithWhite:0.0 alpha:0.4];

		[self buildChrome];
	}

	return self;
}

- (void)buildChrome {
	self.adjustsImageWhenHighlighted = NO;
	self.translatesAutoresizingMaskIntoConstraints = NO;

	_chromeCanvas = [SCIChromeCanvas new];
	_chromeCanvas.userInteractionEnabled = NO;
	[self addSubview:_chromeCanvas];
	sciPinEdges(_chromeCanvas, self);

	_bubbleView = [UIView new];
	_bubbleView.userInteractionEnabled = NO;
	_bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
	_bubbleView.backgroundColor = _bubbleColor;
	_bubbleView.layer.cornerRadius = _diameter / 2.0;
	_bubbleView.clipsToBounds = YES;

	_iconView = [UIImageView new];
	_iconView.userInteractionEnabled = NO;
	_iconView.contentMode = UIViewContentModeCenter;
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconView.tintColor = _iconTint;

	[self reloadIcon];

	UIView *host = _chromeCanvas.contentContainer;
	[host addSubview:_bubbleView];
	[host addSubview:_iconView];

	sciPinEdges(_bubbleView, host);

	[NSLayoutConstraint activateConstraints:@[
		[_iconView.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
		[_iconView.centerYAnchor constraintEqualToAnchor:host.centerYAnchor]
	]];
}

- (CGSize)intrinsicContentSize {
	return CGSizeMake(_diameter, _diameter);
}

- (void)setSymbolName:(NSString *)symbolName {
	_symbolName = symbolName.copy;
	[self reloadIcon];
}

- (void)setSymbolPointSize:(CGFloat)symbolPointSize {
	_symbolPointSize = symbolPointSize;
	[self reloadIcon];
}

- (void)setIconTint:(UIColor *)iconTint {
	_iconTint = iconTint;
	_iconView.tintColor = iconTint;
}

- (void)setBubbleColor:(UIColor *)bubbleColor {
	_bubbleColor = bubbleColor;
	_bubbleView.backgroundColor = bubbleColor;
}

- (void)reloadIcon {
	if (!_symbolName.length) {
		_iconView.image = nil;
		return;
	}

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:_symbolPointSize weight:UIImageSymbolWeightSemibold];
	_iconView.image = [UIImage systemImageNamed:_symbolName withConfiguration:config];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) / 2.0;
	if (_bubbleView.layer.cornerRadius != radius) _bubbleView.layer.cornerRadius = radius;
}

@end

@interface SCIChromeLabel ()
@property (nonatomic, strong) SCIChromeCanvas *chromeCanvas;
@property (nonatomic, strong) UILabel *label;
@end

@implementation SCIChromeLabel

- (instancetype)initWithText:(NSString *)text {
	self = [super initWithFrame:CGRectZero];

	if (self) {
		self.translatesAutoresizingMaskIntoConstraints = NO;

		_chromeCanvas = [SCIChromeCanvas new];
		_chromeCanvas.userInteractionEnabled = NO;
		[self addSubview:_chromeCanvas];
		sciPinEdges(_chromeCanvas, self);

		_label = [UILabel new];
		_label.translatesAutoresizingMaskIntoConstraints = NO;
		_label.text = text;

		UIView *host = _chromeCanvas.contentContainer;
		[host addSubview:_label];
		sciPinEdges(_label, host);
	}

	return self;
}

- (NSString *)text { return _label.text; }
- (void)setText:(NSString *)text { _label.text = text; }
- (UIFont *)font { return _label.font; }
- (void)setFont:(UIFont *)font { _label.font = font; }
- (UIColor *)textColor { return _label.textColor; }
- (void)setTextColor:(UIColor *)textColor { _label.textColor = textColor; }
- (NSTextAlignment)textAlignment { return _label.textAlignment; }
- (void)setTextAlignment:(NSTextAlignment)textAlignment { _label.textAlignment = textAlignment; }

@end

UIBarButtonItem *SCIChromeBarButtonItem(NSString *symbol, CGFloat pointSize, id target, SEL action, SCIChromeButton **outButton) {
	SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:symbol pointSize:pointSize diameter:28.0];
	button.bubbleColor = UIColor.clearColor;

	if (target && action) {
		[button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
	}

	if (outButton) *outButton = button;
	return [[UIBarButtonItem alloc] initWithCustomView:button];
}

SCIChromeButton *SCIChromeButtonForBarItem(UIBarButtonItem *item) {
	UIView *view = item.customView;
	return [view isKindOfClass:SCIChromeButton.class] ? (SCIChromeButton *)view : nil;
}