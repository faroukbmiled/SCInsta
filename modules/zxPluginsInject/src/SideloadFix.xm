#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>

#import "../../fishhook/fishhook.h"

@interface LSBundleProxy : NSObject
+ (instancetype)bundleProxyForCurrentProcess;
@property (nonatomic, readonly) NSDictionary *entitlements;
@property (nonatomic, readonly) NSDictionary *groupContainerURLs;
@end

static NSString *accessGroupId;
static NSString *bundleId;

static BOOL createDirectoryIfNotExists(NSString *path) {
	if (!path.length) return NO;

	BOOL isDir = NO;
	NSFileManager *fm = NSFileManager.defaultManager;

	if ([fm fileExistsAtPath:path isDirectory:&isDir])
		return isDir;

	return [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

static NSURL *getAppGroupPathIfExists(void) {
	static NSURL *path;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		LSBundleProxy *proxy = [objc_getClass("LSBundleProxy") bundleProxyForCurrentProcess];
		NSArray *groups = proxy.entitlements[@"com.apple.security.application-groups"];
		NSDictionary *urls = proxy.groupContainerURLs;

		if ([groups isKindOfClass:NSArray.class] && groups.count && [urls isKindOfClass:NSDictionary.class]) {
			NSURL *url = urls[groups.firstObject];
			if ([url isKindOfClass:NSURL.class]) path = url;
		}
	});

	return path;
}

static NSURL *fakeGroupURL(NSString *identifier) {
	if (!identifier.length) return nil;

	NSURL *base = getAppGroupPathIfExists();

	if (!base) {
		NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject;
		base = [NSURL fileURLWithPath:docs];
	}

	NSURL *url = [base URLByAppendingPathComponent:identifier];
	createDirectoryIfNotExists(url.path);
	return url;
}

static BOOL isAppExtension(void) {
	static BOOL value;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		value = NSBundle.mainBundle.infoDictionary[@"NSExtension"] != nil;
	});

	return value;
}

%hook CKContainer
- (id)_setupWithContainerID:(id)a options:(id)b { return nil; }
- (id)_initWithContainerIdentifier:(id)a { return nil; }
%end

%hook CKEntitlements
- (id)initWithEntitlementsDict:(NSDictionary *)entitlements {
	NSMutableDictionary *m = entitlements.mutableCopy;

	[m removeObjectsForKeys:@[
		@"com.apple.developer.icloud-container-environment",
		@"com.apple.developer.icloud-services"
	]];

	return %orig(m.copy);
}
%end

%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
	return fakeGroupURL(groupIdentifier) ?: %orig(groupIdentifier);
}
%end

%hook NSUserDefaults
- (id)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container {
	NSURL *url = isAppExtension() && [suiteName hasPrefix:@"group"] ? fakeGroupURL(suiteName) : nil;
	return %orig(suiteName, url ?: container);
}
%end

static OSStatus (*origSecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*origSecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*origSecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*origSecItemDelete)(CFDictionaryRef);

static CFDictionaryRef keychainQueryWithAccessGroup(CFDictionaryRef query) {
	if (!query || !accessGroupId.length) return NULL;

	CFMutableDictionaryRef m = CFDictionaryCreateMutableCopy(NULL, 0, query);
	if (!m) return NULL;

	CFDictionarySetValue(m, kSecAttrAccessGroup, (__bridge const void *)accessGroupId);
	return m;
}

static OSStatus zxSecItemAdd(CFDictionaryRef q, CFTypeRef *r) {
	CFDictionaryRef d = keychainQueryWithAccessGroup(q);
	OSStatus s = origSecItemAdd(d ?: q, r);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemCopyMatching(CFDictionaryRef q, CFTypeRef *r) {
	CFDictionaryRef d = keychainQueryWithAccessGroup(q);
	OSStatus s = origSecItemCopyMatching(d ?: q, r);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemUpdate(CFDictionaryRef q, CFDictionaryRef u) {
	CFDictionaryRef d = keychainQueryWithAccessGroup(q);
	OSStatus s = origSecItemUpdate(d ?: q, u);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemDelete(CFDictionaryRef q) {
	CFDictionaryRef d = keychainQueryWithAccessGroup(q);
	OSStatus s = origSecItemDelete(d ?: q);
	if (d) CFRelease(d);
	return s;
}

static void rebindSecFuncs(void) {
	struct rebinding r[] = {
		{"SecItemAdd", (void *)zxSecItemAdd, (void **)&origSecItemAdd},
		{"SecItemCopyMatching", (void *)zxSecItemCopyMatching, (void **)&origSecItemCopyMatching},
		{"SecItemUpdate", (void *)zxSecItemUpdate, (void **)&origSecItemUpdate},
		{"SecItemDelete", (void *)zxSecItemDelete, (void **)&origSecItemDelete}
	};

	rebind_symbols(r, sizeof(r) / sizeof(*r));
}

static BOOL setRequiredIDs(void) {
	NSDictionary *q = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrAccount: @"zxPluginsInjectGenericEntry",
		(__bridge id)kSecAttrService: @"",
		(__bridge id)kSecReturnAttributes: @YES
	};

	CFTypeRef res = nil;
	OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)q, &res);

	if (s == errSecItemNotFound)
		s = SecItemAdd((__bridge CFDictionaryRef)q, &res);

	if (s != errSecSuccess || !res) return NO;

	NSDictionary *attrs = CFBridgingRelease(res);
	bundleId = NSBundle.mainBundle.bundleIdentifier;
	accessGroupId = attrs[(__bridge id)kSecAttrAccessGroup];

	return accessGroupId.length > 0;
}

__attribute__((constructor))
static void zxInit(void) {
	if (setRequiredIDs())
		rebindSecFuncs();
}