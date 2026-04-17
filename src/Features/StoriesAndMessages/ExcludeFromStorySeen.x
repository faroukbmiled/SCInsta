// Per-user story seen-receipt exclusions. Excluded users' stories behave
// normally (your view appears in their viewer list). Provides owner detection
// helpers, 3-dot menu injection, and overlay refresh utilities.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "StoryHelpers.h"
#import "SCIExcludedStoryUsers.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

NSDictionary *sciOwnerInfoFromObject(id obj);

// ============ Active story VC tracking ============

__weak UIViewController *sciActiveStoryViewerVC = nil;

%hook IGStoryViewerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sciActiveStoryViewerVC = self;
}
- (void)viewWillDisappear:(BOOL)animated {
    if (sciActiveStoryViewerVC == (UIViewController *)self) sciActiveStoryViewerVC = nil;
    %orig;
}
%end

// ============ Owner extraction ============

NSDictionary *sciOwnerInfoFromObject(id obj) {
    if (!obj) return nil;
    @try {
        id pk = nil, un = nil, fn = nil;
        if ([obj respondsToSelector:@selector(pk)])
            pk = ((id(*)(id, SEL))objc_msgSend)(obj, @selector(pk));
        if ([obj respondsToSelector:@selector(username)])
            un = ((id(*)(id, SEL))objc_msgSend)(obj, @selector(username));
        if ([obj respondsToSelector:@selector(fullName)])
            fn = ((id(*)(id, SEL))objc_msgSend)(obj, @selector(fullName));
        if (pk && un) {
            return @{ @"pk": [NSString stringWithFormat:@"%@", pk],
                      @"username": [NSString stringWithFormat:@"%@", un],
                      @"fullName": fn ? [NSString stringWithFormat:@"%@", fn] : @"" };
        }
        NSArray *nestedKeys = @[@"user", @"owner", @"author", @"reelUser", @"reelOwner"];
        for (NSString *k in nestedKeys) {
            @try {
                id sub = [obj valueForKey:k];
                if (sub && sub != obj) {
                    NSDictionary *d = sciOwnerInfoFromObject(sub);
                    if (d) return d;
                }
            } @catch (__unused id e) {}
        }
    } @catch (__unused id e) {}
    return nil;
}

NSDictionary *sciOwnerInfoForStoryVC(UIViewController *vc) {
    if (!vc) return nil;
    @try {
        id vm = ((id(*)(id, SEL))objc_msgSend)(vc, @selector(currentViewModel));
        if (!vm) return nil;
        id owner = nil;
        @try { owner = [vm valueForKey:@"owner"]; } @catch (__unused id e) {}
        if (!owner) return nil;
        return sciOwnerInfoFromObject(owner);
    } @catch (__unused id e) { return nil; }
}

NSDictionary *sciCurrentStoryOwnerInfo(void) {
    return sciOwnerInfoForStoryVC(sciActiveStoryViewerVC);
}

// Find the section controller for a specific cell via ivar scan.
static id sciFindSectionControllerForCell(UICollectionViewCell *cell) {
    Class sectionClass = NSClassFromString(@"IGStoryFullscreenSectionController");
    if (!sectionClass || !cell) return nil;
    unsigned int cCount = 0;
    Ivar *cIvars = class_copyIvarList([cell class], &cCount);
    for (unsigned int i = 0; i < cCount; i++) {
        const char *type = ivar_getTypeEncoding(cIvars[i]);
        if (!type || type[0] != '@') continue;
        id val = object_getIvar(cell, cIvars[i]);
        if (!val) continue;
        if ([val isKindOfClass:sectionClass]) { free(cIvars); return val; }
        unsigned int vCount = 0;
        Ivar *vIvars = class_copyIvarList([val class], &vCount);
        for (unsigned int j = 0; j < vCount; j++) {
            const char *type2 = ivar_getTypeEncoding(vIvars[j]);
            if (!type2 || type2[0] != '@') continue;
            id val2 = object_getIvar(val, vIvars[j]);
            if (val2 && [val2 isKindOfClass:sectionClass]) { free(vIvars); free(cIvars); return val2; }
        }
        if (vIvars) free(vIvars);
    }
    if (cIvars) free(cIvars);
    return nil;
}

static NSDictionary *sciOwnerInfoFromSectionController(id sc) {
    if (!sc) return nil;
    NSArray *tryKeys = @[@"viewModel", @"item", @"model", @"object"];
    for (NSString *k in tryKeys) {
        @try {
            id obj = [sc valueForKey:k];
            if (obj) {
                NSDictionary *info = sciOwnerInfoFromObject(obj);
                if (info) return info;
            }
        } @catch (__unused id e) {}
    }
    return sciOwnerInfoFromObject(sc);
}

// Per-cell owner lookup: walks from the overlay to its IGStoryFullscreenCell,
// finds the cell's section controller, and reads the owner. Gives the correct
// owner even when multiple cells are alive (pre-loaded adjacent reels).
NSDictionary *sciOwnerInfoForView(UIView *view) {
    if (!view) return nil;
    Class cellClass = NSClassFromString(@"IGStoryFullscreenCell");
    UIView *cur = view;
    UICollectionViewCell *cell = nil;
    while (cur) {
        if (cellClass && [cur isKindOfClass:cellClass]) { cell = (UICollectionViewCell *)cur; break; }
        cur = cur.superview;
    }
    if (cell) {
        id sc = sciFindSectionControllerForCell(cell);
        NSDictionary *info = sciOwnerInfoFromSectionController(sc);
        if (info) return info;
    }
    // Fallback: VC's currentViewModel
    UIViewController *vc = sciFindVC(view, @"IGStoryViewerViewController");
    return sciOwnerInfoForStoryVC(vc);
}

BOOL sciIsCurrentStoryOwnerExcluded(void) {
    NSDictionary *info = sciCurrentStoryOwnerInfo();
    // Unknown owner: block_selected → don't block; block_all → block.
    if (!info) return [SCIExcludedStoryUsers isBlockSelectedMode];
    return [SCIExcludedStoryUsers isUserPKExcluded:info[@"pk"]];
}

BOOL sciIsObjectStoryOwnerExcluded(id obj) {
    NSDictionary *info = sciOwnerInfoFromObject(obj);
    if (!info) return [SCIExcludedStoryUsers isBlockSelectedMode];
    return [SCIExcludedStoryUsers isUserPKExcluded:info[@"pk"]];
}

// ============ Overlay utilities ============

void sciTriggerStoryMarkSeen(UIViewController *storyVC) {
    if (!storyVC) return;
    Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayCls) overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayMetalLayerView");
    if (!overlayCls) return;
    SEL markSel = @selector(sciMarkSeenTapped:);
    NSMutableArray *stack = [NSMutableArray arrayWithObject:storyVC.view];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:overlayCls] && [v respondsToSelector:markSel]) {
            ((void(*)(id, SEL, id))objc_msgSend)(v, markSel, nil);
            return;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

void sciRefreshAllVisibleOverlays(UIViewController *storyVC) {
    if (!storyVC) return;
    Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayCls) overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayMetalLayerView");
    if (!overlayCls) return;
    SEL refreshSel = @selector(sciRefreshSeenButton);
    SEL audioSel = @selector(sciRefreshAudioButton);
    NSMutableArray *stack = [NSMutableArray arrayWithObject:storyVC.view];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:overlayCls]) {
            if ([v respondsToSelector:refreshSel])
                ((void(*)(id, SEL))objc_msgSend)(v, refreshSel);
            if ([v respondsToSelector:audioSel])
                ((void(*)(id, SEL))objc_msgSend)(v, audioSel);
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

// ============ 3-dot menu injection ============
// Hooks into the existing IGDSMenu hook in Tweak.x via sciMaybeAppendStoryExcludeMenuItem.
// Always present regardless of master toggle (fallback when eye affordance is hidden).

NSArray *sciMaybeAppendStoryExcludeMenuItem(NSArray *items) {
    if (!sciActiveStoryViewerVC) return items;
    BOOL looksLikeStoryHeader = NO;
    for (id it in items) {
        @try {
            id title = [it valueForKey:@"title"];
            NSString *t = [NSString stringWithFormat:@"%@", title ?: @""];
            if ([t isEqualToString:@"Report"] || [t isEqualToString:@"Mute"] ||
                [t isEqualToString:@"Unfollow"] || [t isEqualToString:@"Follow"] ||
                [t isEqualToString:@"Hide"]) {
                looksLikeStoryHeader = YES; break;
            }
        } @catch (__unused id e) {}
    }
    if (!looksLikeStoryHeader) return items;

    NSDictionary *ownerInfo = sciCurrentStoryOwnerInfo();
    if (!ownerInfo) return items;

    NSString *pk = ownerInfo[@"pk"];
    NSString *username = ownerInfo[@"username"] ?: @"";
    NSString *fullName = ownerInfo[@"fullName"] ?: @"";
    // Bypass master toggle so the 3-dot fallback always shows
    BOOL inList = [SCIExcludedStoryUsers isInList:pk];
    BOOL blockSelected = [SCIExcludedStoryUsers isBlockSelectedMode];

    Class menuItemCls = NSClassFromString(@"IGDSMenuItem");
    if (!menuItemCls) return items;

    NSString *addLabel = blockSelected ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude story seen");
    NSString *removeLabel = blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude story seen");
    NSString *title = inList ? removeLabel : addLabel;

    __weak UIViewController *weakVC = sciActiveStoryViewerVC;
    void (^handler)(void) = ^{
        if (inList) {
            [SCIExcludedStoryUsers removePK:pk];
            [SCIUtils showToastForDuration:2.0 title:blockSelected ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded")];
            // Removing in block_selected = normal behavior → mark seen
            if (blockSelected) sciTriggerStoryMarkSeen(weakVC);
        } else {
            [SCIExcludedStoryUsers addOrUpdateEntry:@{
                @"pk": pk, @"username": username, @"fullName": fullName
            }];
            [SCIUtils showToastForDuration:2.0 title:blockSelected ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded")];
            // Adding in block_all = normal behavior → mark seen
            if (!blockSelected) sciTriggerStoryMarkSeen(weakVC);
        }
        sciRefreshAllVisibleOverlays(weakVC);
    };

    id newItem = nil;
    @try {
        SEL initSel = @selector(initWithTitle:image:handler:);
        typedef id (*Init)(id, SEL, id, id, id);
        newItem = ((Init)objc_msgSend)([menuItemCls alloc], initSel, title, nil, handler);
    } @catch (__unused id e) { newItem = nil; }

    if (!newItem) return items;

    NSMutableArray *newItems = [items mutableCopy] ?: [NSMutableArray array];
    [newItems addObject:newItem];
    return [newItems copy];
}
