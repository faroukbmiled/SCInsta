#import "SCIProfileAnalyzerListViewController.h"
#import "SCIProfileAnalyzerStorage.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Utils.h"
#import "../../SCIURLOpener.h"
#import "../../SCIImageCache.h"
#import "../../Settings/SCISearchBarStyler.h"
#import "../../Localization/SCILocalization.h"

// IG throttles /friendships/ — 50/session + 1.5s cushion stays inside the limit.
static const NSInteger kSCIPABatchCap = 50;
static const NSTimeInterval kSCIPABatchDelay = 1.5;
static const NSTimeInterval kSCIPAFriendshipTTL = 10 * 60;
static const NSTimeInterval kSCIPAPicRefreshTTL = 5 * 60;

@interface SCIPAFriendshipCache : NSObject
+ (NSNumber *)followingForPK:(NSString *)pk;
+ (void)setFollowing:(BOOL)following forPK:(NSString *)pk;
+ (void)invalidatePK:(NSString *)pk;
@end

static NSMutableDictionary<NSString *, NSDate *> *sciPicRefreshAttempted(void) {
    static NSMutableDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [NSMutableDictionary dictionary]; });
    return m;
}

@implementation SCIPAFriendshipCache
+ (NSMutableDictionary *)store {
    static NSMutableDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [NSMutableDictionary dictionary]; });
    return m;
}
+ (NSNumber *)followingForPK:(NSString *)pk {
    if (!pk.length) return nil;
    NSDictionary *e = [self store][pk];
    if (!e) return nil;
    if (-[e[@"ts"] timeIntervalSinceNow] > kSCIPAFriendshipTTL) {
        [[self store] removeObjectForKey:pk];
        return nil;
    }
    return e[@"following"];
}
+ (void)setFollowing:(BOOL)following forPK:(NSString *)pk {
    if (!pk.length) return;
    [self store][pk] = @{ @"following": @(following), @"ts": [NSDate date] };
}
+ (void)invalidatePK:(NSString *)pk {
    if (!pk.length) return;
    [[self store] removeObjectForKey:pk];
}
@end

typedef NS_ENUM(NSInteger, SCIPASortMode) {
    SCIPASortModeDefault,
    SCIPASortModeAZ,
    SCIPASortModeZA,
    SCIPASortModeRecent,
    SCIPASortModeOldest,
    SCIPASortModeMostVisited,
};

typedef NS_ENUM(NSInteger, SCIPADateFilter) {
    SCIPADateFilterAny,
    SCIPADateFilterToday,
    SCIPADateFilter7d,
    SCIPADateFilter30d,
};

#pragma mark - Cell

@interface SCIPAUserCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIImageView *verifiedBadge;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIActivityIndicatorView *actionSpinner;
@property (nonatomic, strong) NSLayoutConstraint *usernameTrailingToButton;
@property (nonatomic, strong) NSLayoutConstraint *usernameTrailingToEdge;
@property (nonatomic, copy) NSString *boundPK;
@property (nonatomic, copy) void(^onActionTap)(SCIPAUserCell *);
@end

@implementation SCIPAUserCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return self;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    _avatar = [UIImageView new];
    _avatar.translatesAutoresizingMaskIntoConstraints = NO;
    _avatar.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _avatar.layer.cornerRadius = 24;
    _avatar.layer.masksToBounds = YES;
    _avatar.contentMode = UIViewContentModeScaleAspectFill;
    [self.contentView addSubview:_avatar];

    _usernameLabel = [UILabel new];
    _usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _usernameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _usernameLabel.textColor = [UIColor labelColor];
    [_usernameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [_usernameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_usernameLabel];

    _verifiedBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill"]];
    _verifiedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _verifiedBadge.tintColor = [UIColor systemBlueColor];
    _verifiedBadge.contentMode = UIViewContentModeScaleAspectFit;
    _verifiedBadge.hidden = YES;
    [_verifiedBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_verifiedBadge];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont systemFontOfSize:13];
    _subtitleLabel.textColor = [UIColor secondaryLabelColor];
    _subtitleLabel.numberOfLines = 2;
    [self.contentView addSubview:_subtitleLabel];

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _actionButton.layer.cornerRadius = 8;
    _actionButton.contentEdgeInsets = UIEdgeInsetsMake(6, 14, 6, 14);
    _actionButton.hidden = YES;
    [_actionButton addTarget:self action:@selector(onAction) forControlEvents:UIControlEventTouchUpInside];
    [_actionButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.contentView addSubview:_actionButton];

    _actionSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _actionSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _actionSpinner.color = [UIColor secondaryLabelColor];
    _actionSpinner.hidesWhenStopped = YES;
    [self.contentView addSubview:_actionSpinner];

    _usernameTrailingToButton = [_verifiedBadge.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-10];
    _usernameTrailingToEdge = [_verifiedBadge.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_avatar.widthAnchor constraintEqualToConstant:48],
        [_avatar.heightAnchor constraintEqualToConstant:48],

        [_usernameLabel.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
        [_usernameLabel.topAnchor constraintEqualToAnchor:_avatar.topAnchor constant:2],

        [_verifiedBadge.leadingAnchor constraintEqualToAnchor:_usernameLabel.trailingAnchor constant:4],
        [_verifiedBadge.centerYAnchor constraintEqualToAnchor:_usernameLabel.centerYAnchor],
        [_verifiedBadge.widthAnchor constraintEqualToConstant:14],
        [_verifiedBadge.heightAnchor constraintEqualToConstant:14],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_usernameLabel.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_usernameLabel.bottomAnchor constant:2],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-10],
        [_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],

        [_actionButton.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [_actionButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

        [_actionSpinner.centerXAnchor constraintEqualToAnchor:_actionButton.centerXAnchor],
        [_actionSpinner.centerYAnchor constraintEqualToAnchor:_actionButton.centerYAnchor],

        _usernameTrailingToButton,
    ]];
    return self;
}

typedef NS_ENUM(NSInteger, SCIPACellAction) {
    SCIPACellActionLoading,
    SCIPACellActionFollow,
    SCIPACellActionUnfollow,
    SCIPACellActionPending,
};

- (void)applyAction:(SCIPACellAction)state pending:(BOOL)pending tint:(UIColor *)tint {
    self.usernameTrailingToButton.active = YES;
    self.usernameTrailingToEdge.active = NO;
    UIColor *primary = tint ?: [UIColor systemBlueColor];

    switch (state) {
        case SCIPACellActionLoading:
            self.actionButton.hidden = YES;
            [self.actionSpinner startAnimating];
            break;
        case SCIPACellActionFollow:
            self.actionButton.hidden = NO;
            [self.actionSpinner stopAnimating];
            [self.actionButton setTitle:SCILocalized(@"Follow") forState:UIControlStateNormal];
            self.actionButton.backgroundColor = primary;
            [self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.actionButton.enabled = !pending;
            self.actionButton.alpha = pending ? 0.55 : 1.0;
            break;
        case SCIPACellActionUnfollow:
            self.actionButton.hidden = NO;
            [self.actionSpinner stopAnimating];
            [self.actionButton setTitle:SCILocalized(@"Unfollow") forState:UIControlStateNormal];
            self.actionButton.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.12];
            [self.actionButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
            self.actionButton.enabled = !pending;
            self.actionButton.alpha = pending ? 0.55 : 1.0;
            break;
        case SCIPACellActionPending:
            self.actionButton.hidden = NO;
            self.actionButton.enabled = NO;
            self.actionButton.alpha = 0.55;
            [self.actionSpinner startAnimating];
            break;
    }
}

- (void)hideAction {
    self.actionButton.hidden = YES;
    [self.actionSpinner stopAnimating];
    self.usernameTrailingToButton.active = NO;
    self.usernameTrailingToEdge.active = YES;
}

- (void)onAction { if (self.onActionTap) self.onActionTap(self); }
- (void)prepareForReuse {
    [super prepareForReuse];
    self.avatar.image = nil;
    self.onActionTap = nil;
    self.verifiedBadge.hidden = YES;
    self.boundPK = nil;
    [self.actionSpinner stopAnimating];
    self.actionButton.hidden = YES;
}
@end

#pragma mark - VC

@interface SCIProfileAnalyzerListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerUser *> *allUsers;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerUser *> *filteredUsers;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerProfileChange *> *allChanges;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerProfileChange *> *filteredChanges;
@property (nonatomic, assign) SCIPAListKind kind;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingPKs;

@property (nonatomic, assign) BOOL selectionMode;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedPKs;
@property (nonatomic, strong) UIView *batchBar;
@property (nonatomic, strong) UIButton *batchActionButton;

@property (nonatomic, assign) SCIPASortMode sortMode;
@property (nonatomic, assign) BOOL filterVerifiedOnly;
@property (nonatomic, assign) BOOL filterNotVerifiedOnly;
@property (nonatomic, assign) BOOL filterPrivateOnly;
@property (nonatomic, assign) SCIPADateFilter dateFilter;
@property (nonatomic, copy) NSString *currentQuery;

@property (nonatomic, copy) NSArray<SCIProfileAnalyzerVisit *> *allVisits;
@property (nonatomic, copy) NSArray<SCIProfileAnalyzerVisit *> *filteredVisits;

// nil = unknown, @YES = following, @NO = not. Only written on successful
// show_many or confirmed action; errors leave entries nil so cells stay loading.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *friendshipStatus;
@property (nonatomic, strong) NSMutableSet<NSString *> *lookupQueue;
@property (nonatomic, strong) NSMutableSet<NSString *> *lookupInflight;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lookupBackoff;
@property (nonatomic, assign) BOOL lookupFlushScheduled;
@end

@implementation SCIProfileAnalyzerListViewController

- (instancetype)initWithTitle:(NSString *)title
                        users:(NSArray<SCIProfileAnalyzerUser *> *)users
                         kind:(SCIPAListKind)kind {
    self = [super init];
    if (!self) return self;
    self.title = title;
    self.kind = kind;
    self.allUsers = users ?: @[];
    self.filteredUsers = self.allUsers;
    self.pendingPKs = [NSMutableSet set];
    self.selectedPKs = [NSMutableSet set];
    self.friendshipStatus = [NSMutableDictionary dictionary];
    self.lookupQueue = [NSMutableSet set];
    self.lookupInflight = [NSMutableSet set];
    self.lookupBackoff = [NSMutableDictionary dictionary];
    return self;
}

- (instancetype)initVisitedListWithTitle:(NSString *)title
                                   visits:(NSArray<SCIProfileAnalyzerVisit *> *)visits {
    self = [super init];
    if (!self) return self;
    self.title = title;
    self.kind = SCIPAListKindVisited;
    self.allVisits = visits ?: @[];
    self.filteredVisits = self.allVisits;
    self.sortMode = SCIPASortModeRecent;
    self.pendingPKs = [NSMutableSet set];
    self.selectedPKs = [NSMutableSet set];
    self.friendshipStatus = [NSMutableDictionary dictionary];
    self.lookupQueue = [NSMutableSet set];
    self.lookupInflight = [NSMutableSet set];
    self.lookupBackoff = [NSMutableDictionary dictionary];
    return self;
}

- (instancetype)initWithTitle:(NSString *)title
              profileUpdates:(NSArray<SCIProfileAnalyzerProfileChange *> *)updates {
    self = [super init];
    if (!self) return self;
    self.title = title;
    self.kind = SCIPAListKindProfileUpdate;
    self.allChanges = updates ?: @[];
    self.filteredChanges = self.allChanges;
    self.pendingPKs = [NSMutableSet set];
    self.selectedPKs = [NSMutableSet set];
    self.friendshipStatus = [NSMutableDictionary dictionary];
    self.lookupQueue = [NSMutableSet set];
    self.lookupInflight = [NSMutableSet set];
    self.lookupBackoff = [NSMutableDictionary dictionary];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self setupTable];
    [self setupSearch];
    [self setupEmptyState];
    [self setupBatchBar];
    [self seedFriendshipStatusFromKind];
    [self updateNavBar];
    [self refreshCounts];
}

// Snapshot-derived kinds imply a friendship direction; seed them so we skip
// the show_many roundtrip. Other kinds fall back to the cross-VC cache.
- (void)seedFriendshipStatusFromKind {
    NSNumber *seed;
    if (self.kind == SCIPAListKindUnfollow || self.kind == SCIPAListKindMutual) seed = @YES;
    else if (self.kind == SCIPAListKindFollow) seed = @NO;

    NSArray *src;
    if (self.kind == SCIPAListKindVisited) {
        NSMutableArray *us = [NSMutableArray arrayWithCapacity:self.allVisits.count];
        for (SCIProfileAnalyzerVisit *v in self.allVisits) [us addObject:v.user];
        src = us;
    } else if (self.kind == SCIPAListKindProfileUpdate) {
        NSMutableArray *us = [NSMutableArray arrayWithCapacity:self.allChanges.count];
        for (SCIProfileAnalyzerProfileChange *c in self.allChanges) [us addObject:c.current];
        src = us;
    } else {
        src = self.allUsers;
    }
    for (SCIProfileAnalyzerUser *u in src) {
        if (!u.pk.length) continue;
        if (seed) {
            self.friendshipStatus[u.pk] = seed;
            [SCIPAFriendshipCache setFollowing:seed.boolValue forPK:u.pk];
            continue;
        }
        NSNumber *cached = [SCIPAFriendshipCache followingForPK:u.pk];
        if (cached) self.friendshipStatus[u.pk] = cached;
    }
}

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    // Visited rows show two subtitle lines (fullName + timestamp); 72pt clips.
    self.tableView.rowHeight = (self.kind == SCIPAListKindVisited) ? 84 : 72;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 78, 0, 0);
    self.tableView.allowsMultipleSelection = NO;
    [self.tableView registerClass:[SCIPAUserCell class] forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.tableView];

    // Pull-to-refresh: visited list only — others are snapshot-bound.
    if (self.kind == SCIPAListKindVisited) {
        UIRefreshControl *rc = [UIRefreshControl new];
        [rc addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
        self.tableView.refreshControl = rc;
    }
}

- (void)setupSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.delegate = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = SCILocalized(@"Search by username or name");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self sciStyleSearchBar];
}

- (void)sciStyleSearchBar {
    [SCISearchBarStyler styleSearchBar:self.searchController.searchBar];
}

- (void)willPresentSearchController:(UISearchController *)searchController { [self sciStyleSearchBar]; }
- (void)didPresentSearchController:(UISearchController *)searchController {
    [self sciStyleSearchBar];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self sciStyleSearchBar];
    });
}

- (void)setupEmptyState {
    self.emptyLabel = [UILabel new];
    self.emptyLabel.text = SCILocalized(@"No results");
    self.emptyLabel.textColor = [UIColor tertiaryLabelColor];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.hidden = YES;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
    ]];
}

- (void)setupBatchBar {
    self.batchActionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.batchActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.batchActionButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.batchActionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.batchActionButton.backgroundColor = [UIColor systemRedColor];
    self.batchActionButton.layer.cornerRadius = 26;
    self.batchActionButton.contentEdgeInsets = UIEdgeInsetsMake(0, 28, 0, 28);
    self.batchActionButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.batchActionButton.layer.shadowOffset = CGSizeMake(0, 6);
    self.batchActionButton.layer.shadowOpacity = 0.22;
    self.batchActionButton.layer.shadowRadius = 12;
    [self.batchActionButton addTarget:self action:@selector(batchActionTapped) forControlEvents:UIControlEventTouchUpInside];
    self.batchActionButton.hidden = YES;
    [self.view addSubview:self.batchActionButton];

    self.batchBar = self.batchActionButton;

    [NSLayoutConstraint activateConstraints:@[
        [self.batchActionButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.batchActionButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [self.batchActionButton.heightAnchor constraintEqualToConstant:52],
        [self.batchActionButton.widthAnchor constraintGreaterThanOrEqualToConstant:220],
        [self.batchActionButton.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-40],
    ]];
}

- (BOOL)supportsBatchAction {
    return self.kind == SCIPAListKindUnfollow
        || self.kind == SCIPAListKindFollow
        || self.kind == SCIPAListKindMutual;
}


- (void)updateNavBar {
    NSMutableArray *rights = [NSMutableArray array];
    if (self.supportsBatchAction) {
        NSString *t = self.selectionMode ? SCILocalized(@"Done") : SCILocalized(@"Select");
        UIBarButtonItem *sel = [[UIBarButtonItem alloc] initWithTitle:t
                                                                style:UIBarButtonItemStylePlain
                                                               target:self action:@selector(toggleSelectionMode)];
        [rights addObject:sel];
    }
    NSString *symbol = [self hasActiveFilterOrSort]
        ? @"line.3.horizontal.decrease.circle.fill"
        : @"line.3.horizontal.decrease.circle";
    UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:symbol]
                                                                menu:[self buildFilterMenu]];
    [rights addObject:filter];
    self.navigationItem.rightBarButtonItems = rights;
}

- (UIMenu *)buildFilterMenu {
    __weak typeof(self) weakSelf = self;

    NSMutableArray *sortChildren = [NSMutableArray array];
    if (self.kind == SCIPAListKindVisited) {
        UIAction *recent = [UIAction actionWithTitle:SCILocalized(@"Most recent")
                                               image:[UIImage systemImageNamed:@"clock.arrow.circlepath"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *_) {
            weakSelf.sortMode = SCIPASortModeRecent; [weakSelf applyFiltersAndSort];
        }];
        recent.state = (self.sortMode == SCIPASortModeRecent) ? UIMenuElementStateOn : UIMenuElementStateOff;

        UIAction *oldest = [UIAction actionWithTitle:SCILocalized(@"Oldest first")
                                               image:[UIImage systemImageNamed:@"clock"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *_) {
            weakSelf.sortMode = SCIPASortModeOldest; [weakSelf applyFiltersAndSort];
        }];
        oldest.state = (self.sortMode == SCIPASortModeOldest) ? UIMenuElementStateOn : UIMenuElementStateOff;

        UIAction *mostVisited = [UIAction actionWithTitle:SCILocalized(@"Most visited")
                                                    image:[UIImage systemImageNamed:@"flame.fill"]
                                               identifier:nil
                                                  handler:^(__kindof UIAction *_) {
            weakSelf.sortMode = SCIPASortModeMostVisited; [weakSelf applyFiltersAndSort];
        }];
        mostVisited.state = (self.sortMode == SCIPASortModeMostVisited) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [sortChildren addObjectsFromArray:@[recent, oldest, mostVisited]];
    }

    UIAction *az = [UIAction actionWithTitle:SCILocalized(@"Username A → Z")
                                        image:[UIImage systemImageNamed:@"arrow.up"]
                                   identifier:nil
                                      handler:^(__kindof UIAction *_) {
        weakSelf.sortMode = weakSelf.sortMode == SCIPASortModeAZ ? SCIPASortModeDefault : SCIPASortModeAZ;
        [weakSelf applyFiltersAndSort];
    }];
    az.state = (self.sortMode == SCIPASortModeAZ) ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *za = [UIAction actionWithTitle:SCILocalized(@"Username Z → A")
                                        image:[UIImage systemImageNamed:@"arrow.down"]
                                   identifier:nil
                                      handler:^(__kindof UIAction *_) {
        weakSelf.sortMode = weakSelf.sortMode == SCIPASortModeZA ? SCIPASortModeDefault : SCIPASortModeZA;
        [weakSelf applyFiltersAndSort];
    }];
    za.state = (self.sortMode == SCIPASortModeZA) ? UIMenuElementStateOn : UIMenuElementStateOff;
    [sortChildren addObjectsFromArray:@[az, za]];

    UIMenu *sortGroup = [UIMenu menuWithTitle:SCILocalized(@"Sort")
                                        image:nil identifier:nil
                                      options:UIMenuOptionsDisplayInline
                                     children:sortChildren];

    UIAction *verified = [UIAction actionWithTitle:SCILocalized(@"Verified only")
                                              image:[UIImage systemImageNamed:@"checkmark.seal.fill"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *_) {
        weakSelf.filterVerifiedOnly = !weakSelf.filterVerifiedOnly;
        if (weakSelf.filterVerifiedOnly) weakSelf.filterNotVerifiedOnly = NO;
        [weakSelf applyFiltersAndSort];
    }];
    verified.state = self.filterVerifiedOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *notVerified = [UIAction actionWithTitle:SCILocalized(@"Not verified only")
                                                 image:[UIImage systemImageNamed:@"seal"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *_) {
        weakSelf.filterNotVerifiedOnly = !weakSelf.filterNotVerifiedOnly;
        if (weakSelf.filterNotVerifiedOnly) weakSelf.filterVerifiedOnly = NO;
        [weakSelf applyFiltersAndSort];
    }];
    notVerified.state = self.filterNotVerifiedOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIAction *priv = [UIAction actionWithTitle:SCILocalized(@"Private only")
                                          image:[UIImage systemImageNamed:@"lock.fill"]
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
        weakSelf.filterPrivateOnly = !weakSelf.filterPrivateOnly;
        [weakSelf applyFiltersAndSort];
    }];
    priv.state = self.filterPrivateOnly ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIMenu *filterGroup = [UIMenu menuWithTitle:SCILocalized(@"Filter")
                                          image:nil identifier:nil
                                        options:UIMenuOptionsDisplayInline
                                       children:@[verified, notVerified, priv]];

    NSMutableArray *children = [NSMutableArray arrayWithObjects:sortGroup, filterGroup, nil];

    if (self.kind == SCIPAListKindVisited) {
        UIAction *(^df)(NSString *, NSString *, SCIPADateFilter) =
        ^UIAction *(NSString *title, NSString *symbol, SCIPADateFilter mode) {
            UIAction *a = [UIAction actionWithTitle:title
                                              image:[UIImage systemImageNamed:symbol]
                                         identifier:nil
                                            handler:^(__kindof UIAction *_) {
                weakSelf.dateFilter = (weakSelf.dateFilter == mode) ? SCIPADateFilterAny : mode;
                [weakSelf applyFiltersAndSort];
            }];
            a.state = (self.dateFilter == mode) ? UIMenuElementStateOn : UIMenuElementStateOff;
            return a;
        };
        UIMenu *dateGroup = [UIMenu menuWithTitle:SCILocalized(@"Visited")
                                            image:nil identifier:nil
                                          options:UIMenuOptionsDisplayInline
                                         children:@[
            df(SCILocalized(@"Today"),         @"sun.max",         SCIPADateFilterToday),
            df(SCILocalized(@"Last 7 days"),   @"calendar.badge.clock", SCIPADateFilter7d),
            df(SCILocalized(@"Last 30 days"),  @"calendar",        SCIPADateFilter30d),
        ]];
        [children insertObject:dateGroup atIndex:1];
    }

    if ([self hasActiveFilterOrSort]) {
        UIAction *clear = [UIAction actionWithTitle:SCILocalized(@"Clear")
                                              image:[UIImage systemImageNamed:@"arrow.counterclockwise"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *_) {
            weakSelf.sortMode = (weakSelf.kind == SCIPAListKindVisited) ? SCIPASortModeRecent : SCIPASortModeDefault;
            weakSelf.filterVerifiedOnly = NO;
            weakSelf.filterNotVerifiedOnly = NO;
            weakSelf.filterPrivateOnly = NO;
            weakSelf.dateFilter = SCIPADateFilterAny;
            [weakSelf applyFiltersAndSort];
        }];
        clear.attributes = UIMenuElementAttributesDestructive;
        [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
                                           options:UIMenuOptionsDisplayInline children:@[clear]]];
    }
    return [UIMenu menuWithChildren:children];
}

- (void)refreshCounts {
    NSUInteger total, shown;
    if (self.kind == SCIPAListKindProfileUpdate) {
        total = self.allChanges.count; shown = self.filteredChanges.count;
    } else if (self.kind == SCIPAListKindVisited) {
        total = self.allVisits.count;  shown = self.filteredVisits.count;
    } else {
        total = self.allUsers.count;   shown = self.filteredUsers.count;
    }
    self.navigationItem.prompt = [NSString stringWithFormat:SCILocalized(@"%lu of %lu"),
                                  (unsigned long)shown, (unsigned long)total];
    self.emptyLabel.hidden = shown > 0;
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.currentQuery = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [self applyFiltersAndSort];
}

- (void)applyFiltersAndSort {
    NSString *q = self.currentQuery;
    BOOL hasQuery = q.length > 0;
    BOOL verified = self.filterVerifiedOnly;
    BOOL notVerified = self.filterNotVerifiedOnly;
    BOOL priv = self.filterPrivateOnly;

    NSArray *(^applyToUsers)(NSArray *) = ^NSArray *(NSArray *src) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:src.count];
        for (SCIProfileAnalyzerUser *u in src) {
            if (hasQuery && ![u.username localizedCaseInsensitiveContainsString:q]
                         && ![u.fullName localizedCaseInsensitiveContainsString:q]) continue;
            if (verified && !u.isVerified) continue;
            if (notVerified && u.isVerified) continue;
            if (priv && !u.isPrivate) continue;
            [out addObject:u];
        }
        return [self sortUsers:out];
    };

    if (self.kind == SCIPAListKindProfileUpdate) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:self.allChanges.count];
        for (SCIProfileAnalyzerProfileChange *c in self.allChanges) {
            SCIProfileAnalyzerUser *u = c.current;
            if (hasQuery && ![u.username localizedCaseInsensitiveContainsString:q]
                         && ![u.fullName localizedCaseInsensitiveContainsString:q]) continue;
            if (verified && !u.isVerified) continue;
            if (notVerified && u.isVerified) continue;
            if (priv && !u.isPrivate) continue;
            [out addObject:c];
        }
        self.filteredChanges = [self sortChanges:out];
    } else if (self.kind == SCIPAListKindVisited) {
        NSDate *cutoff = [self dateCutoffForCurrentFilter];
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:self.allVisits.count];
        for (SCIProfileAnalyzerVisit *vst in self.allVisits) {
            SCIProfileAnalyzerUser *u = vst.user;
            if (hasQuery && ![u.username localizedCaseInsensitiveContainsString:q]
                         && ![u.fullName localizedCaseInsensitiveContainsString:q]) continue;
            if (verified && !u.isVerified) continue;
            if (notVerified && u.isVerified) continue;
            if (priv && !u.isPrivate) continue;
            if (cutoff && [vst.lastSeen compare:cutoff] == NSOrderedAscending) continue;
            [out addObject:vst];
        }
        self.filteredVisits = [self sortVisits:out];
    } else {
        self.filteredUsers = applyToUsers(self.allUsers);
    }
    [self refreshCounts];
    [self updateNavBar];  // refresh filter-icon "active" state
    [self.tableView reloadData];
}

- (NSArray *)sortUsers:(NSArray<SCIProfileAnalyzerUser *> *)src {
    if (self.sortMode == SCIPASortModeDefault) return src;
    BOOL asc = (self.sortMode == SCIPASortModeAZ);
    return [src sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerUser *a, SCIProfileAnalyzerUser *b) {
        NSComparisonResult r = [a.username caseInsensitiveCompare:b.username ?: @""];
        return asc ? r : -r;
    }];
}

- (NSDate *)dateCutoffForCurrentFilter {
    NSTimeInterval secs = 0;
    switch (self.dateFilter) {
        case SCIPADateFilterToday: secs = 86400;        break;
        case SCIPADateFilter7d:    secs = 7  * 86400;   break;
        case SCIPADateFilter30d:   secs = 30 * 86400;   break;
        default: return nil;
    }
    return [NSDate dateWithTimeIntervalSinceNow:-secs];
}

- (NSArray *)sortVisits:(NSArray<SCIProfileAnalyzerVisit *> *)src {
    SCIPASortMode m = self.sortMode;
    if (m == SCIPASortModeRecent || m == SCIPASortModeDefault) {
        return [src sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerVisit *a, SCIProfileAnalyzerVisit *b) {
            return [b.lastSeen compare:a.lastSeen];
        }];
    }
    if (m == SCIPASortModeOldest) {
        return [src sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerVisit *a, SCIProfileAnalyzerVisit *b) {
            return [a.lastSeen compare:b.lastSeen];
        }];
    }
    if (m == SCIPASortModeMostVisited) {
        return [src sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerVisit *a, SCIProfileAnalyzerVisit *b) {
            if (a.visitCount == b.visitCount) return [b.lastSeen compare:a.lastSeen];
            return (a.visitCount < b.visitCount) ? NSOrderedDescending : NSOrderedAscending;
        }];
    }
    BOOL asc = (m == SCIPASortModeAZ);
    return [src sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerVisit *a, SCIProfileAnalyzerVisit *b) {
        NSComparisonResult r = [a.user.username caseInsensitiveCompare:b.user.username ?: @""];
        return asc ? r : -r;
    }];
}

- (NSArray *)sortChanges:(NSArray<SCIProfileAnalyzerProfileChange *> *)src {
    if (self.sortMode == SCIPASortModeDefault) return src;
    BOOL asc = (self.sortMode == SCIPASortModeAZ);
    return [src sortedArrayUsingComparator:^NSComparisonResult(SCIProfileAnalyzerProfileChange *a, SCIProfileAnalyzerProfileChange *b) {
        NSComparisonResult r = [a.current.username caseInsensitiveCompare:b.current.username ?: @""];
        return asc ? r : -r;
    }];
}

- (BOOL)hasActiveFilterOrSort {
    SCIPASortMode neutral = (self.kind == SCIPAListKindVisited) ? SCIPASortModeRecent : SCIPASortModeDefault;
    return self.filterVerifiedOnly || self.filterNotVerifiedOnly || self.filterPrivateOnly
        || self.dateFilter != SCIPADateFilterAny
        || self.sortMode != neutral;
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (self.kind == SCIPAListKindProfileUpdate) return self.filteredChanges.count;
    if (self.kind == SCIPAListKindVisited)       return self.filteredVisits.count;
    return self.filteredUsers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SCIPAUserCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    SCIProfileAnalyzerUser *user;
    SCIProfileAnalyzerProfileChange *change = nil;
    SCIProfileAnalyzerVisit *visit = nil;
    if (self.kind == SCIPAListKindProfileUpdate) {
        change = self.filteredChanges[indexPath.row];
        user = change.current;
    } else if (self.kind == SCIPAListKindVisited) {
        visit = self.filteredVisits[indexPath.row];
        user = visit.user;
    } else {
        user = self.filteredUsers[indexPath.row];
    }

    cell.usernameLabel.text = user.username.length ? [NSString stringWithFormat:@"@%@", user.username] : SCILocalized(@"(unknown)");
    cell.verifiedBadge.hidden = !user.isVerified;

    if (self.kind == SCIPAListKindProfileUpdate) {
        NSMutableArray *lines = [NSMutableArray array];
        if (change.usernameChanged) {
            [lines addObject:[NSString stringWithFormat:SCILocalized(@"Username: @%@ → @%@"),
                              change.previous.username ?: @"", change.current.username ?: @""]];
        }
        if (change.fullNameChanged) {
            [lines addObject:[NSString stringWithFormat:SCILocalized(@"Name: %@ → %@"),
                              change.previous.fullName.length ? change.previous.fullName : @"—",
                              change.current.fullName.length ? change.current.fullName : @"—"]];
        }
        if (change.profilePicChanged) [lines addObject:SCILocalized(@"Profile picture changed")];
        cell.subtitleLabel.text = [lines componentsJoinedByString:@"\n"];
        cell.subtitleLabel.numberOfLines = 3;
    } else if (self.kind == SCIPAListKindVisited) {
        NSString *when = [self relativeStringForDate:visit.lastSeen];
        NSString *dateLine = (visit.visitCount > 1)
            ? [NSString stringWithFormat:@"%@ · %ld", when, (long)visit.visitCount]
            : when;
        NSString *first = user.fullName.length ? user.fullName : (user.isPrivate ? SCILocalized(@"Private account") : @"");
        if (first.length) {
            cell.subtitleLabel.text = [NSString stringWithFormat:@"%@\n%@", first, dateLine];
            cell.subtitleLabel.numberOfLines = 2;
        } else {
            cell.subtitleLabel.text = dateLine;
            cell.subtitleLabel.numberOfLines = 1;
        }
    } else {
        cell.subtitleLabel.text = user.fullName.length ? user.fullName : (user.isPrivate ? SCILocalized(@"Private account") : @"");
        cell.subtitleLabel.numberOfLines = 1;
    }

    [self configureActionForCell:cell user:user];

    if (self.selectionMode) {
        BOOL on = [self.selectedPKs containsObject:user.pk];
        cell.accessoryType = on ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    // Skip avatar reset when reconfiguring the same row — avoids a grey flash.
    BOOL pkChanged = ![cell.boundPK isEqualToString:user.pk];
    if (pkChanged) {
        cell.boundPK = user.pk;
        cell.avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
        cell.avatar.tintColor = [UIColor systemGrayColor];
    }
    if (user.profilePicURL.length) {
        NSURL *url = [NSURL URLWithString:user.profilePicURL];
        NSString *boundPK = user.pk;
        __weak typeof(self) weakSelf = self;
        __weak SCIPAUserCell *weakCell = cell;
        [SCIImageCache loadImageFromURL:url completion:^(UIImage *image) {
            SCIPAUserCell *strongCell = weakCell;
            if (image) {
                if ([strongCell.boundPK isEqualToString:boundPK]) strongCell.avatar.image = image;
                return;
            }
            // CDN URL expired — fetch a fresh one.
            [weakSelf refreshProfilePicForUser:user];
        }];
    } else {
        // Visit captured before fieldCache populated — fetch identity now.
        [self refreshProfilePicForUser:user];
    }
    return cell;
}

- (void)refreshProfilePicForUser:(SCIProfileAnalyzerUser *)user {
    if (!user.pk.length) return;
    NSMutableDictionary *seen = sciPicRefreshAttempted();
    @synchronized (seen) {
        NSDate *last = seen[user.pk];
        if (last && -[last timeIntervalSinceNow] < kSCIPAPicRefreshTTL) return;
        seen[user.pk] = [NSDate date];
    }
    __weak typeof(self) weakSelf = self;
    [SCIInstagramAPI sendRequestWithMethod:@"GET"
                                      path:[NSString stringWithFormat:@"users/%@/info/", user.pk]
                                      body:nil
                                completion:^(NSDictionary *resp, NSError *error) {
        NSDictionary *info = [resp[@"user"] isKindOfClass:[NSDictionary class]] ? resp[@"user"] : nil;
        if (!info.count) return;

        NSString *fresh = [info[@"profile_pic_url"] isKindOfClass:[NSString class]] ? info[@"profile_pic_url"] : nil;
        if (!fresh.length) {
            // Some private / restricted accounts only expose the HD url.
            NSDictionary *hd = info[@"hd_profile_pic_url_info"];
            if ([hd isKindOfClass:[NSDictionary class]]) {
                id u = hd[@"url"];
                if ([u isKindOfClass:[NSString class]]) fresh = u;
            }
        }

        BOOL changed = NO;
        if (fresh.length && ![user.profilePicURL isEqualToString:fresh]) {
            user.profilePicURL = fresh; changed = YES;
        }
        NSString *un = [info[@"username"] isKindOfClass:[NSString class]] ? info[@"username"] : nil;
        if (un.length && ![user.username isEqualToString:un]) { user.username = un; changed = YES; }
        NSString *fn = [info[@"full_name"] isKindOfClass:[NSString class]] ? info[@"full_name"] : nil;
        if (fn && ![(user.fullName ?: @"") isEqualToString:fn]) { user.fullName = fn; changed = YES; }
        BOOL ver = [info[@"is_verified"] boolValue];
        BOOL pri = [info[@"is_private"] boolValue];
        if (user.isVerified != ver) { user.isVerified = ver; changed = YES; }
        if (user.isPrivate  != pri) { user.isPrivate  = pri; changed = YES; }

        if (!changed) return;

        if (weakSelf.kind == SCIPAListKindVisited) {
            [SCIProfileAnalyzerStorage refreshVisitedUser:user forUserPK:[SCIUtils currentUserPK]];
        }
        [weakSelf reloadVisibleRowsForPKs:@[user.pk]];
    }];
}

- (NSString *)relativeStringForDate:(NSDate *)date {
    if (!date) return @"—";
    NSTimeInterval delta = -[date timeIntervalSinceNow];
    if (delta < 60)    return SCILocalized(@"just now");
    if (delta < 3600)  return [NSString stringWithFormat:SCILocalized(@"%dm ago"), MAX(1, (int)(delta / 60))];
    if (delta < 86400) return [NSString stringWithFormat:SCILocalized(@"%dh ago"), (int)(delta / 3600)];
    if (delta < 7 * 86400) return [NSString stringWithFormat:SCILocalized(@"%dd ago"), (int)(delta / 86400)];
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = NSDateFormatterNoStyle;
    return [f stringFromDate:date];
}

- (void)configureActionForCell:(SCIPAUserCell *)cell user:(SCIProfileAnalyzerUser *)user {
    if (self.selectionMode) {
        [cell hideAction];
        return;
    }
    BOOL pending = [self.pendingPKs containsObject:user.pk];
    NSNumber *status = self.friendshipStatus[user.pk];
    UIColor *primary = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];

    if (pending) {
        [cell applyAction:SCIPACellActionPending pending:YES tint:primary];
    } else if (!status) {
        [cell applyAction:SCIPACellActionLoading pending:NO tint:primary];
    } else if ([status boolValue]) {
        [cell applyAction:SCIPACellActionUnfollow pending:NO tint:primary];
    } else {
        [cell applyAction:SCIPACellActionFollow pending:NO tint:primary];
    }
    __weak typeof(self) weakSelf = self;
    cell.onActionTap = ^(SCIPAUserCell *c) { [weakSelf performActionForUser:user]; };
}

#pragma mark - Single-row action

- (void)performActionForUser:(SCIProfileAnalyzerUser *)user {
    if ([self.pendingPKs containsObject:user.pk]) return;
    NSNumber *status = self.friendshipStatus[user.pk];
    if (!status) return;
    BOOL currentlyFollowing = [status boolValue];
    if (currentlyFollowing) {
        NSString *msg = [NSString stringWithFormat:SCILocalized(@"Unfollow @%@?"), user.username ?: @""];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        __weak typeof(self) weakSelf = self;
        [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Unfollow") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
            [weakSelf sendFriendshipForUser:user follow:NO reload:YES];
        }]];
        [self presentViewController:a animated:YES completion:nil];
    } else {
        [self sendFriendshipForUser:user follow:YES reload:YES];
    }
}

- (void)sendFriendshipForUser:(SCIProfileAnalyzerUser *)user follow:(BOOL)follow reload:(BOOL)reload {
    [self.pendingPKs addObject:user.pk];
    if (reload) [self reloadVisibleRowsForPKs:@[user.pk]];
    __weak typeof(self) weakSelf = self;
    void(^done)(NSDictionary *, NSError *) = ^(NSDictionary *resp, NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.pendingPKs removeObject:user.pk];
        BOOL success = (err == nil) && ([resp[@"status"] isEqualToString:@"ok"] || resp[@"friendship_status"]);
        if (success) {
            strongSelf.friendshipStatus[user.pk] = @(follow);
            [SCIPAFriendshipCache setFollowing:follow forPK:user.pk];
            [strongSelf persistFriendshipChangeForUser:user followed:follow];
            BOOL membershipChanged =
                ((strongSelf.kind == SCIPAListKindUnfollow || strongSelf.kind == SCIPAListKindMutual) && !follow)
             || (strongSelf.kind == SCIPAListKindFollow && follow);
            if (membershipChanged) {
                [strongSelf removeUserFromList:user];
            } else {
                [strongSelf reloadVisibleRowsForPKs:@[user.pk]];
            }
        } else {
            [SCIUtils showErrorHUDWithDescription:err.localizedDescription ?: SCILocalized(@"Request failed")];
            [strongSelf reloadVisibleRowsForPKs:@[user.pk]];
        }
    };
    if (follow) [SCIInstagramAPI followUserPK:user.pk completion:done];
    else        [SCIInstagramAPI unfollowUserPK:user.pk completion:done];
}

// Mirror in-app follow/unfollow into the snapshot so category counts update live.
- (void)persistFriendshipChangeForUser:(SCIProfileAnalyzerUser *)user followed:(BOOL)followed {
    NSString *pk = [SCIUtils currentUserPK];
    SCIProfileAnalyzerSnapshot *snap = [SCIProfileAnalyzerStorage currentSnapshotForUserPK:pk];
    if (!snap) return;
    NSMutableArray *following = [snap.following mutableCopy] ?: [NSMutableArray array];
    BOOL alreadyIn = [following containsObject:user];
    if (followed && !alreadyIn) {
        [following addObject:user];
        snap.followingCount = MAX(0, snap.followingCount + 1);
    } else if (!followed && alreadyIn) {
        [following removeObject:user];
        snap.followingCount = MAX(0, snap.followingCount - 1);
    } else {
        return;
    }
    snap.following = following;
    [SCIProfileAnalyzerStorage updateCurrentSnapshot:snap forUserPK:pk];
}

- (void)removeUserFromList:(SCIProfileAnalyzerUser *)user {
    if (self.kind == SCIPAListKindVisited || self.kind == SCIPAListKindProfileUpdate) {
        [self reloadVisibleRowsForPKs:@[user.pk]];   // history kinds keep the row
        return;
    }
    NSMutableArray *all = [self.allUsers mutableCopy];
    [all removeObject:user];
    self.allUsers = all;
    NSMutableArray *filt = [self.filteredUsers mutableCopy];
    [filt removeObject:user];
    self.filteredUsers = filt;
    [self.selectedPKs removeObject:user.pk];
    [self refreshCounts];
    [self.tableView reloadData];
}

#pragma mark - Tap row

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    SCIProfileAnalyzerUser *user;
    if (self.kind == SCIPAListKindProfileUpdate) {
        user = self.filteredChanges[indexPath.row].current;
    } else if (self.kind == SCIPAListKindVisited) {
        user = self.filteredVisits[indexPath.row].user;
    } else {
        user = self.filteredUsers[indexPath.row];
    }

    if (self.selectionMode) {
        if ([self.selectedPKs containsObject:user.pk]) [self.selectedPKs removeObject:user.pk];
        else [self.selectedPKs addObject:user.pk];
        [self refreshBatchBar];
        [tv reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }

    if (!user.username.length) return;
    [SCIURLOpener dismiss:self thenOpenInstagramProfileForUsername:user.username];
}

#pragma mark - Pull-to-refresh

- (void)pullToRefresh:(UIRefreshControl *)sender {
    // Re-read disk, drop cached friendship/pic dedup, then force a fresh
    // /users/{pk}/info/ for every visible row so identity + pic resync.
    self.allVisits = [SCIProfileAnalyzerStorage visitedProfilesForUserPK:[SCIUtils currentUserPK]] ?: @[];

    @synchronized (sciPicRefreshAttempted()) {
        for (SCIProfileAnalyzerVisit *v in self.allVisits) {
            NSString *pk = v.user.pk;
            if (!pk.length) continue;
            [sciPicRefreshAttempted() removeObjectForKey:pk];
            [self.friendshipStatus removeObjectForKey:pk];
            [self.lookupBackoff removeObjectForKey:pk];
            [SCIPAFriendshipCache invalidatePK:pk];
        }
    }

    [self applyFiltersAndSort];

    NSMutableSet<SCIProfileAnalyzerUser *> *visibleUsers = [NSMutableSet set];
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        if (ip.row >= (NSInteger)self.filteredVisits.count) continue;
        SCIProfileAnalyzerUser *u = self.filteredVisits[ip.row].user;
        if (u.pk.length) [visibleUsers addObject:u];
    }
    for (SCIProfileAnalyzerUser *u in visibleUsers) [self refreshProfilePicForUser:u];

    [self.tableView reloadData];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [sender endRefreshing];
    });
}

#pragma mark - Lazy friendship lookup

- (NSString *)pkAtIndexPath:(NSIndexPath *)indexPath {
    if (self.kind == SCIPAListKindProfileUpdate) {
        if (indexPath.row >= (NSInteger)self.filteredChanges.count) return nil;
        return self.filteredChanges[indexPath.row].current.pk;
    }
    if (self.kind == SCIPAListKindVisited) {
        if (indexPath.row >= (NSInteger)self.filteredVisits.count) return nil;
        return self.filteredVisits[indexPath.row].user.pk;
    }
    if (indexPath.row >= (NSInteger)self.filteredUsers.count) return nil;
    return self.filteredUsers[indexPath.row].pk;
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *pk = [self pkAtIndexPath:indexPath];
    if (!pk.length) return;
    if (self.friendshipStatus[pk]) return;
    if ([self.lookupInflight containsObject:pk]) return;
    NSDate *backoff = self.lookupBackoff[pk];
    if (backoff && -[backoff timeIntervalSinceNow] < 60.0) return;
    [self.lookupQueue addObject:pk];
    [self scheduleLookupFlush];
}

- (void)scheduleLookupFlush {
    if (self.lookupFlushScheduled) return;
    self.lookupFlushScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        weakSelf.lookupFlushScheduled = NO;
        [weakSelf flushPendingLookups];
    });
}

- (void)flushPendingLookups {
    if (!self.lookupQueue.count) return;
    NSArray *all = [self.lookupQueue allObjects];
    [self.lookupQueue removeAllObjects];
    NSInteger chunkSize = 80;   // show_many caps around ~100 ids
    for (NSInteger i = 0; i < (NSInteger)all.count; i += chunkSize) {
        NSArray *chunk = [all subarrayWithRange:NSMakeRange(i, MIN(chunkSize, (NSInteger)all.count - i))];
        for (NSString *pk in chunk) [self.lookupInflight addObject:pk];
        __weak typeof(self) weakSelf = self;
        [SCIInstagramAPI fetchFriendshipStatusesForPKs:chunk
                                             completion:^(NSDictionary *statuses, NSError *error) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            for (NSString *pk in chunk) [strongSelf.lookupInflight removeObject:pk];
            if (error || !statuses.count) {
                // Back off so willDisplay doesn't re-queue the same pks each scroll.
                NSDate *now = [NSDate date];
                for (NSString *pk in chunk) strongSelf.lookupBackoff[pk] = now;
            } else {
                for (NSString *pk in chunk) {
                    NSDictionary *st = statuses[pk];
                    BOOL following = [st isKindOfClass:[NSDictionary class]] ? [st[@"following"] boolValue] : NO;
                    strongSelf.friendshipStatus[pk] = @(following);
                    [SCIPAFriendshipCache setFollowing:following forPK:pk];
                }
            }
            [strongSelf reloadVisibleRowsForPKs:chunk];
        }];
    }
}

- (void)reloadVisibleRowsForPKs:(NSArray<NSString *> *)pks {
    NSSet *set = [NSSet setWithArray:pks];
    NSMutableArray *paths = [NSMutableArray array];
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        NSString *pk = [self pkAtIndexPath:ip];
        if (pk && [set containsObject:pk]) [paths addObject:ip];
    }
    if (paths.count) [self.tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationFade];
}

#pragma mark - Swipe actions (visited only)

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
        trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.kind != SCIPAListKindVisited) return nil;
    if (indexPath.row >= (NSInteger)self.filteredVisits.count) return nil;
    SCIProfileAnalyzerVisit *vst = self.filteredVisits[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:SCILocalized(@"Remove")
                          handler:^(UIContextualAction *_, UIView *__, void(^done)(BOOL)) {
        [SCIProfileAnalyzerStorage removeVisitForUserPK:[SCIUtils currentUserPK] visitedPK:vst.user.pk];
        NSMutableArray *all = [weakSelf.allVisits mutableCopy];
        [all removeObject:vst];
        weakSelf.allVisits = all;
        [weakSelf applyFiltersAndSort];
        done(YES);
    }];
    del.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

#pragma mark - Multi-select

- (void)toggleSelectionMode {
    self.selectionMode = !self.selectionMode;
    [self.selectedPKs removeAllObjects];
    self.batchActionButton.hidden = !self.selectionMode;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, self.selectionMode ? 96 : 0, 0);
    [self updateNavBar];
    [self refreshBatchBar];
    [self.tableView reloadData];
}

- (void)refreshBatchBar {
    NSUInteger n = self.selectedPKs.count;
    BOOL follow = (self.kind == SCIPAListKindFollow);
    NSString *t = follow
        ? [NSString stringWithFormat:SCILocalized(@"Follow %lu"), (unsigned long)n]
        : [NSString stringWithFormat:SCILocalized(@"Unfollow %lu"), (unsigned long)n];
    [self.batchActionButton setTitle:t forState:UIControlStateNormal];
    self.batchActionButton.backgroundColor = follow
        ? ([SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor])
        : [UIColor systemRedColor];
    self.batchActionButton.enabled = n > 0;
    self.batchActionButton.alpha = n > 0 ? 1.0 : 0.5;
}

- (void)batchActionTapped {
    NSUInteger n = self.selectedPKs.count;
    if (!n) return;
    BOOL follow = (self.kind == SCIPAListKindFollow);
    NSString *verb = follow ? SCILocalized(@"Follow") : SCILocalized(@"Unfollow");
    NSString *title = follow ? SCILocalized(@"Batch follow") : SCILocalized(@"Batch unfollow");
    NSString *msg;
    if (n > kSCIPABatchCap) {
        msg = [NSString stringWithFormat:SCILocalized(@"%@ %lu accounts? The first %ld will be processed to avoid rate limits."),
               verb, (unsigned long)n, (long)kSCIPABatchCap];
    } else {
        msg = [NSString stringWithFormat:SCILocalized(@"%@ %lu accounts? This runs sequentially with a short pause between each."),
               verb, (unsigned long)n];
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIAlertActionStyle style = follow ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive;
    __weak typeof(self) weakSelf = self;
    [a addAction:[UIAlertAction actionWithTitle:verb style:style handler:^(UIAlertAction *_) {
        [weakSelf runBatchAction];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)runBatchAction {
    BOOL follow = (self.kind == SCIPAListKindFollow);
    NSMutableArray<SCIProfileAnalyzerUser *> *queue = [NSMutableArray array];
    for (SCIProfileAnalyzerUser *u in self.allUsers) {
        if (![self.selectedPKs containsObject:u.pk]) continue;
        // Skip users already in the target state.
        NSNumber *st = self.friendshipStatus[u.pk];
        if (st && [st boolValue] == follow) continue;
        [queue addObject:u];
        if (queue.count >= kSCIPABatchCap) break;
    }
    [self.selectedPKs removeAllObjects];
    [self refreshBatchBar];
    [self batchStep:queue done:0 total:queue.count];
}

- (void)batchStep:(NSMutableArray<SCIProfileAnalyzerUser *> *)queue
             done:(NSUInteger)done
            total:(NSUInteger)total {
    BOOL follow = (self.kind == SCIPAListKindFollow);
    if (!queue.count) {
        NSString *finishedTitle = follow ? SCILocalized(@"Batch follow finished") : SCILocalized(@"Batch unfollow finished");
        NSString *finishedSub = follow
            ? [NSString stringWithFormat:SCILocalized(@"%lu accounts followed"), (unsigned long)total]
            : [NSString stringWithFormat:SCILocalized(@"%lu accounts unfollowed"), (unsigned long)total];
        SCINotifySuccess(SCI_NOTIF_ANALYZER_DONE, finishedTitle, finishedSub);
        self.navigationItem.prompt = nil;
        [self toggleSelectionMode];
        [self refreshCounts];
        return;
    }
    SCIProfileAnalyzerUser *u = queue.firstObject;
    [queue removeObjectAtIndex:0];
    __weak typeof(self) weakSelf = self;
    void(^handler)(NSDictionary *, NSError *) = ^(NSDictionary *resp, NSError *err) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSUInteger nextDone = done + 1;
        BOOL ok = (err == nil) && ([resp[@"status"] isEqualToString:@"ok"] || resp[@"friendship_status"]);
        if (ok) {
            strongSelf.friendshipStatus[u.pk] = @(follow);
            [SCIPAFriendshipCache setFollowing:follow forPK:u.pk];
            [strongSelf persistFriendshipChangeForUser:u followed:follow];
            [strongSelf removeUserFromList:u];
        }
        NSString *progressFmt = follow ? SCILocalized(@"Following… %lu / %lu") : SCILocalized(@"Unfollowing… %lu / %lu");
        strongSelf.navigationItem.prompt = [NSString stringWithFormat:progressFmt,
                                            (unsigned long)nextDone, (unsigned long)total];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSCIPABatchDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf batchStep:queue done:nextDone total:total];
        });
    };
    if (follow) [SCIInstagramAPI followUserPK:u.pk completion:handler];
    else        [SCIInstagramAPI unfollowUserPK:u.pk completion:handler];
}

@end
