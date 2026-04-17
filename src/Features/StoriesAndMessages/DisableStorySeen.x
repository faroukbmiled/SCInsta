// Story seen-receipt blocking. Legacy + Sundial uploads are Swift-dispatched
// via a `networker` ivar — we cache the uploaders at init and nil the ivar
// while the active owner is blocked. `keep_seen_visual_local` ON runs orig
// (local stores update, server blocked). OFF skips orig (full block).

#import "StoryHelpers.h"
#import "SCIStoryInteractionPipeline.h"
#import "SCIExcludedStoryUsers.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

BOOL sciSeenBypassActive = NO;
BOOL sciAdvanceBypassActive = NO;
BOOL sciStorySeenToggleEnabled = NO; // toggle-mode session bypass
NSMutableSet *sciAllowedSeenPKs = nil;

extern BOOL sciIsCurrentStoryOwnerExcluded(void);
extern BOOL sciIsObjectStoryOwnerExcluded(id obj);

static void sciStateRestore(void); // fwd — used by VC hook above its definition

static BOOL sciStorySeenToggleBypass(void) {
    return [[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"] && sciStorySeenToggleEnabled;
}

void sciAllowSeenForPK(id media) {
    if (!media) return;
    id pk = sciCall(media, @selector(pk));
    if (!pk) return;
    if (!sciAllowedSeenPKs) sciAllowedSeenPKs = [NSMutableSet set];
    [sciAllowedSeenPKs addObject:[NSString stringWithFormat:@"%@", pk]];
}

static BOOL sciIsPKAllowed(id media) {
    if (!media || !sciAllowedSeenPKs || sciAllowedSeenPKs.count == 0) return NO;
    id pk = sciCall(media, @selector(pk));
    if (!pk) return NO;
    NSString *pkStr = [NSString stringWithFormat:@"%@", pk];
    if (![sciAllowedSeenPKs containsObject:pkStr]) return NO;
    if ([SCIExcludedStoryUsers isFeatureEnabled] && ![SCIExcludedStoryUsers isUserPKExcluded:pkStr])
        return NO;
    return YES;
}

// ============ Feature gates ============

static BOOL sciShouldBlockSeenNetwork(void) {
    if (sciSeenBypassActive) return NO;
    if (sciStorySeenToggleBypass()) return NO;
    if (sciIsCurrentStoryOwnerExcluded()) return NO;
    return [SCIUtils getBoolPref:@"no_seen_receipt"];
}

static BOOL sciShouldBlockSeenVisual(void) {
    if (sciSeenBypassActive) return NO;
    if (sciStorySeenToggleBypass()) return NO;
    if (sciIsCurrentStoryOwnerExcluded()) return NO;
    if (![SCIUtils getBoolPref:@"no_seen_receipt"]) return NO;
    return ![SCIUtils getBoolPref:@"keep_seen_visual_local"];
}

// Per-instance gate — tray/item/ring models may not match the active VC.
static BOOL sciShouldBlockSeenVisualForObj(id obj) {
    if (sciSeenBypassActive) return NO;
    if (sciStorySeenToggleBypass()) return NO;
    if (![SCIUtils getBoolPref:@"no_seen_receipt"]) return NO;
    if ([SCIUtils getBoolPref:@"keep_seen_visual_local"]) return NO;
    if (sciIsObjectStoryOwnerExcluded(obj)) return NO;
    return YES;
}

// ============ Legacy network-upload hooks (pre-Sundial fallback) ============
%hook IGStorySeenStateUploader
- (void)uploadSeenStateWithMedia:(id)arg1 {
    if (!sciSeenBypassActive && sciShouldBlockSeenNetwork() && !sciIsPKAllowed(arg1)) return;
    %orig;
}
- (void)uploadSeenState {
    if (!sciSeenBypassActive && sciShouldBlockSeenNetwork()) return;
    %orig;
}
- (void)_uploadSeenState:(id)arg1 {
    if (!sciSeenBypassActive && sciShouldBlockSeenNetwork() && !sciIsPKAllowed(arg1)) return;
    %orig;
}
- (void)sendSeenReceipt:(id)arg1 {
    if (!sciSeenBypassActive && sciShouldBlockSeenNetwork() && !sciIsPKAllowed(arg1)) return;
    %orig;
}
%end

// ============ Visual-seen hooks + auto-advance ============

%hook IGStoryFullscreenSectionController
- (void)markItemAsSeen:(id)arg1 { if (sciShouldBlockSeenVisual() && !sciIsPKAllowed(arg1)) return; %orig; }
- (void)_markItemAsSeen:(id)arg1 { if (sciShouldBlockSeenVisual() && !sciIsPKAllowed(arg1)) return; %orig; }
- (void)storySeenStateDidChange:(id)arg1 { if (sciShouldBlockSeenVisual()) return; %orig; }
- (void)markCurrentItemAsSeen { if (sciShouldBlockSeenVisual()) return; %orig; }
- (void)sendSeenRequestForCurrentItem { if (sciShouldBlockSeenNetwork()) return; %orig; }
- (void)storyPlayerMediaViewDidPlayToEnd:(id)arg1 {
    if (!sciAdvanceBypassActive && [SCIUtils getBoolPref:@"stop_story_auto_advance"]) return;
    %orig;
}
- (void)advanceToNextReelForAutoScroll {
    if (!sciAdvanceBypassActive && [SCIUtils getBoolPref:@"stop_story_auto_advance"]) return;
    %orig;
}
%end

%hook IGStoryTrayViewModel
- (void)markAsSeen { if (sciShouldBlockSeenVisualForObj(self)) return; %orig; }
- (void)setHasUnseenMedia:(BOOL)arg1 { if (sciShouldBlockSeenVisualForObj(self)) { %orig(YES); return; } %orig; }
- (BOOL)hasUnseenMedia { if (sciShouldBlockSeenVisualForObj(self)) return YES; return %orig; }
- (void)setIsSeen:(BOOL)arg1 { if (sciShouldBlockSeenVisualForObj(self)) { %orig(NO); return; } %orig; }
- (BOOL)isSeen { if (sciShouldBlockSeenVisualForObj(self)) return NO; return %orig; }
%end

%hook IGStoryItem
- (void)setHasSeen:(BOOL)arg1 { if (sciShouldBlockSeenVisualForObj(self)) { %orig(NO); return; } %orig; }
- (BOOL)hasSeen { if (sciShouldBlockSeenVisualForObj(self)) return NO; return %orig; }
%end

%hook IGStoryGradientRingView
- (void)setIsSeen:(BOOL)arg1 { if (sciShouldBlockSeenVisual()) { %orig(NO); return; } %orig; }
- (void)setSeen:(BOOL)arg1 { if (sciShouldBlockSeenVisual()) { %orig(NO); return; } %orig; }
- (void)updateRingForSeenState:(BOOL)arg1 { if (sciShouldBlockSeenVisual()) { %orig(NO); return; } %orig; }
%end

// ============ Active story VC tracking ============

__weak UIViewController *sciActiveStoryVC = nil;

%hook IGStoryViewerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sciActiveStoryVC = self;
}
- (void)viewWillDisappear:(BOOL)animated {
    if (sciActiveStoryVC == (UIViewController *)self) sciActiveStoryVC = nil;
    sciStateRestore();
    %orig;
}
- (void)fullscreenSectionController:(id)arg1 didMarkItemAsSeen:(id)arg2 {
    if (sciShouldBlockSeenVisual() && !sciIsPKAllowed(arg2)) return;
    %orig;
}
%end

// ============ Networker-ivar swap (v425+ split-mode) ============

static __weak id sciLegacyUploader = nil;   // IGStorySeenStateUploader
static __weak id sciSundialManager = nil;   // IGSundialSeenStateManager

static id (*orig_pendingStoreInit)(id, SEL, id, id, id, BOOL);
static id new_pendingStoreInit(id self, SEL _cmd, id sessionPK, id uploader, id fileMgr, BOOL bgTask) {
    if (uploader) sciLegacyUploader = uploader;
    return orig_pendingStoreInit(self, _cmd, sessionPK, uploader, fileMgr, bgTask);
}

static id (*orig_sundialMgrInit)(id, SEL, id, id, id, id);
static id new_sundialMgrInit(id self, SEL _cmd, id networker, id diskMgr, id launcherSet, id announcer) {
    id res = orig_sundialMgrInit(self, _cmd, networker, diskMgr, launcherSet, announcer);
    if (res) sciSundialManager = res;
    return res;
}

// Swap each cached uploader's networker ivar; saved dict is used to restore.
static NSDictionary *sciSwapNetworkers(id newNetworker) {
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    @try {
        id legacy = sciLegacyUploader;
        if (legacy) {
            Ivar iv = class_getInstanceVariable([legacy class], "_networker");
            if (iv) {
                id old = object_getIvar(legacy, iv);
                if (old) saved[@"legacy"] = old;
                object_setIvar(legacy, iv, newNetworker);
            }
        }
        id mgr = sciSundialManager;
        if (mgr) {
            for (NSString *ivName in @[@"seenStateUploader", @"seenStateUploaderDeprecated"]) {
                Ivar mgrIv = class_getInstanceVariable([mgr class], [ivName UTF8String]);
                if (!mgrIv) continue;
                id up = object_getIvar(mgr, mgrIv);
                if (!up) continue;
                Ivar netIv = class_getInstanceVariable([up class], "networker");
                if (!netIv) continue;
                id oldNet = object_getIvar(up, netIv);
                if (oldNet) saved[ivName] = oldNet;
                object_setIvar(up, netIv, newNetworker);
            }
        }
    } @catch (__unused id e) {}
    return saved;
}

static void sciRestoreNetworkers(NSDictionary *saved) {
    @try {
        id legacy = sciLegacyUploader;
        if (legacy && saved[@"legacy"]) {
            Ivar iv = class_getInstanceVariable([legacy class], "_networker");
            if (iv) object_setIvar(legacy, iv, saved[@"legacy"]);
        }
        id mgr = sciSundialManager;
        if (mgr) {
            for (NSString *ivName in @[@"seenStateUploader", @"seenStateUploaderDeprecated"]) {
                if (!saved[ivName]) continue;
                Ivar mgrIv = class_getInstanceVariable([mgr class], [ivName UTF8String]);
                if (!mgrIv) continue;
                id up = object_getIvar(mgr, mgrIv);
                if (!up) continue;
                Ivar netIv = class_getInstanceVariable([up class], "networker");
                if (netIv) object_setIvar(up, netIv, saved[ivName]);
            }
        }
    } @catch (__unused id e) {}
}

// Idempotent block/restore. Guard prevents double-swap clobbering the saved originals.
static BOOL sciNetBlocked = NO;
static NSDictionary *sciNetSaved = nil;

static void sciStateBlock(void) {
    if (sciNetBlocked) return;
    sciNetSaved = sciSwapNetworkers(nil);
    sciNetBlocked = YES;
}

static void sciStateRestore(void) {
    if (!sciNetBlocked) return;
    sciRestoreNetworkers(sciNetSaved);
    sciNetSaved = nil;
    sciNetBlocked = NO;
}

static NSString *sciExtractOwnerPKFromItem(id item) {
    NSString *pk = nil;
    @try {
        id reelPk = [item respondsToSelector:@selector(reelPk)] ? [item performSelector:@selector(reelPk)] : nil;
        if (reelPk) pk = [reelPk description];
        if (!pk) {
            id media = [item respondsToSelector:@selector(media)] ? [item performSelector:@selector(media)] : item;
            id user = [media respondsToSelector:@selector(user)] ? [media performSelector:@selector(user)] : nil;
            if (!user) user = [media respondsToSelector:@selector(owner)] ? [media performSelector:@selector(owner)] : nil;
            if (user) {
                Ivar pkIvar = NULL;
                for (Class c = [user class]; c && !pkIvar; c = class_getSuperclass(c))
                    pkIvar = class_getInstanceVariable(c, "_pk");
                if (pkIvar) pk = [object_getIvar(user, pkIvar) description];
            }
        }
    } @catch (__unused id e) {}
    return pk;
}

// Mark-seen delegate: restore on non-blocked owners, block + run orig on
// blocked owners when split-mode is on, skip orig when it's off.
static void (*orig_delegateMarkSeen)(id, SEL, id, id);
static void new_delegateMarkSeen(id self, SEL _cmd, id ctrl, id item) {
    if (sciSeenBypassActive) { sciStateRestore(); orig_delegateMarkSeen(self, _cmd, ctrl, item); return; }
    if (![SCIUtils getBoolPref:@"no_seen_receipt"]) { sciStateRestore(); orig_delegateMarkSeen(self, _cmd, ctrl, item); return; }

    NSString *ownerPK = sciExtractOwnerPKFromItem(item);
    BOOL shouldBlock;
    if ([SCIExcludedStoryUsers isFeatureEnabled])
        shouldBlock = ownerPK.length && ![SCIExcludedStoryUsers isUserPKExcluded:ownerPK];
    else
        shouldBlock = YES;

    if (!shouldBlock) {
        sciStateRestore();
        orig_delegateMarkSeen(self, _cmd, ctrl, item);
        return;
    }

    if (![SCIUtils getBoolPref:@"keep_seen_visual_local"]) {
        sciStateRestore();
        return;
    }

    sciStateBlock();
    @try { orig_delegateMarkSeen(self, _cmd, ctrl, item); }
    @catch (__unused id e) { sciStateRestore(); }
}

// ============ Like → mark-seen side effects ============

static void (*orig_didLikeSundial)(id, SEL, id);
static void new_didLikeSundial(id self, SEL _cmd, id pk) {
    orig_didLikeSundial(self, _cmd, pk);
    sciStoryInteractionSideEffects(SCIStoryInteractionLike);
}

static void (*orig_overlaySetIsLiked)(id, SEL, BOOL, BOOL);
static void new_overlaySetIsLiked(id self, SEL _cmd, BOOL isLiked, BOOL animated) {
    orig_overlaySetIsLiked(self, _cmd, isLiked, animated);
    if (isLiked) sciStoryInteractionSideEffects(SCIStoryInteractionLike);
}

static void (*orig_likeButtonSetIsLiked)(id, SEL, BOOL, BOOL);
static void new_likeButtonSetIsLiked(id self, SEL _cmd, BOOL isLiked, BOOL animated) {
    orig_likeButtonSetIsLiked(self, _cmd, isLiked, animated);
    if (isLiked) sciStoryInteractionSideEffects(SCIStoryInteractionLike);
}

%ctor {
    Class overlayCtl = NSClassFromString(@"IGSundialViewerControlsOverlayController");
    if (overlayCtl) {
        SEL didLike = NSSelectorFromString(@"didLikeSundialWithMediaPK:");
        if (class_getInstanceMethod(overlayCtl, didLike))
            MSHookMessageEx(overlayCtl, didLike, (IMP)new_didLikeSundial, (IMP *)&orig_didLikeSundial);
        SEL setLiked = @selector(setIsLiked:animated:);
        if (class_getInstanceMethod(overlayCtl, setLiked))
            MSHookMessageEx(overlayCtl, setLiked, (IMP)new_overlaySetIsLiked, (IMP *)&orig_overlaySetIsLiked);
    }

    Class likeBtn = NSClassFromString(@"IGSundialViewerUFI.IGSundialLikeButton");
    if (likeBtn) {
        SEL setLiked = @selector(setIsLiked:animated:);
        if (class_getInstanceMethod(likeBtn, setLiked))
            MSHookMessageEx(likeBtn, setLiked, (IMP)new_likeButtonSetIsLiked, (IMP *)&orig_likeButtonSetIsLiked);
    }

    Class pending = NSClassFromString(@"IGStoryPendingSeenStateStore");
    SEL pendingSel = NSSelectorFromString(@"initWithUserSessionPK:uploader:fileManager:uploadInBackgroundTask:");
    if (pending && class_getInstanceMethod(pending, pendingSel))
        MSHookMessageEx(pending, pendingSel, (IMP)new_pendingStoreInit, (IMP *)&orig_pendingStoreInit);

    Class sundialMgr = NSClassFromString(@"_TtC23IGSundialSeenStateSwift25IGSundialSeenStateManager");
    SEL mgrSel = NSSelectorFromString(@"initWithNetworker:diskManager:launcherSet:seenStateManagerAnnouncer:");
    if (sundialMgr && class_getInstanceMethod(sundialMgr, mgrSel))
        MSHookMessageEx(sundialMgr, mgrSel, (IMP)new_sundialMgrInit, (IMP *)&orig_sundialMgrInit);

    // Mark-as-seen delegate; extras are forward-compat candidates.
    for (NSString *clsName in @[
        @"IGStoryViewerViewController",
        @"IGStoryViewerUpdater",
        @"IGStoryFullscreenViewModel",
        @"IGStoriesManager",
    ]) {
        Class cls = NSClassFromString(clsName);
        if (!cls) continue;
        SEL delegateSel = NSSelectorFromString(@"fullscreenSectionController:didMarkItemAsSeen:");
        if (class_getInstanceMethod(cls, delegateSel))
            MSHookMessageEx(cls, delegateSel, (IMP)new_delegateMarkSeen, (IMP *)&orig_delegateMarkSeen);
    }
}
