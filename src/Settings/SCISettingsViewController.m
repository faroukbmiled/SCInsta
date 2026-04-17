#import "SCISettingsViewController.h"
#import "SCISearchBarStyler.h"

static char rowStaticRef[] = "row";

@interface SCISettingsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray *sections;
@property (nonatomic) BOOL reduceMargin;

@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<NSDictionary *> *searchResults;
@property (nonatomic) BOOL isRoot;

@end

///

@implementation SCISettingsViewController

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray *)sections reduceMargin:(BOOL)reduceMargin {
    self = [super init];
    
    if (self) {
        self.title = title;
        self.reduceMargin = reduceMargin;
        self.isRoot = reduceMargin; // root call uses reduceMargin=YES
        
        // Exclude development cells from release builds
        NSMutableArray *mutableSections = [sections mutableCopy];
        
        [mutableSections enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSDictionary *section, NSUInteger index, BOOL *stop) {
        
            if ([section[@"header"] hasPrefix:@"_"] && [section[@"footer"] hasPrefix:@"_"]) {
                if (![[SCIUtils IGVersionString] isEqualToString:@"0.0.0"]) {
                    [mutableSections removeObjectAtIndex:index];
                }
            }

            else if ([section[@"header"] isEqualToString:@"Experimental"]) {
                if (![[SCIUtils IGVersionString] hasSuffix:@"-dev"]) {
                    [mutableSections removeObjectAtIndex:index];
                }
            }
            
        }];
        
        self.sections = [mutableSections copy];
    }
    
    
    return self;
}

- (instancetype)init {
    return [self initWithTitle:[SCITweakSettings title] sections:[SCITweakSettings sections] reduceMargin:YES];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.contentInset = UIEdgeInsetsMake(self.reduceMargin ? -30 : -10, 0, 0, 0);
    self.tableView.delegate = self;

    [self.view addSubview:self.tableView];

    if (self.isRoot) {
        UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
        sc.searchResultsUpdater = self;
        sc.delegate = self;
        sc.obscuresBackgroundDuringPresentation = NO;
        sc.searchBar.placeholder = SCILocalized(@"settings.search.placeholder");
        self.navigationItem.searchController = sc;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
        if (![SCIUtils getBoolPref:@"liquid_glass_buttons"]) {
            self.definesPresentationContext = YES;
        }
        self.searchController = sc;

        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                 target:self action:@selector(sciDismissSettings)];

        UIImage *globe = [UIImage systemImageNamed:@"globe"];
        UIBarButtonItem *langItem = [[UIBarButtonItem alloc] initWithImage:globe
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:nil
                                                                    action:nil];
        langItem.menu = [self sciBuildLanguageMenu];
        self.navigationItem.rightBarButtonItem = langItem;
    }
}

- (void)sciShowLanguageInfo {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"settings.language.title")
                         message:SCILocalized(@"settings.language.english_only")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"settings.language.ok") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"settings.language.help_translate") style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
        NSURL *url = [NSURL URLWithString:@"https://github.com/faroukbmiled/RyukGram#translating-ryukgram"];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIMenu *)sciBuildLanguageMenu {
    NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:SCILanguagePrefKey] ?: @"system";
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];

    for (NSDictionary<NSString *, NSString *> *lang in SCIAvailableLanguages()) {
        NSString *code = lang[@"code"];
        NSString *title = [code isEqualToString:@"system"]
            ? SCILocalized(@"settings.language.system")
            : lang[@"native"];

        UIAction *action = [UIAction actionWithTitle:title
                                                image:nil
                                           identifier:nil
                                              handler:^(UIAction * _Nonnull a) {
            NSString *prev = [[NSUserDefaults standardUserDefaults] stringForKey:SCILanguagePrefKey] ?: @"system";
            if ([prev isEqualToString:code]) return;
            [[NSUserDefaults standardUserDefaults] setObject:code forKey:SCILanguagePrefKey];
            SCILocalizationReset();
            [self sciApplyLanguageChange];
            // Most IG-side hooks cache their labels at load time, so a full
            // restart is the only way to flip every menu/button cleanly.
            [SCIUtils showRestartConfirmation];
        }];
        action.state = [code isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }

    UIAction *help = [UIAction actionWithTitle:[NSString stringWithFormat:@"❤️ %@", SCILocalized(@"settings.language.help_translate")]
                                          image:nil
                                     identifier:nil
                                        handler:^(__unused UIAction *a) {
        NSURL *url = [NSURL URLWithString:@"https://github.com/faroukbmiled/RyukGram#translating-ryukgram"];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }];

    return [UIMenu menuWithTitle:SCILocalized(@"settings.language.title")
                        children:[actions arrayByAddingObject:help]];
}

- (void)sciApplyLanguageChange {
    // Root title + search placeholder reflect the new language immediately.
    self.title = SCILocalized(@"settings.title");
    self.searchController.searchBar.placeholder = SCILocalized(@"settings.search.placeholder");
    if (self.navigationItem.rightBarButtonItem.menu) {
        self.navigationItem.rightBarButtonItem.menu = [self sciBuildLanguageMenu];
    }
    [self.tableView reloadData];

    // Features watching for runtime label refreshes (IG menu items, overlay
    // buttons, toasts) can subscribe to this to re-read their strings.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SCILanguageDidChange" object:nil];
}

- (void)sciDismissSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    [self sciStyleSearchBar];
}

- (void)sciStyleSearchBar { [SCISearchBarStyler styleSearchBar:self.searchController.searchBar]; }

- (void)willPresentSearchController:(UISearchController *)searchController { [self sciStyleSearchBar]; }
- (void)didPresentSearchController:(UISearchController *)searchController {
    [self sciStyleSearchBar];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self sciStyleSearchBar];
    });
}

#pragma mark - Search

- (BOOL)isSearching {
    return self.searchController.isActive && self.searchController.searchBar.text.length > 0;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = searchController.searchBar.text ?: @"";
    if (q.length == 0) {
        self.searchResults = @[];
    } else {
        NSMutableArray *out = [NSMutableArray array];
        [self collectMatchingFromSections:self.sections breadcrumb:@"" query:q into:out];
        self.searchResults = out;
    }
    [self.tableView reloadData];
}

- (void)collectMatchingFromSections:(NSArray *)sections
                         breadcrumb:(NSString *)breadcrumb
                              query:(NSString *)q
                               into:(NSMutableArray *)out
{
    for (id sectionObj in sections) {
        if (![sectionObj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *section = sectionObj;
        NSString *header = section[@"header"] ?: @"";
        NSArray *rows = section[@"rows"];
        for (id rowObj in rows) {
            if (![rowObj isKindOfClass:[SCISetting class]]) continue;
            SCISetting *row = rowObj;

            NSString *titleHay = row.title ?: @"";
            NSString *subHay   = row.subtitle ?: @"";
            BOOL matches = [titleHay rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound
                        || [subHay   rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound;

            if (matches) {
                NSMutableString *crumb = [NSMutableString string];
                if (breadcrumb.length) [crumb appendString:breadcrumb];
                if (header.length) {
                    if (crumb.length) [crumb appendString:@" › "];
                    [crumb appendString:header];
                }
                [out addObject:@{ @"setting": row, @"breadcrumb": crumb ?: @"" }];
            }

            if (row.navSections) {
                NSString *child = breadcrumb.length
                    ? [NSString stringWithFormat:@"%@ › %@", breadcrumb, row.title ?: @""]
                    : (row.title ?: @"");
                [self collectMatchingFromSections:row.navSections breadcrumb:child query:q into:out];
            }
        }
    }
}

- (SCISetting *)settingForIndexPath:(NSIndexPath *)indexPath breadcrumbOut:(NSString **)outCrumb {
    if ([self isSearching]) {
        if (indexPath.row >= (NSInteger)self.searchResults.count) return nil;
        NSDictionary *entry = self.searchResults[indexPath.row];
        if (outCrumb) *outCrumb = entry[@"breadcrumb"];
        return entry[@"setting"];
    }
    return self.sections[indexPath.section][@"rows"][indexPath.row];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Without this the search bar strands itself as a floating bar on return.
    if (![SCIUtils getBoolPref:@"liquid_glass_buttons"] && self.searchController.isActive) {
        self.searchController.active = NO;
    }

    if (![[[NSUserDefaults standardUserDefaults] objectForKey:@"SCInstaFirstRun"] isEqualToString:SCIVersionString]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"settings.firstrun.title")
                                                                       message:SCILocalized(@"settings.firstrun.message")
                                                                preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"settings.firstrun.ok")
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        
        UIViewController *presenter = self.presentingViewController;
        [presenter presentViewController:alert animated:YES completion:nil];
        
        // Done with first-time setup for this version
        [[NSUserDefaults standardUserDefaults] setValue:SCIVersionString forKey:@"SCInstaFirstRun"];
    }
}

// MARK: - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *searchBreadcrumb = nil;
    SCISetting *row = [self settingForIndexPath:indexPath breadcrumbOut:&searchBreadcrumb];
    if (!row) return nil;
    
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    UIListContentConfiguration *cellContentConfig = cell.defaultContentConfiguration;
    
    cellContentConfig.text = row.dynamicTitle ? row.dynamicTitle() : row.title;

    // While searching, show the breadcrumb path instead of the row subtitle.
    NSString *displaySubtitle = [self isSearching] && searchBreadcrumb.length ? searchBreadcrumb : row.subtitle;
    if (displaySubtitle.length) {
        cellContentConfig.secondaryText = displaySubtitle;
        cellContentConfig.textToSecondaryTextVerticalPadding = 4.5;
    }
    
    // Icon
    if (row.icon != nil) {
        cellContentConfig.image = [row.icon image];
        cellContentConfig.imageProperties.tintColor = row.icon.color;
    }
    
    // Image url
    if (row.imageUrl != nil) {
        [self loadImageFromURL:row.imageUrl atIndexPath:indexPath forTableView:tableView];
        
        cellContentConfig.imageToTextPadding = 14;
    }
    
    switch (row.type) {
        case SCITableCellStatic: {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
            
        case SCITableCellLink: {
            cellContentConfig.textProperties.color = [UIColor systemBlueColor];
            cellContentConfig.textProperties.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize
                                                                      weight:UIFontWeightMedium];
            
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            
            UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"safari"]];
            imageView.tintColor = [UIColor systemGray3Color];
            cell.accessoryView = imageView;
            
            break;
        }
            
        case SCITableCellSwitch: {
            UISwitch *toggle = [UISwitch new];
            toggle.on = row.disabled ? NO : [[NSUserDefaults standardUserDefaults] boolForKey:row.defaultsKey];
            toggle.onTintColor = [SCIUtils SCIColor_Primary];
            toggle.enabled = !row.disabled;

            objc_setAssociatedObject(toggle, rowStaticRef, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];

            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (row.disabled) {
                cell.contentView.alpha = 0.4;
            }
            break;
        }
            
        case SCITableCellStepper: {
            UIStepper *stepper = [UIStepper new];
            stepper.minimumValue = row.min;
            stepper.maximumValue = row.max;
            stepper.stepValue = row.step;
            stepper.value = [[NSUserDefaults standardUserDefaults] doubleForKey:row.defaultsKey];
            
            objc_setAssociatedObject(stepper, rowStaticRef, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            [stepper addTarget:self
                        action:@selector(stepperChanged:)
              forControlEvents:UIControlEventValueChanged];
            
            // Template subtitle
            if (row.subtitle.length) {
                cellContentConfig.secondaryText = [self formatString:row.subtitle withValue:stepper.value label:row.label singularLabel:row.singularLabel];
            }
            
            cell.accessoryView = stepper;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
            
        case SCITableCellButton: {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
            
        case SCITableCellMenu: {
            UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
            [menuButton setTitle:@"•••" forState:UIControlStateNormal];
            menuButton.menu = [row menuForButton:menuButton];
            menuButton.showsMenuAsPrimaryAction = YES;
            menuButton.titleLabel.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize
                                                           weight:UIFontWeightMedium];
            
            UIButtonConfiguration *config = menuButton.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
            menuButton.configuration.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
            menuButton.configuration = config;

            [menuButton sizeToFit];

            cell.accessoryView = menuButton;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (row.disabled) {
                menuButton.enabled = NO;
                cell.contentView.alpha = 0.4;
            }
            break;
        }
            
        case SCITableCellNavigation: {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
    }
    
    cell.contentConfiguration = cellContentConfig;

    return cell;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isSearching]) return self.searchResults.count;
    return [self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self isSearching]) {
        NSUInteger n = self.searchResults.count;
        if (n == 0) return SCILocalized(@"settings.results.none");
        NSString *fmt = n == 1 ? SCILocalized(@"settings.results.one") : SCILocalized(@"settings.results.many");
        return [NSString stringWithFormat:fmt, (unsigned long)n];
    }
    return self.sections[section][@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self isSearching]) return nil;
    return self.sections[section][@"footer"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if ([self isSearching]) return 1;
    return self.sections.count;
}

// MARK: - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    SCISetting *row = [self settingForIndexPath:indexPath breadcrumbOut:NULL];
    if (!row) return;

    if (row.type == SCITableCellLink) {
        [[UIApplication sharedApplication] openURL:row.url options:@{} completionHandler:nil];
    }
    else if (row.type == SCITableCellButton) {
        if (row.action != nil) {
            row.action();
        }
    }
    else if (row.type == SCITableCellNavigation) {
        if (row.navSections.count > 0) {
            UIViewController *vc = [[SCISettingsViewController alloc] initWithTitle:row.title sections:row.navSections reduceMargin:NO];
            vc.title = row.title;
            [self.navigationController pushViewController:vc animated:YES];
        }
        else if (row.navViewController) {
            [self.navigationController pushViewController:row.navViewController animated:YES];
        }
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

// MARK: - Actions

- (void)switchChanged:(UISwitch *)sender {
    SCISetting *row = objc_getAssociatedObject(sender, rowStaticRef);
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:row.defaultsKey];
    
    NSLog(@"Switch changed: %@", sender.isOn ? @"ON" : @"OFF");
    
    if (row.requiresRestart) {
        [SCIUtils showRestartConfirmation];
    }

    if ([row.defaultsKey isEqualToString:@"hide_suggested_stories"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SCISuggestedStoriesReload" object:nil];
    }
}

- (void)stepperChanged:(UIStepper *)sender {
    SCISetting *row = objc_getAssociatedObject(sender, rowStaticRef);
    [[NSUserDefaults standardUserDefaults] setDouble:sender.value forKey:row.defaultsKey];
    
    NSLog(@"Stepper changed: %f", sender.value);
    
    [self reloadCellForView:sender];
}

- (void)menuChanged:(UICommand *)command {
    NSDictionary *properties = command.propertyList;
    
    [[NSUserDefaults standardUserDefaults] setValue:properties[@"value"] forKey:properties[@"defaultsKey"]];
    
    NSLog(@"Menu changed: %@", command.propertyList[@"value"]);
    
    [self reloadCellForView:command.sender animated:YES];
    [self.tableView reloadData];

    if (properties[@"requiresRestart"]) {
        [SCIUtils showRestartConfirmation];
    }
}

// MARK: - Helper

- (NSString *)formatString:(NSString *)template withValue:(double)value label:(NSString *)label singularLabel:(NSString *)singularLabel {
    // Singular or plural labels
    NSString *applicableLabel = fabs(value - 1.0) < 0.00001 ? singularLabel : label;
    
    // Force value to 0 to prevent it being -0
    if (fabs(value) < 0.00001) {
        value = 0.0;
    }

    // Get correct decimal value based on step value
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = [SCIUtils decimalPlacesInDouble:value];

    NSString *stringValue = [formatter stringFromNumber:@(value)];

    return [NSString stringWithFormat:template, stringValue, applicableLabel];
}

- (void)reloadCellForView:(UIView *)view animated:(BOOL)animated {
    UITableViewCell *cell = (UITableViewCell *)view.superview;
    while (cell && ![cell isKindOfClass:[UITableViewCell class]]) {
        cell = (UITableViewCell *)cell.superview;
    }
    if (!cell) return;

    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath) return;
    
    [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                          withRowAnimation:animated ? UITableViewRowAnimationAutomatic : UITableViewRowAnimationNone];
}
- (void)reloadCellForView:(UIView *)view {
    [self reloadCellForView:view animated:NO];
}

- (void)loadImageFromURL:(NSURL *)url atIndexPath:(NSIndexPath *)indexPath forTableView:(UITableView *)tableView
{
    if (!url) return;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
    {
        if (!data || error) return;

        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            if (!cell) return;

            UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
            config.image = image;
            config.imageProperties.maximumSize = CGSizeMake(45, 45);
            cell.contentConfiguration = config;
        });
    }];

    [task resume];
}

@end
