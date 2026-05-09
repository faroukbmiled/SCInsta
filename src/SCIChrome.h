// Capture-aware chrome primitives. SCIChromeCanvas handles redaction via
// the UITextField secure-canvas technique; SCIChromeButton / SCIChromeLabel
// own the full visible hierarchy so IG's liquid glass can't wrap them.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - SCIChromeCanvas

@interface SCIChromeCanvas : UIView
@property (nonatomic, readonly) UIView *contentContainer;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// YES if `field` is the secure-canvas helper owned by SCIChromeCanvas.
/// Used by the Instants screenshot bypass to skip our own redaction fields.
BOOL SCIChromeCanvasOwnsSecureField(UITextField *field);

#ifdef __cplusplus
}
#endif

// MARK: - SCIChromeButton

@interface SCIChromeButton : UIButton
- (instancetype)initWithSymbol:(NSString *)symbol
                     pointSize:(CGFloat)pointSize
                      diameter:(CGFloat)diameter NS_DESIGNATED_INITIALIZER;

@property (nonatomic, assign, readonly) CGFloat diameter;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, assign) CGFloat symbolPointSize;
@property (nonatomic, copy) UIColor *iconTint;
@property (nonatomic, copy) UIColor *bubbleColor;
/// `symbolName` is SF-only. For IG-styled glyphs use `setIconResource:` or
/// assign `iconView.image` directly with a baked image.
@property (nonatomic, strong, readonly) UIImageView *iconView;

/// IG-styled glyph via `+[SCIIcon imageNamed:]`. Clears `symbolName`.
- (void)setIconResource:(NSString *)resourceName pointSize:(CGFloat)pointSize;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end

// MARK: - SCIChromeLabel

@interface SCIChromeLabel : UIView
- (instancetype)initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, assign) NSTextAlignment textAlignment;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end

#ifdef __cplusplus
extern "C" {
#endif

// Bar button item whose customView is an SCIChromeButton. `outButton` yields
// the inner button for menu/tint/etc.
UIBarButtonItem *SCIChromeBarButtonItem(NSString *symbol,
                                         CGFloat pointSize,
                                         id _Nullable target,
                                         SEL _Nullable action,
                                         SCIChromeButton * _Nullable * _Nullable outButton);

SCIChromeButton * _Nullable SCIChromeButtonForBarItem(UIBarButtonItem *item);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
