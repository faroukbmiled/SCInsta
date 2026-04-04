// Story seen receipt blocking + visual seen state blocking
#import "StoryHelpers.h"

BOOL sciSeenBypassActive = NO;
NSMutableSet *sciAllowedSeenPKs = nil;

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
    return [sciAllowedSeenPKs containsObject:[NSString stringWithFormat:@"%@", pk]];
}

static BOOL sciShouldBlockSeenNetwork() {
    if (sciSeenBypassActive) return NO;
    return [SCIUtils getBoolPref:@"no_seen_receipt"];
}

static BOOL sciShouldBlockSeenVisual() {
    if (sciSeenBypassActive) return NO;
    return [SCIUtils getBoolPref:@"no_seen_receipt"] && [SCIUtils getBoolPref:@"no_seen_visual"];
}

// network seen blocking
%hook IGStorySeenStateUploader
- (void)uploadSeenStateWithMedia:(id)arg1 {
    if (!sciSeenBypassActive && sciShouldBlockSeenNetwork() && !sciIsPKAllowed(arg1)) return;
    %orig;
}
- (void)uploadSeenState {
    if (!sciSeenBypassActive && sciShouldBlockSeenNetwork() && !(sciAllowedSeenPKs && sciAllowedSeenPKs.count > 0)) return;
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
- (id)networker { return %orig; }
%end

// visual seen blocking + story auto-advance
%hook IGStoryFullscreenSectionController
- (void)markItemAsSeen:(id)arg1 { if (sciShouldBlockSeenVisual() && !sciIsPKAllowed(arg1)) return; %orig; }
- (void)_markItemAsSeen:(id)arg1 { if (sciShouldBlockSeenVisual() && !sciIsPKAllowed(arg1)) return; %orig; }
- (void)storySeenStateDidChange:(id)arg1 { if (sciShouldBlockSeenVisual()) return; %orig; }
- (void)sendSeenRequestForCurrentItem { if (sciShouldBlockSeenVisual()) return; %orig; }
- (void)markCurrentItemAsSeen { if (sciShouldBlockSeenVisual()) return; %orig; }
- (void)storyPlayerMediaViewDidPlayToEnd:(id)arg1 {
    if ([SCIUtils getBoolPref:@"stop_story_auto_advance"]) return;
    %orig;
}
- (void)advanceToNextReelForAutoScroll {
    if ([SCIUtils getBoolPref:@"stop_story_auto_advance"]) return;
    %orig;
}
%end

%hook IGStoryViewerViewController
- (void)fullscreenSectionController:(id)arg1 didMarkItemAsSeen:(id)arg2 {
    if (sciShouldBlockSeenVisual() && !sciIsPKAllowed(arg2)) return;
    %orig;
}
%end

%hook IGStoryTrayViewModel
- (void)markAsSeen { if (sciShouldBlockSeenVisual()) return; %orig; }
- (void)setHasUnseenMedia:(BOOL)arg1 { if (sciShouldBlockSeenVisual()) { %orig(YES); return; } %orig; }
- (BOOL)hasUnseenMedia { if (sciShouldBlockSeenVisual()) return YES; return %orig; }
- (void)setIsSeen:(BOOL)arg1 { if (sciShouldBlockSeenVisual()) { %orig(NO); return; } %orig; }
- (BOOL)isSeen { if (sciShouldBlockSeenVisual()) return NO; return %orig; }
%end

%hook IGStoryItem
- (void)setHasSeen:(BOOL)arg1 { if (sciShouldBlockSeenVisual()) { %orig(NO); return; } %orig; }
- (BOOL)hasSeen { if (sciShouldBlockSeenVisual()) return NO; return %orig; }
%end

%hook IGStoryGradientRingView
- (void)setIsSeen:(BOOL)arg1 { if (sciShouldBlockSeenVisual()) { %orig(NO); return; } %orig; }
- (void)setSeen:(BOOL)arg1 { if (sciShouldBlockSeenVisual()) { %orig(NO); return; } %orig; }
- (void)updateRingForSeenState:(BOOL)arg1 { if (sciShouldBlockSeenVisual()) { %orig(NO); return; } %orig; }
%end
