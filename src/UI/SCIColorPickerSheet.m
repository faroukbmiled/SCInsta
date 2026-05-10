#import "SCIColorPickerSheet.h"
#import "../Localization/SCILocalization.h"
#import <objc/runtime.h>

// Solid mode presents UIColorPickerViewController directly — embedding it
// breaks the eyedropper dismiss path under IGNavigationController. Gradient
// mode keeps the original two-swatch + embedded picker layout.

static char kSCIPickerSelfRetainKey;
static char kSCIPickerKVOInstalledKey;

@interface SCIColorPickerSheet () <UIColorPickerViewControllerDelegate>
@property (nonatomic, assign) SCIColorPickerSheetMode mode;
@property (nonatomic, strong) UIColor *startColor;
@property (nonatomic, strong, nullable) UIColor *endColor;
@property (nonatomic, copy) SCIColorPickerSheetApplyHandler applyHandler;

@property (nonatomic, assign) BOOL editingEndSlot;
@property (nonatomic, strong) UIColorPickerViewController *embeddedPicker;
@property (nonatomic, weak)   UIColorPickerViewController *standalonePicker;
@property (nonatomic, strong) UIStackView *swatchRow;
@property (nonatomic, strong) UIButton *startSwatch;
@property (nonatomic, strong) UIButton *endSwatch;
@property (nonatomic, assign) CFTimeInterval lastApply;
@end

@implementation SCIColorPickerSheet

+ (instancetype)sheetWithMode:(SCIColorPickerSheetMode)mode
                   startColor:(UIColor *)start
                     endColor:(UIColor *)end
                 applyHandler:(SCIColorPickerSheetApplyHandler)handler {
    SCIColorPickerSheet *vc = [SCIColorPickerSheet new];
    vc.mode = mode;
    vc.startColor = start ?: [UIColor systemPinkColor];
    vc.endColor = end ?: [UIColor systemPurpleColor];
    vc.applyHandler = handler;
    return vc;
}

#pragma mark - Solid mode

- (UIColorPickerViewController *)makeStandalonePickerSeededWith:(UIColor *)seed {
    UIColorPickerViewController *p = [UIColorPickerViewController new];
    p.delegate = self;
    p.supportsAlpha = NO;
    p.title = SCILocalized(@"Colors");
    p.selectedColor = seed ?: [UIColor systemPinkColor];
    [p addObserver:self forKeyPath:@"selectedColor" options:NSKeyValueObservingOptionNew context:NULL];
    objc_setAssociatedObject(p, &kSCIPickerKVOInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(p, &kSCIPickerSelfRetainKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.standalonePicker = p;

    p.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *s = p.sheetPresentationController;
        s.detents = @[[UISheetPresentationControllerDetent mediumDetent],
                      [UISheetPresentationControllerDetent largeDetent]];
        s.prefersGrabberVisible = YES;
        s.preferredCornerRadius = 16.0;
    }
    return p;
}

- (void)tearDownStandalonePicker:(UIColorPickerViewController *)p {
    if (!p) return;
    if ([objc_getAssociatedObject(p, &kSCIPickerKVOInstalledKey) boolValue]) {
        @try { [p removeObserver:self forKeyPath:@"selectedColor"]; }
        @catch (__unused NSException *e) {}
        objc_setAssociatedObject(p, &kSCIPickerKVOInstalledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(p, &kSCIPickerSelfRetainKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.standalonePicker == p) self.standalonePicker = nil;
}

#pragma mark - Public present

- (void)presentFromViewController:(UIViewController *)presenter {
    if (!presenter) return;

    if (_mode == SCIColorPickerSheetModeSolid) {
        UIColorPickerViewController *p = [self makeStandalonePickerSeededWith:_startColor];
        [self fireApply];
        [presenter presentViewController:p animated:YES completion:nil];
        return;
    }

    self.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *s = self.sheetPresentationController;
        s.detents = @[[UISheetPresentationControllerDetent mediumDetent],
                      [UISheetPresentationControllerDetent largeDetent]];
        s.prefersGrabberVisible = YES;
        s.preferredCornerRadius = 16.0;
    }
    [presenter presentViewController:self animated:YES completion:nil];
}

#pragma mark - Gradient host

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    if (_mode != SCIColorPickerSheetModeGradient) return;

    [self buildSwatchRow];
    [self buildEmbeddedPicker];
    [self layoutGradient];
    [self refreshSwatches];
    [self fireApply];
}

- (UIButton *)makeSwatch {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.layer.cornerRadius = 18;
    b.layer.masksToBounds = YES;
    b.layer.borderColor = UIColor.separatorColor.CGColor;
    b.layer.borderWidth = 2;
    [b.widthAnchor constraintEqualToConstant:36].active = YES;
    [b.heightAnchor constraintEqualToConstant:36].active = YES;
    return b;
}

- (UILabel *)makeLabel:(NSString *)t {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    l.textColor = UIColor.secondaryLabelColor;
    return l;
}

- (void)buildSwatchRow {
    _startSwatch = [self makeSwatch];
    _endSwatch = [self makeSwatch];
    [_startSwatch addTarget:self action:@selector(selectStartSlot) forControlEvents:UIControlEventTouchUpInside];
    [_endSwatch addTarget:self action:@selector(selectEndSlot) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *startCol = [[UIStackView alloc] initWithArrangedSubviews:@[[self makeLabel:SCILocalized(@"Start")], _startSwatch]];
    startCol.axis = UILayoutConstraintAxisVertical; startCol.alignment = UIStackViewAlignmentCenter; startCol.spacing = 4;
    UIStackView *endCol = [[UIStackView alloc] initWithArrangedSubviews:@[[self makeLabel:SCILocalized(@"End")], _endSwatch]];
    endCol.axis = UILayoutConstraintAxisVertical; endCol.alignment = UIStackViewAlignmentCenter; endCol.spacing = 4;

    _swatchRow = [[UIStackView alloc] initWithArrangedSubviews:@[startCol, endCol]];
    _swatchRow.axis = UILayoutConstraintAxisHorizontal;
    _swatchRow.alignment = UIStackViewAlignmentCenter;
    _swatchRow.spacing = 32;
    _swatchRow.translatesAutoresizingMaskIntoConstraints = NO;
}

- (void)buildEmbeddedPicker {
    _embeddedPicker = [[UIColorPickerViewController alloc] init];
    _embeddedPicker.delegate = self;
    _embeddedPicker.supportsAlpha = NO;
    _embeddedPicker.title = SCILocalized(@"Colors");
    _embeddedPicker.selectedColor = _startColor;
    [_embeddedPicker addObserver:self forKeyPath:@"selectedColor" options:NSKeyValueObservingOptionNew context:NULL];
    objc_setAssociatedObject(_embeddedPicker, &kSCIPickerKVOInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self addChildViewController:_embeddedPicker];
    _embeddedPicker.view.translatesAutoresizingMaskIntoConstraints = NO;
}

- (void)layoutGradient {
    [self.view addSubview:_swatchRow];
    [self.view addSubview:_embeddedPicker.view];
    [_embeddedPicker didMoveToParentViewController:self];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_swatchRow.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
        [_swatchRow.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],
        [_embeddedPicker.view.topAnchor constraintEqualToAnchor:_swatchRow.bottomAnchor constant:8],
        [_embeddedPicker.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_embeddedPicker.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_embeddedPicker.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)refreshSwatches {
    _startSwatch.backgroundColor = _startColor;
    _endSwatch.backgroundColor = _endColor;
    _startSwatch.layer.borderColor = (_editingEndSlot ? UIColor.separatorColor : UIColor.labelColor).CGColor;
    _endSwatch.layer.borderColor   = (_editingEndSlot ? UIColor.labelColor   : UIColor.separatorColor).CGColor;
    _startSwatch.layer.borderWidth = _editingEndSlot ? 2 : 3;
    _endSwatch.layer.borderWidth   = _editingEndSlot ? 3 : 2;
}

- (void)selectStartSlot { _editingEndSlot = NO;  _embeddedPicker.selectedColor = _startColor; [self refreshSwatches]; }
- (void)selectEndSlot   { _editingEndSlot = YES; _embeddedPicker.selectedColor = _endColor;   [self refreshSwatches]; }

#pragma mark - KVO + delegate

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (![keyPath isEqualToString:@"selectedColor"]) return;
    UIColor *c = change[NSKeyValueChangeNewKey];
    if (![c isKindOfClass:[UIColor class]]) return;
    UIColor *opaque = [c colorWithAlphaComponent:1.0];

    if (_mode == SCIColorPickerSheetModeGradient) {
        if (_editingEndSlot) _endColor = opaque; else _startColor = opaque;
        [self refreshSwatches];
    } else {
        _startColor = opaque;
    }
    [self fireApply];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    if (viewController == self.standalonePicker) [self tearDownStandalonePicker:viewController];
}

#pragma mark - Apply

- (void)fireApply {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastApply < 0.033) return; // ~30 Hz throttle
    _lastApply = now;

    if (_applyHandler) {
        _applyHandler(_mode, _startColor, (_mode == SCIColorPickerSheetModeGradient) ? _endColor : nil);
    }
}

- (void)dealloc {
    if (_embeddedPicker && [objc_getAssociatedObject(_embeddedPicker, &kSCIPickerKVOInstalledKey) boolValue]) {
        @try { [_embeddedPicker removeObserver:self forKeyPath:@"selectedColor"]; }
        @catch (__unused NSException *e) {}
    }
    if (_standalonePicker) [self tearDownStandalonePicker:_standalonePicker];
}

@end
