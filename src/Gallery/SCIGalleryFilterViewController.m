#import "SCIGalleryFilterViewController.h"
#import "SCIGalleryChip.h"
#import "SCIGalleryCoreDataStack.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"

@interface SCIGalleryFilterViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UIControl *favoritesRow;
@property (nonatomic, strong) UIImageView *favoritesIcon;
@property (nonatomic, strong) UILabel *favoritesLabel;
@property (nonatomic, strong) UISwitch *favoritesSwitch;
@property (nonatomic, strong) UIControl *clearRow;
@property (nonatomic, strong) UIImageView *clearIcon;
@property (nonatomic, strong) UILabel *clearLabel;
@property (nonatomic, strong) NSMutableArray<SCIGalleryChip *> *typeChips;
@property (nonatomic, strong) NSMutableArray<SCIGalleryChip *> *sourceChips;
@property (nonatomic, strong) NSMutableArray<SCIGalleryChip *> *usernameChips;
@property (nonatomic, copy) NSArray<NSString *> *allUsernames;
@property (nonatomic, strong) UISearchBar *usernameSearchBar;
@property (nonatomic, strong) UIStackView *usernameStrip;
@end

@implementation SCIGalleryFilterViewController

+ (NSPredicate *)predicateForTypes:(NSSet<NSNumber *> *)types
                           sources:(NSSet<NSNumber *> *)sources
                         usernames:(NSSet<NSString *> *)usernames
                     favoritesOnly:(BOOL)favoritesOnly
                        folderPath:(NSString *)folderPath {
    NSMutableArray<NSPredicate *> *parts = [NSMutableArray new];
    if (types.count > 0) {
        NSArray *typeList = [types.allObjects sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]];
        [parts addObject:[NSPredicate predicateWithFormat:@"mediaType IN %@", typeList]];
    }
    if (sources.count > 0) {
        NSArray *sourceList = [sources.allObjects sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]];
        [parts addObject:[NSPredicate predicateWithFormat:@"source IN %@", sourceList]];
    }
    if (usernames.count > 0) {
        [parts addObject:[NSPredicate predicateWithFormat:@"sourceUsername IN %@", usernames.allObjects]];
    }
    if (favoritesOnly) {
        [parts addObject:[NSPredicate predicateWithFormat:@"isFavorite == %@", @(YES)]];
    }
    if (folderPath.length > 0) {
        [parts addObject:[NSPredicate predicateWithFormat:@"folderPath == %@", folderPath]];
    } else {
        [parts addObject:[NSPredicate predicateWithFormat:@"(folderPath == nil) OR (folderPath == %@)", @""]];
    }
    if (parts.count == 0) return nil;
    return [NSCompoundPredicate andPredicateWithSubpredicates:parts];
}

- (instancetype)init {
    if ((self = [super init])) {
        _filterTypes = [NSMutableSet new];
        _filterSources = [NSMutableSet new];
        _filterUsernames = [NSMutableSet new];
        _typeChips = [NSMutableArray new];
        _sourceChips = [NSMutableArray new];
        _usernameChips = [NSMutableArray new];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.sheetTitle = SCILocalized(@"Filter");

    [self addCardRow:[self buildFavoritesRow]];

    [self addSectionTitle:SCILocalized(@"Type")];
    [self addContentView:[self buildTypeRow]];

    [self addSectionTitle:SCILocalized(@"Source")];
    [self addContentView:[self buildSourceGrid]];

    self.allUsernames = [self distinctUsernamesFromGallery];
    if (self.allUsernames.count > 0) {
        [self addSectionTitle:SCILocalized(@"Source user")];
        // Search field appears only when the list is long enough to merit it.
        if (self.allUsernames.count > 8) {
            [self addContentView:[self buildUsernameSearchBar]];
        }
        [self addContentView:[self buildUsernameStrip:self.allUsernames]];
    }

    [self addSectionTitle:SCILocalized(@"Options")];
    [self addCardRow:[self buildClearRow]];

    [self updateClearRowState];
}

- (NSArray<NSString *> *)distinctUsernamesFromGallery {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.predicate = [NSPredicate predicateWithFormat:@"sourceUsername != nil AND sourceUsername != %@", @""];
    req.propertiesToFetch = @[@"sourceUsername"];
    req.returnsDistinctResults = YES;
    req.resultType = NSDictionaryResultType;
    NSArray *rows = [ctx executeFetchRequest:req error:nil] ?: @[];
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (NSDictionary *r in rows) {
        NSString *u = r[@"sourceUsername"];
        if ([u isKindOfClass:[NSString class]] && u.length) [set addObject:u];
    }
    NSArray *sorted = [set.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a caseInsensitiveCompare:b];
    }];
    return sorted;
}

// MARK: - Builders

- (UIControl *)buildFavoritesRow {
    UIControl *row = [UIControl new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor tertiarySystemFillColor];
    row.layer.cornerRadius = 14;
    row.layer.cornerCurve = kCACornerCurveContinuous;
    [row.heightAnchor constraintEqualToConstant:50].active = YES;

    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:icon];
    self.favoritesIcon = icon;

    UILabel *label = [UILabel new];
    label.text = SCILocalized(@"Favorites only");
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    self.favoritesLabel = label;

    UISwitch *sw = [UISwitch new];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    sw.on = self.filterFavoritesOnly;
    [sw addTarget:self action:@selector(favoritesSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    self.favoritesSwitch = sw;

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
        [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-8],
    ]];

    self.favoritesRow = row;
    [self updateFavoritesAppearance];
    return row;
}

- (UIView *)buildTypeRow {
    UIStackView *grid = [UIStackView new];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 8;

    NSArray<NSDictionary *> *defs = @[
        @{@"label": SCILocalized(@"Images"), @"symbol": @"photo", @"tag": @(SCIGalleryMediaTypeImage)},
        @{@"label": SCILocalized(@"Videos"), @"symbol": @"video", @"tag": @(SCIGalleryMediaTypeVideo)},
        @{@"label": SCILocalized(@"Audio"),  @"symbol": @"waveform", @"tag": @(SCIGalleryMediaTypeAudio)},
        @{@"label": SCILocalized(@"GIFs"),   @"symbol": @"ig_icon_gif_outline_24", @"tag": @(SCIGalleryMediaTypeGIF)},
    ];
    UIStackView *currentRow = nil;
    for (NSUInteger i = 0; i < defs.count; i++) {
        if (i % 2 == 0) {
            currentRow = [UIStackView new];
            currentRow.axis = UILayoutConstraintAxisHorizontal;
            currentRow.spacing = 8;
            currentRow.distribution = UIStackViewDistributionFillEqually;
            [grid addArrangedSubview:currentRow];
        }
        NSDictionary *def = defs[i];
        NSNumber *tag = def[@"tag"];
        SCIGalleryChip *chip = [SCIGalleryChip chipWithTitle:def[@"label"] symbol:def[@"symbol"]];
        chip.tag = tag.integerValue;
        chip.onState = [self.filterTypes containsObject:tag];
        [chip addTarget:self action:@selector(typeChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [chip.heightAnchor constraintEqualToConstant:44].active = YES;
        [currentRow addArrangedSubview:chip];
        [self.typeChips addObject:chip];
    }
    while (currentRow.arrangedSubviews.count % 2 != 0) {
        UIView *spacer = [UIView new];
        [currentRow addArrangedSubview:spacer];
    }
    return grid;
}

- (UIView *)buildSourceGrid {
    UIStackView *grid = [UIStackView new];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 8;

    NSArray<NSNumber *> *sources = @[
        @(SCIGallerySourceFeed),
        @(SCIGallerySourceStories),
        @(SCIGallerySourceReels),
        @(SCIGallerySourceProfile),
        @(SCIGallerySourceDMs),
        @(SCIGallerySourceInstants),
        @(SCIGallerySourceNotes),
        @(SCIGallerySourceComments),
        @(SCIGallerySourceThumbnail),
    ];
    UIStackView *currentRow = nil;
    for (NSUInteger i = 0; i < sources.count; i++) {
        if (i % 2 == 0) {
            currentRow = [UIStackView new];
            currentRow.axis = UILayoutConstraintAxisHorizontal;
            currentRow.spacing = 8;
            currentRow.distribution = UIStackViewDistributionFillEqually;
            [grid addArrangedSubview:currentRow];
        }
        SCIGallerySource src = (SCIGallerySource)[sources[i] integerValue];
        SCIGalleryChip *chip = [SCIGalleryChip chipWithTitle:[SCIGalleryFile labelForSource:src]
                                                       symbol:[self systemSymbolForSource:src]];
        chip.tag = src;
        chip.onState = [self.filterSources containsObject:@(src)];
        [chip addTarget:self action:@selector(sourceChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [chip.heightAnchor constraintEqualToConstant:44].active = YES;
        [currentRow addArrangedSubview:chip];
        [self.sourceChips addObject:chip];
    }
    while (currentRow.arrangedSubviews.count % 2 != 0) {
        UIView *spacer = [UIView new];
        [currentRow addArrangedSubview:spacer];
    }
    return grid;
}

- (UISearchBar *)buildUsernameSearchBar {
    UISearchBar *bar = [UISearchBar new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.placeholder = SCILocalized(@"Search users");
    bar.delegate = self;
    bar.searchBarStyle = UISearchBarStyleMinimal;
    bar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    bar.autocorrectionType = UITextAutocorrectionTypeNo;
    [bar.heightAnchor constraintEqualToConstant:36].active = YES;
    self.usernameSearchBar = bar;
    return bar;
}

- (UIView *)buildUsernameStrip:(NSArray<NSString *> *)usernames {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsHorizontalScrollIndicator = NO;
    [scroll.heightAnchor constraintEqualToConstant:44].active = YES;

    UIStackView *strip = [UIStackView new];
    strip.translatesAutoresizingMaskIntoConstraints = NO;
    strip.axis = UILayoutConstraintAxisHorizontal;
    strip.alignment = UIStackViewAlignmentCenter;
    strip.spacing = 8;
    [scroll addSubview:strip];

    [NSLayoutConstraint activateConstraints:@[
        [strip.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [strip.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [strip.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [strip.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [strip.heightAnchor constraintEqualToAnchor:scroll.heightAnchor],
    ]];
    self.usernameStrip = strip;
    [self rebuildUsernameChipsForUsernames:usernames];
    return scroll;
}

- (void)rebuildUsernameChipsForUsernames:(NSArray<NSString *> *)usernames {
    for (UIView *v in [self.usernameStrip.arrangedSubviews copy]) {
        [self.usernameStrip removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [self.usernameChips removeAllObjects];
    for (NSString *username in usernames) {
        SCIGalleryChip *chip = [SCIGalleryChip chipWithTitle:[@"@" stringByAppendingString:username] symbol:@"at"];
        chip.accessibilityIdentifier = username;
        chip.onState = [self.filterUsernames containsObject:username];
        [chip addTarget:self action:@selector(usernameChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.usernameStrip addArrangedSubview:chip];
        [self.usernameChips addObject:chip];
    }
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    NSString *q = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *filtered = self.allUsernames;
    if (q.length > 0) {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"SELF CONTAINS[cd] %@", q];
        filtered = [self.allUsernames filteredArrayUsingPredicate:pred];
    }
    [self rebuildUsernameChipsForUsernames:filtered];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [self rebuildUsernameChipsForUsernames:self.allUsernames];
    [searchBar resignFirstResponder];
}

- (UIControl *)buildClearRow {
    UIControl *row = [UIControl new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor tertiarySystemFillColor];
    row.layer.cornerRadius = 14;
    row.layer.cornerCurve = kCACornerCurveContinuous;
    [row.heightAnchor constraintEqualToConstant:50].active = YES;
    [row addTarget:self action:@selector(clearFilters) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [UIImage systemImageNamed:@"xmark.circle"];
    [row addSubview:icon];
    self.clearIcon = icon;

    UILabel *label = [UILabel new];
    label.text = SCILocalized(@"Clear filters");
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    self.clearLabel = label;

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-12],
    ]];
    self.clearRow = row;
    return row;
}

- (NSString *)systemSymbolForSource:(SCIGallerySource)source {
    switch (source) {
        case SCIGallerySourceFeed:      return @"rectangle.stack";
        case SCIGallerySourceStories:   return @"circle.dashed";
        case SCIGallerySourceReels:     return @"film.stack";
        case SCIGallerySourceProfile:   return @"person.crop.circle";
        case SCIGallerySourceDMs:       return @"bubble.left.and.bubble.right";
        case SCIGallerySourceThumbnail: return @"photo.on.rectangle.angled";
        case SCIGallerySourceNotes:     return @"note.text";
        case SCIGallerySourceComments:  return @"text.bubble";
        case SCIGallerySourceInstants:  return @"ig_icon_app_instants_outline_24";
        case SCIGallerySourceOther:
        default:                        return @"photo.on.rectangle";
    }
}

// MARK: - Actions

- (void)typeChipTapped:(SCIGalleryChip *)chip {
    NSNumber *tag = @(chip.tag);
    if ([self.filterTypes containsObject:tag]) [self.filterTypes removeObject:tag];
    else [self.filterTypes addObject:tag];
    [chip setOnState:!chip.isOnState animated:YES];
    [self notify];
}

- (void)sourceChipTapped:(SCIGalleryChip *)chip {
    NSNumber *tag = @(chip.tag);
    if ([self.filterSources containsObject:tag]) [self.filterSources removeObject:tag];
    else [self.filterSources addObject:tag];
    [chip setOnState:!chip.isOnState animated:YES];
    [self notify];
}

- (void)usernameChipTapped:(SCIGalleryChip *)chip {
    NSString *u = chip.accessibilityIdentifier;
    if (!u.length) return;
    if ([self.filterUsernames containsObject:u]) [self.filterUsernames removeObject:u];
    else [self.filterUsernames addObject:u];
    [chip setOnState:!chip.isOnState animated:YES];
    [self notify];
}

- (void)favoritesSwitchChanged:(UISwitch *)sw {
    self.filterFavoritesOnly = sw.isOn;
    [self updateFavoritesAppearance];
    [self notify];
}

- (void)clearFilters {
    if (![self hasActiveFilters]) return;
    [self.filterTypes removeAllObjects];
    [self.filterSources removeAllObjects];
    [self.filterUsernames removeAllObjects];
    self.filterFavoritesOnly = NO;
    self.favoritesSwitch.on = NO;
    [self updateFavoritesAppearance];
    for (SCIGalleryChip *c in self.typeChips) [c setOnState:NO animated:YES];
    for (SCIGalleryChip *c in self.sourceChips) [c setOnState:NO animated:YES];
    for (SCIGalleryChip *c in self.usernameChips) [c setOnState:NO animated:YES];
    if ([self.delegate respondsToSelector:@selector(filterControllerDidClear:)]) {
        [self.delegate filterControllerDidClear:self];
    } else {
        [self notify];
    }
    [self updateClearRowState];
}

// MARK: - Appearance

- (void)updateFavoritesAppearance {
    BOOL on = self.filterFavoritesOnly;
    UIColor *accent = [SCIUtils SCIColor_InstagramFavorite];
    self.favoritesRow.backgroundColor = on
        ? [accent colorWithAlphaComponent:0.18]
        : [UIColor tertiarySystemFillColor];
    self.favoritesIcon.image = [UIImage systemImageNamed:on ? @"heart.fill" : @"heart"];
    self.favoritesIcon.tintColor = on ? accent : [UIColor secondaryLabelColor];
}

- (void)updateClearRowState {
    BOOL active = [self hasActiveFilters];
    self.clearRow.userInteractionEnabled = active;
    self.clearRow.backgroundColor = active
        ? [[UIColor systemRedColor] colorWithAlphaComponent:0.14]
        : [UIColor tertiarySystemFillColor];
    self.clearIcon.tintColor = active ? [UIColor systemRedColor] : [UIColor tertiaryLabelColor];
    self.clearLabel.textColor = active ? [UIColor systemRedColor] : [UIColor tertiaryLabelColor];
}

- (BOOL)hasActiveFilters {
    return self.filterTypes.count > 0
        || self.filterSources.count > 0
        || self.filterUsernames.count > 0
        || self.filterFavoritesOnly;
}

- (void)notify {
    [self updateClearRowState];
    if ([self.delegate respondsToSelector:@selector(filterController:didApplyTypes:sources:usernames:favoritesOnly:)]) {
        [self.delegate filterController:self
                          didApplyTypes:[self.filterTypes copy]
                                sources:[self.filterSources copy]
                              usernames:[self.filterUsernames copy]
                          favoritesOnly:self.filterFavoritesOnly];
    }
}

@end
