// Full profile counts — rewrite IGStatButton labels from "11.9K" to "11,943".

#import "../../Utils.h"

static inline BOOL sciFullFollowersCountEnabled(void) {
	return [SCIUtils getBoolPref:@"full_followers_count"];
}

static inline BOOL sciFullPostsCountEnabled(void) {
	return [SCIUtils getBoolPref:@"full_posts_count"];
}

static id sciSafeValue(id obj, NSString *key) {
	if (!obj || !key.length) return nil;
	@try { return [obj valueForKey:key]; } @catch (__unused id e) { return nil; }
}

static NSNumber *sciNumberValue(id value) {
	if ([value isKindOfClass:NSNumber.class]) return value;
	if (![value isKindOfClass:NSString.class]) return nil;

	NSString *text = [(NSString *)value stringByReplacingOccurrencesOfString:@"," withString:@""];
	return text.length ? @(text.longLongValue) : nil;
}

static NSString *sciFormattedCount(NSNumber *number) {
	if (![number isKindOfClass:NSNumber.class]) return nil;

	static NSNumberFormatter *formatter;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [NSNumberFormatter new];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
		formatter.usesGroupingSeparator = YES;
	});

	return [formatter stringFromNumber:number];
}

static Ivar sciIvar(Class cls, const char *name) {
	return cls ? class_getInstanceVariable(cls, name) : NULL;
}

static NSString *sciButtonName(id button) {
	static Ivar nameIvar;
	static Ivar nameLabelIvar;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		Class cls = NSClassFromString(@"IGStatButton");
		nameIvar = sciIvar(cls, "_name");
		nameLabelIvar = sciIvar(cls, "_nameLabel");
	});

	@try {
		NSString *name = nameIvar ? object_getIvar(button, nameIvar) : nil;
		if ([name isKindOfClass:NSString.class] && name.length) return name;

		UILabel *label = nameLabelIvar ? object_getIvar(button, nameLabelIvar) : nil;
		if ([label isKindOfClass:UILabel.class] && label.text.length) return label.text;
	} @catch (__unused id e) {}

	return nil;
}

static NSInteger sciButtonKind(id button) {
	NSString *low = sciButtonName(button).lowercaseString;
	if (!low.length) return 0;

	if (sciFullFollowersCountEnabled() && [low containsString:@"follower"]) return 1;
	if (sciFullPostsCountEnabled() && [low containsString:@"post"]) return 2;

	return 0;
}

// Own-profile detection — mirrors FakeProfileStats.x.
static Class sciStatsCellClass(void) {
	static Class cached;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cached = NSClassFromString(@"IGProfileSimpleAvatarStatsCell");
		if (!cached) cached = NSClassFromString(@"_TtC21IGProfileDetailHeader30IGProfileSimpleAvatarStatsCell");
		if (!cached) {
			unsigned int n = 0;
			Class *list = objc_copyClassList(&n);
			for (unsigned int i = 0; i < n; i++) {
				const char *nm = class_getName(list[i]);
				if (nm && strstr(nm, "IGProfileSimpleAvatarStatsCell")) {
					cached = list[i];
					break;
				}
			}
			free(list);
		}
	});
	return cached;
}

static BOOL sciButtonIsOnOwnProfile(UIView *btn) {
	Class cellCls = sciStatsCellClass();
	if (!cellCls) return NO;

	UIView *cur = btn;
	while (cur && ![cur isKindOfClass:cellCls]) cur = cur.superview;
	if (!cur) return NO;

	@try {
		id v = [cur valueForKey:@"isCurrentUser"];
		if (v) return [v boolValue];
	} @catch (__unused id e) {}

	Ivar iv = class_getInstanceVariable([cur class], "_isCurrentUser");
	if (!iv) iv = class_getInstanceVariable([cur class], "isCurrentUser");
	if (!iv) return NO;
	return *(BOOL *)((uint8_t *)(__bridge void *)cur + ivar_getOffset(iv));
}

// Fake stats win on own profile.
static BOOL sciFakeOwnsCountForKind(NSInteger kind, UIView *btn) {
	NSString *fakeKey = kind == 1 ? @"fake_follower_count"
	                  : kind == 2 ? @"fake_post_count" : nil;
	if (!fakeKey) return NO;
	if (![SCIUtils getBoolPref:fakeKey]) return NO;
	return sciButtonIsOnOwnProfile(btn);
}

static id sciProfileUserForButton(UIView *button) {
	UIViewController *vc = nil;

	@try {
		vc = [SCIUtils nearestViewControllerForView:button];
	} @catch (__unused id e) {}

	if (!vc) return nil;

	id user = sciSafeValue(vc, @"user");
	if (user) return user;

	user = sciSafeValue(vc, @"userGQL");
	return user ?: sciSafeValue(vc, @"profileUser");
}

static NSDictionary *sciFieldCacheForUser(id user) {
	@try {
		NSDictionary *cache = [SCIUtils fieldCacheForObject:user];
		return [cache isKindOfClass:NSDictionary.class] ? cache : nil;
	} @catch (__unused id e) {
		return nil;
	}
}

static NSNumber *sciFollowerCount(id user, NSDictionary *cache) {
	NSNumber *count = sciNumberValue(sciSafeValue(user, @"followerCount"));
	if (count) return count;

	count = sciNumberValue(sciSafeValue(user, @"followersCount"));
	if (count) return count;

	count = sciNumberValue(sciSafeValue(user, @"followedByCount"));
	if (count) return count;

	count = sciNumberValue(cache[@"follower_count"]);
	if (count) return count;

	id edge = cache[@"edge_followed_by"];
	return [edge isKindOfClass:NSDictionary.class] ? sciNumberValue(edge[@"count"]) : nil;
}

static NSNumber *sciPostCount(id user, NSDictionary *cache) {
	NSNumber *count = sciNumberValue(sciSafeValue(user, @"mediaCount"));
	if (count) return count;

	count = sciNumberValue(sciSafeValue(user, @"postCount"));
	if (count) return count;

	count = sciNumberValue(sciSafeValue(user, @"postsCount"));
	if (count) return count;

	count = sciNumberValue(cache[@"media_count"]);
	if (count) return count;

	count = sciNumberValue(cache[@"post_count"]);
	if (count) return count;

	id edge = cache[@"edge_owner_to_timeline_media"];
	return [edge isKindOfClass:NSDictionary.class] ? sciNumberValue(edge[@"count"]) : nil;
}

static void sciSetCountLabel(id button, NSString *text) {
	if (!text.length) return;

	static Ivar countLabelIvar;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		countLabelIvar = sciIvar(NSClassFromString(@"IGStatButton"), "_countLabel");
	});

	if (!countLabelIvar) return;

	@try {
		UILabel *label = object_getIvar(button, countLabelIvar);
		if ([label isKindOfClass:UILabel.class]) {
			label.text = text;
			[label sizeToFit];
		}
	} @catch (__unused id e) {}
}

static void sciApplyFullProfileCount(id button) {
	if (![button isKindOfClass:UIView.class]) return;
	if (!sciFullFollowersCountEnabled() && !sciFullPostsCountEnabled()) return;

	NSInteger kind = sciButtonKind(button);
	if (kind == 0) return;

	if (sciFakeOwnsCountForKind(kind, (UIView *)button)) return;

	id user = sciProfileUserForButton((UIView *)button);
	if (!user) return;

	NSDictionary *cache = sciFieldCacheForUser(user);
	NSNumber *count = kind == 1 ? sciFollowerCount(user, cache) : sciPostCount(user, cache);

	sciSetCountLabel(button, sciFormattedCount(count));
}

%hook IGStatButton

- (void)setName:(id)name {
	%orig;
	sciApplyFullProfileCount(self);
}

- (void)setCount:(id)count {
	%orig;
	sciApplyFullProfileCount(self);
}

- (void)layoutSubviews {
	%orig;
	sciApplyFullProfileCount(self);
}

%end
