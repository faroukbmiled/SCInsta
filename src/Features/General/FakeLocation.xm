// Fake location — overrides CLLocationManager so IG receives the selected fake coordinate.

#import "../../Utils.h"
#import <CoreLocation/CoreLocation.h>

static BOOL SCIFakeLocationEnabled(void) {
	return [SCIUtils getBoolPref:@"fake_location_enabled"];
}

static CLLocationCoordinate2D SCIFakeCoordinate(void) {
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	double lat = [[defaults objectForKey:@"fake_location_lat"] doubleValue];
	double lon = [[defaults objectForKey:@"fake_location_lon"] doubleValue];
	return CLLocationCoordinate2DMake(lat, lon);
}

static CLLocation *SCIFakeLocation(void) {
	CLLocationCoordinate2D coord = SCIFakeCoordinate();

	if (!CLLocationCoordinate2DIsValid(coord)) {
		coord = CLLocationCoordinate2DMake(0.0, 0.0);
	}

	return [[CLLocation alloc] initWithCoordinate:coord altitude:35.0 horizontalAccuracy:5.0 verticalAccuracy:5.0 timestamp:NSDate.date];
}

static void SCIFeedFakeLocation(CLLocationManager *manager) {
	if (!manager || !SCIFakeLocationEnabled()) return;

	id<CLLocationManagerDelegate> delegate = manager.delegate;
	if (!delegate) return;

	CLLocation *location = SCIFakeLocation();

	dispatch_async(dispatch_get_main_queue(), ^{
		if ([delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
			[delegate locationManager:manager didUpdateLocations:@[location]];
			return;
		}

		if ([delegate respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
			[delegate locationManager:manager didUpdateToLocation:location fromLocation:location];
		}
	});
}

%hook CLLocationManager

- (CLLocation *)location {
	return SCIFakeLocationEnabled() ? SCIFakeLocation() : %orig;
}

- (void)setDelegate:(id<CLLocationManagerDelegate>)delegate {
	%orig;

	if (SCIFakeLocationEnabled()) {
		SCIFeedFakeLocation(self);
	}
}

- (void)startUpdatingLocation {
	if (SCIFakeLocationEnabled()) {
		SCIFeedFakeLocation(self);
		return;
	}

	%orig;
}

- (void)requestLocation {
	if (SCIFakeLocationEnabled()) {
		SCIFeedFakeLocation(self);
		return;
	}

	%orig;
}

- (void)startMonitoringSignificantLocationChanges {
	if (SCIFakeLocationEnabled()) {
		SCIFeedFakeLocation(self);
		return;
	}

	%orig;
}

%end