#import "SCIGalleryOriginController.h"

#import <objc/message.h>

#import "SCIGalleryFile.h"
#import "SCIGallerySaveMetadata.h"
#import "../Utils.h"
#import "../SCIURLOpener.h"
#import "SCIGalleryShim.h"

#import <objc/runtime.h>

// Inlined replacements for upstream's ActionButtonLookupUtils helpers.
static id SCIObjectForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(target, selector); }
    @catch (__unused id e) { return nil; }
}

static id SCIKVCObject(id target, NSString *key) {
    if (!target || key.length == 0) return nil;
    @try { return [target valueForKey:key]; }
    @catch (__unused id e) { return nil; }
}

// fieldCache helpers consolidated on SCIUtils — see +fieldCacheForObject: /
// +fieldCacheValue:forKey:.
#define SCIFieldCacheDict(o) [SCIUtils fieldCacheForObject:(o)]

static NSString *SCIFieldCacheString(id obj, NSString *key) {
    id v = [SCIUtils fieldCacheValue:obj forKey:key];
    return ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) ? v : nil;
}

// Walks media→user→username across selectors + fieldCache + a couple of
// fallback nested objects. IGMedia stores user inside its Pando _fieldCache —
// KVC alone can't see it.
static NSString *SCIUsernameFromMediaObject(id media) {
    if (!media) return nil;
    for (NSString *userKey in @[@"user", @"owner", @"author", @"creator", @"actor", @"profileUser"]) {
        id user = SCIObjectForSelector(media, userKey);
        if (!user) user = SCIKVCObject(media, userKey);
        if (!user) {
            NSDictionary *fc = SCIFieldCacheDict(media);
            user = fc[userKey];
        }
        if (!user) continue;
        id u = SCIObjectForSelector(user, @"username");
        if (!u) u = SCIKVCObject(user, @"username");
        if (![u isKindOfClass:[NSString class]] || !((NSString *)u).length) {
            NSString *fcU = SCIFieldCacheString(user, @"username");
            if (fcU.length) u = fcU;
            else if ([user isKindOfClass:[NSDictionary class]]) {
                id v = ((NSDictionary *)user)[@"username"];
                if ([v isKindOfClass:[NSString class]]) u = v;
            }
        }
        if ([u isKindOfClass:[NSString class]] && [(NSString *)u length]) return u;
    }
    for (NSString *nestedKey in @[@"media", @"item", @"storyItem", @"visualMessage", @"explorePostInFeed", @"rootItem", @"clipsItem", @"clipsMedia", @"post"]) {
        id nested = SCIObjectForSelector(media, nestedKey);
        if (!nested) nested = SCIKVCObject(media, nestedKey);
        if (!nested || nested == media) continue;
        NSString *u = SCIUsernameFromMediaObject(nested);
        if (u.length) return u;
    }
    return nil;
}

static id SCIUserFromMediaWithFieldCache(id media) {
    if (!media) return nil;
    for (NSString *userKey in @[@"user", @"owner", @"author", @"creator", @"actor", @"profileUser"]) {
        id user = SCIObjectForSelector(media, userKey);
        if (!user) user = SCIKVCObject(media, userKey);
        if (!user) {
            NSDictionary *fc = SCIFieldCacheDict(media);
            user = fc[userKey];
        }
        if (user) return user;
    }
    return nil;
}

static NSString *SCIGalleryStringValue(id value) {
    if (!value) return nil;
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value length] > 0 ? value : nil;
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *string = [value stringValue];
        return string.length > 0 ? string : nil;
    }
    if ([value respondsToSelector:@selector(description)]) {
        NSString *string = [value description];
        return string.length > 0 ? string : nil;
    }
    return nil;
}

static NSString *SCIGalleryStringForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;
    id value = SCIObjectForSelector(target, selectorName);
    if (!value) value = SCIKVCObject(target, selectorName);
    return SCIGalleryStringValue(value);
}

static NSURL *SCIGalleryURLForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;
    id value = SCIObjectForSelector(target, selectorName);
    if (!value) value = SCIKVCObject(target, selectorName);
    if ([value isKindOfClass:[NSURL class]]) return value;
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return [NSURL URLWithString:(NSString *)value];
    }
    return nil;
}

static id SCIGalleryNestedObjectForSelector(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;
    id value = SCIObjectForSelector(target, selectorName);
    if (!value) value = SCIKVCObject(target, selectorName);
    if ([value isKindOfClass:[NSArray class]]) {
        return ((NSArray *)value).firstObject;
    }
    return value;
}

static NSString *SCIGalleryRecursiveStringForSelectors(id target, NSArray<NSString *> *selectorNames, NSInteger depth) {
    if (!target || depth > 3) return nil;

    for (NSString *selectorName in selectorNames) {
        NSString *value = SCIGalleryStringForSelector(target, selectorName);
        if (value.length > 0) return value;
    }

    for (NSString *selectorName in @[@"media", @"item", @"storyItem", @"visualMessage", @"explorePostInFeed", @"rootItem", @"clipsItem", @"clipsMedia", @"post"]) {
        id nested = SCIGalleryNestedObjectForSelector(target, selectorName);
        if (!nested || nested == target) continue;
        NSString *value = SCIGalleryRecursiveStringForSelectors(nested, selectorNames, depth + 1);
        if (value.length > 0) return value;
    }

    return nil;
}

static NSURL *SCIGalleryRecursiveURLForSelectors(id target, NSArray<NSString *> *selectorNames, NSInteger depth) {
    if (!target || depth > 3) return nil;

    for (NSString *selectorName in selectorNames) {
        NSURL *value = SCIGalleryURLForSelector(target, selectorName);
        if (value) return value;
    }

    for (NSString *selectorName in @[@"media", @"item", @"storyItem", @"visualMessage", @"explorePostInFeed", @"rootItem", @"clipsItem", @"clipsMedia", @"post"]) {
        id nested = SCIGalleryNestedObjectForSelector(target, selectorName);
        if (!nested || nested == target) continue;
        NSURL *value = SCIGalleryRecursiveURLForSelectors(nested, selectorNames, depth + 1);
        if (value) return value;
    }

    return nil;
}

static id SCIGalleryUserFromMedia(id media) {
    if (!media) return nil;

    for (NSString *selectorName in @[@"user", @"owner", @"author", @"creator", @"actor", @"profileUser"]) {
        id user = SCIObjectForSelector(media, selectorName);
        if (!user) user = SCIKVCObject(media, selectorName);
        if (user) return user;
    }

    for (NSString *nestedSelector in @[@"media", @"item", @"storyItem", @"visualMessage"]) {
        id nested = SCIObjectForSelector(media, nestedSelector);
        if (!nested) nested = SCIKVCObject(media, nestedSelector);
        if (nested && nested != media) {
            id user = SCIGalleryUserFromMedia(nested);
            if (user) return user;
        }
    }

    return nil;
}

static NSString *SCIGalleryProfileURLStringForUsername(NSString *username) {
    NSString *encodedUsername = [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    return encodedUsername.length > 0 ? [NSString stringWithFormat:@"instagram://user?username=%@", encodedUsername] : nil;
}

static NSString *SCIGalleryMediaURLStringFromMetadata(SCIGallerySaveMetadata *metadata) {
    if (metadata.sourceMediaURLString.length > 0) return metadata.sourceMediaURLString;
    if (metadata.sourceMediaCode.length > 0) {
        NSString *pathComponent = (metadata.source == SCIGallerySourceReels) ? @"reel" : @"p";
        return [NSString stringWithFormat:@"https://www.instagram.com/%@/%@/", pathComponent, metadata.sourceMediaCode];
    }
    return nil;
}

@implementation SCIGalleryOriginController

+ (void)populateProfileMetadata:(SCIGallerySaveMetadata *)metadata username:(NSString *)username user:(id)user {
    if (!metadata) return;

    if (username.length > 0) {
        metadata.sourceUsername = username;
        if (metadata.sourceProfileURLString.length == 0) {
            metadata.sourceProfileURLString = SCIGalleryProfileURLStringForUsername(username);
        }
    }

    NSString *userPK = SCIGalleryStringForSelector(user, @"pk");
    if (userPK.length == 0) userPK = SCIGalleryStringForSelector(user, @"id");
    if (userPK.length == 0) userPK = SCIFieldCacheString(user, @"pk") ?: SCIFieldCacheString(user, @"strong_id__") ?: SCIFieldCacheString(user, @"id");
    if (userPK.length > 0) metadata.sourceUserPK = userPK;

    NSURL *profileURL = nil;
    for (NSString *selectorName in @[@"profileURL", @"profileUrl", @"url"]) {
        profileURL = SCIGalleryURLForSelector(user, selectorName);
        if (profileURL) break;
    }
    if (!profileURL && username.length > 0) {
        profileURL = [NSURL URLWithString:SCIGalleryProfileURLStringForUsername(username)];
    }
    if (profileURL) metadata.sourceProfileURLString = profileURL.absoluteString;
}

+ (void)populateMetadata:(SCIGallerySaveMetadata *)metadata fromMedia:(id)media {
    if (!metadata || !media) return;

    NSString *username = SCIUsernameFromMediaObject(media);
    id user = SCIUserFromMediaWithFieldCache(media);
    if (!user) user = SCIGalleryUserFromMedia(media);
    [self populateProfileMetadata:metadata username:username user:user];

    NSString *mediaPK = SCIGalleryRecursiveStringForSelectors(media, @[@"pk", @"id", @"mediaID", @"mediaId"], 0);
    if (mediaPK.length == 0) {
        mediaPK = SCIFieldCacheString(media, @"pk") ?: SCIFieldCacheString(media, @"id") ?: SCIFieldCacheString(media, @"strong_id__");
    }
    if (mediaPK.length > 0) metadata.sourceMediaPK = mediaPK;

    NSString *mediaCode = SCIGalleryRecursiveStringForSelectors(media, @[@"code", @"shortCode", @"shortcode", @"mediaCode", @"mediaShortcode", @"shortCodeToken"], 0);
    if (mediaCode.length == 0) {
        mediaCode = SCIFieldCacheString(media, @"code") ?: SCIFieldCacheString(media, @"shortcode");
    }
    if (mediaCode.length > 0) metadata.sourceMediaCode = mediaCode;

    NSURL *mediaURL = SCIGalleryRecursiveURLForSelectors(media, @[@"permalink", @"permaLink", @"shareURL", @"shareUrl", @"canonicalURL", @"canonicalUrl", @"permalinkURL", @"instagramURL", @"instagramUrl", @"webURL", @"webUrl"], 0);
    if (!mediaURL) {
        NSString *generatedURLString = SCIGalleryMediaURLStringFromMetadata(metadata);
        if (generatedURLString.length > 0) {
            mediaURL = [NSURL URLWithString:generatedURLString];
        }
    }
    if (mediaURL) metadata.sourceMediaURLString = mediaURL.absoluteString;
}

+ (BOOL)openOriginalPostForGalleryFile:(SCIGalleryFile *)file {
    NSURL *url = [file preferredOriginalMediaURL];
    return url ? [SCIURLOpener openURL:url] : NO;
}

+ (BOOL)openProfileForGalleryFile:(SCIGalleryFile *)file {
    if (file.sourceUsername.length > 0) {
        return [SCIURLOpener openInstagramProfileForUsername:file.sourceUsername];
    }
    NSURL *url = [file preferredProfileURL];
    return url ? [SCIURLOpener openURL:url] : NO;
}

@end
