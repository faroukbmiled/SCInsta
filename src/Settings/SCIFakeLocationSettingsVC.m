#import "SCIFakeLocationSettingsVC.h"
#import "SCIFakeLocationPickerVC.h"
#import "../Utils.h"

static NSString *const kEnabled = @"fake_location_enabled";
static NSString *const kShowBtn = @"show_fake_location_map_button";
static NSString *const kLat = @"fake_location_lat";
static NSString *const kLon = @"fake_location_lon";
static NSString *const kName = @"fake_location_name";
static NSString *const kPresets = @"fake_location_presets";
static NSString *const kMapBtnChanged = @"SCIFakeLocationMapBtnPrefChanged";

@interface SCIFakeLocationSettingsVC ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SCIFakeLocationSettingsVC

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = SCILocalized(@"Fake location");
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	[self.view addSubview:self.tableView];
}

// MARK: - Helpers

- (NSUserDefaults *)defaults {
	return NSUserDefaults.standardUserDefaults;
}

- (NSArray<NSDictionary *> *)presets {
	id raw = [self.defaults objectForKey:kPresets];
	return [raw isKindOfClass:NSArray.class] ? raw : @[];
}

- (void)setPresets:(NSArray<NSDictionary *> *)presets {
	[self.defaults setObject:(presets ?: @[]) forKey:kPresets];
}

- (CLLocationCoordinate2D)currentCoord {
	return CLLocationCoordinate2DMake([[self.defaults objectForKey:kLat] doubleValue], [[self.defaults objectForKey:kLon] doubleValue]);
}

- (void)refreshMapButton {
	[NSNotificationCenter.defaultCenter postNotificationName:kMapBtnChanged object:nil];
}

- (void)applyLat:(double)lat lon:(double)lon name:(NSString *)name enable:(BOOL)enable {
	NSUserDefaults *d = self.defaults;
	[d setObject:@(lat) forKey:kLat];
	[d setObject:@(lon) forKey:kLon];
	[d setObject:(name ?: @"") forKey:kName];
	if (enable) [d setBool:YES forKey:kEnabled];

	[self.tableView reloadData];
	[self refreshMapButton];
}

- (UITableViewCell *)cell:(UITableView *)tv id:(NSString *)rid style:(UITableViewCellStyle)style {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
	return cell ?: [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:rid];
}

- (UISwitch *)switchOn:(BOOL)on action:(SEL)action {
	UISwitch *sw = UISwitch.new;
	sw.on = on;
	[sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	return sw;
}

- (void)presentPickerWithTitle:(NSString *)title completion:(void (^)(double lat, double lon, NSString *name))completion {
	SCIFakeLocationPickerVC *vc = SCIFakeLocationPickerVC.new;
	vc.initialCoord = [self currentCoord];
	vc.titleText = title;
	vc.onPick = completion;

	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)askNameAndSavePresetWithLat:(double)lat lon:(double)lon name:(NSString *)name {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Save preset") message:nil preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = SCILocalized(@"Name");
		tf.text = name;
		tf.autocapitalizationType = UITextAutocapitalizationTypeSentences;
	}];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *finalName = alert.textFields.firstObject.text.length ? alert.textFields.firstObject.text : name;
		NSMutableArray *items = self.presets.mutableCopy ?: NSMutableArray.array;
		[items addObject:@{@"name": finalName ?: @"", @"lat": @(lat), @"lon": @(lon)}];
		[self setPresets:items];
		[self.tableView reloadData];
	}]];

	[self presentViewController:alert animated:YES completion:nil];
}

// MARK: - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 2;
	if (section == 1) return 2;
	return self.presets.count + 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
	if (section == 1) return SCILocalized(@"Current location");
	if (section == 2) return SCILocalized(@"Saved locations");
	return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	if (section == 0) return SCILocalized(@"When on, Instagram location requests return your selected fake location. The map button adds a quick shortcut inside Friends Map.");
	if (section == 2) return SCILocalized(@"Tap a preset to make it active. Swipe left to delete.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	NSUserDefaults *d = self.defaults;

	if (ip.section == 0) {
		BOOL isEnabledRow = ip.row == 0;
		UITableViewCell *cell = [self cell:tv id:(isEnabledRow ? @"enabled" : @"show") style:UITableViewCellStyleDefault];
		cell.textLabel.text = isEnabledRow ? SCILocalized(@"Enable fake location") : SCILocalized(@"Show map button");
		cell.accessoryView = [self switchOn:[SCIUtils getBoolPref:(isEnabledRow ? kEnabled : kShowBtn)] action:(isEnabledRow ? @selector(enabledToggled:) : @selector(showButtonToggled:))];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.imageView.image = nil;
		return cell;
	}

	if (ip.section == 1 && ip.row == 0) {
		UITableViewCell *cell = [self cell:tv id:@"current" style:UITableViewCellStyleSubtitle];
		double lat = [[d objectForKey:kLat] doubleValue], lon = [[d objectForKey:kLon] doubleValue];
		NSString *name = [d objectForKey:kName] ?: @"";

		cell.textLabel.text = name.length ? name : SCILocalized(@"(unset)");
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%.5f, %.5f", lat, lon];
		cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
		cell.imageView.image = [UIImage systemImageNamed:@"location.fill"];
		cell.imageView.tintColor = UIColor.systemGreenColor;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	}

	if (ip.section == 1) {
		UITableViewCell *cell = [self cell:tv id:@"select" style:UITableViewCellStyleDefault];
		cell.textLabel.text = SCILocalized(@"Select location on map");
		cell.textLabel.textColor = UIColor.systemBlueColor;
		cell.imageView.image = [UIImage systemImageNamed:@"map"];
		cell.imageView.tintColor = UIColor.systemBlueColor;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	NSArray<NSDictionary *> *presets = self.presets;

	if (ip.row < (NSInteger)presets.count) {
		NSDictionary *p = presets[ip.row];
		UITableViewCell *cell = [self cell:tv id:@"preset" style:UITableViewCellStyleSubtitle];

		cell.textLabel.text = p[@"name"] ?: SCILocalized(@"Preset");
		cell.textLabel.textColor = UIColor.labelColor;
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%.5f, %.5f", [p[@"lat"] doubleValue], [p[@"lon"] doubleValue]];
		cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
		cell.imageView.image = [UIImage systemImageNamed:@"mappin.circle.fill"];
		cell.imageView.tintColor = UIColor.systemRedColor;
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	}

	UITableViewCell *cell = [self cell:tv id:@"add" style:UITableViewCellStyleDefault];
	cell.textLabel.text = SCILocalized(@"Add preset");
	cell.textLabel.textColor = UIColor.systemBlueColor;
	cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
	cell.imageView.tintColor = UIColor.systemBlueColor;
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
	return ip.section == 2 && ip.row < (NSInteger)self.presets.count;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
	if (style != UITableViewCellEditingStyleDelete) return;

	NSMutableArray *items = self.presets.mutableCopy;
	[items removeObjectAtIndex:ip.row];
	[self setPresets:items];

	[tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];

	if (ip.section == 1 && ip.row == 1) {
		[self openCurrentPicker];
		return;
	}

	if (ip.section != 2) return;

	NSArray<NSDictionary *> *items = self.presets;

	if (ip.row < (NSInteger)items.count) {
		NSDictionary *p = items[ip.row];
		[self applyLat:[p[@"lat"] doubleValue] lon:[p[@"lon"] doubleValue] name:p[@"name"] enable:YES];
		return;
	}

	[self openPresetPicker];
}

// MARK: - Actions

- (void)enabledToggled:(UISwitch *)sw {
	[self.defaults setBool:sw.on forKey:kEnabled];
	[self refreshMapButton];
}

- (void)showButtonToggled:(UISwitch *)sw {
	[self.defaults setBool:sw.on forKey:kShowBtn];
	[self refreshMapButton];
}

- (void)openCurrentPicker {
	__weak typeof(self) weakSelf = self;

	[self presentPickerWithTitle:SCILocalized(@"Set current location") completion:^(double lat, double lon, NSString *name) {
		[weakSelf applyLat:lat lon:lon name:name enable:YES];
	}];
}

- (void)openPresetPicker {
	__weak typeof(self) weakSelf = self;

	[self presentPickerWithTitle:SCILocalized(@"Add preset") completion:^(double lat, double lon, NSString *name) {
		[weakSelf askNameAndSavePresetWithLat:lat lon:lon name:name];
	}];
}

@end