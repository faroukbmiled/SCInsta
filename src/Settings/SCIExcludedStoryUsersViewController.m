#import "SCIExcludedStoryUsersViewController.h"
#import "../Features/StoriesAndMessages/SCIExcludedStoryUsers.h"
#import "../Networking/SCIInstagramAPI.h"
#import "../Utils.h"

@interface SCIExcludedStoryUsersViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy)   NSArray<NSDictionary *> *filtered;
@property (nonatomic, copy)   NSString *query;
@property (nonatomic, assign) NSInteger sortMode;
@property (nonatomic, strong) UIBarButtonItem *sortBtn;
@property (nonatomic, strong) UIBarButtonItem *editBtn;
@property (nonatomic, strong) UIToolbar *batchToolbar;
@end

@implementation SCIExcludedStoryUsersViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SCILocalized(@"Story users");
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = SCILocalized(@"Search by username or name");
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
    if (entering) {
        UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        UIBarButtonItem *del = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Remove Selected") style:UIBarButtonItemStylePlain target:self action:@selector(removeSelected)];
        del.tintColor = [UIColor systemRedColor];
        self.batchToolbar.items = @[flex, del, flex];
    }
}

- (void)removeSelected {
    NSArray<NSIndexPath *> *sel = self.tableView.indexPathsForSelectedRows;
    if (!sel.count) return;
    for (NSIndexPath *ip in sel) {
        NSDictionary *e = self.filtered[ip.row];
        [SCIExcludedStoryUsers removePK:e[@"pk"]];
    }
    [self toggleEdit];
    [self reload];
}

- (void)addUserTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add user")
                                                                   message:SCILocalized(@"Enter username")
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

        NSString *msg = [NSString stringWithFormat:@"@%@%@", uname, fullName.length ? [NSString stringWithFormat:@" (%@)", fullName] : @""];
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add to list?")
                                                                         message:msg
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [SCIExcludedStoryUsers addOrUpdateEntry:@{@"pk": pk, @"username": uname, @"fullName": fullName}];
            [self reload];
        }]];
        [self presentViewController:confirm animated:YES completion:nil];
    }];
}

- (void)toggleSort {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Sort by")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *titles = @[@"Recently added", @"Username (A–Z)"];
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
    NSArray *all = [SCIExcludedStoryUsers allEntries];
    NSString *q = [self.query lowercaseString];
    if (q.length > 0) {
        all = [all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id _) {
            if ([[e[@"username"] lowercaseString] containsString:q]) return YES;
            if ([[e[@"fullName"] lowercaseString] containsString:q]) return YES;
            return NO;
        }]];
    }
    if (self.sortMode == 0) {
        all = [all sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"addedAt"] ?: @0 compare:a[@"addedAt"] ?: @0];
        }];
    } else {
        all = [all sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"username"] ?: @"" caseInsensitiveCompare:b[@"username"] ?: @""];
        }];
    }
    self.filtered = all;
    BOOL bs = [SCIExcludedStoryUsers isBlockSelectedMode];
    NSString *label = bs ? SCILocalized(@"Included users") : SCILocalized(@"Excluded users");
    self.title = [NSString stringWithFormat:@"%@ (%lu)", label, (unsigned long)self.filtered.count];
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText;
    [self reload];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.filtered.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuse = @"sciStoryExclCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];

    NSDictionary *e = self.filtered[indexPath.row];
    NSString *username = e[@"username"] ?: @"";
    NSString *fullName = e[@"fullName"] ?: @"";

    cell.textLabel.text = fullName.length ? fullName : (username.length ? [@"@" stringByAppendingString:username] : @"(unknown)");
    cell.detailTextLabel.text = username.length ? [@"@" stringByAppendingString:username] : @"";
    cell.accessoryType = tv.isEditing ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tv.isEditing) return;
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *username = e[@"username"];
    if (!username.length) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://user?username=%@", username]];
    if ([[UIApplication sharedApplication] canOpenURL:url])
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *pk = e[@"pk"];
    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:SCILocalized(@"Remove")
                          handler:^(UIContextualAction *_, UIView *__, void (^cb)(BOOL)) {
        [SCIExcludedStoryUsers removePK:pk];
        [self reload];
        cb(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end
