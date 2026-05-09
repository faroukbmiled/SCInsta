// SCIProfileHelpers — see header for the contract.
//
// Targeted hooks on IGProfileViewController populate a (VC pointer → IGUser *)
// registry on every viewWillAppear so menu builders + media handlers can
// resolve the active user in O(1) without ivar reflection.

#import "SCIProfileHelpers.h"
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../Downloader/Download.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Gallery/SCIGalleryOriginController.h"
#import <objc/runtime.h>
#import <objc/message.h>

// MARK: - Registry

// Both keys (VCs) and values (IGUser) held weakly so this map cannot extend
// any object's lifetime. iOS does not collect dictionary entries automatically
// when one side dies — but the lookups gracefully return nil for dangling
// weak refs, and we prune the map opportunistically on each lookup miss.
static NSMapTable<UIViewController *, id> *sciProfileVCToUser(void) {
    static NSMapTable *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                  valueOptions:NSPointerFunctionsWeakMemory];
    });
    return m;
}

// Stack of weak refs to currently-shown profile VCs, top of stack = active.
static NSPointerArray *sciActiveProfileVCs(void) {
    static NSPointerArray *a;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ a = [NSPointerArray weakObjectsPointerArray]; });
    return a;
}

static void sciCompactActiveStack(void) {
    NSPointerArray *a = sciActiveProfileVCs();
    [a compact];
}

// MARK: - KVC helpers

static id sciSafe(id obj, NSString *key) {
    if (!obj || !key.length) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused id e) { return nil; }
}

static NSString *sciStr(id v) {
    return ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) ? v : nil;
}

static NSNumber *sciNum(id v) {
    if ([v isKindOfClass:[NSNumber class]]) return v;
    if ([v respondsToSelector:@selector(integerValue)]) return @([v integerValue]);
    return nil;
}

static NSURL *sciURL(id v) {
    if (!v || [v isKindOfClass:[NSNull class]]) return nil;
    if ([v isKindOfClass:[NSURL class]]) return v;
    NSString *s = sciStr(v);
    return s.length ? [NSURL URLWithString:s] : nil;
}

// fieldCache helpers consolidated on SCIUtils.
#define sciFieldCacheDict(o) [SCIUtils fieldCacheForObject:(o)]

// MARK: - SCIProfileHelpers

@implementation SCIProfileHelpers

// MARK: - Registry API

+ (void)registerProfileVC:(UIViewController *)vc user:(id)user {
    if (!vc) return;
    if (user) {
        [sciProfileVCToUser() setObject:user forKey:vc];
    }
    NSPointerArray *stack = sciActiveProfileVCs();
    // Move-to-top semantics — remove any existing entry, then add.
    sciCompactActiveStack();
    NSUInteger count = stack.count;
    for (NSUInteger i = 0; i < count; i++) {
        if ((__bridge UIViewController *)[stack pointerAtIndex:i] == vc) {
            [stack removePointerAtIndex:i];
            break;
        }
    }
    [stack addPointer:(__bridge void *)vc];

    NSLog(@"[RyukGram][Profile] register vc=%@ user=@%@ pk=%@",
          NSStringFromClass([vc class]),
          [self usernameForUser:user] ?: @"?",
          [self pkForUser:user] ?: @"?");
}

+ (void)unregisterProfileVC:(UIViewController *)vc {
    if (!vc) return;
    NSPointerArray *stack = sciActiveProfileVCs();
    sciCompactActiveStack();
    NSUInteger count = stack.count;
    for (NSUInteger i = 0; i < count; i++) {
        if ((__bridge UIViewController *)[stack pointerAtIndex:i] == vc) {
            [stack removePointerAtIndex:i];
            break;
        }
    }
}

// MARK: - Lookup API

+ (UIViewController *)activeProfileViewController {
    NSPointerArray *stack = sciActiveProfileVCs();
    sciCompactActiveStack();
    NSUInteger n = stack.count;
    return n > 0 ? (__bridge UIViewController *)[stack pointerAtIndex:n - 1] : nil;
}

+ (id)userForViewController:(UIViewController *)vc {
    if (!vc) return nil;

    id user = [sciProfileVCToUser() objectForKey:vc];
    if (user) return user;

    // Late-binding fallback: on first paint, registerProfileVC may not have
    // fired yet (the hook runs in viewWillAppear). Try direct KVC then.
    for (NSString *key in @[@"user", @"userGQL", @"profileUser"]) {
        id v = sciSafe(vc, key);
        if (v) return v;
    }
    return nil;
}

+ (id)userForView:(UIView *)view {
    if (!view) return nil;
    Class profileCls = NSClassFromString(@"IGProfileViewController");
    UIResponder *r = view;
    while (r) {
        if (profileCls && [r isKindOfClass:profileCls]) {
            return [self userForViewController:(UIViewController *)r];
        }
        r = [r nextResponder];
    }
    // Fallback: active stack top — useful when view is a detached overlay.
    return [self userForViewController:[self activeProfileViewController]];
}

// MARK: - User accessors

+ (NSString *)usernameForUser:(id)user {
    NSString *s = sciStr(sciSafe(user, @"username"));
    if (!s) {
        NSDictionary *fc = sciFieldCacheDict(user);
        s = sciStr(fc[@"username"]);
    }
    return s;
}

+ (NSString *)pkForUser:(id)user {
    NSString *s = sciStr(sciSafe(user, @"pk"));
    if (!s) s = sciStr(sciSafe(user, @"id"));
    if (!s) {
        NSDictionary *fc = sciFieldCacheDict(user);
        s = sciStr(fc[@"pk"]) ?: sciStr(fc[@"strong_id__"]) ?: sciStr(fc[@"id"]);
    }
    return s;
}

+ (NSString *)fullNameForUser:(id)user {
    NSString *s = sciStr(sciSafe(user, @"fullName"));
    if (!s) s = sciStr(sciSafe(user, @"full_name"));
    if (!s) s = sciStr(sciSafe(user, @"name"));
    if (!s) {
        NSDictionary *fc = sciFieldCacheDict(user);
        s = sciStr(fc[@"full_name"]);
    }
    return s;
}

+ (NSString *)biographyForUser:(id)user {
    NSString *s = sciStr(sciSafe(user, @"biography"));
    if (!s) s = sciStr(sciSafe(user, @"bio"));
    if (!s) {
        NSDictionary *fc = sciFieldCacheDict(user);
        s = sciStr(fc[@"biography"]);
    }
    return s;
}

+ (NSURL *)profileLinkForUser:(id)user {
    NSString *u = [self usernameForUser:user];
    if (!u.length) return nil;
    NSString *enc = [u stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    return enc.length ? [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/%@/", enc]] : nil;
}

+ (NSNumber *)privacyStatusForUser:(id)user {
    NSNumber *n = sciNum(sciSafe(user, @"privacyStatus"));
    if (n) return n;
    NSDictionary *fc = sciFieldCacheDict(user);
    n = sciNum(fc[@"privacy_status"]);
    if (n) return n;
    // Fallback to is_private boolean
    id b = sciSafe(user, @"isPrivate");
    if (!b) b = sciSafe(user, @"privateAccount");
    if (!b) b = fc[@"is_private"];
    if ([b respondsToSelector:@selector(boolValue)]) {
        return @([b boolValue] ? 2 : 1);
    }
    return nil;
}

+ (NSNumber *)followerCountForUser:(id)user {
    NSNumber *n = sciNum(sciSafe(user, @"followerCount"));
    if (n) return n;
    NSDictionary *fc = sciFieldCacheDict(user);
    return sciNum(fc[@"follower_count"]);
}

+ (NSNumber *)followingCountForUser:(id)user {
    NSNumber *n = sciNum(sciSafe(user, @"followingCount"));
    if (n) return n;
    NSDictionary *fc = sciFieldCacheDict(user);
    return sciNum(fc[@"following_count"]);
}

// MARK: - Picture URL

+ (NSURL *)cachedPictureURLForUser:(id)user {
    if (!user) return nil;
    NSDictionary *fc = sciFieldCacheDict(user);

    // 1. fieldCache hd_profile_pic_url_info → { url, ... }
    id hd = fc[@"hd_profile_pic_url_info"];
    if ([hd isKindOfClass:[NSDictionary class]]) {
        NSURL *u = sciURL(((NSDictionary *)hd)[@"url"]);
        if (u) return u;
    }
    // 2. hd_profile_pic_versions array → take the largest.
    NSArray *versions = fc[@"hd_profile_pic_versions"];
    if ([versions isKindOfClass:[NSArray class]] && versions.count) {
        id last = versions.lastObject;
        if ([last isKindOfClass:[NSDictionary class]]) {
            NSURL *u = sciURL(((NSDictionary *)last)[@"url"]);
            if (u) return u;
        }
    }
    // 3. Plain profile_pic_url.
    NSURL *u = sciURL(fc[@"profile_pic_url"]);
    if (u) return u;

    // 4. KVC accessor variants (older IGUser shapes).
    for (NSString *sel in @[@"profilePicURLHd", @"profilePicURLHD",
                             @"profilePicURLString", @"profilePicURL",
                             @"profilePictureURL", @"hdProfilePicURL"]) {
        id v = sciSafe(user, sel);
        u = sciURL(v);
        if (u) return u;
    }
    return nil;
}

+ (void)resolveHDPictureURLForUser:(id)user
                          completion:(void(^)(NSURL * _Nullable url))completion {
    if (!completion) return;
    NSURL *cached = [self cachedPictureURLForUser:user];
    NSString *pk = [self pkForUser:user];
    if (!pk.length) {
        completion(cached);
        return;
    }

    NSString *path = [NSString stringWithFormat:@"users/%@/info/", pk];
    [SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil
                                completion:^(NSDictionary *response, NSError *error) {
        if (error || ![response isKindOfClass:[NSDictionary class]]) {
            completion(cached);
            return;
        }
        NSDictionary *u = response[@"user"];
        if (![u isKindOfClass:[NSDictionary class]]) { completion(cached); return; }

        NSDictionary *hd = u[@"hd_profile_pic_url_info"];
        if ([hd isKindOfClass:[NSDictionary class]]) {
            NSURL *url = sciURL(hd[@"url"]);
            if (url) { completion(url); return; }
        }
        NSArray *versions = u[@"hd_profile_pic_versions"];
        if ([versions isKindOfClass:[NSArray class]] && versions.count) {
            id last = versions.lastObject;
            if ([last isKindOfClass:[NSDictionary class]]) {
                NSURL *url = sciURL(((NSDictionary *)last)[@"url"]);
                if (url) { completion(url); return; }
            }
        }
        NSURL *url = sciURL(u[@"profile_pic_url"]);
        completion(url ?: cached);
    }];
}

// MARK: - Caption

+ (NSString *)captionForUser:(id)user {
    NSString *name = [self fullNameForUser:user];
    NSString *username = [self usernameForUser:user];
    NSString *bio = [self biographyForUser:user];
    NSMutableString *out = [NSMutableString string];
    if (name.length) [out appendString:name];
    if (username.length) {
        if (out.length) [out appendString:@"\n"];
        [out appendFormat:@"@%@", username];
    }
    if (bio.length) {
        if (out.length) [out appendString:@"\n\n"];
        [out appendString:bio];
    }
    return out.length ? out : nil;
}

// MARK: - Actions (delegate retention)

static SCIDownloadDelegate *sciActivePictureDelegate = nil;

+ (void)viewPictureForUser:(id)user {
    if (!user) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Picture not found")];
        return;
    }
    NSString *caption = [self captionForUser:user];
    NSURL *cached = [self cachedPictureURLForUser:user];

    [self resolveHDPictureURLForUser:user completion:^(NSURL *url) {
        NSURL *target = url ?: cached;
        if (!target) {
            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Picture not found")];
            return;
        }
        SCIMediaViewerItem *item = [SCIMediaViewerItem itemWithVideoURL:nil
                                                                photoURL:target
                                                                 caption:caption];
        item.metadata = sciProfileGalleryMetadata(user);
        [SCIMediaViewer showItem:item];
    }];
}

// Build gallery metadata for a profile picture save: source = profile, with
// username/pk/profile-link populated.
static SCIGallerySaveMetadata *sciProfileGalleryMetadata(id user) {
    SCIGallerySaveMetadata *m = [[SCIGallerySaveMetadata alloc] init];
    m.source = (int16_t)SCIGallerySourceProfile;
    NSString *username = [SCIProfileHelpers usernameForUser:user];
    @try { [SCIGalleryOriginController populateProfileMetadata:m username:username user:user]; }
    @catch (__unused id e) {}
    return m;
}

+ (void)sharePictureForUser:(id)user {
    if (!user) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Picture not found")];
        return;
    }
    [self resolveHDPictureURLForUser:user completion:^(NSURL *url) {
        if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Picture not found")]; return; }
        NSString *ext = [[url pathExtension] lowercaseString];
        if (!ext.length) ext = @"jpg";
        sciActivePictureDelegate = [[SCIDownloadDelegate alloc] initWithAction:share showProgress:YES];
        sciActivePictureDelegate.pendingGallerySaveMetadata = sciProfileGalleryMetadata(user);
        [sciActivePictureDelegate downloadFileWithURL:url fileExtension:ext hudLabel:nil];
    }];
}

+ (void)savePictureForUser:(id)user {
    if (!user) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Picture not found")];
        return;
    }
    [self resolveHDPictureURLForUser:user completion:^(NSURL *url) {
        if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Picture not found")]; return; }
        NSString *ext = [[url pathExtension] lowercaseString];
        if (!ext.length) ext = @"jpg";

        // SCIAID_SavePictureGallery = explicit gallery target (always save to gallery).
        BOOL galleryOnly = NO; // default: Photos with optional mirror.
        // (The dedicated "Save to Gallery" menu entry below uses savePictureToGalleryForUser:.)
        sciActivePictureDelegate = [[SCIDownloadDelegate alloc] initWithAction:(galleryOnly ? saveToGallery : saveToPhotos)
                                                                  showProgress:YES];
        sciActivePictureDelegate.pendingGallerySaveMetadata = sciProfileGalleryMetadata(user);
        [sciActivePictureDelegate downloadFileWithURL:url fileExtension:ext hudLabel:nil];
    }];
}

+ (void)savePictureToGalleryForUser:(id)user {
    if (!user) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Picture not found")];
        return;
    }
    [self resolveHDPictureURLForUser:user completion:^(NSURL *url) {
        if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Picture not found")]; return; }
        NSString *ext = [[url pathExtension] lowercaseString];
        if (!ext.length) ext = @"jpg";
        sciActivePictureDelegate = [[SCIDownloadDelegate alloc] initWithAction:saveToGallery showProgress:YES];
        sciActivePictureDelegate.pendingGallerySaveMetadata = sciProfileGalleryMetadata(user);
        [sciActivePictureDelegate downloadFileWithURL:url fileExtension:ext hudLabel:nil];
    }];
}

@end


// MARK: - Hooks

%hook IGProfileViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    id user = nil;
    for (NSString *key in @[@"user", @"userGQL", @"profileUser"]) {
        @try { user = [self valueForKey:key]; } @catch (__unused id e) {}
        if (user) break;
    }
    [SCIProfileHelpers registerProfileVC:self user:user];
}

- (void)viewWillDisappear:(BOOL)animated {
    [SCIProfileHelpers unregisterProfileVC:self];
    %orig;
}

%end
