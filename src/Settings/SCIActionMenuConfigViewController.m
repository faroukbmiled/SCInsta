#import "SCIActionMenuConfigViewController.h"
#import "../ActionButton/SCIActionMenuConfig.h"
#import "../UI/SCIIcon.h"
#import "../Utils.h"

#pragma mark - Reusable row layout helpers
//
// Reorderable row: ≡ grip → icon → title → optional accessory.

static UIImageView *sciMakeGripImageView(void) {
    UIImageView *grip = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
    grip.translatesAutoresizingMaskIntoConstraints = NO;
    grip.tintColor = [UIColor tertiaryLabelColor];
    grip.contentMode = UIViewContentModeCenter;
    return grip;
}

static UIImageView *sciMakeRowIconImageView(UIImage *image) {
    UIImageView *iv = [[UIImageView alloc] initWithImage:image];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.tintColor = [UIColor labelColor];
    iv.contentMode = UIViewContentModeCenter;
    return iv;
}

static void sciInstallReorderRow(UITableViewCell *cell,
                                  UIView *grip,
                                  UIView *_Nullable icon,
                                  UIView *title,
                                  UIView *_Nullable accessory) {
    cell.textLabel.text = nil;
    cell.imageView.image = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    [cell.contentView addSubview:grip];
    if (icon) [cell.contentView addSubview:icon];
    [cell.contentView addSubview:title];
    if (accessory) [cell.contentView addSubview:accessory];

    NSMutableArray *cs = [NSMutableArray array];
    [cs addObjectsFromArray:@[
        [grip.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [grip.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [grip.widthAnchor constraintEqualToConstant:20],
    ]];
    if (icon) {
        [cs addObjectsFromArray:@[
            [icon.leadingAnchor constraintEqualToAnchor:grip.trailingAnchor constant:14],
            [icon.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:24],
            [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        ]];
    } else {
        [cs addObject:[title.leadingAnchor constraintEqualToAnchor:grip.trailingAnchor constant:14]];
    }
    [cs addObject:[title.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]];
    if (accessory) {
        [cs addObjectsFromArray:@[
            [accessory.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [accessory.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [title.trailingAnchor constraintLessThanOrEqualToAnchor:accessory.leadingAnchor constant:-12],
        ]];
    } else {
        [cs addObject:[title.trailingAnchor constraintLessThanOrEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor]];
    }
    [NSLayoutConstraint activateConstraints:cs];
}

// MARK: - Section reorder VC (pushed from main page)

@interface SCISectionReorderViewController : UITableViewController <UITableViewDragDelegate, UITableViewDropDelegate>
- (instancetype)initWithConfig:(SCIActionMenuConfig *)config;
@end

@interface SCISectionReorderViewController ()
@property (nonatomic, strong) SCIActionMenuConfig *config;
@end

@implementation SCISectionReorderViewController

- (instancetype)initWithConfig:(SCIActionMenuConfig *)config {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (!self) return nil;
    _config = config;
    self.title = SCILocalized(@"Reorder sections");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.dragInteractionEnabled = YES;
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"section"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.config.sections.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return SCILocalized(@"Drag the ≡ handle to reorder sections.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"section" forIndexPath:ip];
    SCIActionConfigSection *s = self.config.sections[ip.row];

    UIImageView *grip = sciMakeGripImageView();
    UIImage *iconImg = s.iconSF.length ? [SCIIcon sfImageNamed:s.iconSF pointSize:18] : nil;
    UIImageView *icon = iconImg ? sciMakeRowIconImageView(iconImg) : nil;
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = s.title.length ? s.title : s.identifier;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    sciInstallReorderRow(cell, grip, icon, title, nil);
    return cell;
}

- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return YES; }

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tv itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)ip {
    SCIActionConfigSection *s = self.config.sections[ip.row];
    NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:s.identifier ?: @""];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
    item.localObject = ip;
    return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tv dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)dst {
    if (!session.localDragSession || !dst) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
                                                            intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tv performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *dst = coordinator.destinationIndexPath;
    if (!dst) return;
    for (id<UITableViewDropItem> dropItem in coordinator.items) {
        NSIndexPath *src = (NSIndexPath *)dropItem.dragItem.localObject;
        if (!src || src.row == dst.row) continue;
        [self.config moveSectionFromIndex:src.row toIndex:dst.row];
        [self.config save];
    }
    [tv reloadData];
}

@end


// MARK: - Default tap picker

@interface SCIDefaultTapPickerViewController : UITableViewController
- (instancetype)initWithConfig:(SCIActionMenuConfig *)config;
@end

@interface SCIDefaultTapPickerViewController ()
@property (nonatomic, strong) SCIActionMenuConfig *config;
@property (nonatomic, copy) NSArray<SCIActionDescriptor *> *eligible;
@end

@implementation SCIDefaultTapPickerViewController

- (instancetype)initWithConfig:(SCIActionMenuConfig *)config {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (!self) return nil;
    _config = config;
    NSMutableArray *eligible = [NSMutableArray array];
    for (SCIActionDescriptor *d in [SCIActionCatalog descriptorsForSource:config.source]) {
        if (d.eligibleForDefaultTap) [eligible addObject:d];
    }
    _eligible = eligible;
    self.title = SCILocalized(@"Default tap action");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"opt"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.eligible.count + 1; // +1 for "Open menu"
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return SCILocalized(@"What happens on a single tap. Long-press always opens the full menu.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"opt" forIndexPath:ip];
    NSString *currentID = self.config.defaultTap.length ? self.config.defaultTap : @"menu";
    NSString *aid = (ip.row == 0) ? @"menu" : self.eligible[ip.row - 1].identifier;
    NSString *title = (ip.row == 0)
        ? SCILocalized(@"Open menu")
        : self.eligible[ip.row - 1].title;
    NSString *icon = (ip.row == 0) ? @"line.3.horizontal" : self.eligible[ip.row - 1].iconSF;
    cell.textLabel.text = title;
    cell.imageView.image = icon.length ? [SCIIcon sfImageNamed:icon pointSize:18] : nil;
    cell.imageView.tintColor = [UIColor labelColor];
    cell.accessoryType = [aid isEqualToString:currentID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSString *aid = (ip.row == 0) ? @"menu" : self.eligible[ip.row - 1].identifier;
    self.config.defaultTap = aid;
    [self.config save];
    [tv reloadData];
}

@end


// MARK: - Main configure VC

@interface SCIActionMenuConfigViewController () <UITableViewDragDelegate, UITableViewDropDelegate>
@property (nonatomic, assign) SCIActionSource source;
@property (nonatomic, strong) SCIActionMenuConfig *config;
@end

@implementation SCIActionMenuConfigViewController

- (instancetype)initForSource:(SCIActionSource)source {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (!self) return nil;
    _source = source;
    _config = [SCIActionMenuConfig configForSource:source];
    self.title = [NSString stringWithFormat:SCILocalized(@"Configure: %@"),
                  [SCIActionCatalog displayNameForSource:source]];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.dragInteractionEnabled = YES;
    self.tableView.dragDelegate = self;
    self.tableView.dropDelegate = self;
}

// MARK: - UI section layout
//   0 = Behavior (show date / default tap / reorder sections / reset)
//   1..N = Config sections (one UI section per config section)
//   Within each config section the first row is the "Show as submenu" toggle.

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return 1 + (NSInteger)self.config.sections.count;
}

- (BOOL)isBehaviorSection:(NSInteger)section { return section == 0; }

- (SCIActionConfigSection *)configSectionForUISection:(NSInteger)section {
    NSInteger idx = section - 1;
    if (idx < 0 || idx >= (NSInteger)self.config.sections.count) return nil;
    return self.config.sections[idx];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if ([self isBehaviorSection:section]) {
        NSInteger n = 1; // default tap
        if ([SCIActionCatalog sourceSupportsDate:self.source]) n++;
        n += 2; // reorder sections + reset
        return n;
    }
    SCIActionConfigSection *cs = [self configSectionForUISection:section];
    return 1 + (NSInteger)cs.actionIDs.count; // toggle + actions
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if ([self isBehaviorSection:section]) return SCILocalized(@"Behavior");
    SCIActionConfigSection *cs = [self configSectionForUISection:section];
    return cs.title.length ? cs.title : cs.identifier;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"";
    if (section == 1) {
        return SCILocalized(@"Drag the ≡ handle to reorder. Toggle a row off to hide it from the menu. Mark a section as a submenu to collapse its actions behind a single entry.");
    }
    return @"";
}

// MARK: - Behavior cells

- (UITableViewCell *)cellForBehaviorRow:(NSInteger)row reuse:(UITableView *)tv {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"row"];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    NSInteger r = row;
    BOOL hasDate = [SCIActionCatalog sourceSupportsDate:self.source];
    if (hasDate && r == 0) {
        cell.textLabel.text = SCILocalized(@"Show date");
        UISwitch *sw = [UISwitch new];
        sw.on = self.config.showDate;
        [sw addTarget:self action:@selector(showDateChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.imageView.image = [SCIIcon sfImageNamed:@"calendar" pointSize:18];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (hasDate) r--;

    if (r == 0) {
        cell.textLabel.text = SCILocalized(@"Default tap action");
        SCIActionDescriptor *d = [SCIActionCatalog descriptorForActionID:self.config.defaultTap source:self.source];
        cell.detailTextLabel.text = d ? d.title : SCILocalized(@"Open menu");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.image = [SCIIcon sfImageNamed:@"hand.tap" pointSize:18];
        return cell;
    }
    r--;

    if (r == 0) {
        cell.textLabel.text = SCILocalized(@"Reorder sections");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.image = [SCIIcon sfImageNamed:@"arrow.up.arrow.down" pointSize:18];
        return cell;
    }

    cell.textLabel.text = SCILocalized(@"Reset to defaults");
    cell.textLabel.textColor = [UIColor systemRedColor];
    cell.imageView.image = [SCIIcon imageNamed:@"bcn_arrow-ccw_outline_24" pointSize:18 weight:UIImageSymbolWeightRegular];
    cell.imageView.tintColor = [UIColor systemRedColor];
    return cell;
}

- (void)didSelectBehaviorRow:(NSInteger)row {
    NSInteger r = row;
    BOOL hasDate = [SCIActionCatalog sourceSupportsDate:self.source];
    if (hasDate && r == 0) return; // switch row, no-op
    if (hasDate) r--;

    if (r == 0) {
        SCIDefaultTapPickerViewController *vc = [[SCIDefaultTapPickerViewController alloc] initWithConfig:self.config];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    r--;
    if (r == 0) {
        SCISectionReorderViewController *vc = [[SCISectionReorderViewController alloc] initWithConfig:self.config];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Reset to defaults")]
                         message:SCILocalized(@"This will restore the default sections, order, and toggles for this menu.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset")
                                          style:UIAlertActionStyleDestructive
                                        handler:^(__unused UIAlertAction *x) {
        [self.config resetToDefaults];
        [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

// MARK: - Action cells

- (UITableViewCell *)cellForActionRow:(NSInteger)row inSection:(SCIActionConfigSection *)section reuse:(UITableView *)tv {
    if (row == 0) {
        // Section options "Show as submenu" toggle — not draggable, stock cell.
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = SCILocalized(@"Show as submenu");
        cell.detailTextLabel.text = SCILocalized(@"Collapse this section's actions behind a single entry");
        UISwitch *sw = [UISwitch new];
        sw.on = section.collapsible;
        sw.tag = (NSInteger)[self.config.sections indexOfObject:section];
        [sw addTarget:self action:@selector(collapsibleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.imageView.image = [SCIIcon sfImageNamed:section.iconSF.length ? section.iconSF : @"folder" pointSize:18];
        return cell;
    }

    // Action row — drag-reorderable. Layout: ≡ grip → action icon → title → toggle.
    NSInteger actionIdx = row - 1;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
    if (actionIdx < 0 || actionIdx >= (NSInteger)section.actionIDs.count) return cell;
    NSString *aid = section.actionIDs[actionIdx];
    SCIActionDescriptor *d = [SCIActionCatalog descriptorForActionID:aid source:self.source];

    UIImageView *grip = sciMakeGripImageView();
    UIImage *iconImg = d.iconSF.length ? [SCIIcon sfImageNamed:d.iconSF pointSize:18] : nil;
    UIImageView *icon = iconImg ? sciMakeRowIconImageView(iconImg) : nil;
    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = d ? d.title : aid;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    UISwitch *sw = [UISwitch new];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    sw.on = ![self.config isActionDisabled:aid];
    sw.accessibilityIdentifier = aid;
    [sw addTarget:self action:@selector(actionToggleChanged:) forControlEvents:UIControlEventValueChanged];

    sciInstallReorderRow(cell, grip, icon, title, sw);
    return cell;
}

// MARK: - Datasource shell

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isBehaviorSection:ip.section]) {
        return [self cellForBehaviorRow:ip.row reuse:tv];
    }
    SCIActionConfigSection *cs = [self configSectionForUISection:ip.section];
    return [self cellForActionRow:ip.row inSection:cs reuse:tv];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if ([self isBehaviorSection:ip.section]) {
        [self didSelectBehaviorRow:ip.row];
    }
}

// MARK: - Drag and drop reorder

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tv itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)ip {
    if ([self isBehaviorSection:ip.section]) return @[];
    if (ip.row == 0) return @[]; // section-options toggle row
    SCIActionConfigSection *cs = [self configSectionForUISection:ip.section];
    NSInteger actionIdx = ip.row - 1;
    if (!cs || actionIdx < 0 || actionIdx >= (NSInteger)cs.actionIDs.count) return @[];

    NSString *aid = cs.actionIDs[actionIdx];
    NSItemProvider *provider = [[NSItemProvider alloc] initWithObject:aid];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:provider];
    item.localObject = ip;
    return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tv dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)dst {
    if (!session.localDragSession) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }
    if (!dst || [self isBehaviorSection:dst.section]) {
        return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationCancel];
    }
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
                                                            intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tv performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *dst = coordinator.destinationIndexPath;
    if (!dst || [self isBehaviorSection:dst.section]) return;
    SCIActionConfigSection *dstSec = [self configSectionForUISection:dst.section];
    if (!dstSec) return;

    // Drop above the section-options toggle row pins to position 0 of the action list.
    NSInteger dstActionIdx = MAX(0, dst.row - 1);

    for (id<UITableViewDropItem> dropItem in coordinator.items) {
        UIDragItem *dragItem = dropItem.dragItem;
        NSIndexPath *src = dragItem.localObject;
        if (![src isKindOfClass:[NSIndexPath class]]) continue;
        if ([self isBehaviorSection:src.section] || src.row == 0) continue;

        SCIActionConfigSection *srcSec = [self configSectionForUISection:src.section];
        NSInteger srcActionIdx = src.row - 1;
        if (!srcSec || srcActionIdx < 0 || srcActionIdx >= (NSInteger)srcSec.actionIDs.count) continue;

        NSString *aid = srcSec.actionIDs[srcActionIdx];
        if (srcSec == dstSec) {
            [self.config moveActionInSection:srcSec fromIndex:srcActionIdx toIndex:dstActionIdx];
        } else {
            [self.config moveActionID:aid toSection:dstSec index:dstActionIdx];
        }
    }
    [self.config save];
    [tv reloadData];
}

// MARK: - Toggles

- (void)showDateChanged:(UISwitch *)sw {
    self.config.showDate = sw.isOn;
    [self.config save];
}

- (void)collapsibleChanged:(UISwitch *)sw {
    NSInteger idx = sw.tag;
    if (idx < 0 || idx >= (NSInteger)self.config.sections.count) return;
    [self.config setSection:self.config.sections[idx] collapsible:sw.isOn];
    [self.config save];
}

- (void)actionToggleChanged:(UISwitch *)sw {
    NSString *aid = sw.accessibilityIdentifier;
    if (!aid.length) return;
    [self.config setAction:aid disabled:!sw.isOn];
    [self.config save];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

@end
