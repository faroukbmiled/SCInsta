// Date format hooks — replace IG's relative timestamps with a custom format.
// Supports absolute formats, relative threshold, and compact relative style.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "SCIDateFormatEntries.h"
#import <substrate.h>

static NSString *const kDateFmtKey = @"feed_date_format";
static NSString *const kShowSecondsKey = @"feed_date_show_seconds";
static NSString *const kRelativeThresholdKey = @"feed_date_relative_days_threshold";
static NSString *const kCompactRelativeKey = @"feed_date_compact_relative";

static NSDictionary<NSString *, NSArray<NSString *> *> *sciDatePatternMap(void) {
	static NSDictionary *map = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		map = @{
			@"short": @[@"MMM d", @"MMM d"],
			@"medium": @[@"MMM d, yyyy", @"MMM d, yyyy"],
			@"full": @[@"MMM d, yyyy 'at' h:mm a", @"MMM d, yyyy 'at' h:mm:ss a"],
			@"time_12": @[@"MMM d 'at' h:mm a", @"MMM d 'at' h:mm:ss a"],
			@"time_24": @[@"MMM d 'at' HH:mm", @"MMM d 'at' HH:mm:ss"],
			@"dd_mmm": @[@"dd-MMM-yyyy 'at' h:mm a", @"dd-MMM-yyyy 'at' h:mm:ss a"],
			@"day_slash": @[@"dd/MM/yyyy h:mm a", @"dd/MM/yyyy h:mm:ss a"],
			@"month_slash": @[@"MM/dd/yyyy h:mm a", @"MM/dd/yyyy h:mm:ss a"],
			@"euro": @[@"dd.MM.yyyy HH:mm", @"dd.MM.yyyy HH:mm:ss"],
			@"iso": @[@"yyyy-MM-dd", @"yyyy-MM-dd"],
			@"iso_time": @[@"yyyy-MM-dd HH:mm", @"yyyy-MM-dd HH:mm:ss"],
		};
	});
	return map;
}

static NSDateFormatter *sciFormatterForPattern(NSString *pattern) {
	if (!pattern.length) return nil;

	static NSMutableDictionary<NSString *, NSDateFormatter *> *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [NSMutableDictionary dictionary];
	});

	@synchronized(cache) {
		NSDateFormatter *df = cache[pattern];
		if (!df) {
			df = [NSDateFormatter new];
			df.locale = [NSLocale currentLocale];
			df.dateFormat = pattern;
			cache[pattern] = df;
		}
		return df;
	}
}

static NSString *sciRelativeUnit(NSInteger value, NSString *compactUnit, NSString *fullUnit, BOOL compact) {
	if (compact) return [NSString stringWithFormat:@"%ld%@", (long)value, compactUnit];

	NSString *suffix = value == 1 ? fullUnit : [fullUnit stringByAppendingString:@"s"];
	return [NSString stringWithFormat:@"%ld %@ ago", (long)value, suffix];
}

static NSString *sciRelativeFormat(NSDate *date) {
	if (!date) return nil;

	NSInteger thresholdDays = [[NSUserDefaults standardUserDefaults] integerForKey:kRelativeThresholdKey];
	if (thresholdDays <= 0) return nil;

	NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:date];
	if (diff < 0) diff = 0;

	NSTimeInterval maxAge = (NSTimeInterval)thresholdDays * 86400.0;
	if (diff >= maxAge) return nil;

	BOOL compact = [[NSUserDefaults standardUserDefaults] boolForKey:kCompactRelativeKey];

	if (diff < 60.0) return compact ? @"now" : @"just now";

	NSInteger minutes = (NSInteger)(diff / 60.0);
	if (minutes < 60) return sciRelativeUnit(minutes, @"m", @"minute", compact);

	NSInteger hours = (NSInteger)(diff / 3600.0);
	if (hours < 24) return sciRelativeUnit(hours, @"h", @"hour", compact);

	NSInteger days = (NSInteger)(diff / 86400.0);
	if (days < 7) return sciRelativeUnit(MAX(days, 1), @"d", @"day", compact);

	NSInteger weeks = (NSInteger)(diff / 604800.0);
	return sciRelativeUnit(MAX(weeks, 1), @"w", @"week", compact);
}

static NSString *sciAbsoluteFormat(NSDate *date) {
	if (!date) return nil;

	NSString *fmt = [SCIUtils getStringPref:kDateFmtKey];
	if (!fmt.length || [fmt isEqualToString:@"default"]) return nil;

	NSArray *patterns = sciDatePatternMap()[fmt];
	if (!patterns.count) return nil;

	BOOL showSeconds = [[NSUserDefaults standardUserDefaults] boolForKey:kShowSecondsKey];
	NSString *pattern = patterns[showSeconds ? 1 : 0];

	NSDateFormatter *df = sciFormatterForPattern(pattern);
	if (!df) return nil;

	@synchronized(df) {
		return [df stringFromDate:date];
	}
}

static NSString *sciFormatDate(NSDate *date) {
	NSString *relative = sciRelativeFormat(date);
	if (relative.length) return relative;

	return sciAbsoluteFormat(date);
}

#define SCI_HOOK0(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd); \
	}

#define SCI_HOOK1(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1); \
	}

#define SCI_HOOK2(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1, a2); \
	}

#define SCI_HOOK3(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2, NSInteger a3) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1, a2, a3); \
	}

#define SCI_HOOK4(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger, NSInteger, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2, NSInteger a3, NSInteger a4) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1, a2, a3, a4); \
	}

#define SCI_EMIT_HOOK(NAME, SEL_, LABEL, ARITY, PREF) SCI_HOOK##ARITY(NAME, SEL_, LABEL, PREF)
SCI_DATE_FORMAT_ENTRIES(SCI_EMIT_HOOK)

#define SCI_INSTALL_HOOK(NAME, SEL_, LABEL, ARITY, PREF) do { \
	SEL s = sel_registerName(SEL_); \
	if ([[NSDate class] instancesRespondToSelector:s]) { \
		MSHookMessageEx([NSDate class], s, (IMP)hook_##NAME, (IMP *)&orig_##NAME); \
	} \
} while (0);

%ctor {
	SCI_DATE_FORMAT_ENTRIES(SCI_INSTALL_HOOK)
}