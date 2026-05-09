#import "SCIHomeShortcutConfigViewController.h"
#import "../Utils.h"
#import "../Features/Feed/SCIHomeShortcutCatalog.h"

#pragma mark - Persistence

// New catalog entries get appended (disabled). Stale ones get dropped.
static NSMutableArray<NSMutableDictionary *> *sciLoadOrderedActions(void) {
    NSArray *stored = [SCIUtils getArrayPref:kSCIHomeShortcutActionsPrefKey];
    NSMutableArray<NSMutableDictionary *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSDictionary *row in stored) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        NSString *aid = row[@"id"];
        if (![aid isKindOfClass:[NSString class]] || !aid.length) continue;
        if (![SCIHomeShortcutCatalog actionForID:aid]) continue;
        if ([seen containsObject:aid]) continue;
        [seen addObject:aid];
        [out addObject:[@{ @"id": aid, @"enabled": @([row[@"enabled"] boolValue]) } mutableCopy]];
    }
    for (SCIHomeShortcutAction *a in [SCIHomeShortcutCatalog allActions]) {
        if ([seen containsObject:a.actionID]) continue;
        [out addObject:[@{ @"id": a.actionID, @"enabled": @(NO) } mutableCopy]];
    }
    return out;
}

static void sciSaveOrderedActions(NSArray<NSDictionary *> *actions) {
    [SCIUtils setPref:[actions copy] forKey:kSCIHomeShortcutActionsPrefKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIHomeShortcutConfigDidChangeNotification object:nil];
}

static NSString *sciCurrentIcon(void) {
    NSString *cur = [SCIUtils getStringPref:kSCIHomeShortcutIconPrefKey];
    return cur.length ? cur : @"auto";
}

#pragma mark - Icon picker (sub-page)

@interface SCIHomeShortcutIconPickerCell : UICollectionViewCell
- (void)configureWithSymbol:(NSString *)symbol selected:(BOOL)selected;
@end

@interface SCIHomeShortcutIconPickerCell ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *checkBadge;
@property (nonatomic, strong) UILabel *autoLabel;
@end

@implementation SCIHomeShortcutIconPickerCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.contentView.layer.cornerRadius = 16;
    self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    self.contentView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.contentView.layer.borderColor = [UIColor separatorColor].CGColor;
    self.contentView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeCenter;
    _iconView.tintColor = [UIColor labelColor];
    [self.contentView addSubview:_iconView];

    _autoLabel = [UILabel new];
    _autoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _autoLabel.text = SCILocalized(@"Auto");
    _autoLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _autoLabel.textColor = [UIColor secondaryLabelColor];
    _autoLabel.hidden = YES;
    [self.contentView addSubview:_autoLabel];

    UIImageSymbolConfiguration *checkCfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
    _checkBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:checkCfg]];
    _checkBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _checkBadge.tintColor = [UIColor systemBlueColor];
    _checkBadge.backgroundColor = [UIColor whiteColor];
    _checkBadge.layer.cornerRadius = 9;
    _checkBadge.layer.masksToBounds = YES;
    _checkBadge.hidden = YES;
    [self.contentView addSubview:_checkBadge];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-6],
        [_autoLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [_autoLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:4],
        [_checkBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
        [_checkBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6],
        [_checkBadge.widthAnchor constraintEqualToConstant:18],
        [_checkBadge.heightAnchor constraintEqualToConstant:18],
    ]];
    return self;
}

- (void)applySelected:(BOOL)selected {
    self.checkBadge.hidden = !selected;
    UIColor *iconTint = selected ? [UIColor systemBlueColor] : [UIColor labelColor];
    self.iconView.tintColor = iconTint;
    self.autoLabel.textColor = selected ? [UIColor systemBlueColor] : [UIColor secondaryLabelColor];
    self.contentView.backgroundColor = selected
        ? [[UIColor systemBlueColor] colorWithAlphaComponent:0.16]
        : [UIColor secondarySystemGroupedBackgroundColor];
    self.contentView.layer.borderColor = (selected ? [UIColor systemBlueColor] : [UIColor separatorColor]).CGColor;
    self.contentView.layer.borderWidth = selected ? 2.0 : (1.0 / UIScreen.mainScreen.scale);
}

- (void)configureWithSymbol:(NSString *)symbol selected:(BOOL)selected {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
    BOOL isAuto = [symbol isEqualToString:@"auto"];
    self.iconView.image = [UIImage systemImageNamed:(isAuto ? @"wand.and.stars" : symbol) withConfiguration:cfg];
    self.autoLabel.hidden = !isAuto;
    [self applySelected:selected];
}

- (void)prepareForReuse { [super prepareForReuse]; [self applySelected:NO]; }

@end


@interface SCIHomeShortcutIconPickerViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSArray<NSString *> *icons;
@end

@implementation SCIHomeShortcutIconPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SCILocalized(@"Icon");
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    NSMutableArray *valid = [NSMutableArray arrayWithObject:@"auto"];
    for (NSString *name in [SCIHomeShortcutCatalog availableIcons]) {
        if ([UIImage systemImageNamed:name]) [valid addObject:name];
    }
    self.icons = valid;

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 10;
    layout.minimumLineSpacing = 10;
    layout.sectionInset = UIEdgeInsetsMake(16, 16, 24, 16);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[SCIHomeShortcutIconPickerCell class] forCellWithReuseIdentifier:@"icon"];
    [self.view addSubview:self.collectionView];
    [NSLayoutConstraint activateConstraints:@[
        [self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSUInteger idx = [self.icons indexOfObject:sciCurrentIcon()];
    if (idx != NSNotFound && idx > 4) {
        [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:idx inSection:0]
                                    atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                            animated:NO];
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
    CGFloat available = self.view.bounds.size.width - 32;
    NSInteger cols = MAX(4, (NSInteger)floor(available / 76.0));
    CGFloat side = floor((available - layout.minimumInteritemSpacing * (cols - 1)) / cols);
    layout.itemSize = CGSizeMake(side, side);
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.icons.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    SCIHomeShortcutIconPickerCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"icon" forIndexPath:ip];
    NSString *name = self.icons[ip.item];
    [cell configureWithSymbol:name selected:[name isEqualToString:sciCurrentIcon()]];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSString *picked = self.icons[ip.item];
    if ([picked isEqualToString:sciCurrentIcon()]) {
        [cv deselectItemAtIndexPath:ip animated:YES];
        return;
    }
    [SCIUtils setPref:picked forKey:kSCIHomeShortcutIconPrefKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIHomeShortcutConfigDidChangeNotification object:nil];
    [cv reloadData];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

@end


#pragma mark - Main config VC

@interface SCIHomeShortcutConfigViewController () <UITableViewDragDelegate, UITableViewDropDelegate>
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *actions;
@end

@implementation SCIHomeShortcutConfigViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (!self) return nil;
    self.title = SCILocalized(@"Home shortcut button");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.actions = sciLoadOrderedActions();
    self.tableView.dragInteractionEnabled = YES;
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"row"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData]; // refresh icon row title on return from picker
}

#pragma mark - Sections

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : (NSInteger)self.actions.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? SCILocalized(@"Behavior") : SCILocalized(@"Actions");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return SCILocalized(@"Adds a button to the home top bar, right of the create-post +. Off entirely turns it off.");
    }
    return SCILocalized(@"Drag the ≡ handle to reorder. Toggle a row off to hide that destination. With one action enabled tapping fires it; with two or more, tapping presents a menu.");
}

#pragma mark - Cells

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) return [self behaviorCellForRow:ip.row];
    return [self actionCellForRow:ip.row];
}

- (UITableViewCell *)behaviorCellForRow:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"row"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (row == 0) {
        cell.textLabel.text = SCILocalized(@"Show button");
        UISwitch *sw = [UISwitch new];
        sw.on = [SCIUtils getBoolPref:kSCIHomeShortcutEnabledPrefKey];
        [sw addTarget:self action:@selector(masterToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.imageView.image = [UIImage systemImageNamed:@"power"];
        return cell;
    }
    NSString *cur = sciCurrentIcon();
    BOOL isAuto = [cur isEqualToString:@"auto"];
    cell.textLabel.text = SCILocalized(@"Icon");
    cell.detailTextLabel.text = isAuto ? SCILocalized(@"Auto") : cur;
    cell.imageView.image = [UIImage systemImageNamed:(isAuto ? @"wand.and.stars" : cur)];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)actionCellForRow:(NSInteger)row {
    NSDictionary *rowDict = self.actions[row];
    SCIHomeShortcutAction *entry = [SCIHomeShortcutCatalog actionForID:rowDict[@"id"]];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = nil;
    cell.imageView.image = nil;

    UIImageView *grip = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
    grip.translatesAutoresizingMaskIntoConstraints = NO;
    grip.tintColor = [UIColor tertiaryLabelColor];
    grip.contentMode = UIViewContentModeCenter;

    UIImageView *icon = [[UIImageView alloc] initWithImage:entry.symbol ? [UIImage systemImageNamed:entry.symbol] : nil];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor labelColor];
    icon.contentMode = UIViewContentModeCenter;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = entry.title ?: rowDict[@"id"];
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    UISwitch *sw = [UISwitch new];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    sw.on = [rowDict[@"enabled"] boolValue];
    sw.accessibilityIdentifier = entry.actionID;
    [sw addTarget:self action:@selector(actionToggleChanged:) forControlEvents:UIControlEventValueChanged];

    [cell.contentView addSubview:grip];
    [cell.contentView addSubview:icon];
    [cell.contentView addSubview:title];
    [cell.contentView addSubview:sw];

    [NSLayoutConstraint activateConstraints:@[
        [grip.leadingAnchor  constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [grip.centerYAnchor  constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [grip.widthAnchor    constraintEqualToConstant:20],

        [icon.leadingAnchor  constraintEqualToAnchor:grip.trailingAnchor constant:14],
        [icon.centerYAnchor  constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [icon.widthAnchor    constraintEqualToConstant:24],

        [title.leadingAnchor  constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [title.centerYAnchor  constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-12],

        [sw.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        [sw.centerYAnchor  constraintEqualToAnchor:cell.contentView.centerYAnchor],
    ]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 && ip.row == 1) {
        [self.navigationController pushViewController:[SCIHomeShortcutIconPickerViewController new] animated:YES];
    }
}

#pragma mark - Toggle handlers

- (void)masterToggleChanged:(UISwitch *)sw {
    [SCIUtils setPref:@(sw.isOn) forKey:kSCIHomeShortcutEnabledPrefKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIHomeShortcutConfigDidChangeNotification object:nil];
}

- (void)actionToggleChanged:(UISwitch *)sw {
    NSString *aid = sw.accessibilityIdentifier;
    for (NSMutableDictionary *row in self.actions) {
        if ([row[@"id"] isEqualToString:aid]) {
            row[@"enabled"] = @(sw.isOn);
            break;
        }
    }
    sciSaveOrderedActions(self.actions);
}

#pragma mark - Drag and drop reorder

- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 1; }

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tv itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)ip {
    if (ip.section != 1) return @[];
    NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:self.actions[ip.row][@"id"] ?: @""];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
    item.localObject = ip;
    return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tv dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)dst {
    if (!session.localDragSession || !dst || dst.section != 1) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
                                                            intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tv performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *dst = coordinator.destinationIndexPath;
    if (!dst || dst.section != 1) return;
    for (id<UITableViewDropItem> dropItem in coordinator.items) {
        NSIndexPath *src = (NSIndexPath *)dropItem.dragItem.localObject;
        if (!src || src.section != 1 || src.row == dst.row) continue;

        NSMutableDictionary *row = self.actions[src.row];
        [self.actions removeObjectAtIndex:src.row];
        NSInteger insertIdx = MIN(dst.row, (NSInteger)self.actions.count);
        [self.actions insertObject:row atIndex:insertIdx];

        [tv performBatchUpdates:^{
            [tv deleteRowsAtIndexPaths:@[src] withRowAnimation:UITableViewRowAnimationFade];
            [tv insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:insertIdx inSection:1]]
                       withRowAnimation:UITableViewRowAnimationFade];
        } completion:nil];
        [coordinator dropItem:dropItem.dragItem toRowAtIndexPath:[NSIndexPath indexPathForRow:insertIdx inSection:1]];
    }
    sciSaveOrderedActions(self.actions);
}

@end
