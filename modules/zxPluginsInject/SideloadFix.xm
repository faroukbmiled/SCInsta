// Sideload compatibility shim for IG. Upstream: github.com/asdfzxcvbn/zxPluginsInject.
//
// Four pieces:
//   1. SecItem* rebind — IG hard-codes `group.com.facebook.family` as its
//      keychain access group; sideload doesn't have it. Every query is
//      rewritten to the entitled group.
//   2. NSUserDefaults init redirect (appex-only) — appex reads what the
//      main app wrote so rich-notification previews fill in. Applying it
//      in the main process breaks NUX dismiss flags on IG 423+.
//   3. Main-app fan-out — cfprefsd caches group.* writes per-process; the
//      appex sees stale data until flush. Mirror writes through an explicit
//      shared-container `_initWithSuiteName:container:`. Skipped without
//      a real app-groups entitlement.
//   4. `containerURLForSecurityApplicationGroupIdentifier:` never returns
//      nil — IG's IGProductSaveStatusStore crashes inside `hasPrefix:nil`
//      otherwise. Real URL when entitled, Documents-dir sandbox path when not.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "../fishhook/fishhook.h"

@interface LSBundleProxy: NSObject
@property(nonatomic, assign, readonly) NSDictionary *entitlements;
@property(nonatomic, assign, readonly) NSDictionary *groupContainerURLs;
+ (instancetype)bundleProxyForCurrentProcess;
@end

@interface NSUserDefaults (Sideload)
- (id)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

static NSString *accessGroupId;

static BOOL createDirectoryIfNotExists(NSString *path) {
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:path]) return YES;
	NSError *error = nil;
	[fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
	return error == nil;
}

static NSURL *getAppGroupPathIfExists(void) {
	static NSURL *cached = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		LSBundleProxy *proxy = [objc_getClass("LSBundleProxy") bundleProxyForCurrentProcess];
		if (!proxy) return;

		NSDictionary *entitlements = proxy.entitlements;
		if (![entitlements isKindOfClass:[NSDictionary class]]) return;

		NSArray *appGroups = entitlements[@"com.apple.security.application-groups"];
		if (![appGroups isKindOfClass:[NSArray class]] || appGroups.count == 0) return;

		NSDictionary *paths = proxy.groupContainerURLs;
		if (![paths isKindOfClass:[NSDictionary class]]) return;

		NSURL *url = paths[[appGroups firstObject]];
		if ([url isKindOfClass:[NSURL class]]) cached = url;
	});
	return cached;
}

static BOOL sciIsAppExtensionProcess(void) {
	static BOOL cached = NO;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cached = ([[NSBundle mainBundle] infoDictionary][@"NSExtension"] != nil);
	});
	return cached;
}

// Marker on the fan-out NSUserDefaults so its own writes don't recurse here.
static const void *kSCIFanoutTagKey = &kSCIFanoutTagKey;

static NSURL *sciSharedContainerURLForSuite(NSString *suiteName) {
	NSURL *appGroup = getAppGroupPathIfExists();
	if (!appGroup || !suiteName.length) return nil;
	NSURL *container = [appGroup URLByAppendingPathComponent:suiteName isDirectory:YES];
	NSURL *prefs = [[container URLByAppendingPathComponent:@"Library"] URLByAppendingPathComponent:@"Preferences"];
	createDirectoryIfNotExists(prefs.path);
	return container;
}

static NSUserDefaults *sciFanoutDefaultsForSuite(NSString *suiteName) {
	static NSMutableDictionary<NSString *, NSUserDefaults *> *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSMutableDictionary new]; });

	@synchronized(cache) {
		if (NSUserDefaults *hit = cache[suiteName]) return hit;
		NSURL *container = sciSharedContainerURLForSuite(suiteName);
		if (!container) return nil;
		NSUserDefaults *fanout = [[NSUserDefaults alloc] _initWithSuiteName:suiteName container:container];
		if (!fanout) return nil;
		objc_setAssociatedObject(fanout, kSCIFanoutTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		cache[suiteName] = fanout;
		return fanout;
	}
}

static NSString *sciSuiteNameForDefaults(NSUserDefaults *defaults) {
	if (![defaults respondsToSelector:@selector(_identifier)]) return nil;
	return ((NSString *(*)(id, SEL))objc_msgSend)(defaults, @selector(_identifier));
}

static BOOL sciShouldFanout(NSUserDefaults *defaults) {
	if (sciIsAppExtensionProcess()) return NO;
	if (!getAppGroupPathIfExists()) return NO;  // no appex on the other end
	if (objc_getAssociatedObject(defaults, kSCIFanoutTagKey)) return NO;
	return [sciSuiteNameForDefaults(defaults) hasPrefix:@"group"];
}

// === keychain access-group rebind ==========================================

static OSStatus (*origSecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*origSecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*origSecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*origSecItemDelete)(CFDictionaryRef);

static CFDictionaryRef sciFixedQuery(CFDictionaryRef query) {
	if (!query || !accessGroupId.length) return NULL;
	CFMutableDictionaryRef dict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
	if (dict) CFDictionarySetValue(dict, kSecAttrAccessGroup, (__bridge const void *)accessGroupId);
	return dict;
}

static OSStatus zxSecItemAdd(CFDictionaryRef q, CFTypeRef *r) {
	CFDictionaryRef d = sciFixedQuery(q);
	OSStatus s = origSecItemAdd(d ?: q, r);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemCopyMatching(CFDictionaryRef q, CFTypeRef *r) {
	CFDictionaryRef d = sciFixedQuery(q);
	OSStatus s = origSecItemCopyMatching(d ?: q, r);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemUpdate(CFDictionaryRef q, CFDictionaryRef u) {
	CFDictionaryRef d = sciFixedQuery(q);
	OSStatus s = origSecItemUpdate(d ?: q, u);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemDelete(CFDictionaryRef q) {
	CFDictionaryRef d = sciFixedQuery(q);
	OSStatus s = origSecItemDelete(d ?: q);
	if (d) CFRelease(d);
	return s;
}

static void rebindSecFuncs(void) {
	struct rebinding rebinds[4] = {
		{"SecItemAdd", (void *)zxSecItemAdd, (void **)&origSecItemAdd},
		{"SecItemCopyMatching", (void *)zxSecItemCopyMatching, (void **)&origSecItemCopyMatching},
		{"SecItemUpdate", (void *)zxSecItemUpdate, (void **)&origSecItemUpdate},
		{"SecItemDelete", (void *)zxSecItemDelete, (void **)&origSecItemDelete},
	};
	rebind_symbols(rebinds, 4);
}

// === CloudKit disable ======================================================

%hook CKContainer
- (id)_setupWithContainerID:(id)a options:(id)b { return nil; }
- (id)_initWithContainerIdentifier:(id)a { return nil; }
%end

%hook CKEntitlements
- (id)initWithEntitlementsDict:(NSDictionary *)entitlements {
	NSMutableDictionary *m = [entitlements mutableCopy];
	[m removeObjectForKey:@"com.apple.developer.icloud-container-environment"];
	[m removeObjectForKey:@"com.apple.developer.icloud-services"];
	return %orig([m copy]);
}
%end

// === NSFileManager group container URL =====================================

%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
	if (NSURL *appGroupURL = getAppGroupPathIfExists()) {
		NSURL *url = [appGroupURL URLByAppendingPathComponent:groupIdentifier];
		createDirectoryIfNotExists(url.path);
		return url;
	}
	// No entitlement → sandbox path so the caller never sees nil.
	NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
	NSString *path = [docs stringByAppendingPathComponent:groupIdentifier];
	createDirectoryIfNotExists(path);
	return [NSURL fileURLWithPath:path];
}
%end

// === NSUserDefaults: appex redirect + main-app fan-out =====================

%hook NSUserDefaults

- (id)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container {
	if (!sciIsAppExtensionProcess()) return %orig(suiteName, container);

	NSURL *appGroupURL = getAppGroupPathIfExists();
	if (!appGroupURL || ![suiteName hasPrefix:@"group"]) return %orig(suiteName, container);

	NSURL *redirect = [appGroupURL URLByAppendingPathComponent:suiteName isDirectory:YES];
	if (!redirect) return %orig(suiteName, container);

	NSURL *prefs = [[redirect URLByAppendingPathComponent:@"Library"] URLByAppendingPathComponent:@"Preferences"];
	createDirectoryIfNotExists(prefs.path);
	return %orig(suiteName, redirect);
}

- (void)setObject:(id)value forKey:(NSString *)key {
	%orig;
	if (!sciShouldFanout(self)) return;
	[sciFanoutDefaultsForSuite(sciSuiteNameForDefaults(self)) setObject:value forKey:key];
}

- (void)removeObjectForKey:(NSString *)key {
	%orig;
	if (!sciShouldFanout(self)) return;
	[sciFanoutDefaultsForSuite(sciSuiteNameForDefaults(self)) removeObjectForKey:key];
}

%end

// === keychain access-group bootstrap =======================================

static void setRequiredIDs(void) {
	NSDictionary *query = @{
		(__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassGenericPassword,
		(__bridge NSString *)kSecAttrAccount: @"zxPluginsInjectGenericEntry",
		(__bridge NSString *)kSecAttrService: @"",
		(__bridge id)kSecReturnAttributes: (id)kCFBooleanTrue,
	};

	CFDictionaryRef result = nil;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
	if (status == errSecItemNotFound) {
		status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
	}
	if (status != errSecSuccess) return;

	accessGroupId = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];
	if (result) CFRelease(result);
}

__attribute__((constructor)) static void init(void) {
	setRequiredIDs();
	rebindSecFuncs();
}
