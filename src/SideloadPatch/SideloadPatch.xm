// Sideload compatibility patch for Instagram.
// Fixes keychain, app groups, CloudKit, and container access when sideloaded.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../modules/fishhook/fishhook.h"

static NSString *bundleId = nil;
static NSString *accessGroupId = nil;

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef) = NULL;

static IMP orig_CKEntitlements_initWithEntitlementsDict __attribute__((unused)) = NULL;
static IMP orig_CKContainer_setupWithContainerID __attribute__((unused)) = NULL;
static IMP orig_CKContainer_initWithContainerIdentifier __attribute__((unused)) = NULL;
static IMP orig_NSFileManager_containerURL __attribute__((unused)) = NULL;

// -- app group path --

static NSString *_appGroupPath = nil;
static dispatch_once_t _appGroupOnce = 0;

static NSString *getAppGroupPathIfExists(void) {
    dispatch_once(&_appGroupOnce, ^{
        Class LSBundleProxy = objc_getClass("LSBundleProxy");
        if (!LSBundleProxy) return;

        id proxy = ((id(*)(id, SEL))objc_msgSend)(
            (id)LSBundleProxy, sel_registerName("bundleProxyForCurrentProcess"));
        if (!proxy) return;

        NSDictionary *ents = ((NSDictionary *(*)(id, SEL))objc_msgSend)(
            proxy, sel_registerName("entitlements"));
        if (!ents || ![ents isKindOfClass:[NSDictionary class]]) return;

        NSArray *groups = ents[@"com.apple.security.application-groups"];
        if (!groups || groups.count == 0) return;

        NSDictionary *urls = ((NSDictionary *(*)(id, SEL))objc_msgSend)(
            proxy, sel_registerName("groupContainerURLs"));
        if (!urls || ![urls isKindOfClass:[NSDictionary class]]) return;

        NSURL *url = urls[groups.firstObject];
        if (url) _appGroupPath = [url path];
    });
    return _appGroupPath;
}

static BOOL createDirectoryIfNotExists(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) return YES;
    return [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

// -- SecItem replacements: set the correct access group on every call --

static OSStatus replaced_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (attributes && accessGroupId) {
        NSMutableDictionary *q = [(__bridge NSDictionary *)attributes mutableCopy];
        q[(__bridge id)kSecAttrAccessGroup] = accessGroupId;
        return orig_SecItemAdd((__bridge CFDictionaryRef)q, result);
    }
    return orig_SecItemAdd(attributes, result);
}

static OSStatus replaced_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (query && accessGroupId) {
        NSMutableDictionary *q = [(__bridge NSDictionary *)query mutableCopy];
        q[(__bridge id)kSecAttrAccessGroup] = accessGroupId;
        return orig_SecItemCopyMatching((__bridge CFDictionaryRef)q, result);
    }
    return orig_SecItemCopyMatching(query, result);
}

static OSStatus replaced_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attrs) {
    if (query && accessGroupId) {
        NSMutableDictionary *q = [(__bridge NSDictionary *)query mutableCopy];
        q[(__bridge id)kSecAttrAccessGroup] = accessGroupId;
        return orig_SecItemUpdate((__bridge CFDictionaryRef)q, attrs);
    }
    return orig_SecItemUpdate(query, attrs);
}

static OSStatus replaced_SecItemDelete(CFDictionaryRef query) {
    if (query && accessGroupId) {
        NSMutableDictionary *q = [(__bridge NSDictionary *)query mutableCopy];
        q[(__bridge id)kSecAttrAccessGroup] = accessGroupId;
        return orig_SecItemDelete((__bridge CFDictionaryRef)q);
    }
    return orig_SecItemDelete(query);
}

// -- CloudKit patches: strip iCloud entitlements, disable container init --

static id replaced_CKEntitlements_init(id self, SEL _cmd, NSDictionary *dict) {
    NSMutableDictionary *d = [dict mutableCopy];
    [d removeObjectForKey:@"com.apple.developer.icloud-container-environment"];
    [d removeObjectForKey:@"com.apple.developer.icloud-services"];
    return ((id(*)(id, SEL, NSDictionary *))orig_CKEntitlements_initWithEntitlementsDict)(self, _cmd, [d copy]);
}

static id replaced_CKContainer_setup(id self, SEL _cmd, id containerID, id options) {
    return nil;
}

static id replaced_CKContainer_init(id self, SEL _cmd, id identifier) {
    return nil;
}

// -- NSFileManager: redirect app group container to a local fallback --

static NSURL *replaced_containerURL(id self, SEL _cmd, NSString *groupId) {
    NSString *groupPath = getAppGroupPathIfExists();
    if (!groupPath) {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject;
        NSString *fallback = [docs stringByAppendingPathComponent:groupId];
        createDirectoryIfNotExists(fallback);
        return [NSURL fileURLWithPath:fallback];
    }
    NSURL *url = [[NSURL fileURLWithPath:groupPath] URLByAppendingPathComponent:groupId];
    createDirectoryIfNotExists([url path]);
    return url;
}

// -- swizzle helper: walks class hierarchy, handles inherited methods --

static void swizzleMethod(Class cls, SEL sel, IMP newIMP, IMP *outOrig) {
    if (!cls) return;
    Class cur = cls;
    while (cur) {
        unsigned int count = 0;
        Method *list = class_copyMethodList(cur, &count);
        for (unsigned int i = 0; i < count; i++) {
            if (method_getName(list[i]) == sel) {
                if (cur == cls) {
                    *outOrig = method_setImplementation(list[i], newIMP);
                } else {
                    *outOrig = method_getImplementation(list[i]);
                    class_addMethod(cls, sel, newIMP, method_getTypeEncoding(list[i]));
                }
                free(list);
                return;
            }
        }
        free(list);
        cur = class_getSuperclass(cur);
    }
}

// -- keychain bootstrap: discover the access group assigned to this app --

static void bootstrapKeychainAccessGroup(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass:            (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount:      @"RyukGramSideloadPatch",
        (__bridge id)kSecAttrService:      @"",
        (__bridge id)kSecReturnAttributes: @YES,
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound)
        status = SecItemAdd((__bridge CFDictionaryRef)query, &result);

    if (status == errSecSuccess && result) {
        bundleId = [[NSBundle mainBundle] bundleIdentifier];
        NSDictionary *attrs = (__bridge NSDictionary *)result;
        NSString *group = attrs[(__bridge id)kSecAttrAccessGroup];
        if (group) accessGroupId = [group copy];
        CFRelease(result);
    }
}

// -- init --

%ctor {
    @autoreleasepool {
        bootstrapKeychainAccessGroup();

        // rebind SecItem functions so keychain calls use the right access group
        struct rebinding rebindings[] = {
            {"SecItemAdd",          (void *)replaced_SecItemAdd,          (void **)&orig_SecItemAdd},
            {"SecItemCopyMatching", (void *)replaced_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
            {"SecItemUpdate",       (void *)replaced_SecItemUpdate,       (void **)&orig_SecItemUpdate},
            {"SecItemDelete",       (void *)replaced_SecItemDelete,       (void **)&orig_SecItemDelete},
        };
        rebind_symbols(rebindings, 4);

        // patch NSFileManager for app group container fallback
        Class fm = objc_getClass("NSFileManager");
        if (fm) swizzleMethod(fm, sel_registerName("containerURLForSecurityApplicationGroupIdentifier:"),
                              (IMP)replaced_containerURL, &orig_NSFileManager_containerURL);

        // patch CloudKit to prevent crashes from missing entitlements
        Class ckEnt = objc_getClass("CKEntitlements");
        if (ckEnt) swizzleMethod(ckEnt, sel_registerName("initWithEntitlementsDict:"),
                                 (IMP)replaced_CKEntitlements_init, &orig_CKEntitlements_initWithEntitlementsDict);

        Class ckCon = objc_getClass("CKContainer");
        if (ckCon) {
            swizzleMethod(ckCon, sel_registerName("_setupWithContainerID:options:"),
                          (IMP)replaced_CKContainer_setup, &orig_CKContainer_setupWithContainerID);
            swizzleMethod(ckCon, sel_registerName("_initWithContainerIdentifier:"),
                          (IMP)replaced_CKContainer_init, &orig_CKContainer_initWithContainerIdentifier);
        }

        // NSUserDefaults _initWithSuiteName:container: intentionally not patched —
        // crashes on current IG versions. the NSFileManager patch covers the
        // group container redirect which is what actually matters.
    }
}
