#import "SCIGalleryChip.h"
#import "../Utils.h"
#import "../UI/SCIIcon.h"

// SF Symbol first, FB catalog fallback.
static UIImage *SCIGalleryChipGlyph(NSString *name, CGFloat pointSize) {
    if (name.length == 0) return nil;
    UIImage *sf = [UIImage systemImageNamed:name];
    if (sf) return sf;
    return [SCIIcon fbImageNamed:name pointSize:pointSize];
}

@implementation SCIGalleryChip

+ (instancetype)chipWithTitle:(NSString *)title symbol:(NSString *)sfSymbol {
    return [self chipWithTitle:title symbol:sfSymbol fontSize:13.5 padding:UIEdgeInsetsMake(8, 12, 8, 12) cornerRadius:18 minHeight:36];
}

+ (instancetype)compactChipWithTitle:(NSString *)title symbol:(NSString *)sfSymbol {
    return [self chipWithTitle:title symbol:sfSymbol fontSize:12.0 padding:UIEdgeInsetsMake(5, 9, 5, 9) cornerRadius:14 minHeight:28];
}

+ (instancetype)chipWithTitle:(NSString *)title
                        symbol:(NSString *)sfSymbol
                      fontSize:(CGFloat)fontSize
                       padding:(UIEdgeInsets)padding
                  cornerRadius:(CGFloat)cornerRadius
                     minHeight:(CGFloat)minHeight {
    SCIGalleryChip *chip = [SCIGalleryChip buttonWithType:UIButtonTypeSystem];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    chip.layer.cornerRadius = cornerRadius;
    chip.layer.cornerCurve = kCACornerCurveContinuous;
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.title = title ?: @"";
        if (sfSymbol.length) cfg.image = SCIGalleryChipGlyph(sfSymbol, ceil(fontSize * 1.7));
        cfg.imagePadding = MAX(4.0, fontSize * 0.4);
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(padding.top, padding.left, padding.bottom, padding.right);
        cfg.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
        cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
            NSMutableDictionary *m = [attrs mutableCopy];
            m[NSFontAttributeName] = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
            return m;
        };
        chip.configuration = cfg;
        chip.titleLabel.adjustsFontSizeToFitWidth = YES;
        chip.titleLabel.minimumScaleFactor = 0.85;
        chip.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    } else {
        [chip setTitle:title forState:UIControlStateNormal];
        if (sfSymbol.length) [chip setImage:SCIGalleryChipGlyph(sfSymbol, ceil(fontSize * 1.7)) forState:UIControlStateNormal];
        chip.contentEdgeInsets = padding;
        chip.imageEdgeInsets = UIEdgeInsetsMake(0, -3, 0, 3);
        chip.titleLabel.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
        chip.titleLabel.adjustsFontSizeToFitWidth = YES;
        chip.titleLabel.minimumScaleFactor = 0.85;
    }
    [chip applyAppearance];
    [chip.heightAnchor constraintGreaterThanOrEqualToConstant:minHeight].active = YES;
    return chip;
}

- (void)setOnState:(BOOL)on { [self setOnState:on animated:NO]; }

- (void)setOnState:(BOOL)on animated:(BOOL)animated {
    _onState = on;
    if (animated) {
        [UIView animateWithDuration:0.15 animations:^{ [self applyAppearance]; }];
    } else {
        [self applyAppearance];
    }
}

- (void)applyAppearance {
    if (self.isOnState) {
        UIColor *primary = [SCIUtils SCIColor_Primary];
        self.backgroundColor = [primary colorWithAlphaComponent:0.20];
        self.tintColor = primary;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [primary colorWithAlphaComponent:0.55].CGColor;
    } else {
        self.backgroundColor = [UIColor tertiarySystemFillColor];
        self.tintColor = [UIColor secondaryLabelColor];
        self.layer.borderWidth = 0.0;
        self.layer.borderColor = [UIColor clearColor].CGColor;
    }
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = self.configuration;
        if (cfg) {
            UIColor *titleColor = self.isOnState ? [UIColor labelColor] : [UIColor labelColor];
            cfg.baseForegroundColor = self.tintColor;
            cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attrs) {
                NSMutableDictionary *m = [attrs mutableCopy];
                m[NSFontAttributeName] = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
                m[NSForegroundColorAttributeName] = titleColor;
                return m;
            };
            self.configuration = cfg;
        }
    } else {
        [self setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    }
}

@end
