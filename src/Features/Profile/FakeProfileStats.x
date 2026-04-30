// Fake profile stats for own profile — follower/following/post counts
// and verified badge. Counts rewrite IGStatButton labels; verified flips
// is_verified at the JSON parse layer + swizzles IGUsernameModel to catch
// cached-model renders.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static BOOL sciFakeOn(NSString *key) {
	return [SCIUtils getBoolPref:key];
}

// IG format — 1,192 / 12.3K / 1.2M / 1.2B. Raw digits only; passthrough otherwise.
static NSString *sciFormatCount(NSString *raw) {
	raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (!raw.length) return nil;

	NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];

	for (NSUInteger i = 0; i < raw.length; i++) {
		if (![digits characterIsMember:[raw characterAtIndex:i]]) {
			return raw;
		}
	}

	long long n = raw.longLongValue;

	if (n < 10000) {
		NSNumberFormatter *f = [NSNumberFormatter new];
		f.numberStyle = NSNumberFormatterDecimalStyle;
		return [f stringFromNumber:@(n)];
	}

	double d;
	NSString *suf;

	if (n >= 1000000000LL) {
		d = n / 1000000000.0;
		suf = @"B";
	} else if (n >= 1000000LL) {
		d = n / 1000000.0;
		suf = @"M";
	} else {
		d = n / 1000.0;
		suf = @"K";
	}

	NSString *s = [NSString stringWithFormat:@"%.1f", d];

	if ([s hasSuffix:@".0"]) {
		s = [s substringToIndex:s.length - 2];
	}

	return [s stringByAppendingString:suf];
}

static NSString *sciFakeValue(NSString *valueKey) {
	return sciFormatCount([[NSUserDefaults standardUserDefaults] stringForKey:valueKey]);
}

// ============ Fake counts — IGStatButton label rewrite ============

static BOOL sciButtonIsOnOwnProfile(UIView *btn) {
	Class selfCellCls = NSClassFromString(@"IGProfileSimpleAvatarStatsCell");
	if (!selfCellCls) return NO;

	UIView *cur = btn;

	while (cur && ![cur isKindOfClass:selfCellCls]) {
		cur = cur.superview;
	}

	if (!cur) return NO;

	@try {
		id value = [cur valueForKey:@"isCurrentUser"];
		if (value) return [value boolValue];
	} @catch (__unused id e) {}

	Ivar iv = class_getInstanceVariable([cur class], "_isCurrentUser");
	if (!iv) return NO;

	return *(BOOL *)((uint8_t *)(__bridge void *)cur + ivar_getOffset(iv));
}

static NSString *sciFakeTextForName(NSString *name) {
	if (![name isKindOfClass:[NSString class]]) return nil;

	NSString *low = name.lowercaseString;

	if ([low containsString:@"follower"]) {
		if (sciFakeOn(@"fake_follower_count")) {
			return sciFakeValue(@"fake_follower_count_value");
		}
	} else if ([low containsString:@"following"]) {
		if (sciFakeOn(@"fake_following_count")) {
			return sciFakeValue(@"fake_following_count_value");
		}
	} else if ([low containsString:@"post"]) {
		if (sciFakeOn(@"fake_post_count")) {
			return sciFakeValue(@"fake_post_count_value");
		}
	}

	return nil;
}

static void sciApplyFakeToButton(id btn) {
	if (!sciFakeOn(@"fake_follower_count") &&
		!sciFakeOn(@"fake_following_count") &&
		!sciFakeOn(@"fake_post_count")) {
		return;
	}

	if (!sciButtonIsOnOwnProfile(btn)) return;

	Ivar nmIv = class_getInstanceVariable([btn class], "_name");
	NSString *name = nil;

	if (nmIv) {
		@try {
			name = object_getIvar(btn, nmIv);
		} @catch (__unused id e) {}
	}

	NSString *fake = sciFakeTextForName(name);
	if (!fake.length) return;

	Ivar lblIv = class_getInstanceVariable([btn class], "_countLabel");
	UILabel *lbl = nil;

	if (lblIv) {
		@try {
			lbl = object_getIvar(btn, lblIv);
		} @catch (__unused id e) {}
	}

	if ([lbl isKindOfClass:[UILabel class]]) {
		lbl.text = fake;
	}
}

static void (*orig_setName)(id, SEL, id);
static void new_setName(id self, SEL _cmd, id name) {
	if (orig_setName) {
		orig_setName(self, _cmd, name);
	}

	sciApplyFakeToButton(self);
}

static void (*orig_setCount)(id, SEL, id);
static void new_setCount(id self, SEL _cmd, id cfg) {
	if (orig_setCount) {
		orig_setCount(self, _cmd, cfg);
	}

	sciApplyFakeToButton(self);
}

static void (*orig_layout)(id, SEL);
static void new_layout(id self, SEL _cmd) {
	if (orig_layout) {
		orig_layout(self, _cmd);
	}

	sciApplyFakeToButton(self);
}

// ============ Fake verified — JSON response rewrite ============

static NSString *gSelfPK = nil;
static NSString *gSelfUsername = nil;

static BOOL sciPKMatchesSelf(id pk) {
	if (!gSelfPK.length) return NO;

	if ([pk isKindOfClass:[NSString class]]) {
		return [pk isEqualToString:gSelfPK];
	}

	if ([pk isKindOfClass:[NSNumber class]]) {
		return [[(NSNumber *)pk stringValue] isEqualToString:gSelfPK];
	}

	return NO;
}

static void sciFlipVerifiedInJSON(id obj, int depth) {
	if (![SCIUtils getBoolPref:@"fake_verified"]) return;
	if (depth > 16) return;

	if ([obj isKindOfClass:[NSMutableDictionary class]]) {
		NSMutableDictionary *d = obj;

		id pk = d[@"pk"] ?: d[@"strong_id__"] ?: d[@"user_id"] ?: d[@"id"];

		if (sciPKMatchesSelf(pk)) {
			d[@"is_verified"] = @YES;
		}

		for (id v in d.allValues) {
			sciFlipVerifiedInJSON(v, depth + 1);
		}
	} else if ([obj isKindOfClass:[NSMutableArray class]]) {
		for (id v in (NSMutableArray *)obj) {
			sciFlipVerifiedInJSON(v, depth + 1);
		}
	}
}

// Belt-and-suspenders — profile header reads isVerified from a cached
// IGUsernameModel without re-parsing JSON on every refresh.
typedef BOOL (*SciIsVerifiedFn)(id, SEL);
static SciIsVerifiedFn orig_UsernameModel_isVerified = NULL;

static BOOL new_UsernameModel_isVerified(id self, SEL _cmd) {
	BOOL originalValue = orig_UsernameModel_isVerified ? orig_UsernameModel_isVerified(self, _cmd) : NO;

	if (![SCIUtils getBoolPref:@"fake_verified"]) {
		return originalValue;
	}

	if (originalValue) {
		return YES;
	}

	if (!gSelfUsername.length) {
		return NO;
	}

	NSString *username = nil;

	@try {
		username = [self valueForKey:@"username"];
	} @catch (__unused id e) {}

	if ([username isKindOfClass:[NSString class]] && [username isEqualToString:gSelfUsername]) {
		return YES;
	}

	return NO;
}

static id (*orig_JSONObjectWithData)(Class, SEL, NSData *, NSJSONReadingOptions, NSError **);
static id new_JSONObjectWithData(Class self, SEL _cmd, NSData *data, NSJSONReadingOptions opts, NSError **err) {
	if (!orig_JSONObjectWithData) return nil;

	if (![SCIUtils getBoolPref:@"fake_verified"]) {
		return orig_JSONObjectWithData(self, _cmd, data, opts, err);
	}

	opts |= NSJSONReadingMutableContainers;

	id result = orig_JSONObjectWithData(self, _cmd, data, opts, err);

	if (result) {
		sciFlipVerifiedInJSON(result, 0);
	}

	return result;
}

static void sciRefreshSelfIdentity(void) {
	NSString *pk = nil;
	NSString *username = nil;

	@try {
		pk = [[SCIUtils currentUserPK] copy];
	} @catch (__unused id e) {}

	@try {
		id session = [SCIUtils activeUserSession];
		id user = [session valueForKey:@"user"];
		username = [[user valueForKey:@"username"] copy];
	} @catch (__unused id e) {}

	if (pk.length) {
		gSelfPK = pk;
	}

	if (username.length) {
		gSelfUsername = username;
	}
}

__attribute__((constructor)) static void _sciFakeStatsInit(void) {
	Class sb = NSClassFromString(@"IGStatButton");

	if (sb) {
		MSHookMessageEx(sb, @selector(setName:), (IMP)new_setName, (IMP *)&orig_setName);
		MSHookMessageEx(sb, @selector(setCount:), (IMP)new_setCount, (IMP *)&orig_setCount);
		MSHookMessageEx(sb, @selector(layoutSubviews), (IMP)new_layout, (IMP *)&orig_layout);
	}

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		sciRefreshSelfIdentity();
	});

	[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
													  object:nil
													   queue:nil
												  usingBlock:^(__unused NSNotification *n) {
		sciRefreshSelfIdentity();
	}];

	Class jc = object_getClass([NSJSONSerialization class]);

	if (jc) {
		MSHookMessageEx(jc,
						@selector(JSONObjectWithData:options:error:),
						(IMP)new_JSONObjectWithData,
						(IMP *)&orig_JSONObjectWithData);
	}

	Class um = NSClassFromString(@"IGUsernameModel");

	if (um) {
		Method m = class_getInstanceMethod(um, @selector(isVerified));

		if (m) {
			orig_UsernameModel_isVerified = (SciIsVerifiedFn)method_getImplementation(m);
			method_setImplementation(m, (IMP)new_UsernameModel_isVerified);
		}
	}
}