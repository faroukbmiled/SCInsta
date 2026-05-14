// Hide Instagram TestFlight beta update popup.

#import "../../Utils.h"
#import <Foundation/Foundation.h>

// spoof appStoreReceiptURL away from "sandboxReceipt"
%group SCIHideTestFlightNagReceipt
%hook NSBundle
- (NSURL *)appStoreReceiptURL {
	NSURL *url = %orig;
	if ([url.lastPathComponent isEqualToString:@"sandboxReceipt"]) {
		return [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"receipt"];
	}
	return url;
}
%end
%end

// Disabled: Hide Instagram TestFlight / beta update popup.
// %group SCIHideTestFlightNagVC
// %hook _TtC29IGCoreRootTestFlightNagPlugin35TestFlightUpdateNudgeViewController

// - (void)viewDidLoad {
// 	%orig;
// 	UIViewController *vc = (UIViewController *)(id)self;
// 	if (![vc isKindOfClass:UIViewController.class]) return;
// 	vc.view.hidden = YES;
// 	vc.view.userInteractionEnabled = NO;
// }

// - (void)viewDidAppear:(BOOL)animated {
// 	%orig;
// 	UIViewController *vc = (UIViewController *)(id)self;
// 	if (![vc isKindOfClass:UIViewController.class]) return;
// 	[vc dismissViewControllerAnimated:NO completion:nil];
// }

// %end
// %end

%ctor {
	if ([SCIUtils getBoolPref:@"hide_testflight_nag"]) {
		%init(SCIHideTestFlightNagReceipt);
	}
}
