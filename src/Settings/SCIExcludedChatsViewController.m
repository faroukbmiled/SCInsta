#import "SCIExcludedChatsViewController.h"
#import "../Features/StoriesAndMessages/SCIExcludedThreads.h"
#import "../Networking/SCIInstagramAPI.h"
#import "../Utils.h"

@interface SCIExcludedChatsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy)   NSArray<NSDictionary *> *filtered;
@property (nonatomic, copy)   NSString *query;
@property (nonatomic, assign) NSInteger sortMode;
@property (nonatomic, strong) UIBarButtonItem *sortBtn;
@property (nonatomic, strong) UIBarButtonItem *editBtn;
@property (nonatomic, strong) UIToolbar *batchToolbar;
@end

@implementation SCIExcludedChatsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SCILocalized(@"Chats");
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = SCILocalized(@"Search by name or username");
    [self.searchBar sizeToFit];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.tableHeaderView = self.searchBar;
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.batchToolbar = [[UIToolbar alloc] init];
    self.batchToolbar.translatesAutoresizingMaskIntoConstraints = NO;
    self.batchToolbar.hidden = YES;
    [self.view addSubview:self.batchToolbar];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor   constraintEqualToAnchor:self.batchToolbar.topAnchor],
        [self.batchToolbar.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.batchToolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.batchToolbar.bottomAnchor   constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];

    self.sortBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
                style:UIBarButtonItemStylePlain target:self action:@selector(toggleSort)];
    self.editBtn = [[UIBarButtonItem alloc]
        initWithTitle:SCILocalized(@"Select") style:UIBarButtonItemStylePlain target:self action:@selector(toggleEdit)];
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addUserTapped)];
    self.navigationItem.rightBarButtonItems = @[self.editBtn, self.sortBtn, addBtn];

    [self reload];
}

- (void)toggleEdit {
    BOOL entering = !self.tableView.isEditing;
    [self.tableView setEditing:entering animated:YES];
    self.editBtn.title = entering ? SCILocalized(@"Done") : SCILocalized(@"Select");
    self.editBtn.style = entering ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain;
    self.batchToolbar.hidden = !entering;
    if (entering) [self updateToolbar];
}

- (void)updateToolbar {
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *del = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Remove") style:UIBarButtonItemStylePlain target:self action:@selector(removeSelected)];
    del.tintColor = [UIColor systemRedColor];
    UIBarButtonItem *kd = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Keep-deleted") style:UIBarButtonItemStylePlain target:self action:@selector(batchKeepDeleted)];
    self.batchToolbar.items = @[del, flex, kd];
}

- (void)removeSelected {
    NSArray<NSIndexPath *> *sel = self.tableView.indexPathsForSelectedRows;
    if (!sel.count) return;
    for (NSIndexPath *ip in sel) {
        NSDictionary *e = self.filtered[ip.row];
        [SCIExcludedThreads removeThreadId:e[@"threadId"]];
    }
    [self toggleEdit];
    [self reload];
}

- (void)batchKeepDeleted {
    NSArray<NSIndexPath *> *sel = self.tableView.indexPathsForSelectedRows;
    if (!sel.count) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Set keep-deleted override") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    void (^apply)(SCIKeepDeletedOverride) = ^(SCIKeepDeletedOverride mode) {
        for (NSIndexPath *ip in sel) {
            NSDictionary *e = self.filtered[ip.row];
            [SCIExcludedThreads setKeepDeletedOverride:mode forThreadId:e[@"threadId"]];
        }
        [self toggleEdit];
        [self reload];
    };
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Follow default") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        apply(SCIKeepDeletedOverrideDefault);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Force ON (preserve unsends)") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        apply(SCIKeepDeletedOverrideIncluded);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Force OFF (allow unsends)") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        apply(SCIKeepDeletedOverrideExcluded);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.batchToolbar.items.lastObject;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)addUserTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add chat")
                                                                   message:SCILocalized(@"Enter username of the DM thread")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"username"; tf.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Search") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        NSString *q = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!q.length) return;
        [self lookupUsername:q];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)lookupUsername:(NSString *)username {
    // Step 1: resolve user info.
    [SCIInstagramAPI sendRequestWithMethod:@"GET"
        path:[NSString stringWithFormat:@"users/web_profile_info/?username=%@", username]
        body:nil completion:^(NSDictionary *resp, NSError *err) {
        NSDictionary *user = resp[@"data"][@"user"];
        if (!user || err) {
            [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"User '%@' not found"), username]];
            return;
        }
        NSString *pk = [user[@"id"] description] ?: @"";
        NSString *uname = user[@"username"] ?: username;
        NSString *fullName = user[@"full_name"] ?: @"";
        if (!pk.length) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not resolve user ID")]; return; }

        // Step 2: resolve DM thread with this user.
        [SCIInstagramAPI sendRequestWithMethod:@"GET"
            path:[NSString stringWithFormat:@"direct_v2/threads/get_by_participants/?recipient_users=[%@]", pk]
            body:nil completion:^(NSDictionary *threadResp, NSError *tErr) {
            NSString *threadId = threadResp[@"thread"][@"thread_id"];
            NSString *threadName = threadResp[@"thread"][@"thread_title"] ?: uname;
            if (!threadId.length || tErr) {
                [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"No DM thread found with @%@"), uname]];
                return;
            }

            NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];
            UIAlertController *confirm = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add to list?")
                                                                             message:msg
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
            [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
                [SCIExcludedThreads addOrUpdateEntry:@{
                    @"threadId": threadId,
                    @"threadName": threadName,
                    @"isGroup": @NO,
                    @"users": @[@{@"pk": pk, @"username": uname, @"fullName": fullName}],
                }];
                [self reload];
            }]];
            [self presentViewController:confirm animated:YES completion:nil];
        }];
    }];
}

- (void)toggleSort {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Sort by")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[@"Recently added", @"Name (A–Z)"];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        UIAlertAction *a = [UIAlertAction actionWithTitle:titles[i]
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *_) {
            self.sortMode = i;
            [self reload];
        }];
        if (i == self.sortMode) [a setValue:@YES forKey:@"checked"];
        [sheet addAction:a];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.sortBtn;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)reload {
    NSArray *all = [SCIExcludedThreads allEntries];
    NSString *q = [self.query lowercaseString];
    if (q.length > 0) {
        all = [all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id _) {
            if ([[e[@"threadName"] lowercaseString] containsString:q]) return YES;
            for (NSDictionary *u in (NSArray *)e[@"users"]) {
                if ([[u[@"username"] lowercaseString] containsString:q]) return YES;
                if ([[u[@"fullName"] lowercaseString] containsString:q]) return YES;
            }
            return NO;
        }]];
    }
    if (self.sortMode == 0) {
        all = [all sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"addedAt"] ?: @0 compare:a[@"addedAt"] ?: @0];
        }];
    } else {
        all = [all sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"threadName"] ?: @"" caseInsensitiveCompare:b[@"threadName"] ?: @""];
        }];
    }
    self.filtered = all;
    BOOL bs = [SCIExcludedThreads isBlockSelectedMode];
    NSString *label = bs ? SCILocalized(@"Included chats") : SCILocalized(@"Excluded chats");
    self.title = [NSString stringWithFormat:@"%@ (%lu)", label, (unsigned long)self.filtered.count];
    [self.tableView reloadData];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText;
    [self reload];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.filtered.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"sciExclCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];

    NSDictionary *e = self.filtered[indexPath.row];
    NSString *name = e[@"threadName"] ?: @"(unknown)";
    BOOL isGroup = [e[@"isGroup"] boolValue];

    NSMutableArray *unames = [NSMutableArray array];
    for (NSDictionary *u in (NSArray *)e[@"users"]) {
        if (u[@"username"]) [unames addObject:[@"@" stringByAppendingString:u[@"username"]]];
    }
    NSString *subtitle = [unames componentsJoinedByString:@", "];

    SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
    NSString *kdLabel = (mode == SCIKeepDeletedOverrideExcluded) ? @"  • Keep-deleted: OFF"
                      : (mode == SCIKeepDeletedOverrideIncluded) ? @"  • Keep-deleted: ON"
                      : @"";
    if (kdLabel.length) subtitle = [subtitle stringByAppendingString:kdLabel];

    cell.textLabel.text = [NSString stringWithFormat:@"%@%@", isGroup ? @"👥 " : @"", name];
    cell.detailTextLabel.text = subtitle;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = (isGroup || tv.isEditing) ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tv.isEditing) return;
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *e = self.filtered[indexPath.row];
    NSArray *users = e[@"users"];
    if ([e[@"isGroup"] boolValue] || users.count != 1) return;
    NSString *username = users.firstObject[@"username"];
    if (!username) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", username]];
    if ([[UIApplication sharedApplication] canOpenURL:url])
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *tid = e[@"threadId"];
    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:SCILocalized(@"Remove")
                          handler:^(UIContextualAction *_, UIView *__, void (^cb)(BOOL)) {
        [SCIExcludedThreads removeThreadId:tid];
        [self reload];
        cb(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *tid = e[@"threadId"];
    SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];

    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *_) {
        UIAction *(^kdAction)(NSString *, SCIKeepDeletedOverride) = ^UIAction *(NSString *title, SCIKeepDeletedOverride v) {
            UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil
                                            handler:^(__kindof UIAction *_) {
                [SCIExcludedThreads setKeepDeletedOverride:v forThreadId:tid];
                [self reload];
            }];
            if (v == mode) a.state = UIMenuElementStateOn;
            return a;
        };
        UIMenu *kdMenu = [UIMenu menuWithTitle:SCILocalized(@"Keep-deleted override")
                                         image:[UIImage systemImageNamed:@"trash.slash"]
                                    identifier:nil
                                       options:0
                                      children:@[
            kdAction(@"Follow default", SCIKeepDeletedOverrideDefault),
            kdAction(@"Force ON (preserve unsends)", SCIKeepDeletedOverrideIncluded),
            kdAction(@"Force OFF (allow unsends)", SCIKeepDeletedOverrideExcluded),
        ]];
        UIAction *remove = [UIAction actionWithTitle:SCILocalized(@"Remove from list")
                                               image:[UIImage systemImageNamed:@"trash"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *_) {
            [SCIExcludedThreads removeThreadId:tid];
            [self reload];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;
        return [UIMenu menuWithChildren:@[kdMenu, remove]];
    }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *tid = e[@"threadId"];
    SCIKeepDeletedOverride mode = [e[@"keepDeletedOverride"] integerValue];
    SCIKeepDeletedOverride next = (mode + 1) % 3;
    NSString *title = (next == SCIKeepDeletedOverrideExcluded) ? @"KD: OFF"
                    : (next == SCIKeepDeletedOverrideIncluded) ? SCILocalized(@"KD: ON")
                    : SCILocalized(@"KD: default");
    UIContextualAction *toggle = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:title
                          handler:^(UIContextualAction *_, UIView *__, void (^cb)(BOOL)) {
        [SCIExcludedThreads setKeepDeletedOverride:next forThreadId:tid];
        [self reload];
        cb(YES);
    }];
    toggle.backgroundColor = [UIColor systemBlueColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[toggle]];
}

@end
