#import "SCIFakeLocationPickerVC.h"
#import <MapKit/MapKit.h>
#import "../Localization/SCILocalization.h"

@interface SCIFakeLocationSearchResultsVC : UITableViewController <MKLocalSearchCompleterDelegate>
@property (nonatomic,strong) MKLocalSearchCompleter *completer;
@property (nonatomic,copy) NSArray<MKLocalSearchCompletion *> *results;
@property (nonatomic,copy) void (^onSelect)(MKLocalSearchCompletion *);
@property (nonatomic,assign) MKCoordinateRegion region;
@end

@implementation SCIFakeLocationSearchResultsVC

- (instancetype)init {
	if ((self = [super initWithStyle:UITableViewStylePlain])) {
		_completer = [MKLocalSearchCompleter new];
		_completer.delegate = self;
		_results = @[];
	}
	return self;
}

- (void)dealloc {
	_completer.delegate = nil;
}

- (void)setRegion:(MKCoordinateRegion)region {
	_region = region;
	if (CLLocationCoordinate2DIsValid(region.center)) _completer.region = region;
}

- (void)setQuery:(NSString *)query {
	if (!query.length) {
		self.results = @[];
		[self.tableView reloadData];
		return;
	}
	_completer.queryFragment = query;
}

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
	self.results = completer.results ?: @[];
	[self.tableView reloadData];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
	self.results = @[];
	[self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"result"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"result"];

	MKLocalSearchCompletion *result = self.results[indexPath.row];
	cell.textLabel.text = result.title;
	cell.detailTextLabel.text = result.subtitle;
	cell.imageView.image = [UIImage systemImageNamed:@"mappin.circle"];
	cell.imageView.tintColor = UIColor.systemRedColor;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row < self.results.count && self.onSelect) self.onSelect(self.results[indexPath.row]);
}

@end

@interface SCIFakeLocationPickerVC () <MKMapViewDelegate,UISearchResultsUpdating,CLLocationManagerDelegate>
@property (nonatomic,strong) MKMapView *mapView;
@property (nonatomic,strong) MKPointAnnotation *pin;
@property (nonatomic,strong) UISearchController *searchController;
@property (nonatomic,strong) SCIFakeLocationSearchResultsVC *resultsVC;
@property (nonatomic,strong) UIButton *locateButton;
@property (nonatomic,strong) UIVisualEffectView *cardView;
@property (nonatomic,strong) UILabel *titleLabel;
@property (nonatomic,strong) UILabel *subtitleLabel;
@property (nonatomic,strong) UIButton *useButton;
@property (nonatomic,strong) CLLocationManager *locationManager;
@property (nonatomic,strong) CLGeocoder *geocoder;
@property (nonatomic,strong) MKLocalSearch *activeSearch;
@property (nonatomic,copy) NSString *resolvedName;
@property (nonatomic,assign) BOOL didRequestAuth;
@end

@implementation SCIFakeLocationPickerVC

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.title = self.titleText.length ? self.titleText : SCILocalized(@"Pick location");
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];

	_locationManager = [CLLocationManager new];
	_locationManager.delegate = self;
	_geocoder = [CLGeocoder new];

	[self setupMap];
	[self setupSearch];
	[self setupLocateButton];
	[self setupCard];

	CLLocationCoordinate2D coord = CLLocationCoordinate2DIsValid(self.initialCoord) ? self.initialCoord : CLLocationCoordinate2DMake(48.8584,2.2945);
	[self.mapView setRegion:MKCoordinateRegionMakeWithDistance(coord,1500,1500) animated:NO];
	self.resultsVC.region = self.mapView.region;

	if (CLLocationCoordinate2DIsValid(self.initialCoord)) [self dropPinAt:self.initialCoord name:nil resolve:YES];
}

- (void)dealloc {
	_mapView.delegate = nil;
	_locationManager.delegate = nil;
	_resultsVC.completer.delegate = nil;
	[_geocoder cancelGeocode];
	[_activeSearch cancel];
}

- (void)setupMap {
	self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
	self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.mapView.delegate = self;
	self.mapView.showsCompass = YES;
	self.mapView.showsUserLocation = YES;
	[self.view addSubview:self.mapView];

	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
	lp.minimumPressDuration = 0.35;
	[self.mapView addGestureRecognizer:lp];
}

- (void)setupSearch {
	self.resultsVC = [SCIFakeLocationSearchResultsVC new];

	__weak typeof(self) weakSelf = self;
	self.resultsVC.onSelect = ^(MKLocalSearchCompletion *completion) {
		[weakSelf searchCompletion:completion];
	};

	self.searchController = [[UISearchController alloc] initWithSearchResultsController:self.resultsVC];
	self.searchController.searchResultsUpdater = self;
	self.searchController.obscuresBackgroundDuringPresentation = YES;
	self.searchController.searchBar.placeholder = SCILocalized(@"Search address or place");

	self.navigationItem.searchController = self.searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;
}

- (void)setupLocateButton {
	self.locateButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.locateButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
	self.locateButton.tintColor = UIColor.systemBlueColor;
	self.locateButton.layer.cornerRadius = 8.0;
	self.locateButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.locateButton setImage:[UIImage systemImageNamed:@"location"] forState:UIControlStateNormal];
	[self.locateButton addTarget:self action:@selector(onLocateTap) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.locateButton];

	[NSLayoutConstraint activateConstraints:@[
		[self.locateButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12.0],
		[self.locateButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-140.0],
		[self.locateButton.widthAnchor constraintEqualToConstant:40.0],
		[self.locateButton.heightAnchor constraintEqualToConstant:40.0]
	]];
}

- (void)setupCard {
	self.cardView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
	self.cardView.layer.cornerRadius = 16.0;
	self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
	self.cardView.clipsToBounds = YES;
	self.cardView.hidden = YES;
	self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.cardView];

	self.titleLabel = [self labelWithFont:[UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold] color:nil];
	self.subtitleLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular] color:UIColor.secondaryLabelColor];

	self.useButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.useButton.backgroundColor = UIColor.systemBlueColor;
	self.useButton.layer.cornerRadius = 12.0;
	self.useButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.useButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
	[self.useButton setTitle:SCILocalized(@"Use this location") forState:UIControlStateNormal];
	[self.useButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	[self.useButton addTarget:self action:@selector(commit) forControlEvents:UIControlEventTouchUpInside];

	UIView *content = self.cardView.contentView;
	[content addSubview:self.titleLabel];
	[content addSubview:self.subtitleLabel];
	[content addSubview:self.useButton];

	[NSLayoutConstraint activateConstraints:@[
		[self.cardView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12.0],
		[self.cardView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12.0],
		[self.cardView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0],

		[self.titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:14.0],
		[self.titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
		[self.titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],

		[self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2.0],
		[self.subtitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
		[self.subtitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],

		[self.useButton.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:12.0],
		[self.useButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12.0],
		[self.useButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12.0],
		[self.useButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12.0],
		[self.useButton.heightAnchor constraintEqualToConstant:46.0]
	]];
}

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
	UILabel *label = [UILabel new];
	label.font = font;
	label.textColor = color ?: UIColor.labelColor;
	label.numberOfLines = 1;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	return label;
}

- (void)onLocateTap {
	if (!CLLocationManager.locationServicesEnabled) {
		[self showAlert:SCILocalized(@"Location Services off") message:SCILocalized(@"Turn Location Services on in Settings → Privacy to use your current location.") settings:NO];
		return;
	}

	CLAuthorizationStatus status = self.locationManager.authorizationStatus;
	if (status == kCLAuthorizationStatusNotDetermined) {
		self.didRequestAuth = YES;
		[self.locationManager requestWhenInUseAuthorization];
		return;
	}
	if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
		[self showAlert:SCILocalized(@"Location access denied") message:SCILocalized(@"Enable Location Services for Instagram in Settings to use your current location.") settings:YES];
		return;
	}

	CLLocation *loc = self.mapView.userLocation.location ?: self.locationManager.location;
	if (loc) [self useCoordinate:loc.coordinate name:SCILocalized(@"Current location") distance:800.0 resolve:YES];
	else [self.locationManager requestLocation];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
	if (!self.didRequestAuth) return;
	self.didRequestAuth = NO;
	[self onLocateTap];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
	CLLocation *loc = locations.lastObject;
	if (loc) [self useCoordinate:loc.coordinate name:SCILocalized(@"Current location") distance:800.0 resolve:YES];
}

- (void)showAlert:(NSString *)title message:(NSString *)message settings:(BOOL)settings {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

	if (settings) {
		[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Open Settings") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
			[UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
		}]];
	}

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)onLongPress:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan) return;
	CGPoint point = [gesture locationInView:self.mapView];
	[self dropPinAt:[self.mapView convertPoint:point toCoordinateFromView:self.mapView] name:nil resolve:YES];
}

- (void)useCoordinate:(CLLocationCoordinate2D)coord name:(NSString *)name distance:(CLLocationDistance)distance resolve:(BOOL)resolve {
	if (!CLLocationCoordinate2DIsValid(coord)) return;
	[self.mapView setRegion:MKCoordinateRegionMakeWithDistance(coord,distance,distance) animated:YES];
	[self dropPinAt:coord name:name resolve:resolve];
}

- (void)dropPinAt:(CLLocationCoordinate2D)coord name:(NSString *)name resolve:(BOOL)resolve {
	if (!CLLocationCoordinate2DIsValid(coord)) return;

	if (self.pin) [self.mapView removeAnnotation:self.pin];

	self.pin = [MKPointAnnotation new];
	self.pin.coordinate = coord;
	self.pin.title = name;
	self.resolvedName = name;

	[self.mapView addAnnotation:self.pin];
	[self.mapView selectAnnotation:self.pin animated:YES];
	[self updateCard];

	if (resolve) [self resolveCoordinate:coord];
}

- (void)resolveCoordinate:(CLLocationCoordinate2D)coord {
	[self.geocoder cancelGeocode];

	__weak typeof(self) weakSelf = self;
	CLLocation *loc = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];

	[self.geocoder reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *placemarks,NSError *error) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || error || !placemarks.count || ![self sameCoord:self.pin.coordinate other:coord]) return;

		CLPlacemark *p = placemarks.firstObject;
		NSString *name = p.name ?: p.locality ?: p.administrativeArea ?: p.country;
		if (!name.length) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			if (![self sameCoord:self.pin.coordinate other:coord]) return;
			self.resolvedName = name;
			self.pin.title = name;
			[self updateCard];
		});
	}];
}

- (BOOL)sameCoord:(CLLocationCoordinate2D)a other:(CLLocationCoordinate2D)b {
	return fabs(a.latitude - b.latitude) <= 0.0001 && fabs(a.longitude - b.longitude) <= 0.0001;
}

- (void)updateCard {
	if (!self.pin) {
		self.cardView.hidden = YES;
		return;
	}

	CLLocationCoordinate2D c = self.pin.coordinate;
	self.cardView.hidden = NO;
	self.titleLabel.text = self.resolvedName.length ? self.resolvedName : SCILocalized(@"Dropped pin");
	self.subtitleLabel.text = [NSString stringWithFormat:@"%.5f, %.5f",c.latitude,c.longitude];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	self.resultsVC.region = self.mapView.region;
	[self.resultsVC setQuery:searchController.searchBar.text];
}

- (void)searchCompletion:(MKLocalSearchCompletion *)completion {
	if (!completion) return;

	[self.activeSearch cancel];

	MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] initWithCompletion:completion];
	request.region = self.mapView.region;

	MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
	self.activeSearch = search;

	__weak typeof(self) weakSelf = self;
	[search startWithCompletionHandler:^(MKLocalSearchResponse *response,NSError *error) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || search != self.activeSearch || error || !response.mapItems.count) return;

		MKMapItem *item = response.mapItems.firstObject;
		CLLocationCoordinate2D coord = item.placemark.coordinate;
		NSString *name = item.name.length ? item.name : completion.title;

		dispatch_async(dispatch_get_main_queue(), ^{
			if (search != self.activeSearch) return;
			self.activeSearch = nil;
			[self.searchController setActive:NO];
			[self useCoordinate:coord name:name distance:1500.0 resolve:NO];
		});
	}];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
	if ([annotation isKindOfClass:MKUserLocation.class]) return nil;

	static NSString *identifier = @"SCIFakeLocationPin";
	MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:identifier];

	if (!view) view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
	else view.annotation = annotation;

	view.draggable = YES;
	view.canShowCallout = YES;
	view.markerTintColor = UIColor.systemRedColor;
	view.animatesWhenAdded = YES;
	return view;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view didChangeDragState:(MKAnnotationViewDragState)newState fromOldState:(MKAnnotationViewDragState)oldState {
	if (newState != MKAnnotationViewDragStateEnding) return;
	view.dragState = MKAnnotationViewDragStateNone;
	self.resolvedName = nil;
	[self updateCard];
	[self resolveCoordinate:view.annotation.coordinate];
}

- (void)cancel {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)commit {
	if (!self.pin) return;

	CLLocationCoordinate2D c = self.pin.coordinate;
	NSString *name = self.resolvedName.length ? self.resolvedName : [NSString stringWithFormat:@"%.4f, %.4f",c.latitude,c.longitude];
	void (^callback)(double,double,NSString *) = self.onPick;

	[self dismissViewControllerAnimated:YES completion:^{
		if (callback) callback(c.latitude,c.longitude,name);
	}];
}

@end