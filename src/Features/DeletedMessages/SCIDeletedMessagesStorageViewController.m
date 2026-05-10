#import "SCIDeletedMessagesStorageViewController.h"
#import "../../UI/SCIPopupChrome.h"
#import "SCIDeletedMessagesStorage.h"
#import "SCIDeletedMessagesModels.h"
#import "../../Utils.h"
#import "../../Localization/SCILocalization.h"

@interface SCIDeletedMessagesStorageViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy)   NSString *ownerPK;
@property (nonatomic, assign) NSUInteger messageCount;
@property (nonatomic, assign) unsigned long long mediaBytes;
@end

@implementation SCIDeletedMessagesStorageViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SCILocalized(@"Storage");
    self.view.backgroundColor = [SCIPopupChrome backgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = self.view.backgroundColor;
    [self.view addSubview:self.tableView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:SCIDeletedMessagesDidChangeNotification
                                               object:nil];
    [self reload];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)reload {
    self.ownerPK = [SCIUtils currentUserPK];
    self.messageCount = [SCIDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK].count;
    self.mediaBytes   = [SCIDeletedMessagesStorage mediaSizeBytesForOwnerPK:self.ownerPK];
    [self.tableView reloadData];
}

#pragma mark - Helpers

+ (NSString *)formatBytes:(unsigned long long)b {
    if (b == 0) return SCILocalized(@"Empty");
    return [NSByteCountFormatter stringFromByteCount:(long long)b countStyle:NSByteCountFormatterCountStyleFile];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 2 : 2;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? SCILocalized(@"This account") : SCILocalized(@"Manage");
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) return SCILocalized(@"Clearing media keeps the records (text, sender, timestamp). Clearing the log removes everything for this account.");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *rid = @"sci_dm_storage";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:rid];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType  = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;

    if (ip.section == 0) {
        if (ip.row == 0) {
            cell.imageView.image = [UIImage systemImageNamed:@"tray.full"];
            cell.imageView.tintColor = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];
            cell.textLabel.text = SCILocalized(@"Messages");
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.messageCount];
        } else {
            cell.imageView.image = [UIImage systemImageNamed:@"externaldrive"];
            cell.imageView.tintColor = [UIColor systemTealColor];
            cell.textLabel.text = SCILocalized(@"Media on disk");
            cell.detailTextLabel.text = [SCIDeletedMessagesStorageViewController formatBytes:self.mediaBytes];
        }
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        if (ip.row == 0) {
            cell.imageView.image = [UIImage systemImageNamed:@"externaldrive.badge.minus"];
            cell.imageView.tintColor = [UIColor systemOrangeColor];
            cell.textLabel.text = SCILocalized(@"Clear media files");
            cell.textLabel.textColor = [UIColor systemOrangeColor];
            cell.detailTextLabel.text = [SCIDeletedMessagesStorageViewController formatBytes:self.mediaBytes];
        } else {
            cell.imageView.image = [UIImage systemImageNamed:@"trash"];
            cell.imageView.tintColor = [UIColor systemRedColor];
            cell.textLabel.text = SCILocalized(@"Clear log for this account");
            cell.textLabel.textColor = [UIColor systemRedColor];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 1) return;
    if (ip.row == 0) [self confirmClearMedia];
    else             [self confirmClearAll];
}

- (void)confirmClearMedia {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Clear media files")]
                                                              message:SCILocalized(@"Removes every saved photo, video and voice clip. Records keep their text and sender info.")
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear")  style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *_) {
        [self clearMediaFiles];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmClearAll {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Clear log for this account")]
                                                              message:SCILocalized(@"Removes every preserved deleted message and its captured media for the current account. This cannot be undone.")
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear")  style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *_) {
        [SCIDeletedMessagesStorage resetForOwnerPK:self.ownerPK];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

// Selectively wipe media blobs while keeping JSON records — strips mediaPath /
// thumbnailPath off every record so the UI knows the local file is gone.
- (void)clearMediaFiles {
    NSArray<SCIDeletedMessage *> *all = [SCIDeletedMessagesStorage allMessagesForOwnerPK:self.ownerPK];
    for (SCIDeletedMessage *m in all) {
        if (m.mediaPath.length) {
            NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.mediaPath ownerPK:self.ownerPK];
            if (abs.length) [[NSFileManager defaultManager] removeItemAtPath:abs error:nil];
            m.mediaPath = nil;
        }
        if (m.thumbnailPath.length) {
            NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.thumbnailPath ownerPK:self.ownerPK];
            if (abs.length) [[NSFileManager defaultManager] removeItemAtPath:abs error:nil];
            m.thumbnailPath = nil;
        }
        [SCIDeletedMessagesStorage saveMessage:m forOwnerPK:self.ownerPK];
    }
}

@end
