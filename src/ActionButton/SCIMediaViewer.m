#import "SCIMediaViewer.h"
#import "../Utils.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

// ═══════════════════════════════════════════════════════════════════════════
#pragma mark - Data model
// ═══════════════════════════════════════════════════════════════════════════

@implementation SCIMediaViewerItem
+ (instancetype)itemWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL caption:(NSString *)caption {
    SCIMediaViewerItem *i = [SCIMediaViewerItem new];
    i.videoURL = videoURL;
    i.photoURL = photoURL;
    i.caption = caption;
    return i;
}
@end


// ═══════════════════════════════════════════════════════════════════════════
#pragma mark - Single photo page
// ═══════════════════════════════════════════════════════════════════════════

@interface _SCIPhotoPageVC : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation _SCIPhotoPageVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.delegate = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 5.0;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];

    self.imageView = [[UIImageView alloc] initWithFrame:self.scrollView.bounds];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.scrollView addSubview:self.imageView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = [UIColor whiteColor];
    self.spinner.center = self.view.center;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin
                                  | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.spinner];
    [self.spinner startAnimating];

    NSURL *url = [self.photoURL copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:url];
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (img) self.imageView.image = img;
        });
    });

    // Double-tap to zoom
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.scrollView addGestureRecognizer:doubleTap];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)sv { return self.imageView; }

- (void)handleDoubleTap:(UITapGestureRecognizer *)gr {
    if (self.scrollView.zoomScale > 1.0) {
        [self.scrollView setZoomScale:1.0 animated:YES];
    } else {
        CGPoint pt = [gr locationInView:self.imageView];
        CGRect rect = CGRectMake(pt.x - 50, pt.y - 50, 100, 100);
        [self.scrollView zoomToRect:rect animated:YES];
    }
}

- (UIImage *)currentImage { return self.imageView.image; }

@end


// ═══════════════════════════════════════════════════════════════════════════
#pragma mark - Single video page
// ═══════════════════════════════════════════════════════════════════════════

@interface _SCIVideoPageVC : UIViewController
@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, strong) AVPlayerViewController *playerVC;
@end

@implementation _SCIVideoPageVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    AVPlayer *player = [AVPlayer playerWithURL:self.videoURL];
    self.playerVC = [[AVPlayerViewController alloc] init];
    self.playerVC.player = player;
    self.playerVC.showsPlaybackControls = YES;

    [self addChildViewController:self.playerVC];
    self.playerVC.view.frame = self.view.bounds;
    self.playerVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.playerVC.view];
    [self.playerVC didMoveToParentViewController:self];

    [player play];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.playerVC.player pause];
}

@end


// ═══════════════════════════════════════════════════════════════════════════
#pragma mark - Container VC (PageViewController-based)
// ═══════════════════════════════════════════════════════════════════════════

@interface _SCIMediaViewerContainerVC : UIViewController <UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSArray<SCIMediaViewerItem *> *items;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) UIPageViewController *pageVC;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UIButton *shareBtn;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, assign) BOOL chromeVisible;
@property (nonatomic, assign) BOOL captionExpanded;
@end

@implementation _SCIMediaViewerContainerVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.chromeVisible = YES;

    // Page view controller
    self.pageVC = [[UIPageViewController alloc]
        initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
        navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
        options:nil];
    self.pageVC.dataSource = self.items.count > 1 ? self : nil;
    self.pageVC.delegate = self;

    UIViewController *firstPage = [self viewControllerForIndex:self.currentIndex];
    if (firstPage) [self.pageVC setViewControllers:@[firstPage] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];

    [self addChildViewController:self.pageVC];
    self.pageVC.view.frame = self.view.bounds;
    self.pageVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.pageVC.view];
    [self.pageVC didMoveToParentViewController:self];

    // Top bar
    self.topBar = [[UIView alloc] init];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topBar];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];

    self.closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeBtn setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:cfg] forState:UIControlStateNormal];
    self.closeBtn.tintColor = [UIColor whiteColor];
    self.closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.closeBtn];

    self.shareBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.shareBtn setImage:[UIImage systemImageNamed:@"square.and.arrow.up" withConfiguration:cfg] forState:UIControlStateNormal];
    self.shareBtn.tintColor = [UIColor whiteColor];
    self.shareBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.shareBtn addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.shareBtn];

    self.counterLabel = [[UILabel alloc] init];
    self.counterLabel.textColor = [UIColor whiteColor];
    self.counterLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.counterLabel.textAlignment = NSTextAlignmentCenter;
    self.counterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topBar addSubview:self.counterLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topBar.heightAnchor constraintEqualToConstant:44],
        [self.closeBtn.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:16],
        [self.closeBtn.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.shareBtn.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-16],
        [self.shareBtn.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.counterLabel.centerXAnchor constraintEqualToAnchor:self.topBar.centerXAnchor],
        [self.counterLabel.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
    ]];

    // Bottom bar (caption — tap to expand/collapse)
    self.bottomBar = [[UIView alloc] init];
    self.bottomBar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.bottomBar];

    self.captionLabel = [[UILabel alloc] init];
    self.captionLabel.textColor = [UIColor whiteColor];
    self.captionLabel.font = [UIFont systemFontOfSize:14];
    self.captionLabel.numberOfLines = 3; // collapsed
    self.captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.captionLabel.userInteractionEnabled = YES;
    [self.bottomBar addSubview:self.captionLabel];

    UITapGestureRecognizer *captionTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(toggleCaption)];
    [self.captionLabel addGestureRecognizer:captionTap];

    [NSLayoutConstraint activateConstraints:@[
        [self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.captionLabel.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:12],
        [self.captionLabel.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:16],
        [self.captionLabel.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-16],
        [self.captionLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
    ]];

    // Swipe down to dismiss
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissPan:)];
    pan.delegate = (id<UIGestureRecognizerDelegate>)self;
    [self.view addGestureRecognizer:pan];

    // Single tap toggles chrome
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleChrome)];
    tap.cancelsTouchesInView = NO;
    [self.pageVC.view addGestureRecognizer:tap];

    [self updateChrome];
}

- (void)updateChrome {
    SCIMediaViewerItem *item = self.items[self.currentIndex];

    // Counter (hide for single items)
    if (self.items.count > 1) {
        self.counterLabel.text = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)(self.currentIndex + 1), (unsigned long)self.items.count];
        self.counterLabel.hidden = NO;
    } else {
        self.counterLabel.hidden = YES;
    }

    // Caption
    if (item.caption.length) {
        self.captionLabel.text = item.caption;
        self.bottomBar.hidden = NO;
    } else {
        self.bottomBar.hidden = YES;
    }
}

- (void)toggleChrome {
    self.chromeVisible = !self.chromeVisible;
    [UIView animateWithDuration:0.25 animations:^{
        CGFloat a = self.chromeVisible ? 1.0 : 0.0;
        self.topBar.alpha = a;
        self.bottomBar.alpha = a;
    }];
}

- (void)toggleCaption {
    self.captionExpanded = !self.captionExpanded;
    [UIView animateWithDuration:0.25 animations:^{
        self.captionLabel.numberOfLines = self.captionExpanded ? 0 : 3;
        [self.view layoutIfNeeded];
    }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gr {
    if (![gr isKindOfClass:[UIPanGestureRecognizer class]]) return YES;
    CGPoint v = [gr velocityInView:self.view];
    return fabs(v.y) > fabs(v.x) && v.y > 0;
}

- (void)handleDismissPan:(UIPanGestureRecognizer *)gr {
    CGFloat ty = [gr translationInView:self.view].y;
    CGFloat h = self.view.bounds.size.height;
    CGFloat progress = fmin(fmax(ty / h, 0), 1);

    switch (gr.state) {
        case UIGestureRecognizerStateChanged: {
            self.view.transform = CGAffineTransformMakeTranslation(0, ty);
            self.view.alpha = 1.0 - progress * 0.5;
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat vy = [gr velocityInView:self.view].y;
            if (progress > 0.25 || vy > 800) {
                [UIView animateWithDuration:0.2 animations:^{
                    self.view.transform = CGAffineTransformMakeTranslation(0, h);
                    self.view.alpha = 0;
                } completion:^(BOOL finished) {
                    [self dismissViewControllerAnimated:NO completion:nil];
                }];
            } else {
                [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
                    self.view.transform = CGAffineTransformIdentity;
                    self.view.alpha = 1;
                } completion:nil];
            }
            break;
        }
        default: break;
    }
}

- (void)closeTapped {
    // Pause any playing video
    UIViewController *current = self.pageVC.viewControllers.firstObject;
    if ([current isKindOfClass:[_SCIVideoPageVC class]]) {
        [(((_SCIVideoPageVC *)current).playerVC.player) pause];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)shareTapped {
    SCIMediaViewerItem *item = self.items[self.currentIndex];
    NSMutableArray *shareItems = [NSMutableArray array];

    UIViewController *current = self.pageVC.viewControllers.firstObject;
    if ([current isKindOfClass:[_SCIPhotoPageVC class]]) {
        UIImage *img = [(_SCIPhotoPageVC *)current currentImage];
        if (img) [shareItems addObject:img];
    }

    // For videos or if no image loaded, share the URL
    if (!shareItems.count) {
        NSURL *url = item.videoURL ?: item.photoURL;
        if (url) [shareItems addObject:url];
    }

    if (!shareItems.count) return;

    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:shareItems applicationActivities:nil];
    vc.popoverPresentationController.sourceView = self.shareBtn;
    [self presentViewController:vc animated:YES completion:nil];
}

// ─── Page data source ───

- (UIViewController *)viewControllerForIndex:(NSUInteger)idx {
    if (idx >= self.items.count) return nil;
    SCIMediaViewerItem *item = self.items[idx];

    if (item.videoURL) {
        _SCIVideoPageVC *vc = [[_SCIVideoPageVC alloc] init];
        vc.videoURL = item.videoURL;
        vc.view.tag = (NSInteger)idx;
        return vc;
    } else if (item.photoURL) {
        _SCIPhotoPageVC *vc = [[_SCIPhotoPageVC alloc] init];
        vc.photoURL = item.photoURL;
        vc.view.tag = (NSInteger)idx;
        return vc;
    }
    return nil;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pvc viewControllerBeforeViewController:(UIViewController *)vc {
    NSInteger idx = vc.view.tag;
    if (idx <= 0) return nil;
    return [self viewControllerForIndex:idx - 1];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pvc viewControllerAfterViewController:(UIViewController *)vc {
    NSInteger idx = vc.view.tag;
    if (idx + 1 >= (NSInteger)self.items.count) return nil;
    return [self viewControllerForIndex:idx + 1];
}

- (void)pageViewController:(UIPageViewController *)pvc didFinishAnimating:(BOOL)finished
   previousViewControllers:(NSArray<UIViewController *> *)prev transitionCompleted:(BOOL)completed {
    if (!completed) return;
    UIViewController *current = pvc.viewControllers.firstObject;
    self.currentIndex = (NSUInteger)current.view.tag;

    // Pause previous video
    for (UIViewController *p in prev) {
        if ([p isKindOfClass:[_SCIVideoPageVC class]]) {
            [((_SCIVideoPageVC *)p).playerVC.player pause];
        }
    }
    // Play new video
    if ([current isKindOfClass:[_SCIVideoPageVC class]]) {
        [((_SCIVideoPageVC *)current).playerVC.player play];
    }

    [self updateChrome];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

@end


// ═══════════════════════════════════════════════════════════════════════════
#pragma mark - Public API
// ═══════════════════════════════════════════════════════════════════════════

@implementation SCIMediaViewer

+ (void)presentNativeVideoPlayer:(NSURL *)url {
    dispatch_async(dispatch_get_main_queue(), ^{
        AVPlayerViewController *playerVC = [[AVPlayerViewController alloc] init];
        playerVC.player = [AVPlayer playerWithURL:url];
        playerVC.modalPresentationStyle = UIModalPresentationFullScreen;
        [topMostController() presentViewController:playerVC animated:YES completion:^{
            [playerVC.player play];
        }];
    });
}

+ (void)showItem:(SCIMediaViewerItem *)item {
    if (!item) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No media to show")]; return; }

    // Single video → native AVPlayerViewController directly (no wrapper)
    if (item.videoURL) {
        [self presentNativeVideoPlayer:item.videoURL];
        return;
    }

    // Single photo → use our photo viewer container
    [self showItems:@[item] startIndex:0];
}

+ (void)showItems:(NSArray<SCIMediaViewerItem *> *)items startIndex:(NSUInteger)index {
    if (!items.count) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No media to show")]; return; }
    if (index >= items.count) index = 0;

    // Single video item → native player
    if (items.count == 1 && items[0].videoURL) {
        [self presentNativeVideoPlayer:items[0].videoURL];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        _SCIMediaViewerContainerVC *vc = [[_SCIMediaViewerContainerVC alloc] init];
        vc.items = items;
        vc.currentIndex = index;
        vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
        vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        [topMostController() presentViewController:vc animated:YES completion:nil];
    });
}

+ (void)showWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL caption:(NSString *)caption {
    [self showItem:[SCIMediaViewerItem itemWithVideoURL:videoURL photoURL:photoURL caption:caption]];
}

@end
