// Floating round button that appears once a scroll view is past one viewport
// down; tapping snaps it back to the top inset.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIScrollToTopButton : UIButton

- (void)attachToScrollView:(UIScrollView *)scrollView
                    inView:(UIView *)host
               bottomInset:(CGFloat)bottomInset;

// Updates the offset above the host's safe-area bottom — bump when chrome appears.
- (void)setBottomInset:(CGFloat)bottomInset;

@end

NS_ASSUME_NONNULL_END
