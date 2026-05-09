#import "SCIGallerySettingsViewController.h"
#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryCoreDataStack.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"
#import "../UI/SCIPopupChrome.h"

static NSString * const kFavoritesAtTopKey = @"show_favorites_at_top";

typedef NS_ENUM(NSInteger, SCIGalleryStatsRow) {
    SCIGalleryStatsRowTotal = 0,
    SCIGalleryStatsRowImages,
    SCIGalleryStatsRowVideos,
    SCIGalleryStatsRowSize,
    SCIGalleryStatsRowCount
};

typedef NS_ENUM(NSInteger, SCIGallerySettingsSection) {
    SCIGallerySettingsSectionStats = 0,
    SCIGallerySettingsSectionBrowsing,
    SCIGallerySettingsSectionDelete,
    SCIGallerySettingsSectionCount
};

@interface SCIGalleryStorageStats : NSObject
@property (nonatomic, assign) NSInteger totalFiles;
@property (nonatomic, assign) NSInteger imageCount;
@property (nonatomic, assign) NSInteger videoCount;
@property (nonatomic, assign) long long totalSize;
@end

@implementation SCIGalleryStorageStats
@end

@interface SCIGallerySettingsViewController ()
@property (nonatomic, strong) SCIGalleryStorageStats *stats;
@end

@implementation SCIGallerySettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SCILocalized(@"Gallery Settings");
    self.view.backgroundColor = [SCIPopupChrome backgroundColor];
    self.tableView.backgroundColor = self.view.backgroundColor;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"value"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"toggle"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"action"];
    [self reloadStats];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadStats];
    [self.tableView reloadData];
}

- (void)reloadStats {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    NSArray<SCIGalleryFile *> *files = [ctx executeFetchRequest:req error:nil] ?: @[];

    SCIGalleryStorageStats *stats = [SCIGalleryStorageStats new];
    for (SCIGalleryFile *file in files) {
        stats.totalFiles += 1;
        stats.totalSize += file.fileSize;
        if (file.mediaType == SCIGalleryMediaTypeVideo) {
            stats.videoCount += 1;
        } else {
            stats.imageCount += 1;
        }
    }
    self.stats = stats;
}

- (NSString *)formattedSize:(long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SCIGallerySettingsSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SCIGallerySettingsSectionStats:    return SCILocalized(@"Storage");
        case SCIGallerySettingsSectionBrowsing: return SCILocalized(@"Browsing");
        case SCIGallerySettingsSectionDelete:   return SCILocalized(@"Manage");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == SCIGallerySettingsSectionBrowsing) {
        return SCILocalized(@"When enabled, favorites are pinned above other files inside the current sort and folder context.");
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SCIGallerySettingsSectionStats:    return SCIGalleryStatsRowCount;
        case SCIGallerySettingsSectionBrowsing: return 1;
        case SCIGallerySettingsSectionDelete:   return 1;
    }
    return 0;
}

- (UITableViewCell *)valueCellWithTitle:(NSString *)title value:(NSString *)value {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"value"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = title;
    cell.detailTextLabel.text = value;
    return cell;
}

- (UITableViewCell *)statsCellForRow:(NSInteger)row {
    switch (row) {
        case SCIGalleryStatsRowTotal:
            return [self valueCellWithTitle:SCILocalized(@"Total files")
                                       value:[NSString stringWithFormat:@"%ld", (long)self.stats.totalFiles]];
        case SCIGalleryStatsRowImages:
            return [self valueCellWithTitle:SCILocalized(@"Images")
                                       value:[NSString stringWithFormat:@"%ld", (long)self.stats.imageCount]];
        case SCIGalleryStatsRowVideos:
            return [self valueCellWithTitle:SCILocalized(@"Videos")
                                       value:[NSString stringWithFormat:@"%ld", (long)self.stats.videoCount]];
        case SCIGalleryStatsRowSize:
            return [self valueCellWithTitle:SCILocalized(@"Total size")
                                       value:[self formattedSize:self.stats.totalSize]];
    }
    return [self valueCellWithTitle:@"" value:@""];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == SCIGallerySettingsSectionStats) {
        return [self statsCellForRow:indexPath.row];
    }

    if (indexPath.section == SCIGallerySettingsSectionBrowsing) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"toggle"];
        cell.textLabel.text = SCILocalized(@"Show favorites at top");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = [UISwitch new];
        sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:kFavoritesAtTopKey];
        [sw addTarget:self action:@selector(favoritesAtTopSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"action"];
    cell.textLabel.text = SCILocalized(@"Delete files");
    cell.textLabel.textColor = [UIColor systemRedColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)favoritesAtTopSwitchChanged:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kFavoritesAtTopKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SCIGalleryFavoritesSortPreferenceChanged" object:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SCIGallerySettingsSectionDelete) {
        SCIGalleryDeleteViewController *vc = [[SCIGalleryDeleteViewController alloc] initWithMode:SCIGalleryDeletePageModeRoot];
        __weak typeof(self) weakSelf = self;
        vc.onDidDelete = ^{
            [weakSelf reloadStats];
            [weakSelf.tableView reloadData];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SCIGalleryFavoritesSortPreferenceChanged" object:nil];
        };
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end
