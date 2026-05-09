#import "SCIGalleryViewController.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryGridCell.h"
#import "SCIGalleryListCollectionCell.h"
#import "SCIGalleryFolderCell.h"
#import "SCIGalleryCoreDataStack.h"
#import "SCIGallerySheetViewController.h"
#import "SCIGallerySortViewController.h"
#import "SCIGalleryFilterViewController.h"
#import "SCIGallerySettingsViewController.h"
#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryOriginController.h"
#import "SCIMediaChrome.h"
#import "../InstagramHeaders.h"
#import "../ActionButton/SCIMediaViewer.h"
#import "../ActionButton/SCIMediaActions.h"
#import "SCIAssetUtils.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"
#import "../UI/SCIPopupChrome.h"
#import <CoreData/CoreData.h>

static NSString * const kGridCellID = @"SCIGalleryGridCell";
static NSString * const kListCellID = @"SCIGalleryListCell";
static NSString * const kFolderCellID = @"SCIGalleryFolderCell";

static NSString * const kSortModeKey    = @"gallery_sort_mode";
static NSString * const kViewModeKey    = @"gallery_view_mode"; // 0 = grid, 1 = list
static NSString * const kFavoritesAtTopKey = @"show_favorites_at_top";

static CGFloat const kGridSpacing = 2.0;
static NSInteger const kGridColumns = 3;
static CGFloat const kGalleryMenuIconPointSize = 17.0;
// Floating capsule height (52) + bottom gap (12). See SCIMediaChrome.
static CGFloat const kGalleryBottomBarInsetHeight = 64.0;

static UIImage *SCIGalleryMenuActionIcon(NSString *resourceName) {
    return [SCIAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
                                   pointSize:kGalleryMenuIconPointSize];
}

static NSInteger SCIGalleryItemCountForFolderPath(NSManagedObjectContext *context, NSString *folderPath) {
    if (folderPath.length == 0) return 0;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    request.predicate = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@",
                         folderPath, [folderPath stringByAppendingString:@"/"]];
    return [context countForFetchRequest:request error:nil];
}

#import "SCIGalleryViewController_Internal.h"


@implementation SCIGalleryViewController

#pragma mark - Presentation

+ (void)presentGallery {
    [SCIPopupChrome presentVC:[SCIGalleryViewController new] from:topMostController()];
}

+ (void)presentPickerWithMediaTypes:(NSArray<NSNumber *> *)allowedMediaTypes
                              title:(NSString *)title
                             fromVC:(UIViewController *)fromVC
                         completion:(void (^)(NSURL *, SCIGalleryFile *))completion {
    UIViewController *presenter = fromVC ?: topMostController();
    SCIGalleryViewController *vc = [[SCIGalleryViewController alloc] init];
    vc.pickerMode = YES;
    vc.pickerAllowedMediaTypes = [allowedMediaTypes copy];
    vc.pickerCompletion = [completion copy];
    vc.pickerTitleOverride = [title copy];

    [SCIPopupChrome presentVC:vc from:presenter];
}

#pragma mark - Init

- (instancetype)init {
    return [self initWithFolderPath:nil];
}

- (instancetype)initWithFolderPath:(NSString *)folderPath {
    if ((self = [super init])) {
        _currentFolderPath = [folderPath copy];
        _filterTypes = [NSMutableSet set];
        _filterSources = [NSMutableSet set];
        _filterUsernames = [NSMutableSet set];
        _filterFavoritesOnly = NO;
        _selectedFileIDs = [NSMutableSet set];

        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _sortMode = (SCIGallerySortMode)[d integerForKey:kSortModeKey];
        _viewMode = (SCIGalleryViewMode)[d integerForKey:kViewModeKey];
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [SCIPopupChrome backgroundColor];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleGalleryPreferencesChanged:)
                                                 name:@"SCIGalleryFavoritesSortPreferenceChanged"
                                               object:nil];

    [self setupCenteredTitle];
    [self setupNavigationItems];
    [self setupSearchController];
    [self setupBottomToolbar];
    [self setupCollectionView];
    [self setupEmptyState];
    [self setupFetchedResultsController];
    [self reloadSubfolders];
    [self updateEmptyState];

    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationController.presentationController.delegate = self;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyGalleryNavigationChrome];
    [self installBottomToolbarIfNeeded];
    [self refreshNavigationItems];
    [self refreshBottomToolbarItems];
    [self updateCollectionInsets];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.bottomBar.superview) {
        [self.bottomBar removeFromSuperview];
    }
    if (self.navigationController.viewControllers.firstObject != self) return;
    if (self.isMovingFromParentViewController) return;
    // Lock-on-dismiss disabled — padlock feature deferred.
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    // Lock-on-dismiss disabled — padlock feature deferred.
    if (self.pickerMode && self.pickerCompletion) {
        void (^cb)(NSURL *, SCIGalleryFile *) = self.pickerCompletion;
        self.pickerCompletion = nil;
        cb(nil, nil);
    }
}

- (void)dismissSelf {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)pickerCancelTapped {
    void (^cb)(NSURL *, SCIGalleryFile *) = self.pickerCompletion;
    UINavigationController *nav = self.navigationController;
    for (UIViewController *vc in nav.viewControllers) {
        if ([vc isKindOfClass:[SCIGalleryViewController class]]) {
            ((SCIGalleryViewController *)vc).pickerCompletion = nil;
        }
    }
    [nav dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(nil, nil);
    }];
}

#pragma mark - Navigation & chrome

- (void)applyGalleryNavigationChrome {
    // Use the default UINavigationBar appearance so titles, search bar, and
    // pushed VCs render with the same chrome as the rest of Settings.
}

- (void)setupCenteredTitle {
    NSString *text;
    if (self.pickerMode && self.pickerTitleOverride.length && self.currentFolderPath.length == 0) {
        text = self.pickerTitleOverride;
    } else {
        text = self.currentFolderPath.length > 0 ? [self.currentFolderPath lastPathComponent] : SCILocalized(@"Gallery");
    }
    self.navigationItem.titleView = nil;
    self.title = text;
}

- (void)setupNavigationItems {
    [self refreshNavigationItems];
}

- (void)setupSearchController {
    UISearchController *controller = [[UISearchController alloc] initWithSearchResultsController:nil];
    controller.obscuresBackgroundDuringPresentation = NO;
    controller.hidesNavigationBarDuringPresentation = NO;
    controller.searchResultsUpdater = self;
    controller.searchBar.placeholder = SCILocalized(@"Search");
    self.searchController = controller;
    self.navigationItem.searchController = controller;
    // Search bar collapses under the title until the user scrolls up or
    // taps the bottom-bar Search button (which scrolls + activates).
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    // iOS 26 routes search to the bottom of the screen by default (which
    // overlays our floating bottom toolbar). Force the classic stacked
    // placement so the search bar lives under the title at the top.
    if (@available(iOS 26.0, *)) {
        @try {
            // UINavigationItemSearchBarPlacementStacked = 2
            [self.navigationItem setValue:@2 forKey:@"preferredSearchBarPlacement"];
        } @catch (__unused NSException *exception) {}
    }
    self.definesPresentationContext = YES;
}

- (void)refreshNavigationItems {
    if (self.pickerMode) {
        if (self.navigationController.viewControllers.firstObject == self) {
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Cancel")
                                                                                      style:UIBarButtonItemStylePlain
                                                                                     target:self
                                                                                     action:@selector(pickerCancelTapped)];
        } else {
            self.navigationItem.leftBarButtonItem = nil;
        }
        self.navigationItem.rightBarButtonItem = nil;
        self.navigationItem.rightBarButtonItems = nil;
        return;
    }

    if (self.selectionMode) {
        NSArray<SCIGalleryFile *> *files = [self visibleGalleryFiles];
        BOOL allSelected = files.count > 0 && self.selectedFileIDs.count == files.count;
        self.navigationItem.rightBarButtonItems = nil;
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Cancel")
                                                                                  style:UIBarButtonItemStylePlain
                                                                                 target:self
                                                                                 action:@selector(exitSelectionMode)];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:(allSelected ? SCILocalized(@"Deselect All") : SCILocalized(@"Select All"))
                                                                                  style:UIBarButtonItemStylePlain
                                                                                 target:self
                                                                                 action:@selector(selectAllVisibleFiles)];
        return;
    }

    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = SCIMediaChromeTopBarButtonItem(@"xmark", self, @selector(dismissSelf));
    } else {
        self.navigationItem.leftBarButtonItem = nil;
    }

    self.navigationItem.rightBarButtonItem = nil;
    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];
    if (self.navigationController.viewControllers.firstObject == self) {
        [items addObject:SCIMediaChromeTopBarButtonItem(@"settings", self, @selector(pushSettings))];
    }
    UIBarButtonItem *selectItem = SCIMediaChromeTopBarButtonItem(@"circle_check", self, @selector(enterSelectionMode));
    [items addObject:selectItem];
    self.navigationItem.rightBarButtonItems = items;
}

- (void)setupBottomToolbar {
    [self installBottomToolbarIfNeeded];
    [self refreshBottomToolbarItems];
}

- (void)installBottomToolbarIfNeeded {
    UIView *hostView = self.navigationController.view ?: self.view;
    if (self.bottomBar && self.bottomBar.superview == hostView) {
        return;
    }

    if (self.bottomBar.superview) {
        [self.bottomBar removeFromSuperview];
        self.bottomBar = nil;
        self.bottomBarStack = nil;
    }

    self.bottomBar = SCIMediaChromeInstallBottomBar(hostView);
}

- (UIButton *)galleryBottomBarButtonWithResource:(NSString *)resourceName accessibility:(NSString *)label {
    return SCIMediaChromeBottomButton(resourceName, label);
}

- (void)refreshBottomToolbarItems {
    [self installBottomToolbarIfNeeded];
    [self.bottomBarStack removeFromSuperview];
    self.bottomBarStack = nil;

    UIButton *searchBtn = [self galleryBottomBarButtonWithResource:@"search" accessibility:SCILocalized(@"Search")];
    [searchBtn addTarget:self action:@selector(activateSearch) forControlEvents:UIControlEventTouchUpInside];

    if (self.selectionMode) {
        UIButton *shareBtn = [self galleryBottomBarButtonWithResource:@"share" accessibility:SCILocalized(@"Share selected")];
        [shareBtn addTarget:self action:@selector(shareSelectedFiles) forControlEvents:UIControlEventTouchUpInside];

        UIButton *saveBtn = [self galleryBottomBarButtonWithResource:@"download" accessibility:SCILocalized(@"Save to Photos")];
        [saveBtn addTarget:self action:@selector(saveSelectedFilesToPhotos) forControlEvents:UIControlEventTouchUpInside];

        UIButton *moveBtn = [self galleryBottomBarButtonWithResource:@"folder_move" accessibility:SCILocalized(@"Move selected")];
        [moveBtn addTarget:self action:@selector(moveSelectedFiles) forControlEvents:UIControlEventTouchUpInside];

        UIButton *favoriteBtn = [self galleryBottomBarButtonWithResource:@"heart" accessibility:SCILocalized(@"Favorite selected")];
        [favoriteBtn addTarget:self action:@selector(toggleFavoriteForSelectedFiles) forControlEvents:UIControlEventTouchUpInside];

        UIButton *deleteBtn = [self galleryBottomBarButtonWithResource:@"trash" accessibility:SCILocalized(@"Delete selected")];
        [deleteBtn addTarget:self action:@selector(deleteSelectedFiles) forControlEvents:UIControlEventTouchUpInside];
        deleteBtn.tintColor = [UIColor systemRedColor];

        self.bottomBarStack = SCIMediaChromeInstallBottomRow(self.bottomBar, @[shareBtn, saveBtn, moveBtn, favoriteBtn, deleteBtn]);
        return;
    }

    UIButton *filterBtn = [self galleryBottomBarButtonWithResource:@"filter" accessibility:SCILocalized(@"Filter")];
    [filterBtn addTarget:self action:@selector(presentFilter) forControlEvents:UIControlEventTouchUpInside];

    UIButton *sortBtn = [self galleryBottomBarButtonWithResource:@"sort" accessibility:SCILocalized(@"Sort")];
    [sortBtn addTarget:self action:@selector(presentSort) forControlEvents:UIControlEventTouchUpInside];

    NSString *toggleResource = self.viewMode == SCIGalleryViewModeGrid ? @"list" : @"grid";
    NSString *toggleAX = self.viewMode == SCIGalleryViewModeGrid ? SCILocalized(@"List view") : SCILocalized(@"Grid view");
    UIButton *toggleBtn = [self galleryBottomBarButtonWithResource:toggleResource accessibility:toggleAX];
    [toggleBtn addTarget:self action:@selector(toggleViewMode) forControlEvents:UIControlEventTouchUpInside];

    UIButton *folderBtn = [self galleryBottomBarButtonWithResource:@"folder" accessibility:SCILocalized(@"New Folder")];
    [folderBtn addTarget:self action:@selector(presentCreateFolder) forControlEvents:UIControlEventTouchUpInside];

    NSArray<UIView *> *row = self.pickerMode
        ? @[toggleBtn, sortBtn, filterBtn, searchBtn]
        : @[toggleBtn, sortBtn, filterBtn, folderBtn, searchBtn];

    self.bottomBarStack = SCIMediaChromeInstallBottomRow(self.bottomBar, row);
}

#pragma mark - Collection View

- (void)setupCollectionView {
    UICollectionViewLayout *layout = [self layoutForViewMode:self.viewMode];

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.backgroundColor = self.view.backgroundColor;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.alwaysBounceVertical = YES;
    _collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_collectionView registerClass:[SCIGalleryGridCell class] forCellWithReuseIdentifier:kGridCellID];
    [_collectionView registerClass:[SCIGalleryListCollectionCell class] forCellWithReuseIdentifier:kListCellID];
    [_collectionView registerClass:[SCIGalleryFolderCell class] forCellWithReuseIdentifier:kFolderCellID];
    [self.view addSubview:_collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [_collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateCollectionInsets];
}

- (void)updateCollectionInsets {
    CGFloat bottomInset = kGalleryBottomBarInsetHeight + self.view.safeAreaInsets.bottom;
    UIEdgeInsets contentInsets = self.collectionView.contentInset;
    contentInsets.bottom = bottomInset;
    self.collectionView.contentInset = contentInsets;

    UIEdgeInsets indicatorInsets = self.collectionView.scrollIndicatorInsets;
    indicatorInsets.bottom = bottomInset;
    self.collectionView.scrollIndicatorInsets = indicatorInsets;
}

- (UICollectionViewLayout *)layoutForViewMode:(SCIGalleryViewMode)mode {
    if (mode == SCIGalleryViewModeGrid) {
        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.minimumInteritemSpacing = kGridSpacing;
        layout.minimumLineSpacing = kGridSpacing;
        return layout;
    }

    // List mode = compositional list section. Native trailing-swipe-to-delete
    // (Mail/Files style) comes from `trailingSwipeActionsConfigurationProvider`,
    // which UIKit drives correctly w.r.t. vertical scroll, deceleration, and
    // tap suppression — none of which a hand-rolled pan can replicate.
    __weak typeof(self) weakSelf = self;
    UICollectionViewCompositionalLayoutSectionProvider provider =
        ^NSCollectionLayoutSection *(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> env) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        BOOL isFolderSection = [strongSelf showsFolderSection] && sectionIndex == 0;
        if (isFolderSection) {
            NSCollectionLayoutSize *size = [NSCollectionLayoutSize
                sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:88]];
            NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:size];
            NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size subitems:@[item]];
            NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
            section.contentInsets = NSDirectionalEdgeInsetsMake(10, 0, 6, 0);
            return section;
        }

        UICollectionLayoutListConfiguration *config = [[UICollectionLayoutListConfiguration alloc]
            initWithAppearance:UICollectionLayoutListAppearancePlain];
        config.showsSeparators = NO;
        config.backgroundColor = [UIColor clearColor];
        config.trailingSwipeActionsConfigurationProvider = ^UISwipeActionsConfiguration *(NSIndexPath *idx) {
            typeof(self) inner = weakSelf;
            if (!inner) return nil;
            SCIGalleryFile *file = [inner galleryFileForCollectionIndexPath:idx];
            if (!file) return nil;
            UIContextualAction *del = [UIContextualAction
                contextualActionWithStyle:UIContextualActionStyleDestructive
                                    title:SCILocalized(@"Delete")
                                  handler:^(__unused UIContextualAction *action,
                                            __unused __kindof UIView *view,
                                            void (^completion)(BOOL)) {
                [inner confirmDeleteFile:file];
                completion(YES);
            }];
            del.image = [UIImage systemImageNamed:@"trash.fill"];
            return [UISwipeActionsConfiguration configurationWithActions:@[del]];
        };
        return [NSCollectionLayoutSection sectionWithListConfiguration:config layoutEnvironment:env];
    };
    return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];
}

- (void)toggleViewMode {
    if (self.selectionMode) {
        [self exitSelectionMode];
    }
    self.viewMode = self.viewMode == SCIGalleryViewModeGrid ? SCIGalleryViewModeList : SCIGalleryViewModeGrid;
    [[NSUserDefaults standardUserDefaults] setInteger:self.viewMode forKey:kViewModeKey];

    UICollectionViewLayout *newLayout = [self layoutForViewMode:self.viewMode];
    [self.collectionView setCollectionViewLayout:newLayout animated:NO];
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
    [self updateEmptyState];
    [self refreshBottomToolbarItems];
}

#pragma mark - Empty State

- (void)setupEmptyState {
    _emptyStateView = [[UIView alloc] initWithFrame:CGRectZero];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.hidden = YES;
    [self.view addSubview:_emptyStateView];

    UIImage *emptyIconImage = [SCIAssetUtils instagramIconNamed:@"media_empty"
                                                      pointSize:96.0];
    UIImageView *icon = [[UIImageView alloc] initWithImage:emptyIconImage];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = [UIColor tertiaryLabelColor];
    [_emptyStateView addSubview:icon];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = SCILocalized(@"No files in Gallery");
    label.textColor = [UIColor secondaryLabelColor];
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    [_emptyStateView addSubview:label];
    _emptyStateLabel = label;

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectZero];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = SCILocalized(@"Save media from the preview screen\nto see it here.");
    subtitle.textColor = [UIColor tertiaryLabelColor];
    subtitle.font = [UIFont systemFontOfSize:14];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 0;
    [_emptyStateView addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
        [_emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40],
        [_emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-40],

        [icon.topAnchor constraintEqualToAnchor:_emptyStateView.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:64],
        [icon.heightAnchor constraintEqualToConstant:64],

        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:20],
        [label.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],

        [subtitle.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8],
        [subtitle.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],
        [subtitle.bottomAnchor constraintEqualToAnchor:_emptyStateView.bottomAnchor],
    ]];
}

- (void)updateEmptyState {
    NSInteger files = self.fetchedResultsController.fetchedObjects.count;
    NSInteger folders = [self showsFolderSection] ? self.subfolders.count : 0;
    BOOL hasFilters = self.filterTypes.count > 0 || self.filterSources.count > 0 || self.filterUsernames.count > 0 || self.filterFavoritesOnly;

    BOOL isEmpty = (files == 0 && folders == 0);
    self.emptyStateView.hidden = !isEmpty;
    self.collectionView.hidden = isEmpty;

    if (isEmpty && hasFilters) {
        self.emptyStateLabel.text = SCILocalized(@"No matching files");
    } else {
        self.emptyStateLabel.text = SCILocalized(@"No files in Gallery");
    }
}

#pragma mark - Fetched Results Controller

- (void)setupFetchedResultsController {
    NSFetchRequest *request = [self currentFetchRequest];

    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    _fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
                                                                    managedObjectContext:ctx
                                                                      sectionNameKeyPath:nil
                                                                               cacheName:nil];
    _fetchedResultsController.delegate = self;

    NSError *error;
    if (![_fetchedResultsController performFetch:&error]) {
        NSLog(@"[SCInsta Gallery] Fetch failed: %@", error);
    }
}

- (NSFetchRequest *)currentFetchRequest {
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    NSMutableArray<NSSortDescriptor *> *sortDescriptors = [[SCIGallerySortViewController sortDescriptorsForMode:self.sortMode] mutableCopy];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kFavoritesAtTopKey] && !self.filterFavoritesOnly) {
        [sortDescriptors insertObject:[NSSortDescriptor sortDescriptorWithKey:@"isFavorite" ascending:NO] atIndex:0];
    }
    request.sortDescriptors = sortDescriptors;
    NSPredicate *basePredicate = [SCIGalleryFilterViewController predicateForTypes:self.filterTypes
                                                                         sources:self.filterSources
                                                                       usernames:self.filterUsernames
                                                                   favoritesOnly:self.filterFavoritesOnly
                                                                      folderPath:self.currentFolderPath];
    NSMutableArray<NSPredicate *> *parts = [NSMutableArray array];
    if (basePredicate) [parts addObject:basePredicate];
    if (self.pickerMode && self.pickerAllowedMediaTypes.count > 0) {
        [parts addObject:[NSPredicate predicateWithFormat:@"mediaType IN %@", self.pickerAllowedMediaTypes]];
    }
    NSString *query = [self.searchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length > 0) {
        NSPredicate *searchPredicate = [NSPredicate predicateWithFormat:@"(sourceUsername CONTAINS[cd] %@) OR (customName CONTAINS[cd] %@) OR (relativePath CONTAINS[cd] %@)",
                                        query, query, query];
        [parts addObject:searchPredicate];
    }
    request.predicate = parts.count > 0 ? [NSCompoundPredicate andPredicateWithSubpredicates:parts] : nil;
    return request;
}

- (void)refetch {
    if (self.selectionMode) {
        [self.selectedFileIDs removeAllObjects];
    }
    NSFetchRequest *request = [self currentFetchRequest];
    _fetchedResultsController.fetchRequest.sortDescriptors = request.sortDescriptors;
    _fetchedResultsController.fetchRequest.predicate = request.predicate;

    NSError *error;
    if (![_fetchedResultsController performFetch:&error]) {
        NSLog(@"[SCInsta Gallery] Refetch failed: %@", error);
    }
    [self reloadSubfolders];
    [self.collectionView reloadData];
    [self updateEmptyState];
    [self refreshNavigationItems];
}

#pragma mark - Subfolders

- (void)reloadSubfolders {
    if (self.searchQuery.length > 0) {
        self.subfolders = @[];
        return;
    }
    // Subfolders are derived from distinct `folderPath` values on files whose path
    // is a descendant of the current path.
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.resultType = NSDictionaryResultType;
    req.propertiesToFetch = @[@"folderPath"];
    req.returnsDistinctResults = YES;

    NSString *base = self.currentFolderPath ?: @"";
    NSString *prefix = base.length == 0 ? @"/" : [base stringByAppendingString:@"/"];
    req.predicate = [NSPredicate predicateWithFormat:@"folderPath BEGINSWITH %@", prefix];

    NSArray<NSDictionary *> *results = [ctx executeFetchRequest:req error:nil];
    NSMutableSet<NSString *> *immediate = [NSMutableSet set];

    for (NSDictionary *row in results) {
        NSString *p = row[@"folderPath"];
        if (p.length <= prefix.length) continue;
        NSString *rest = [p substringFromIndex:prefix.length];
        NSRange slash = [rest rangeOfString:@"/"];
        NSString *folderName = slash.location == NSNotFound ? rest : [rest substringToIndex:slash.location];
        if (folderName.length == 0) continue;
        [immediate addObject:[prefix stringByAppendingString:folderName]];
    }

    self.subfolders = [[immediate allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    [self mergePlaceholderSubfolders];
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self reloadSubfolders];
    [self.collectionView reloadData];
    [self updateEmptyState];
    [self refreshNavigationItems];
}

#pragma mark - UICollectionViewDataSource

- (BOOL)showsFolderSection {
    return self.subfolders.count > 0 && self.searchQuery.length == 0;
}

- (BOOL)isFolderIndexPath:(NSIndexPath *)indexPath {
    return [self showsFolderSection] && indexPath.section == 0;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)cv {
    return [self showsFolderSection] ? 2 : 1;
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    if ([self showsFolderSection] && section == 0) return self.subfolders.count;
    NSArray *sections = self.fetchedResultsController.sections;
    if (sections.count == 0) return 0;
    return ((id<NSFetchedResultsSectionInfo>)sections[0]).numberOfObjects;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv
                            cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isFolderIndexPath:indexPath]) {
        SCIGalleryFolderCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kFolderCellID forIndexPath:indexPath];
        NSString *path = self.subfolders[indexPath.item];
        NSInteger itemCount = SCIGalleryItemCountForFolderPath([SCIGalleryCoreDataStack shared].viewContext, path);
        [cell configureWithFolderName:[path lastPathComponent] itemCount:itemCount];
        return cell;
    }

    NSIndexPath *filePath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    SCIGalleryFile *file = [self.fetchedResultsController objectAtIndexPath:filePath];

    if (self.viewMode == SCIGalleryViewModeGrid) {
        SCIGalleryGridCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kGridCellID forIndexPath:indexPath];
        [cell configureWithGalleryFile:file
                       selectionMode:self.selectionMode
                            selected:[self.selectedFileIDs containsObject:file.identifier]];
        return cell;
    }

    SCIGalleryListCollectionCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kListCellID forIndexPath:indexPath];
    [cell configureWithGalleryFile:file
                   selectionMode:self.selectionMode
                        selected:[self.selectedFileIDs containsObject:file.identifier]];
    [cell setMoreActionsMenu:self.selectionMode ? nil : [self fileActionsMenuForFile:file]];
    return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)cv
                  layout:(UICollectionViewLayout *)layout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = cv.bounds.size.width;
    if ([self isFolderIndexPath:indexPath]) {
        return CGSizeMake(width, 88);
    }
    if (self.viewMode == SCIGalleryViewModeGrid) {
        CGFloat totalSpacing = kGridSpacing * (kGridColumns - 1);
        CGFloat side = (width - totalSpacing) / kGridColumns;
        return CGSizeMake(side, side);
    }
    return CGSizeMake(width, 88);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)cv
                        layout:(UICollectionViewLayout *)layout
        insetForSectionAtIndex:(NSInteger)section {
    if ([self showsFolderSection] && section == 0 && self.subfolders.count > 0) {
        return UIEdgeInsetsMake(10, 0, 6, 0);
    }
    return UIEdgeInsetsZero;
}

- (CGFloat)collectionView:(UICollectionView *)cv
                   layout:(UICollectionViewLayout *)layout
 minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    if ([self showsFolderSection] && section == 0) {
        return 0;
    }
    return self.viewMode == SCIGalleryViewModeGrid ? kGridSpacing : 0;
}

- (CGFloat)collectionView:(UICollectionView *)cv
                   layout:(UICollectionViewLayout *)layout
 minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    if ([self showsFolderSection] && section == 0) {
        return 0;
    }
    return self.viewMode == SCIGalleryViewModeGrid ? kGridSpacing : 0;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [cv deselectItemAtIndexPath:indexPath animated:YES];

    if ([self isFolderIndexPath:indexPath]) {
        if (self.selectionMode) {
            return;
        }
        NSString *subfolderPath = self.subfolders[indexPath.item];
        SCIGalleryViewController *child = [[SCIGalleryViewController alloc] initWithFolderPath:subfolderPath];
        child.pickerMode = self.pickerMode;
        child.pickerAllowedMediaTypes = self.pickerAllowedMediaTypes;
        child.pickerCompletion = self.pickerCompletion;
        child.pickerTitleOverride = self.pickerTitleOverride;
        [self.navigationController pushViewController:child animated:YES];
        return;
    }

    NSIndexPath *filePath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    SCIGalleryFile *selectedFile = [self.fetchedResultsController objectAtIndexPath:filePath];

    if (self.pickerMode) {
        void (^cb)(NSURL *, SCIGalleryFile *) = self.pickerCompletion;
        UINavigationController *nav = self.navigationController;
        [nav dismissViewControllerAnimated:YES completion:^{
            if (cb) cb([selectedFile fileURL], selectedFile);
        }];
        // Clear so dismissal-by-cancel doesn't double-fire.
        for (UIViewController *vc in nav.viewControllers) {
            if ([vc isKindOfClass:[SCIGalleryViewController class]]) {
                ((SCIGalleryViewController *)vc).pickerCompletion = nil;
            }
        }
        return;
    }

    if (self.selectionMode) {
        [self toggleSelectionForFile:selectedFile];
        return;
    }

    NSArray *allFiles = self.fetchedResultsController.fetchedObjects;
    NSInteger idx = [allFiles indexOfObject:selectedFile];
    if (idx == NSNotFound) idx = 0;
    NSMutableArray<SCIMediaViewerItem *> *items = [NSMutableArray arrayWithCapacity:allFiles.count];
    for (SCIGalleryFile *f in allFiles) {
        NSURL *fileURL = [f fileURL];
        SCIMediaViewerItem *it = nil;
        switch (f.mediaType) {
            case SCIGalleryMediaTypeVideo:
                it = [SCIMediaViewerItem itemWithVideoURL:fileURL photoURL:nil caption:nil];
                break;
            case SCIGalleryMediaTypeAudio:
                it = [SCIMediaViewerItem itemWithAudioURL:fileURL caption:nil];
                break;
            case SCIGalleryMediaTypeGIF:
                it = [SCIMediaViewerItem itemWithAnimatedImageURL:fileURL caption:nil];
                break;
            case SCIGalleryMediaTypeImage:
            default:
                it = [SCIMediaViewerItem itemWithVideoURL:nil photoURL:fileURL caption:nil];
                break;
        }
        if (it) [items addObject:it];
    }
    if (items.count) [SCIMediaViewer showItems:items startIndex:(NSUInteger)MIN(idx, (NSInteger)items.count - 1) shareSheetOnly:YES];
}

- (NSArray<SCIGalleryFile *> *)visibleGalleryFiles {
    return self.fetchedResultsController.fetchedObjects ?: @[];
}

- (SCIGalleryFile *)galleryFileForCollectionIndexPath:(NSIndexPath *)indexPath {
    if ([self isFolderIndexPath:indexPath]) {
        return nil;
    }
    NSIndexPath *filePath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    return [self.fetchedResultsController objectAtIndexPath:filePath];
}


- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv
    contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath
                                         point:(CGPoint)point {
    if (self.selectionMode) {
        return nil;
    }
    if ([self isFolderIndexPath:indexPath]) {
        NSString *folder = self.subfolders[indexPath.item];
        return [self contextMenuForFolder:folder];
    }

    NSIndexPath *filePath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    SCIGalleryFile *file = [self.fetchedResultsController objectAtIndexPath:filePath];
    return [self contextMenuForFile:file];
}

#pragma mark - Search

- (void)activateSearch {
    UISearchController *sc = self.searchController;
    if (!sc) return;

    // Reveal the navigation bar's search bar by scrolling to the top of the
    // content; with hidesSearchBarWhenScrolling=YES the search bar otherwise
    // sits collapsed and becomeFirstResponder lands on a hidden view.
    UICollectionView *cv = self.collectionView;
    CGFloat revealOffsetY = -cv.adjustedContentInset.top;
    if (cv.contentOffset.y > revealOffsetY) {
        [cv setContentOffset:CGPointMake(cv.contentOffset.x, revealOffsetY) animated:NO];
    }
    [cv layoutIfNeeded];
    [self.navigationController.navigationBar layoutIfNeeded];
    [self.view layoutIfNeeded];

    sc.active = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!sc.active) sc.active = YES;
        [sc.searchBar becomeFirstResponder];
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *nextQuery = searchController.searchBar.text ?: @"";
    if ((self.searchQuery ?: @"").length == nextQuery.length && [(self.searchQuery ?: @"") isEqualToString:nextQuery]) {
        return;
    }
    self.searchQuery = nextQuery;
    [self refetch];
}

#pragma mark - Sort / Filter

// Single sheet helper used for both sort + filter so they always look + feel
// identical. The base VC owns its own custom card transition (so iOS 26's
// liquid-glass sheet material can't bleed in) and exposes preferredCardHeight
// for per-VC sizing.
- (void)presentGallerySheet:(SCIGallerySheetViewController *)contentVC {
    // Sheet base animates the card in itself during viewWillAppear, so we
    // present unanimated to skip the system transition.
    [self presentViewController:contentVC animated:NO completion:nil];
}

- (void)presentSort {
    SCIGallerySortViewController *vc = [[SCIGallerySortViewController alloc] init];
    vc.delegate = self;
    vc.currentSortMode = self.sortMode;
    [self presentGallerySheet:vc];
}

- (void)presentFilter {
    SCIGalleryFilterViewController *vc = [[SCIGalleryFilterViewController alloc] init];
    vc.delegate = self;
    vc.filterTypes = self.filterTypes;
    vc.filterSources = self.filterSources;
    vc.filterUsernames = self.filterUsernames;
    vc.filterFavoritesOnly = self.filterFavoritesOnly;
    [self presentGallerySheet:vc];
}

- (void)sortController:(SCIGallerySortViewController *)controller didSelectSortMode:(SCIGallerySortMode)mode {
    self.sortMode = mode;
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kSortModeKey];
    [self refetch];
}

- (void)filterController:(SCIGalleryFilterViewController *)controller
           didApplyTypes:(NSSet<NSNumber *> *)types
                 sources:(NSSet<NSNumber *> *)sources
               usernames:(NSSet<NSString *> *)usernames
           favoritesOnly:(BOOL)favoritesOnly {
    self.filterTypes = [types mutableCopy];
    self.filterSources = [sources mutableCopy];
    self.filterUsernames = [usernames mutableCopy];
    self.filterFavoritesOnly = favoritesOnly;
    [self refetch];
}

- (void)filterControllerDidClear:(SCIGalleryFilterViewController *)controller {
    [self.filterTypes removeAllObjects];
    [self.filterSources removeAllObjects];
    [self.filterUsernames removeAllObjects];
    self.filterFavoritesOnly = NO;
    [self refetch];
}

- (void)handleGalleryPreferencesChanged:(NSNotification *)note {
    (void)note;
    [self refetch];
}

#pragma mark - Settings

- (void)pushSettings {
    SCIGallerySettingsViewController *vc = [[SCIGallerySettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
