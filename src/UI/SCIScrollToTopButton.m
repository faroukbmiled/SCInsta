#import "SCIScrollToTopButton.h"

@interface SCIScrollToTopButton ()
@property (nonatomic, weak)   UIScrollView *scrollView;
@property (nonatomic, strong) NSLayoutConstraint *bottomConstraint;
@property (nonatomic, assign) BOOL observing;
@property (nonatomic, assign) BOOL visible;
@end

@implementation SCIScrollToTopButton

- (instancetype)init {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22
                                                                                          weight:UIImageSymbolWeightSemibold];
        [self setImage:[UIImage systemImageNamed:@"chevron.up" withConfiguration:cfg] forState:UIControlStateNormal];
        self.tintColor = [UIColor labelColor];
        self.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.layer.cornerRadius = 22;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.18;
        self.layer.shadowRadius = 6;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.alpha = 0;
        self.userInteractionEnabled = NO;
        [self addTarget:self action:@selector(scrollToTop) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)attachToScrollView:(UIScrollView *)scrollView
                    inView:(UIView *)host
               bottomInset:(CGFloat)bottomInset {
    if (!scrollView || !host) return;
    [self detachObserver];
    self.scrollView = scrollView;

    [host addSubview:self];
    self.bottomConstraint = [self.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor
                                                              constant:-bottomInset];
    [NSLayoutConstraint activateConstraints:@[
        [self.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-16],
        self.bottomConstraint,
        [self.widthAnchor  constraintEqualToConstant:44],
        [self.heightAnchor constraintEqualToConstant:44],
    ]];

    [scrollView addObserver:self
                 forKeyPath:@"contentOffset"
                    options:NSKeyValueObservingOptionNew
                    context:(void *)0x5C70];
    self.observing = YES;
    [self refreshVisibility];
}

- (void)setBottomInset:(CGFloat)bottomInset {
    self.bottomConstraint.constant = -bottomInset;
}

- (void)detachObserver {
    if (!self.observing) return;
    @try { [self.scrollView removeObserver:self forKeyPath:@"contentOffset" context:(void *)0x5C70]; } @catch (__unused id e) {}
    self.observing = NO;
}

- (void)dealloc {
    [self detachObserver];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != (void *)0x5C70) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [self refreshVisibility];
}

- (void)refreshVisibility {
    UIScrollView *sv = self.scrollView;
    if (!sv) return;
    // Threshold = one viewport height past the top inset. Below that we hide.
    CGFloat threshold = sv.bounds.size.height;
    BOOL shouldShow = (sv.contentOffset.y + sv.adjustedContentInset.top) > threshold;
    if (shouldShow == self.visible) return;
    self.visible = shouldShow;
    self.userInteractionEnabled = shouldShow;
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.alpha = shouldShow ? 1.0 : 0.0;
        self.transform = shouldShow ? CGAffineTransformIdentity
                                    : CGAffineTransformMakeScale(0.85, 0.85);
    } completion:nil];
}

- (void)scrollToTop {
    UIScrollView *sv = self.scrollView;
    if (!sv) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    CGPoint top = CGPointMake(-sv.adjustedContentInset.left,
                              -sv.adjustedContentInset.top);
    [sv setContentOffset:top animated:YES];
}

@end
