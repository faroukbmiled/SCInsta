#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryCoreDataStack.h"
#import "SCIGalleryFile.h"
#import "SCIAssetUtils.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"

typedef NS_ENUM(NSInteger, SCIGalleryDeleteSection) {
    SCIGalleryDeleteSectionGlobal = 0,
    SCIGalleryDeleteSectionType,
    SCIGalleryDeleteSectionSource,
    SCIGalleryDeleteSectionUser,
    SCIGalleryDeleteSectionCount
};

@interface SCIGalleryDeleteAction : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong, nullable) NSPredicate *predicate;
@property (nonatomic, copy, nullable) NSString *successTitle;
@property (nonatomic, assign) BOOL navigatesToUsers;
@end

@implementation SCIGalleryDeleteAction
@end

@interface SCIGalleryDeleteUserItem : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, assign) NSInteger count;
@end

@implementation SCIGalleryDeleteUserItem
@end

@interface SCIGalleryDeleteViewController ()
@property (nonatomic, assign) SCIGalleryDeletePageMode mode;
@property (nonatomic, strong) NSArray<NSArray<SCIGalleryDeleteAction *> *> *sections;
@property (nonatomic, strong) NSArray<SCIGalleryDeleteUserItem *> *users;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *countCache;
@end

@implementation SCIGalleryDeleteViewController

- (instancetype)initWithMode:(SCIGalleryDeletePageMode)mode {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _mode = mode;
        _countCache = @{};
        _sections = @[];
        _users = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.mode == SCIGalleryDeletePageModeRoot
        ? SCILocalized(@"Delete files")
        : SCILocalized(@"Delete by user");
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self reloadDataModel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadDataModel];
    [self.tableView reloadData];
}

- (SCIGalleryDeleteAction *)actionWithTitle:(NSString *)title
                                 iconName:(NSString *)iconName
                                predicate:(nullable NSPredicate *)predicate
                             successTitle:(nullable NSString *)successTitle {
    SCIGalleryDeleteAction *action = [SCIGalleryDeleteAction new];
    action.title = title;
    action.iconName = iconName;
    action.predicate = predicate;
    action.successTitle = successTitle;
    return action;
}

- (void)reloadDataModel {
    if (self.mode == SCIGalleryDeletePageModeUsers) {
        [self reloadUsers];
        return;
    }

    self.sections = @[
        @[[self actionWithTitle:SCILocalized(@"Delete all files") iconName:@"trash" predicate:nil successTitle:SCILocalized(@"All files deleted")]],
        @[
            [self actionWithTitle:SCILocalized(@"Delete all images") iconName:@"photo" predicate:[NSPredicate predicateWithFormat:@"mediaType == %d", SCIGalleryMediaTypeImage] successTitle:SCILocalized(@"Images deleted")],
            [self actionWithTitle:SCILocalized(@"Delete all videos") iconName:@"video" predicate:[NSPredicate predicateWithFormat:@"mediaType == %d", SCIGalleryMediaTypeVideo] successTitle:SCILocalized(@"Videos deleted")]
        ],
        @[
            [self actionWithTitle:SCILocalized(@"Delete feed posts") iconName:@"feed" predicate:[NSPredicate predicateWithFormat:@"source == %d", SCIGallerySourceFeed] successTitle:SCILocalized(@"Feed posts deleted")],
            [self actionWithTitle:SCILocalized(@"Delete stories") iconName:@"story" predicate:[NSPredicate predicateWithFormat:@"source == %d", SCIGallerySourceStories] successTitle:SCILocalized(@"Stories deleted")],
            [self actionWithTitle:SCILocalized(@"Delete reels") iconName:@"reels" predicate:[NSPredicate predicateWithFormat:@"source == %d", SCIGallerySourceReels] successTitle:SCILocalized(@"Reels deleted")],
            [self actionWithTitle:SCILocalized(@"Delete thumbnails") iconName:@"photo_gallery" predicate:[NSPredicate predicateWithFormat:@"source == %d", SCIGallerySourceThumbnail] successTitle:SCILocalized(@"Thumbnails deleted")],
            [self actionWithTitle:SCILocalized(@"Delete DM media") iconName:@"messages" predicate:[NSPredicate predicateWithFormat:@"source == %d", SCIGallerySourceDMs] successTitle:SCILocalized(@"DM media deleted")],
            [self actionWithTitle:SCILocalized(@"Delete profile pictures") iconName:@"profile" predicate:[NSPredicate predicateWithFormat:@"source == %d", SCIGallerySourceProfile] successTitle:SCILocalized(@"Profile pictures deleted")]
        ],
        @[]
    ];

    SCIGalleryDeleteAction *usersAction = [self actionWithTitle:SCILocalized(@"Delete by user") iconName:@"users" predicate:nil successTitle:nil];
    usersAction.navigatesToUsers = YES;
    self.sections = @[
        self.sections[0],
        self.sections[1],
        self.sections[2],
        @[usersAction]
    ];

    [self rebuildCountCache];
}

- (void)rebuildCountCache {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (NSArray<SCIGalleryDeleteAction *> *section in self.sections) {
        for (SCIGalleryDeleteAction *action in section) {
            if (action.navigatesToUsers) {
                continue;
            }
            NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
            req.predicate = action.predicate;
            NSInteger count = [ctx countForFetchRequest:req error:nil];
            counts[action.title] = @(MAX(count, 0));
        }
    }

    NSFetchRequest *distinctReq = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    distinctReq.resultType = NSDictionaryResultType;
    distinctReq.propertiesToFetch = @[@"sourceUsername"];
    distinctReq.returnsDistinctResults = YES;
    NSArray<NSDictionary *> *rows = [ctx executeFetchRequest:distinctReq error:nil] ?: @[];
    counts[SCILocalized(@"Delete by user")] = @(rows.count);
    self.countCache = counts;
}

- (void)reloadUsers {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    NSArray<SCIGalleryFile *> *files = [ctx executeFetchRequest:req error:nil] ?: @[];

    NSMutableDictionary<NSString *, SCIGalleryDeleteUserItem *> *items = [NSMutableDictionary dictionary];
    for (SCIGalleryFile *file in files) {
        NSString *username = [file.sourceUsername stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *key = username.length > 0 ? username : @"__unknown__";
        SCIGalleryDeleteUserItem *item = items[key];
        if (!item) {
            item = [SCIGalleryDeleteUserItem new];
            item.username = username.length > 0 ? username : nil;
            item.displayName = username.length > 0 ? username : SCILocalized(@"Unknown user");
            items[key] = item;
        }
        item.count += 1;
    }

    self.users = [[items allValues] sortedArrayUsingComparator:^NSComparisonResult(SCIGalleryDeleteUserItem *lhs, SCIGalleryDeleteUserItem *rhs) {
        return [lhs.displayName localizedCaseInsensitiveCompare:rhs.displayName];
    }];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.mode == SCIGalleryDeletePageModeUsers) {
        return nil;
    }
    switch (section) {
        case SCIGalleryDeleteSectionGlobal: return nil;
        case SCIGalleryDeleteSectionType:   return SCILocalized(@"By type");
        case SCIGalleryDeleteSectionSource: return SCILocalized(@"By source");
        case SCIGalleryDeleteSectionUser:   return SCILocalized(@"By user");
    }
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.mode == SCIGalleryDeletePageModeUsers ? 1 : self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.mode == SCIGalleryDeletePageModeUsers) {
        return self.users.count;
    }
    return self.sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];

    if (self.mode == SCIGalleryDeletePageModeUsers) {
        SCIGalleryDeleteUserItem *item = self.users[indexPath.row];
        cell.textLabel.text = item.displayName;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)item.count];
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.imageView.image = [SCIAssetUtils instagramIconNamed:@"profile" pointSize:18.0];
        cell.imageView.tintColor = [UIColor systemRedColor];
        return cell;
    }

    SCIGalleryDeleteAction *action = self.sections[indexPath.section][indexPath.row];
    cell.textLabel.text = action.title;
    NSNumber *count = self.countCache[action.title];
    if (count) {
        cell.detailTextLabel.text = count.integerValue > 0 ? [NSString stringWithFormat:@"%ld", (long)count.integerValue] : nil;
    }
    cell.imageView.image = [SCIAssetUtils instagramIconNamed:action.iconName pointSize:18.0];

    if (action.navigatesToUsers) {
        cell.textLabel.textColor = [UIColor labelColor];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.imageView.tintColor = [UIColor systemRedColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.mode == SCIGalleryDeletePageModeUsers) {
        SCIGalleryDeleteUserItem *item = self.users[indexPath.row];
        NSPredicate *predicate = item.username.length > 0
            ? [NSPredicate predicateWithFormat:@"sourceUsername == %@", item.username]
            : [NSPredicate predicateWithFormat:@"sourceUsername == nil OR sourceUsername == ''"];
        NSString *title = [NSString stringWithFormat:SCILocalized(@"Delete %@?"), item.displayName];
        [self confirmDeleteWithTitle:title predicate:predicate successTitle:SCILocalized(@"User files deleted")];
        return;
    }

    SCIGalleryDeleteAction *action = self.sections[indexPath.section][indexPath.row];
    if (action.navigatesToUsers) {
        SCIGalleryDeleteViewController *vc = [[SCIGalleryDeleteViewController alloc] initWithMode:SCIGalleryDeletePageModeUsers];
        vc.onDidDelete = self.onDidDelete;
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    [self confirmDeleteWithTitle:action.title predicate:action.predicate successTitle:action.successTitle ?: SCILocalized(@"Files deleted")];
}

- (void)confirmDeleteWithTitle:(NSString *)title predicate:(nullable NSPredicate *)predicate successTitle:(NSString *)successTitle {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.predicate = predicate;
    NSArray<SCIGalleryFile *> *files = [ctx executeFetchRequest:req error:nil] ?: @[];
    if (files.count == 0) {
        [SCIUtils showToastForActionIdentifier:kSCIFeedbackActionGalleryBulkDelete duration:2.0
                                 title:SCILocalized(@"No files to delete")
                              subtitle:nil
                          iconResource:@"info"
                                  tone:SCIFeedbackPillToneInfo];
        return;
    }

    NSString *message = [NSString stringWithFormat:SCILocalized(@"This will permanently remove %ld file(s)."), (long)files.count];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        NSFileManager *fm = [NSFileManager defaultManager];
        for (SCIGalleryFile *file in files) {
            NSString *filePath = file.filePath;
            if ([fm fileExistsAtPath:filePath]) {
                [fm removeItemAtPath:filePath error:nil];
            }
            NSString *thumbPath = file.thumbnailPath;
            if ([fm fileExistsAtPath:thumbPath]) {
                [fm removeItemAtPath:thumbPath error:nil];
            }
            [ctx deleteObject:file];
        }
        [ctx save:nil];
        [self reloadDataModel];
        [self.tableView reloadData];
        if (self.onDidDelete) {
            self.onDidDelete();
        }
        [SCIUtils showToastForActionIdentifier:kSCIFeedbackActionGalleryBulkDelete duration:2.0
                                 title:successTitle
                              subtitle:nil
                          iconResource:@"circle_check_filled"
                                  tone:SCIFeedbackPillToneSuccess];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
