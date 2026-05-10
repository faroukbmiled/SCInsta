#import "SCIProfileAnalyzerViewController.h"
#import "../../UI/SCIPopupChrome.h"
#import "SCIProfileAnalyzerModels.h"
#import "SCIProfileAnalyzerStorage.h"
#import "SCIProfileAnalyzerService.h"
#import "SCIProfileAnalyzerListViewController.h"
#import "../../Utils.h"
#import "../../SCIImageCache.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Localization/SCILocalization.h"
#import <objc/runtime.h>

extern NSNotificationName const SCIProfileAnalyzerDataDidChangeNotification;

#pragma mark - Category descriptor

typedef NS_ENUM(NSInteger, SCIPACategory) {
    SCIPACategoryMutual,
    SCIPACategoryNotFollowingBack,
    SCIPACategoryDontFollowBack,
    SCIPACategoryNewFollowers,
    SCIPACategoryLostFollowers,
    SCIPACategoryYouStartedFollowing,
    SCIPACategoryYouUnfollowed,
    SCIPACategoryProfileUpdates,
    SCIPACategoryVisitedProfiles,
};

@interface SCIPACategoryDescriptor : NSObject
@property (nonatomic, assign) SCIPACategory category;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) BOOL requiresPrevious;
@property (nonatomic, assign) BOOL standalone;
@end
@implementation SCIPACategoryDescriptor @end

#pragma mark - Avatar with progress ring

@interface SCIPAAvatarRingView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) CAShapeLayer *trackLayer;
@property (nonatomic, strong) CAShapeLayer *progressLayer;
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) BOOL showProgress;
@end

@implementation SCIPAAvatarRingView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;

    _trackLayer = [CAShapeLayer layer];
    _trackLayer.fillColor = UIColor.clearColor.CGColor;
    _trackLayer.strokeColor = [UIColor systemGray5Color].CGColor;
    _trackLayer.lineWidth = 3.5;
    _trackLayer.hidden = YES;
    [self.layer addSublayer:_trackLayer];

    _progressLayer = [CAShapeLayer layer];
    _progressLayer.fillColor = UIColor.clearColor.CGColor;
    _progressLayer.strokeColor = ([SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor]).CGColor;
    _progressLayer.lineWidth = 3.5;
    _progressLayer.lineCap = kCALineCapRound;
    _progressLayer.strokeEnd = 0;
    _progressLayer.hidden = YES;
    [self.layer addSublayer:_progressLayer];

    _imageView = [UIImageView new];
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    _imageView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _imageView.layer.masksToBounds = YES;
    _imageView.image = [UIImage systemImageNamed:@"person.circle.fill"];
    _imageView.tintColor = [UIColor systemGrayColor];
    [self addSubview:_imageView];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat size = MIN(self.bounds.size.width, self.bounds.size.height);
    if (size < 16) return;
    CGFloat inset = 7;
    CGRect imgFrame = CGRectInset(CGRectMake(0, 0, size, size), inset, inset);
    self.imageView.frame = imgFrame;
    self.imageView.layer.cornerRadius = imgFrame.size.width / 2.0;

    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(size / 2.0, size / 2.0)
                                                         radius:size / 2.0 - 2
                                                     startAngle:-M_PI_2
                                                       endAngle:-M_PI_2 + 2 * M_PI
                                                      clockwise:YES];
    self.trackLayer.frame = self.bounds;
    self.progressLayer.frame = self.bounds;
    self.trackLayer.path = path.CGPath;
    self.progressLayer.path = path.CGPath;
}

- (void)setProgress:(double)progress {
    _progress = MAX(0, MIN(1, progress));
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.25];
    self.progressLayer.strokeEnd = _progress;
    [CATransaction commit];
}

- (void)setShowProgress:(BOOL)show {
    _showProgress = show;
    self.trackLayer.hidden = !show;
    self.progressLayer.hidden = !show;
    if (show) self.progressLayer.strokeEnd = _progress;
}
@end

#pragma mark - Header

@interface SCIPAHeaderView : UIView
@property (nonatomic, strong) SCIPAAvatarRingView *avatar;
@property (nonatomic, strong) UILabel *fullNameLabel;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIStackView *statsRow;
@property (nonatomic, strong) UILabel *scanDateLabel;
@property (nonatomic, strong) UILabel *warningLabel;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UILabel *progressLabel;
@end

@implementation SCIPAHeaderView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    self.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.layer.cornerRadius = 18;

    _avatar = [[SCIPAAvatarRingView alloc] init];
    _avatar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_avatar];

    _fullNameLabel = [UILabel new];
    _fullNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _fullNameLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    _fullNameLabel.textColor = [UIColor labelColor];
    _fullNameLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_fullNameLabel];

    _usernameLabel = [UILabel new];
    _usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _usernameLabel.font = [UIFont systemFontOfSize:14];
    _usernameLabel.textColor = [UIColor secondaryLabelColor];
    _usernameLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_usernameLabel];

    _statsRow = [[UIStackView alloc] init];
    _statsRow.translatesAutoresizingMaskIntoConstraints = NO;
    _statsRow.axis = UILayoutConstraintAxisHorizontal;
    _statsRow.distribution = UIStackViewDistributionFillEqually;
    _statsRow.spacing = 0;
    [self addSubview:_statsRow];

    _scanDateLabel = [UILabel new];
    _scanDateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _scanDateLabel.font = [UIFont systemFontOfSize:12];
    _scanDateLabel.textColor = [UIColor tertiaryLabelColor];
    _scanDateLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_scanDateLabel];

    _warningLabel = [UILabel new];
    _warningLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _warningLabel.font = [UIFont systemFontOfSize:12];
    _warningLabel.textColor = [UIColor systemOrangeColor];
    _warningLabel.numberOfLines = 0;
    _warningLabel.textAlignment = NSTextAlignmentCenter;
    _warningLabel.hidden = YES;
    [self addSubview:_warningLabel];

    _scanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _scanButton.translatesAutoresizingMaskIntoConstraints = NO;
    _scanButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _scanButton.backgroundColor = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];
    [_scanButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _scanButton.layer.cornerRadius = 18;
    _scanButton.contentEdgeInsets = UIEdgeInsetsMake(0, 22, 0, 22);
    [_scanButton setTitle:SCILocalized(@"Run analysis") forState:UIControlStateNormal];
    [self addSubview:_scanButton];

    _progressLabel = [UILabel new];
    _progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _progressLabel.font = [UIFont systemFontOfSize:12];
    _progressLabel.textColor = [UIColor secondaryLabelColor];
    _progressLabel.textAlignment = NSTextAlignmentCenter;
    _progressLabel.hidden = YES;
    [self addSubview:_progressLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_avatar.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_avatar.topAnchor constraintEqualToAnchor:self.topAnchor constant:18],
        [_avatar.widthAnchor constraintEqualToConstant:96],
        [_avatar.heightAnchor constraintEqualToConstant:96],

        [_fullNameLabel.topAnchor constraintEqualToAnchor:_avatar.bottomAnchor constant:10],
        [_fullNameLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_fullNameLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],

        [_usernameLabel.topAnchor constraintEqualToAnchor:_fullNameLabel.bottomAnchor constant:2],
        [_usernameLabel.leadingAnchor constraintEqualToAnchor:_fullNameLabel.leadingAnchor],
        [_usernameLabel.trailingAnchor constraintEqualToAnchor:_fullNameLabel.trailingAnchor],

        [_statsRow.topAnchor constraintEqualToAnchor:_usernameLabel.bottomAnchor constant:14],
        [_statsRow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_statsRow.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_statsRow.heightAnchor constraintEqualToConstant:44],

        [_scanDateLabel.topAnchor constraintEqualToAnchor:_statsRow.bottomAnchor constant:10],
        [_scanDateLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_scanDateLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],

        [_warningLabel.topAnchor constraintEqualToAnchor:_scanDateLabel.bottomAnchor constant:6],
        [_warningLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_warningLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],

        [_scanButton.topAnchor constraintEqualToAnchor:_warningLabel.bottomAnchor constant:12],
        [_scanButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_scanButton.heightAnchor constraintEqualToConstant:36],
        [_scanButton.widthAnchor constraintGreaterThanOrEqualToConstant:160],

        [_progressLabel.topAnchor constraintEqualToAnchor:_scanButton.bottomAnchor constant:6],
        [_progressLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_progressLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_progressLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
    ]];
    return self;
}

- (void)setStatsLabelsPosts:(NSString *)posts followers:(NSString *)followers following:(NSString *)following {
    for (UIView *v in self.statsRow.arrangedSubviews) [self.statsRow removeArrangedSubview:v], [v removeFromSuperview];
    [self.statsRow addArrangedSubview:[self statColumn:posts caption:SCILocalized(@"Posts")]];
    [self.statsRow addArrangedSubview:[self statColumn:followers caption:SCILocalized(@"Followers")]];
    [self.statsRow addArrangedSubview:[self statColumn:following caption:SCILocalized(@"Following")]];
}

- (UIView *)statColumn:(NSString *)value caption:(NSString *)caption {
    UIView *w = [UIView new];
    UILabel *v = [UILabel new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    v.textColor = [UIColor labelColor];
    v.textAlignment = NSTextAlignmentCenter;
    v.text = value;
    [w addSubview:v];

    UILabel *c = [UILabel new];
    c.translatesAutoresizingMaskIntoConstraints = NO;
    c.font = [UIFont systemFontOfSize:12];
    c.textColor = [UIColor secondaryLabelColor];
    c.textAlignment = NSTextAlignmentCenter;
    c.text = caption;
    [w addSubview:c];

    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:w.topAnchor],
        [v.leadingAnchor constraintEqualToAnchor:w.leadingAnchor],
        [v.trailingAnchor constraintEqualToAnchor:w.trailingAnchor],
        [c.topAnchor constraintEqualToAnchor:v.bottomAnchor constant:1],
        [c.leadingAnchor constraintEqualToAnchor:w.leadingAnchor],
        [c.trailingAnchor constraintEqualToAnchor:w.trailingAnchor],
        [c.bottomAnchor constraintEqualToAnchor:w.bottomAnchor],
    ]];
    return w;
}
@end

#pragma mark - Category cell

@interface SCIPACategoryCell : UITableViewCell
@property (nonatomic, strong) UIView *iconBadge;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@end

@implementation SCIPACategoryCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    self = [super initWithStyle:style reuseIdentifier:rid];
    if (!self) return self;
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    _iconBadge = [UIView new];
    _iconBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _iconBadge.layer.cornerRadius = 8;
    [self.contentView addSubview:_iconBadge];

    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = [UIColor whiteColor];
    [_iconBadge addSubview:_iconView];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:16];
    [self.contentView addSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont systemFontOfSize:12];
    _subtitleLabel.textColor = [UIColor tertiaryLabelColor];
    [self.contentView addSubview:_subtitleLabel];

    _countLabel = [UILabel new];
    _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _countLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _countLabel.textColor = [UIColor secondaryLabelColor];
    _countLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_countLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_iconBadge.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_iconBadge.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_iconBadge.widthAnchor constraintEqualToConstant:32],
        [_iconBadge.heightAnchor constraintEqualToConstant:32],

        [_iconView.centerXAnchor constraintEqualToAnchor:_iconBadge.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconBadge.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:18],
        [_iconView.heightAnchor constraintEqualToConstant:18],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconBadge.trailingAnchor constant:12],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_countLabel.leadingAnchor constant:-8],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10],

        [_countLabel.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [_countLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_countLabel.widthAnchor constraintGreaterThanOrEqualToConstant:40],
    ]];
    return self;
}
@end

#pragma mark - Main VC

@interface SCIProfileAnalyzerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) SCIPAHeaderView *headerView;

@property (nonatomic, strong) SCIProfileAnalyzerReport *report;
@property (nonatomic, strong) NSArray<SCIProfileAnalyzerVisit *> *visits;
@property (nonatomic, strong) NSArray<SCIPACategoryDescriptor *> *categories;
@property (nonatomic, strong) NSArray<SCIPACategoryDescriptor *> *trackingCategories;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, copy) NSString *lastHeaderPK;
@property (nonatomic, assign) BOOL pendingHeaderFetch;
@end

@implementation SCIProfileAnalyzerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SCIPopupChrome backgroundColor];
    self.title = SCILocalized(@"Profile Analyzer");
    self.navigationItem.titleView = [self buildTitleViewWithBeta];

    [self setupTable];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(analyzerDataChanged:)
                                                 name:SCIProfileAnalyzerDataDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // Service is a singleton — drop in-flight scan when the VC pops.
    if (self.running) [[SCIProfileAnalyzerService sharedService] cancel];
}

- (void)analyzerDataChanged:(NSNotification *)note {
    if (!self.isViewLoaded || !self.view.window) return;
    NSString *pk = note.userInfo[@"user_pk"];
    NSString *current = [SCIUtils currentUserPK];
    if (pk.length && current.length && ![pk isEqualToString:current]) return;
    @try {
        [self loadCachedReport];
        SCIProfileAnalyzerSnapshot *cur = self.report.current;
        if (cur) {
            [self.headerView setStatsLabelsPosts:[self compactNumber:cur.mediaCount]
                                      followers:[self compactNumber:cur.followerCount]
                                      following:[self compactNumber:cur.followingCount]];
        }
    } @catch (__unused NSException *e) {}
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    @try { [self loadCachedReport]; } @catch (__unused NSException *e) {}
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Header merge + network fetch wait for the transition to settle.
    @try { [self loadHeaderLayered]; } @catch (__unused NSException *e) {}
    if (self.pendingHeaderFetch) {
        self.pendingHeaderFetch = NO;
        @try { [self fetchAndCacheHeader]; } @catch (__unused NSException *e) {}
    }
}

- (UIView *)buildTitleViewWithBeta {
    UILabel *title = [UILabel new];
    title.text = SCILocalized(@"Profile Analyzer");
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textColor = [UIColor labelColor];

    UILabel *beta = [UILabel new];
    beta.text = @" BETA ";
    beta.font = [UIFont systemFontOfSize:10 weight:UIFontWeightHeavy];
    beta.textColor = [UIColor whiteColor];
    beta.backgroundColor = [UIColor systemOrangeColor];
    beta.layer.cornerRadius = 5;
    beta.layer.masksToBounds = YES;
    beta.textAlignment = NSTextAlignmentCenter;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, beta]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 6;
    return row;
}

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.sectionHeaderTopPadding = 0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    [self.tableView registerClass:[SCIPACategoryCell class] forCellReuseIdentifier:@"cat"];

    UIRefreshControl *rc = [UIRefreshControl new];
    [rc addTarget:self action:@selector(pullToRefreshProfile:) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = rc;

    [self.view addSubview:self.tableView];
    [self buildTableHeader];
}

// Re-fetch just the self-profile so the header reflects live IG data. No rescan.
- (void)pullToRefreshProfile:(UIRefreshControl *)sender {
    NSString *pk = [SCIUtils currentUserPK];
    if (!pk.length) { [sender endRefreshing]; return; }
    __weak typeof(self) weakSelf = self;
    [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"users/%@/info/", pk]
                                      body:nil
                                completion:^(NSDictionary *resp, NSError *error) {
        NSDictionary *user = [resp[@"user"] isKindOfClass:[NSDictionary class]] ? resp[@"user"] : nil;
        if (user.count) {
            [SCIProfileAnalyzerStorage saveHeaderInfo:user forUserPK:pk];
            typeof(self) strongSelf = weakSelf;
            if (strongSelf.isViewLoaded && strongSelf.view.window) {
                [strongSelf paintHeaderFromUserInfo:user];
                [strongSelf applyFollowerLimitGateFor:sciHeaderInteger(user, @"follower_count")];
            }
        }
        [sender endRefreshing];
    }];
}

- (void)buildTableHeader {
    self.headerContainer = [UIView new];
    self.headerContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.headerView = [[SCIPAHeaderView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerContainer addSubview:self.headerView];

    [self.headerView.scanButton addTarget:self action:@selector(analyzeTapped) forControlEvents:UIControlEventTouchUpInside];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor constant:12],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor constant:16],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor constant:-16],
        [self.headerView.bottomAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor constant:-4],
    ]];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (!self.headerContainer) return;
    CGFloat w = self.tableView.bounds.size.width;
    if (w < 1) return;

    self.headerContainer.frame = CGRectMake(0, 0, w, 1);
    [self.headerContainer setNeedsLayout];
    [self.headerContainer layoutIfNeeded];
    CGFloat h = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height)
                                    withHorizontalFittingPriority:UILayoutPriorityRequired
                                          verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGRect target = CGRectMake(0, 0, w, h);
    if (!CGRectEqualToRect(self.headerContainer.frame, target)) {
        self.headerContainer.frame = target;
        self.tableView.tableHeaderView = self.headerContainer;
    } else if (self.tableView.tableHeaderView != self.headerContainer) {
        self.tableView.tableHeaderView = self.headerContainer;
    }
}

#pragma mark - Header resolution

// Layered: IG fieldCache → on-disk cache → snapshot identity → network.
- (void)loadHeaderLayered {
    NSString *pk = [SCIUtils currentUserPK];
    self.lastHeaderPK = pk;

    NSDictionary *live = [self liveSelfInfoFromSession];
    NSMutableDictionary *cached = [[SCIProfileAnalyzerStorage headerInfoForUserPK:pk] mutableCopy]
                                ?: [NSMutableDictionary dictionary];
    SCIProfileAnalyzerSnapshot *snap = self.report.current;

    // following_count reconciliation: fieldCache only updates when the user
    // visits their own profile, so we align snapshot ↔ fieldCache when it moves
    // and otherwise let snapshot win (it tracks in-app mutations live).
    NSNumber *liveFollowing = live[@"following_count"];
    NSNumber *lastSeenFollowing = cached[@"last_synced_following_count"];
    BOOL fieldCacheRefreshed = liveFollowing && (!lastSeenFollowing || ![liveFollowing isEqual:lastSeenFollowing]);
    if (fieldCacheRefreshed) {
        cached[@"following_count"] = liveFollowing;
        cached[@"last_synced_following_count"] = liveFollowing;
        if (snap && snap.followingCount != liveFollowing.integerValue) {
            snap.followingCount = liveFollowing.integerValue;
            [SCIProfileAnalyzerStorage updateCurrentSnapshot:snap forUserPK:pk];
        }
    } else if (snap && snap.followingCount > 0) {
        cached[@"following_count"] = @(snap.followingCount);
    } else if (liveFollowing) {
        cached[@"following_count"] = liveFollowing;
    }

    // fieldCache wins, but skip empty strings (half-loaded fieldCache).
    for (NSString *k in @[@"username", @"full_name", @"profile_pic_url",
                          @"profile_pic_id", @"follower_count", @"media_count"]) {
        id v = live[k];
        if (!v) continue;
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] == 0) continue;
        cached[k] = v;
    }
    // Snapshot fallback — successful scans persist identity, use as last resort.
    if (snap) {
        if (![cached[@"username"]  isKindOfClass:[NSString class]] || ![cached[@"username"]  length])
            if (snap.selfUsername.length) cached[@"username"] = snap.selfUsername;
        if (![cached[@"full_name"] isKindOfClass:[NSString class]] || ![cached[@"full_name"] length])
            if (snap.selfFullName.length) cached[@"full_name"] = snap.selfFullName;
        if (![cached[@"profile_pic_url"] isKindOfClass:[NSString class]] || ![cached[@"profile_pic_url"] length])
            if (snap.selfProfilePicURL.length) cached[@"profile_pic_url"] = snap.selfProfilePicURL;
        if (![cached[@"follower_count"] integerValue] && snap.followerCount > 0) cached[@"follower_count"] = @(snap.followerCount);
        if (![cached[@"media_count"]    integerValue] && snap.mediaCount    > 0) cached[@"media_count"]    = @(snap.mediaCount);
    }

    BOOL haveUsername = [cached[@"username"] isKindOfClass:[NSString class]] && [cached[@"username"] length];
    BOOL haveCounts = [cached[@"follower_count"] integerValue] > 0
                   || [cached[@"following_count"] integerValue] > 0
                   || [cached[@"media_count"] integerValue] > 0;

    if (haveUsername || haveCounts) {
        [self paintHeaderFromUserInfo:cached];
        [self applyFollowerLimitGateFor:[cached[@"follower_count"] integerValue]];
    } else if (!snap) {
        self.headerView.fullNameLabel.text = SCILocalized(@"No scan yet");
        self.headerView.usernameLabel.text = @"";
        [self.headerView setStatsLabelsPosts:@"—" followers:@"—" following:@"—"];
    }

    if (haveCounts && haveUsername) {
        [SCIProfileAnalyzerStorage saveHeaderInfo:cached forUserPK:pk];
    }

    // Network fallback whenever local sources didn't yield both username + counts.
    if (!haveUsername || !haveCounts) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.isViewLoaded && weakSelf.view.window) {
                [weakSelf fetchAndCacheHeader];
            } else {
                weakSelf.pendingHeaderFetch = YES;
            }
        });
    }
}

- (NSDictionary *)liveSelfInfoFromSession {
    id session = [SCIUtils activeUserSession];
    id igUser = nil;
    @try { if ([session respondsToSelector:@selector(user)]) igUser = [session valueForKey:@"user"]; } @catch (__unused id e) {}
    NSDictionary *fc = [self fieldCacheForUser:igUser];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    // Skip NSNull — fieldCache stores it for keys IG hasn't filled.
    for (NSString *k in @[@"username", @"full_name", @"profile_pic_url",
                          @"follower_count", @"following_count", @"media_count"]) {
        id v = fc[k];
        if (v && ![v isKindOfClass:[NSNull class]]) out[k] = v;
    }
    return out;
}

- (void)fetchAndCacheHeader {
    NSString *pk = self.lastHeaderPK ?: [SCIUtils currentUserPK];
    if (!pk.length) {
        // Session not ready (cold launch race) — retry after a beat.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!weakSelf.isViewLoaded || !weakSelf.view.window) return;
            if ([SCIUtils currentUserPK].length) [weakSelf fetchAndCacheHeader];
        });
        return;
    }
    self.lastHeaderPK = pk;
    __weak typeof(self) weakSelf = self;
    [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"users/%@/info/", pk]
                                      body:nil
                                completion:^(NSDictionary *resp, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary *user = [resp[@"user"] isKindOfClass:[NSDictionary class]] ? resp[@"user"] : nil;
        // One retry on rate-limit / blip; otherwise the header stays blank.
        if (!user.count) {
            static const char kSCIPARetryKey;
            NSNumber *attempt = objc_getAssociatedObject(strongSelf, &kSCIPARetryKey);
            if (attempt.intValue < 1) {
                objc_setAssociatedObject(strongSelf, &kSCIPARetryKey, @(attempt.intValue + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (weakSelf.isViewLoaded && weakSelf.view.window) [weakSelf fetchAndCacheHeader];
                });
            }
            return;
        }
        [SCIProfileAnalyzerStorage saveHeaderInfo:user forUserPK:pk];
        if (!strongSelf.isViewLoaded || !strongSelf.view.window) return;
        [strongSelf paintHeaderFromUserInfo:user];
        [strongSelf applyFollowerLimitGateFor:sciHeaderInteger(user, @"follower_count")];
    }];
}

- (void)applyFollowerLimitGateFor:(NSInteger)followers {
    if (followers > SCIProfileAnalyzerMaxFollowerCount) {
        self.headerView.warningLabel.hidden = NO;
        self.headerView.warningLabel.text = [NSString stringWithFormat:
            SCILocalized(@"Follower count exceeds %ld — analysis disabled to avoid rate limits."),
            (long)SCIProfileAnalyzerMaxFollowerCount];
        self.headerView.scanButton.enabled = NO;
        self.headerView.scanButton.alpha = 0.5;
    }
}

- (NSDictionary *)fieldCacheForUser:(id)user {
    if (!user) return @{};
    Ivar iv = NULL;
    for (Class c = [user class]; c && !iv; c = class_getSuperclass(c))
        iv = class_getInstanceVariable(c, "_fieldCache");
    if (!iv) return @{};
    id d = object_getIvar(user, iv);
    return [d isKindOfClass:[NSDictionary class]] ? d : @{};
}

- (NSString *)compactNumber:(NSInteger)n {
    if (n < 1000) return [NSString stringWithFormat:@"%ld", (long)n];
    if (n < 10000) return [NSString stringWithFormat:@"%.1fK", n / 1000.0];
    if (n < 1000000) return [NSString stringWithFormat:@"%ldK", (long)(n / 1000)];
    return [NSString stringWithFormat:@"%.1fM", n / 1000000.0];
}

#pragma mark - Data

- (void)loadCachedReport {
    NSString *pk = [SCIUtils currentUserPK];
    SCIProfileAnalyzerSnapshot *cur = [SCIProfileAnalyzerStorage currentSnapshotForUserPK:pk];
    SCIProfileAnalyzerSnapshot *prev = [SCIProfileAnalyzerStorage previousSnapshotForUserPK:pk];
    SCIProfileAnalyzerSnapshot *base = [SCIProfileAnalyzerStorage baselineSnapshotForUserPK:pk];
    // Baseline wins when present (toggled via Keep scan history).
    SCIProfileAnalyzerSnapshot *diffAgainst = base ?: prev;
    self.report = [SCIProfileAnalyzerReport reportFromCurrent:cur previous:diffAgainst];
    self.visits = [SCIProfileAnalyzerStorage visitedProfilesForUserPK:pk];
    [self rebuildCategories];
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)rebuildCategories {
    SCIProfileAnalyzerReport *r = self.report;
    NSArray<SCIPACategoryDescriptor *> *(^build)(void) = ^NSArray *{
        SCIPACategoryDescriptor *(^make)(SCIPACategory, NSString *, NSString *, NSString *, UIColor *, NSInteger, BOOL) =
        ^SCIPACategoryDescriptor *(SCIPACategory c, NSString *t, NSString *s, NSString *sym, UIColor *col, NSInteger count, BOOL needsPrev) {
            SCIPACategoryDescriptor *d = [SCIPACategoryDescriptor new];
            d.category = c; d.title = t; d.subtitle = s; d.symbol = sym; d.color = col;
            d.count = count; d.requiresPrevious = needsPrev;
            return d;
        };
        return @[
            make(SCIPACategoryMutual, SCILocalized(@"Mutual followers"),
                 SCILocalized(@"You both follow each other"),
                 @"person.2.fill", [UIColor systemBlueColor], r.mutualFollowers.count, NO),
            make(SCIPACategoryNotFollowingBack, SCILocalized(@"Not following you back"),
                 SCILocalized(@"You follow them, they don't follow back"),
                 @"person.fill.xmark", [UIColor systemOrangeColor], r.notFollowingYouBack.count, NO),
            make(SCIPACategoryDontFollowBack, SCILocalized(@"You don't follow back"),
                 SCILocalized(@"They follow you, you don't follow back"),
                 @"person.fill.questionmark", [UIColor systemTealColor], r.youDontFollowBack.count, NO),
            make(SCIPACategoryNewFollowers, SCILocalized(@"New followers"),
                 SCILocalized(@"Gained since last scan"),
                 @"person.fill.badge.plus", [UIColor systemGreenColor], r.recentFollowers.count, YES),
            make(SCIPACategoryLostFollowers, SCILocalized(@"Lost followers"),
                 SCILocalized(@"Unfollowed you since last scan"),
                 @"person.fill.badge.minus", [UIColor systemRedColor], r.lostFollowers.count, YES),
            make(SCIPACategoryYouStartedFollowing, SCILocalized(@"You started following"),
                 SCILocalized(@"Since last scan"),
                 @"arrow.up.forward.circle.fill", [UIColor systemIndigoColor], r.youStartedFollowing.count, YES),
            make(SCIPACategoryYouUnfollowed, SCILocalized(@"You unfollowed"),
                 SCILocalized(@"Since last scan"),
                 @"arrow.down.backward.circle.fill", [UIColor systemPurpleColor], r.youUnfollowed.count, YES),
            make(SCIPACategoryProfileUpdates, SCILocalized(@"Profile updates"),
                 SCILocalized(@"Username, name or picture changes"),
                 @"person.crop.circle.badge.exclamationmark", [UIColor systemPinkColor], r.profileUpdates.count, YES),
        ];
    };
    self.categories = build();

    SCIPACategoryDescriptor *visited = [SCIPACategoryDescriptor new];
    visited.category = SCIPACategoryVisitedProfiles;
    visited.title = SCILocalized(@"Visited profiles");
    visited.subtitle = [SCIUtils getBoolPref:@"profile_analyzer_track_visits"]
        ? SCILocalized(@"Profiles you've opened recently")
        : SCILocalized(@"Tracking off — enable below to log visits");
    visited.symbol = @"eye.circle.fill";
    visited.color = [UIColor systemTealColor];
    visited.count = self.visits.count;
    visited.standalone = YES;
    self.trackingCategories = @[visited];
}

// Snapshot-backed paint: scan-date + warning. Identity is owned by loadHeaderLayered.
- (void)refreshHeader {
    self.headerView.scanDateLabel.text = self.report.current
        ? [self scanDateText]
        : SCILocalized(@"Run your first analysis");
    [self refreshWarning];
}

- (NSString *)scanDateText {
    if (!self.report.current.scanDate) return @"";
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = NSDateFormatterShortStyle;
    NSString *when = [f stringFromDate:self.report.current.scanDate];
    if (self.report.previous) return [NSString stringWithFormat:SCILocalized(@"Last scan: %@"), when];
    return [NSString stringWithFormat:SCILocalized(@"First scan: %@"), when];
}

- (void)refreshWarning {
    SCIProfileAnalyzerSnapshot *cur = self.report.current;
    NSInteger followers = cur.followerCount;
    if (!cur) {
        @try {
            id session = [SCIUtils activeUserSession];
            id igUser = session ? [session valueForKey:@"user"] : nil;
            followers = [[self fieldCacheForUser:igUser][@"follower_count"] integerValue];
        } @catch (__unused id e) {}
    }
    if (followers > SCIProfileAnalyzerMaxFollowerCount) {
        self.headerView.warningLabel.hidden = NO;
        self.headerView.warningLabel.text = [NSString stringWithFormat:
            SCILocalized(@"Follower count exceeds %ld — analysis disabled to avoid rate limits."),
            (long)SCIProfileAnalyzerMaxFollowerCount];
        self.headerView.scanButton.enabled = NO;
        self.headerView.scanButton.alpha = 0.5;
    } else {
        self.headerView.warningLabel.hidden = YES;
        self.headerView.scanButton.enabled = !self.running;
        self.headerView.scanButton.alpha = self.running ? 0.5 : 1.0;
    }
    [self.view setNeedsLayout];
}

#pragma mark - Actions

- (void)analyzeTapped {
    if (self.running) { [[SCIProfileAnalyzerService sharedService] cancel]; return; }
    self.running = YES;
    self.headerView.progressLabel.hidden = NO;
    self.headerView.progressLabel.text = SCILocalized(@"Starting…");
    [self.headerView.avatar setShowProgress:YES];
    self.headerView.avatar.progress = 0;
    [self.headerView.scanButton setTitle:SCILocalized(@"Cancel") forState:UIControlStateNormal];
    self.headerView.scanButton.backgroundColor = [UIColor systemRedColor];
    [self.view setNeedsLayout];

    __weak typeof(self) weakSelf = self;
    [[SCIProfileAnalyzerService sharedService] runForSelfWithHeaderInfo:^(NSDictionary *userInfo) {
        [weakSelf paintHeaderFromUserInfo:userInfo];
    } progress:^(NSString *status, double fraction) {
        weakSelf.headerView.progressLabel.text = status;
        weakSelf.headerView.avatar.progress = fraction;
    } completion:^(SCIProfileAnalyzerSnapshot *snapshot, NSError *error) {
        [weakSelf onAnalysisFinished:snapshot error:error];
    }];
}

// IG payloads carry NSNull for absent fields — coerce safely.
static NSString *sciHeaderString(NSDictionary *d, NSString *key) {
    id v = d[key];
    return [v isKindOfClass:[NSString class]] ? (NSString *)v : nil;
}
static NSInteger sciHeaderInteger(NSDictionary *d, NSString *key) {
    id v = d[key];
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v integerValue];
    if ([v isKindOfClass:[NSString class]]) return [(NSString *)v integerValue];
    return 0;
}

- (void)paintHeaderFromUserInfo:(NSDictionary *)user {
    if (![user isKindOfClass:[NSDictionary class]]) return;
    NSString *username = sciHeaderString(user, @"username");
    NSString *fullName = sciHeaderString(user, @"full_name");
    NSString *picURL   = sciHeaderString(user, @"profile_pic_url");
    NSInteger followers = sciHeaderInteger(user, @"follower_count");
    NSInteger following = sciHeaderInteger(user, @"following_count");
    NSInteger posts     = sciHeaderInteger(user, @"media_count");

    self.headerView.fullNameLabel.text = fullName.length ? fullName
                                       : (username.length ? username : SCILocalized(@"No scan yet"));
    self.headerView.usernameLabel.text = username.length ? [NSString stringWithFormat:@"@%@", username] : @"";
    [self.headerView setStatsLabelsPosts:[self compactNumber:posts]
                              followers:[self compactNumber:followers]
                              following:[self compactNumber:following]];
    if (picURL.length) {
        __weak UIImageView *iv = self.headerView.avatar.imageView;
        [SCIImageCache loadImageFromURL:[NSURL URLWithString:picURL] completion:^(UIImage *img) {
            if (img) iv.image = img;
        }];
    }
    // tableHeaderView is sized once when assigned; longer text needs a re-measure.
    [self resizeTableHeader];
}

- (void)resizeTableHeader {
    UIView *header = self.headerContainer;
    if (!header || !self.tableView) return;
    CGFloat w = self.tableView.bounds.size.width;
    if (w < 1) return;
    [header setNeedsLayout];
    [header layoutIfNeeded];
    CGFloat h = [header systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height)
                      withHorizontalFittingPriority:UILayoutPriorityRequired
                            verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if (fabs(h - header.frame.size.height) < 0.5 && self.tableView.tableHeaderView == header) return;
    header.frame = CGRectMake(0, 0, w, h);
    self.tableView.tableHeaderView = header;   // reassignment forces re-measure
}


- (void)onAnalysisFinished:(SCIProfileAnalyzerSnapshot *)snapshot error:(NSError *)error {
    self.running = NO;
    self.headerView.progressLabel.hidden = YES;
    [self.headerView.avatar setShowProgress:NO];
    [self.headerView.scanButton setTitle:SCILocalized(@"Run analysis") forState:UIControlStateNormal];
    self.headerView.scanButton.backgroundColor = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];
    [self.view setNeedsLayout];

    if (error && error.code == SCIProfileAnalyzerErrorTooManyFollowers) {
        [self alertTitle:SCILocalized(@"Too many followers")
                 message:[NSString stringWithFormat:SCILocalized(@"We refuse to run when the follower count exceeds %ld to avoid Instagram rate limits."),
                          (long)SCIProfileAnalyzerMaxFollowerCount]];
        return;
    }
    if (error && error.code != SCIProfileAnalyzerErrorCancelled) {
        [self alertTitle:SCILocalized(@"Analysis failed") message:error.localizedDescription ?: @""];
        return;
    }
    if (!snapshot) { [self loadCachedReport]; return; }

    NSString *pk = [SCIUtils currentUserPK];
    [SCIProfileAnalyzerStorage saveSnapshot:snapshot forUserPK:pk];
    // Baseline lifecycle is bound to scans so toggling mid-session doesn't wipe state.
    BOOL accumulate = [SCIUtils getBoolPref:@"profile_analyzer_accumulate"];
    BOOL baselineExists = [SCIProfileAnalyzerStorage baselineSnapshotForUserPK:pk] != nil;
    if (accumulate && !baselineExists) {
        [SCIProfileAnalyzerStorage saveBaselineSnapshot:snapshot forUserPK:pk];
    } else if (!accumulate && baselineExists) {
        [SCIProfileAnalyzerStorage clearBaselineForUserPK:pk];
    }
    [SCIProfileAnalyzerStorage saveHeaderInfo:@{
        @"username": snapshot.selfUsername ?: @"",
        @"full_name": snapshot.selfFullName ?: @"",
        @"profile_pic_url": snapshot.selfProfilePicURL ?: @"",
        @"follower_count": @(snapshot.followerCount),
        @"following_count": @(snapshot.followingCount),
        @"media_count": @(snapshot.mediaCount),
    } forUserPK:pk];
    [self loadCachedReport];
    SCINotifySuccess(SCI_NOTIF_ANALYZER_DONE,
                     SCILocalized(@"Analysis complete"),
                     [NSString stringWithFormat:SCILocalized(@"%lu followers · %lu following"),
                      (unsigned long)snapshot.followers.count, (unsigned long)snapshot.following.count]);
}

- (void)resetTapped {
    NSString *pk = [SCIUtils currentUserPK];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Reset analyzer data")]
                                                              message:SCILocalized(@"Pick what to remove. Snapshots drop the since-last-scan diffs; visited profiles wipes the visit history.")
                                                       preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset snapshots") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [SCIProfileAnalyzerStorage resetForUserPK:pk];
        [self loadCachedReport];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear visited profiles") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [SCIProfileAnalyzerStorage clearVisitsForUserPK:pk];
        [self loadCachedReport];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset everything") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [SCIProfileAnalyzerStorage resetForUserPK:pk];
        [SCIProfileAnalyzerStorage clearVisitsForUserPK:pk];
        [self loadCachedReport];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    if (a.popoverPresentationController) {
        a.popoverPresentationController.sourceView = self.view;
        a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height - 40, 1, 1);
    }
    [self presentViewController:a animated:YES completion:nil];
}

- (void)infoTapped {
    NSString *body = [@[
        SCILocalized(@"First scan: we collect your followers and following lists and save them locally."),
        SCILocalized(@"Second scan onward: each scan compares against the last, so we can show gained/lost followers, your own follow/unfollow moves, and profile updates."),
        SCILocalized(@"Nothing is uploaded — everything stays on this device and can be wiped from the trash icon."),
        SCILocalized(@"Large accounts are blocked: analysis is disabled above 13,000 followers to avoid Instagram rate-limiting the whole app."),
        SCILocalized(@"Heads up: this feature is in beta and hits Instagram's private API. Running it back-to-back or right after heavy follow/unfollow activity can trigger a short rate-limit. Use it sparingly and at your own risk."),
    ] componentsJoinedByString:@"\n\n"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"About Profile Analyzer") message:body preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)alertTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return (NSInteger)self.categories.count;
    if (section == 1) return (NSInteger)self.trackingCategories.count;
    if (section == 2) return 2;
    return 2;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return SCILocalized(@"Categories");
    if (section == 1) return SCILocalized(@"Tracking");
    if (section == 2) return SCILocalized(@"Preferences");
    return @"";
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (section == 2) return SCILocalized(@"Keep history compares each scan against your first one. Track visits records every profile you open so you can review them here.");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) return [self preferencesCellForRow:indexPath.row tableView:tv];
    if (indexPath.section == 3) return [self actionCellForRow:indexPath.row tableView:tv];
    SCIPACategoryCell *cell = [tv dequeueReusableCellWithIdentifier:@"cat" forIndexPath:indexPath];
    SCIPACategoryDescriptor *d = (indexPath.section == 1)
        ? self.trackingCategories[indexPath.row]
        : self.categories[indexPath.row];
    BOOL waitingForPrev = d.requiresPrevious && !self.report.previous;
    BOOL hasReport = self.report.current != nil;
    BOOL disabled = d.standalone ? (d.count == 0) : (waitingForPrev || !hasReport || d.count == 0);

    cell.titleLabel.text = d.title;
    if (d.standalone) {
        cell.subtitleLabel.text = d.subtitle;
    } else if (waitingForPrev) {
        cell.subtitleLabel.text = SCILocalized(@"Available after your next scan");
    } else {
        cell.subtitleLabel.text = d.subtitle;
    }
    BOOL showDash = !d.standalone && (waitingForPrev || !hasReport);
    cell.countLabel.text = showDash ? @"—" : [NSString stringWithFormat:@"%ld", (long)d.count];
    cell.iconBadge.backgroundColor = disabled ? [UIColor systemGray3Color] : d.color;
    cell.iconView.image = [UIImage systemImageNamed:d.symbol];
    cell.contentView.alpha = disabled ? 0.5 : 1.0;
    cell.selectionStyle = disabled ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) return;
    if (indexPath.section == 3) {
        if (indexPath.row == 0) [self infoTapped];
        else [self resetTapped];
        return;
    }
    SCIPACategoryDescriptor *d = (indexPath.section == 1)
        ? self.trackingCategories[indexPath.row]
        : self.categories[indexPath.row];
    if (!d.standalone) {
        if (d.requiresPrevious && !self.report.previous) return;
        if (!self.report.current) return;
    }
    if (d.count == 0) return;
    [self.navigationController pushViewController:[self listVCForCategory:d] animated:YES];
}

- (UITableViewCell *)preferencesCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    NSString *rid = (row == 0) ? @"pref_acc" : @"pref_visit";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    UISwitch *sw = [UISwitch new];
    sw.onTintColor = [SCIUtils SCIColor_Primary];

    if (row == 0) {
        cell.textLabel.text = SCILocalized(@"Keep scan history");
        cell.detailTextLabel.text = SCILocalized(@"Compare every scan against your first one");
        cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
        cell.imageView.tintColor = [UIColor systemIndigoColor];
        sw.on = [SCIUtils getBoolPref:@"profile_analyzer_accumulate"];
        [sw addTarget:self action:@selector(accumulateToggled:) forControlEvents:UIControlEventValueChanged];
    } else {
        cell.textLabel.text = SCILocalized(@"Track visited profiles");
        cell.detailTextLabel.text = SCILocalized(@"Logs every profile you open. Stays on-device.");
        cell.imageView.image = [UIImage systemImageNamed:@"eye.circle"];
        cell.imageView.tintColor = [UIColor systemTealColor];
        sw.on = [SCIUtils getBoolPref:@"profile_analyzer_track_visits"];
        [sw addTarget:self action:@selector(trackVisitsToggled:) forControlEvents:UIControlEventValueChanged];
    }
    cell.accessoryView = sw;
    return cell;
}

- (void)trackVisitsToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"profile_analyzer_track_visits"];
    [self rebuildCategories];
    [self.tableView reloadData];
}

- (void)accumulateToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"profile_analyzer_accumulate"];
    NSString *pk = [SCIUtils currentUserPK];
    if (sw.isOn) {
        if (![SCIProfileAnalyzerStorage baselineSnapshotForUserPK:pk] && self.report.current) {
            [SCIProfileAnalyzerStorage saveBaselineSnapshot:self.report.current forUserPK:pk];
            [self loadCachedReport];
        }
    }
    // Flipping off defers — baseline drops on next scan.
}

- (UITableViewCell *)actionCellForRow:(NSInteger)row tableView:(UITableView *)tv {
    static NSString *rid = @"action";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.contentMode = UIViewContentModeCenter;
    if (row == 0) {
        cell.textLabel.text = SCILocalized(@"About Profile Analyzer");
        cell.textLabel.textColor = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];
        cell.imageView.image = [UIImage systemImageNamed:@"info.circle"];
        cell.imageView.tintColor = cell.textLabel.textColor;
    } else {
        cell.textLabel.text = SCILocalized(@"Reset analyzer data");
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.imageView.image = [UIImage systemImageNamed:@"trash"];
        cell.imageView.tintColor = [UIColor systemRedColor];
    }
    return cell;
}

- (UIViewController *)listVCForCategory:(SCIPACategoryDescriptor *)d {
    SCIProfileAnalyzerReport *r = self.report;
    switch (d.category) {
        case SCIPACategoryMutual:
            return [[SCIProfileAnalyzerListViewController alloc] initWithTitle:d.title users:r.mutualFollowers kind:SCIPAListKindMutual];
        case SCIPACategoryVisitedProfiles:
            return [[SCIProfileAnalyzerListViewController alloc] initVisitedListWithTitle:d.title visits:self.visits];
        case SCIPACategoryNotFollowingBack:
            return [[SCIProfileAnalyzerListViewController alloc] initWithTitle:d.title users:r.notFollowingYouBack kind:SCIPAListKindUnfollow];
        case SCIPACategoryDontFollowBack:
            return [[SCIProfileAnalyzerListViewController alloc] initWithTitle:d.title users:r.youDontFollowBack kind:SCIPAListKindFollow];
        case SCIPACategoryNewFollowers:
            return [[SCIProfileAnalyzerListViewController alloc] initWithTitle:d.title users:r.recentFollowers kind:SCIPAListKindPlain];
        case SCIPACategoryLostFollowers:
            return [[SCIProfileAnalyzerListViewController alloc] initWithTitle:d.title users:r.lostFollowers kind:SCIPAListKindPlain];
        case SCIPACategoryYouStartedFollowing:
            return [[SCIProfileAnalyzerListViewController alloc] initWithTitle:d.title users:r.youStartedFollowing kind:SCIPAListKindUnfollow];
        case SCIPACategoryYouUnfollowed:
            return [[SCIProfileAnalyzerListViewController alloc] initWithTitle:d.title users:r.youUnfollowed kind:SCIPAListKindFollow];
        case SCIPACategoryProfileUpdates:
            return [[SCIProfileAnalyzerListViewController alloc] initWithTitle:d.title profileUpdates:r.profileUpdates];
    }
}

@end
