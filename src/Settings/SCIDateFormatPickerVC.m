#import "SCIDateFormatPickerVC.h"
#import "../Utils.h"
#import "../Features/General/SCIDateFormatEntries.h"

static NSString *const kFmtKey = @"feed_date_format";
static NSString *const kSecKey = @"feed_date_show_seconds";
static NSString *const kCompactKey = @"feed_date_compact_relative";
static NSString *const kThresholdKey = @"feed_date_relative_days_threshold";
static NSString *const kAppendKey = @"feed_date_append_relative";

static NSArray<NSArray *> *sciDateFormatOptions(void) {
	static NSArray *opts = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		opts = @[
			@[@"default", @"", @""],
			@[@"short", @"MMM d", @"MMM d"],
			@[@"medium", @"MMM d, yyyy", @"MMM d, yyyy"],
			@[@"full", @"MMM d, yyyy 'at' h:mm a", @"MMM d, yyyy 'at' h:mm:ss a"],
			@[@"time_12", @"MMM d 'at' h:mm a", @"MMM d 'at' h:mm:ss a"],
			@[@"time_24", @"MMM d 'at' HH:mm", @"MMM d 'at' HH:mm:ss"],
			@[@"dd_mmm", @"dd-MMM-yyyy 'at' h:mm a", @"dd-MMM-yyyy 'at' h:mm:ss a"],
			@[@"day_slash", @"dd/MM/yyyy h:mm a", @"dd/MM/yyyy h:mm:ss a"],
			@[@"month_slash", @"MM/dd/yyyy h:mm a", @"MM/dd/yyyy h:mm:ss a"],
			@[@"euro", @"dd.MM.yyyy HH:mm", @"dd.MM.yyyy HH:mm:ss"],
			@[@"iso", @"yyyy-MM-dd", @"yyyy-MM-dd"],
			@[@"iso_time", @"yyyy-MM-dd HH:mm", @"yyyy-MM-dd HH:mm:ss"],
		];
	});
	return opts;
}

static NSArray<NSArray<NSString *> *> *sciSurfaceEntries(void) {
	static NSArray *entries = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableArray *m = [NSMutableArray array];
		NSMutableSet *seen = [NSMutableSet set];

		#define SCI_EMIT(NAME, SEL_, LABEL, ARITY, PREF) \
			if (strlen(LABEL) && ![seen containsObject:@PREF]) { \
				[seen addObject:@PREF]; \
				[m addObject:@[@PREF, @LABEL]]; \
			}

		SCI_DATE_FORMAT_ENTRIES(SCI_EMIT)

		#undef SCI_EMIT

		entries = [m copy];
	});
	return entries;
}

static NSDate *sciRefDate(void) {
	static NSDate *ref = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		ref = [NSDate dateWithTimeIntervalSince1970:1736348730];
	});
	return ref;
}

static NSString *sciExampleForKey(NSString *key) {
	if (!key.length || [key isEqualToString:@"default"]) return SCILocalized(@"Default");

	BOOL sec = [SCIUtils getBoolPref:kSecKey];

	for (NSArray *opt in sciDateFormatOptions()) {
		if ([opt[0] isEqualToString:key]) {
			NSString *pattern = sec ? opt[2] : opt[1];
			if (!pattern.length) return SCILocalized(@"Default");

			NSDateFormatter *df = [NSDateFormatter new];
			df.locale = [NSLocale currentLocale];
			df.dateFormat = pattern;
			return [df stringFromDate:sciRefDate()];
		}
	}

	return SCILocalized(@"Default");
}

static NSString *sciThresholdText(void) {
	NSInteger days = (NSInteger)[SCIUtils getDoublePref:kThresholdKey];
	if (days <= 0) return SCILocalized(@"Off");
	if (days == 1) return SCILocalized(@"Within 1 day");
	return [NSString stringWithFormat:SCILocalized(@"Within %ld days"), (long)days];
}

@implementation SCIDateFormatPickerVC {
	UITableView *_tableView;
}

+ (NSString *)currentFormatExample {
	return sciExampleForKey([SCIUtils getStringPref:kFmtKey]);
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = SCILocalized(@"Date format");

	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.dataSource = self;
	_tableView.delegate = self;

	[self.view addSubview:_tableView];
}

// 0 = format, 1 = seconds, 2 = relative, 3 = surfaces
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
	return 4;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return (NSInteger)sciDateFormatOptions().count;
	if (section == 1) return 1;
	if (section == 2) return 3;
	return (NSInteger)sciSurfaceEntries().count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return SCILocalized(@"Absolute format");
	if (section == 1) return SCILocalized(@"Time");
	if (section == 2) return SCILocalized(@"Relative time");
	return SCILocalized(@"Apply to");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return SCILocalized(@"Pick how absolute dates are written. “Default” leaves IG's own format untouched.");
	}

	if (section == 1) {
		return SCILocalized(@"Include seconds when the format already shows time.");
	}

	if (section == 2) {
		return SCILocalized(@"Dates younger than the threshold show as relative time (e.g. “2h”). Older dates fall back to the absolute format. “Append after absolute date” shows both — “Jan 5, 2026 (2h)”.");
	}

	if (section == 3) {
		return SCILocalized(@"Each surface in IG goes through a different NSDate formatter. Toggle the ones you want this format to apply to.");
	}

	return nil;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title key:(NSString *)key action:(SEL)action reuseID:(NSString *)reuseID {
	UITableViewCell *cell = [_tableView dequeueReusableCellWithIdentifier:reuseID];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];

	cell.textLabel.text = title;
	cell.textLabel.numberOfLines = 0;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UISwitch *sw = [UISwitch new];
	sw.on = [SCIUtils getBoolPref:key];
	[sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];

	cell.accessoryView = sw;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == 0) {
		UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"df"];
		if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"df"];

		NSString *key = sciDateFormatOptions()[ip.row][0];
		NSString *current = [SCIUtils getStringPref:kFmtKey];
		if (!current.length) current = @"default";

		cell.textLabel.text = sciExampleForKey(key);
		cell.textLabel.font = [UIFont systemFontOfSize:16.0];
		cell.accessoryType = [current isEqualToString:key] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

		return cell;
	}

	if (ip.section == 1) {
		return [self switchCellWithTitle:SCILocalized(@"Show seconds")
									 key:kSecKey
								  action:@selector(secondsToggled:)
								 reuseID:@"sec"];
	}

	if (ip.section == 2) {
		if (ip.row == 0) {
			UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"threshold"];
			if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"threshold"];

			cell.textLabel.text = SCILocalized(@"Relative within");
			cell.detailTextLabel.text = sciThresholdText();
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

			return cell;
		}

		if (ip.row == 1) {
			return [self switchCellWithTitle:SCILocalized(@"Compact style (e.g. “1h” instead of “1 hour ago”)")
										 key:kCompactKey
									  action:@selector(compactToggled:)
									 reuseID:@"compact"];
		}

		return [self switchCellWithTitle:SCILocalized(@"Append after absolute date")
									 key:kAppendKey
								  action:@selector(appendToggled:)
								 reuseID:@"append"];
	}

	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"surf"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"surf"];

	NSArray *entry = sciSurfaceEntries()[ip.row];

	cell.textLabel.text = SCILocalized(entry[1]);
	cell.textLabel.numberOfLines = 0;
	cell.textLabel.font = [UIFont systemFontOfSize:15.0];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UISwitch *sw = [UISwitch new];
	sw.on = [SCIUtils getBoolPref:entry[0]];
	sw.tag = ip.row;
	[sw addTarget:self action:@selector(surfaceToggled:) forControlEvents:UIControlEventValueChanged];

	cell.accessoryView = sw;

	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];

	if (ip.section == 0) {
		[[NSUserDefaults standardUserDefaults] setObject:sciDateFormatOptions()[ip.row][0] forKey:kFmtKey];
		[tv reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
		return;
	}

	if (ip.section != 2 || ip.row != 0) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Relative within")
																   message:SCILocalized(@"Show relative time for dates younger than this many days. 0 disables it.")
															preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		NSInteger days = (NSInteger)[SCIUtils getDoublePref:kThresholdKey];
		field.keyboardType = UIKeyboardTypeNumberPad;
		field.placeholder = @"0";
		field.text = [NSString stringWithFormat:@"%ld", (long)days];
	}];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		NSInteger days = alert.textFields.firstObject.text.integerValue;
		if (days < 0) days = 0;
		if (days > 365) days = 365;

		[[NSUserDefaults standardUserDefaults] setInteger:days forKey:kThresholdKey];
		[tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (void)secondsToggled:(UISwitch *)sw {
	[[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kSecKey];
	[_tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)compactToggled:(UISwitch *)sw {
	[[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kCompactKey];
}

- (void)appendToggled:(UISwitch *)sw {
	[[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kAppendKey];
}

- (void)surfaceToggled:(UISwitch *)sw {
	NSArray *entry = sciSurfaceEntries()[sw.tag];
	[[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:entry[0]];
}

@end