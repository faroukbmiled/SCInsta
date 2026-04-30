#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%group NoSuggestedUsersGroup

// "Welcome to instagram" suggested users in feed
%hook IGSuggestedUnitViewModel

- (id)initWithAYMFModel:(id)arg1 headerViewModel:(id)arg2 {
	NSLog(@"[SCInsta] Hiding suggested users: main feed welcome section");
	return nil;
}

%end

%hook IGSuggestionsUnitViewModel

- (id)initWithAYMFModel:(id)arg1 headerViewModel:(id)arg2 {
	NSLog(@"[SCInsta] Hiding suggested users: main feed welcome section");
	return nil;
}

%end

// Suggested users in profile header
%hook IGProfileHeaderView

- (id)objectsForListAdapter:(id)arg1 {
	NSArray *originalObjs = %orig();
	NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

	for (id obj in originalObjs) {
		if ([obj isKindOfClass:%c(IGProfileChainingModel)]) {
			NSLog(@"[SCInsta] Hiding suggested users: profile header");
			continue;
		}

		[filteredObjs addObject:obj];
	}

	return [filteredObjs copy];
}

%end

// Notifications/activity feed
%hook IGActivityFeedViewController

- (id)objectsForListAdapter:(id)arg1 {
	NSArray *originalObjs = %orig();
	NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

	for (id obj in originalObjs) {
		BOOL shouldHide = NO;

		if ([obj isKindOfClass:%c(IGLabelItemViewModel)]) {
			@try {
				shouldHide = [[obj valueForKey:@"tag"] intValue] == 2;
			} @catch (__unused id e) {}
		} else if ([obj isKindOfClass:%c(IGDiscoverPeopleItemConfiguration)] || [obj isKindOfClass:%c(IGSeeAllItemConfiguration)]) {
			shouldHide = YES;
		}

		if (!shouldHide) [filteredObjs addObject:obj];
	}

	return [filteredObjs copy];
}

%end

// Profile "following" and "followers" tabs
%hook IGFollowListViewController

- (id)objectsForListAdapter:(id)arg1 {
	NSArray *originalObjs = %orig(arg1);
	NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

	for (id obj in originalObjs) {
		BOOL shouldHide = NO;

		if ([obj isKindOfClass:%c(IGDiscoverPeopleItemConfiguration)]) {
			NSLog(@"[SCInsta] Hiding suggested users: follow list suggested user");
			shouldHide = YES;
		} else if ([obj isKindOfClass:%c(IGLabelItemViewModel)]) {
			@try {
				shouldHide = [[obj valueForKey:@"labelTitle"] isEqualToString:@"Suggested for you"];
			} @catch (__unused id e) {}
		} else if ([obj isKindOfClass:%c(IGSeeAllItemConfiguration)] && ((IGSeeAllItemConfiguration *)obj).destination == 4) {
			NSLog(@"[SCInsta] Hiding suggested users: follow list suggested user");
			shouldHide = YES;
		}

		if (!shouldHide) [filteredObjs addObject:obj];
	}

	return [filteredObjs copy];
}

%end

%hook IGSegmentedTabControl

- (void)setSegments:(id)segments {
	if (![segments isKindOfClass:[NSArray class]]) {
		%orig(segments);
		return;
	}

	NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[segments count]];

	for (id obj in (NSArray *)segments) {
		if ([obj isKindOfClass:%c(IGFindUsersViewController)]) {
			NSLog(@"[SCInsta] Hiding suggested users: find users segmented tab");
			continue;
		}

		[filteredObjs addObject:obj];
	}

	%orig([filteredObjs copy]);
}

%end

// Suggested subscriptions
%hook IGFanClubSuggestedUsersDataSource

- (id)initWithUserSession:(id)arg1 delegate:(id)arg2 {
	return nil;
}

%end

// Follow request/discover section
%hook _TtC17IGFriendingCenter31IGFriendingCenterViewController

- (id)objectsForListAdapter:(id)arg1 {
	NSArray *originalObjs = %orig(arg1);
	NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

	for (id obj in originalObjs) {
		BOOL shouldHide = NO;

		if ([obj isKindOfClass:%c(IGDiscoverPeopleItemConfiguration)]) {
			NSLog(@"[SCInsta] Hiding suggested users: follow list suggested user");
			shouldHide = YES;
		} else if ([obj isKindOfClass:%c(IGLabelItemViewModel)]) {
			@try {
				shouldHide = [[obj valueForKey:@"labelTitle"] isEqualToString:@"Suggested for you"];
			} @catch (__unused id e) {}
		}

		if (!shouldHide) [filteredObjs addObject:obj];
	}

	return [filteredObjs copy];
}

%end

%hook IGProfileActionBarViewModel

- (id)initWithIdentifier:(id)arg1
					rows:(id)arg2
	 allActionsToDisplay:(id)arg3
		 overflowActions:(id)arg4
	actionToBadgeInfoMap:(id)arg5
	  allBusinessActions:(id)arg6
 overflowBusinessActions:(id)arg7
	 contactSheetActions:(id)arg8
					user:(id)arg9
   sponsoredInfoProvider:(id)arg10
  profileBackgroundColor:(id)arg11 {

	NSArray *rows = arg2;
	NSOrderedSet *allActions = [arg3 copy];
	NSOrderedSet *overflowActions = [arg4 copy];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT (SELF IN %@)", @[@(3)]];

	allActions = [allActions filteredOrderedSetUsingPredicate:predicate];
	overflowActions = [overflowActions filteredOrderedSetUsingPredicate:predicate];

	NSMutableArray *filteredRows = [NSMutableArray new];

	for (NSOrderedSet *set in rows) {
		[filteredRows addObject:[set filteredOrderedSetUsingPredicate:predicate]];
	}

	rows = [filteredRows copy];

	return %orig(arg1, rows, allActions, overflowActions, arg5, arg6, arg7, arg8, arg9, arg10, arg11);
}

%end

%end

%ctor {
	if ([SCIUtils getBoolPref:@"no_suggested_users"]) {
		%init(NoSuggestedUsersGroup);
	}
}