// Follow indicator — shows whether the profile user follows you.
// Fetches via /api/v1/friendships/show/{pk}/, renders inside the stats container.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../Networking/SCIInstagramAPI.h"
#import <objc/runtime.h>

static const NSInteger kFollowBadgeTag = 99788;
static const char kFollowStatusKey;
static const char kFollowProfilePKKey;

static NSNumber *sciGetFollowStatus(id vc) {
	return objc_getAssociatedObject(vc, &kFollowStatusKey);
}

static void sciSetFollowStatus(id vc, NSNumber *status) {
	objc_setAssociatedObject(vc, &kFollowStatusKey, status, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *sciGetFollowProfilePK(id vc) {
	return objc_getAssociatedObject(vc, &kFollowProfilePKKey);
}

static void sciSetFollowProfilePK(id vc, NSString *pk) {
	objc_setAssociatedObject(vc, &kFollowProfilePKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static void sciRemoveBadgeFromView(UIView *view) {
	UIView *old = [view viewWithTag:kFollowBadgeTag];
	if (old) [old removeFromSuperview];
}

static UIView *sciFindStatContainer(UIView *rootView) {
	if (!rootView) return nil;

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:rootView];

	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];

		if ([NSStringFromClass([view class]) containsString:@"StatButtonContainerView"]) {
			return view;
		}

		for (UIView *subview in view.subviews) {
			[stack addObject:subview];
		}
	}

	return nil;
}

static void sciRenderBadge(UIViewController *vc) {
	NSNumber *status = sciGetFollowStatus(vc);
	if (!status) return;

	UIView *statContainer = sciFindStatContainer(vc.view);
	if (!statContainer) return;

	sciRemoveBadgeFromView(statContainer);

	BOOL followedBy = status.boolValue;
	NSString *text = followedBy ? SCILocalized(@"Follows you") : SCILocalized(@"Doesn't follow you");

	SCIChromeLabel *badge = [[SCIChromeLabel alloc] initWithText:text];
	badge.tag = kFollowBadgeTag;
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	badge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
	badge.textColor = followedBy
		? [UIColor colorWithRed:0.3 green:0.75 blue:0.4 alpha:1.0]
		: [UIColor colorWithRed:0.85 green:0.3 blue:0.3 alpha:1.0];

	[statContainer addSubview:badge];

	[NSLayoutConstraint activateConstraints:@[
		[badge.leadingAnchor constraintEqualToAnchor:statContainer.leadingAnchor],
		[badge.bottomAnchor constraintEqualToAnchor:statContainer.bottomAnchor constant:-8]
	]];
}

%hook IGProfileViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;

	if (![SCIUtils getBoolPref:@"follow_indicator"]) {
		sciRemoveBadgeFromView(self.view);
		sciSetFollowStatus(self, nil);
		sciSetFollowProfilePK(self, nil);
		return;
	}

	id igUser = nil;
	@try {
		igUser = [self valueForKey:@"user"];
	} @catch (__unused NSException *e) {}

	if (!igUser) {
		sciRemoveBadgeFromView(self.view);
		return;
	}

	NSString *profilePK = [SCIUtils pkFromIGUser:igUser];
	NSString *myPK = [SCIUtils currentUserPK];

	if (!profilePK.length || !myPK.length || [profilePK isEqualToString:myPK]) {
		sciRemoveBadgeFromView(self.view);
		sciSetFollowStatus(self, nil);
		sciSetFollowProfilePK(self, nil);
		return;
	}

	NSString *cachedPK = sciGetFollowProfilePK(self);
	NSNumber *cachedStatus = sciGetFollowStatus(self);

	if (cachedStatus && [cachedPK isEqualToString:profilePK]) {
		sciRenderBadge(self);
		return;
	}

	sciRemoveBadgeFromView(self.view);
	sciSetFollowStatus(self, nil);
	sciSetFollowProfilePK(self, profilePK);

	__weak UIViewController *weakSelf = self;
	NSString *requestedPK = [profilePK copy];
	NSString *path = [NSString stringWithFormat:@"friendships/show/%@/", requestedPK];

	[SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
		if (error || !response) return;

		BOOL followedBy = [response[@"followed_by"] boolValue];

		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *vc = weakSelf;
			if (!vc) return;

			if (![sciGetFollowProfilePK(vc) isEqualToString:requestedPK]) return;

			if (![SCIUtils getBoolPref:@"follow_indicator"]) {
				sciRemoveBadgeFromView(vc.view);
				sciSetFollowStatus(vc, nil);
				sciSetFollowProfilePK(vc, nil);
				return;
			}

			sciSetFollowStatus(vc, @(followedBy));
			sciRenderBadge(vc);
		});
	}];
}

%end