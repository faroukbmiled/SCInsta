// Story overlay buttons — action / audio / eye / mentions (tags 1339–1341, 1345).
// Early-exits in DM context; DMOverlayButtons.xm handles that surface.

#import "OverlayHelpers.h"
#import "SCIExcludedStoryUsers.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIIcon.h"
#import "../../ActionButton/SCIActionButton.h"
#import "../../ActionButton/SCIActionIcon.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../Downloader/Download.h"

extern "C" BOOL sciSeenBypassActive;
extern "C" BOOL sciAdvanceBypassActive;
extern "C" void sciAllowSeenForPK(id);
extern "C" BOOL sciStorySeenToggleEnabled;
extern "C" void sciRefreshAllVisibleOverlays(UIViewController *storyVC);
extern "C" void sciTriggerStoryMarkSeen(UIViewController *storyVC);
extern "C" __weak UIViewController *sciActiveStoryViewerVC;
extern "C" NSDictionary *sciOwnerInfoForView(UIView *view);

static char kStoryActionObservedKey;
static char kStoryActionDefaultKey;
static char kStoryReelItemsProviderKey;
static char kStoryMentionsAnchorKey;
static char kStoryMentionsRetryGenKey;
static void *kStoryActionHighlightContext = &kStoryActionHighlightContext;

static inline BOOL SCIStoryActionEnabled(void) {
	return [SCIUtils getBoolPref:@"stories_action_button"];
}

static inline NSString *SCIStoryDefaultAction(void) {
	return [SCIUtils getStringPref:@"stories_action_default"];
}

static inline SCIChromeButton *SCIStoryButton(NSString *symbol, CGFloat pointSize, CGFloat diameter, NSInteger tag) {
	SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:symbol pointSize:pointSize diameter:diameter];
	button.tag = tag;
	return button;
}

static void SCIRemoveStoryButton(UIView *root, NSInteger tag, id observer) {
	UIView *view = [root viewWithTag:tag];
	if (!view) return;

	if ([objc_getAssociatedObject(view, &kStoryActionObservedKey) boolValue]) {
		@try {
			[view removeObserver:observer forKeyPath:@"highlighted" context:kStoryActionHighlightContext];
		} @catch (__unused id e) {}

		objc_setAssociatedObject(view, &kStoryActionObservedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	[view removeFromSuperview];
}

// MARK: - Playback control

static void sciPauseStoryPlayback(UIView *sourceView) {
	UIViewController *storyVC = sciFindVC(sourceView, @"IGStoryViewerViewController");
	if (!storyVC) return;

	id sectionController = sciFindSectionController(storyVC);
	SEL pauseSel = NSSelectorFromString(@"pauseWithReason:");

	if (sectionController && [sectionController respondsToSelector:pauseSel]) {
		((void(*)(id, SEL, NSInteger))objc_msgSend)(sectionController, pauseSel, 10);
		return;
	}

	if ([storyVC respondsToSelector:pauseSel]) {
		((void(*)(id, SEL, NSInteger))objc_msgSend)(storyVC, pauseSel, 10);
	}
}

static void sciResumeStoryPlayback(UIView *sourceView) {
	UIViewController *storyVC = sciFindVC(sourceView, @"IGStoryViewerViewController");
	if (!storyVC) return;

	id sectionController = sciFindSectionController(storyVC);
	SEL resumeWithReasonSel = NSSelectorFromString(@"tryResumePlaybackWithReason:");
	SEL resumeSel = NSSelectorFromString(@"tryResumePlayback");

	if (sectionController && [sectionController respondsToSelector:resumeWithReasonSel]) {
		((void(*)(id, SEL, NSInteger))objc_msgSend)(sectionController, resumeWithReasonSel, 0);
		return;
	}

	if ([storyVC respondsToSelector:resumeSel]) {
		((void(*)(id, SEL))objc_msgSend)(storyVC, resumeSel);
		return;
	}

	if ([storyVC respondsToSelector:resumeWithReasonSel]) {
		((void(*)(id, SEL, NSInteger))objc_msgSend)(storyVC, resumeWithReasonSel, 0);
	}
}

// Used by SCIMediaActions for "download all".
static NSArray *sciStoryReelItemsForSource(UIView *sourceView) {
	UIViewController *storyVC = sciFindVC(sourceView, @"IGStoryViewerViewController");
	if (!storyVC) return nil;

	id viewModel = sciCall(storyVC, @selector(currentViewModel));
	if (!viewModel) return nil;

	for (NSString *selName in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
		SEL sel = NSSelectorFromString(selName);
		if (![viewModel respondsToSelector:sel]) continue;

		@try {
			id value = ((id(*)(id, SEL))objc_msgSend)(viewModel, sel);
			if ([value isKindOfClass:NSArray.class] && [(NSArray *)value count] > 1) return value;
		} @catch (__unused id e) {}
	}

	return nil;
}

static void SCIConfigureStoryActionButton(SCIChromeButton *button) {
	if (!button) return;

	SCIActionMediaProvider provider = ^id (UIView *sourceView) {
		sciPauseStoryPlayback(sourceView);

		id item = sciGetCurrentStoryItem(sourceView);
		if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) return item;

		id extracted = sciExtractMediaFromItem(item);
		return extracted ?: (id)kCFNull;
	};

	[SCIActionButton configureButton:button
							 context:SCIActionContextStories
							 prefKey:@"stories_action_default"
					   mediaProvider:provider];

	objc_setAssociatedObject(button, &kStoryReelItemsProviderKey, ^NSArray *(UIView *sourceView) {
		return sciStoryReelItemsForSource(sourceView);
	}, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

// MARK: - Overlay hook

%group StoryOverlayGroup

%hook IGStoryFullscreenOverlayView

- (void)didMoveToSuperview {
	%orig;

	if (!self.superview) return;

	// Strip stale tags up-front so nothing flashes when this overlay
	// turns out to belong to a DM viewer.
	SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG, self);
	SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG, self);
	SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG, self);

	// Defer one tick — responder chain is not always complete yet.
	__weak __typeof(self) weakSelf = self;

	dispatch_async(dispatch_get_main_queue(), ^{
		__strong __typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.superview) return;

		if (sciOverlayIsInDMContext(strongSelf)) {
			SCIRemoveStoryButton(strongSelf, SCI_STORY_ACTION_TAG, strongSelf);
			SCIRemoveStoryButton(strongSelf, SCI_STORY_EYE_TAG, strongSelf);
			SCIRemoveStoryButton(strongSelf, SCI_STORY_AUDIO_TAG, strongSelf);
			return;
		}

		((void(*)(id, SEL))objc_msgSend)(strongSelf, @selector(sciInstallStoryOverlayButtons));
	});
}

- (void)dealloc {
	SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG, self);
	SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG, self);
	SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG, self);
	%orig;
}

%new
- (void)sciInstallStoryOverlayButtons {
	if (!self.superview) return;

	// --- Action button (tag 1340) ---
	// Rebuilt here only when installing or when the default action changes.
	SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG, self);

	if (SCIStoryActionEnabled()) {
		SCIChromeButton *button = SCIStoryButton(@"", 18.0, 36.0, SCI_STORY_ACTION_TAG);
		[self addSubview:button];

		[NSLayoutConstraint activateConstraints:@[
			[button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
			[button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
			[button.widthAnchor constraintEqualToConstant:36.0],
			[button.heightAnchor constraintEqualToConstant:36.0]
		]];

		[SCIActionIcon attachAutoUpdate:button pointSize:18.0 style:SCIActionIconStylePlain];
		SCIConfigureStoryActionButton(button);

		// Resume playback when the native UIMenu dismisses.
		[button addObserver:self forKeyPath:@"highlighted" options:NSKeyValueObservingOptionNew context:kStoryActionHighlightContext];

		objc_setAssociatedObject(button, &kStoryActionObservedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(button, &kStoryActionDefaultKey, SCIStoryDefaultAction(), OBJC_ASSOCIATION_COPY_NONATOMIC);
	}

	// --- Audio toggle (tag 1341) ---
	SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG, self);

	if ([SCIUtils getBoolPref:@"story_audio_toggle"]) {
		sciInitStoryAudioState();

		NSString *icon = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
		SCIChromeButton *button = SCIStoryButton(icon, 14.0, 28.0, SCI_STORY_AUDIO_TAG);

		[button addTarget:self action:@selector(sciStoryAudioToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self addSubview:button];

		[NSLayoutConstraint activateConstraints:@[
			[button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
			[button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
			[button.widthAnchor constraintEqualToConstant:28.0],
			[button.heightAnchor constraintEqualToConstant:28.0]
		]];
	}

	// --- Eye / mark-seen (tag 1339) ---
	// layoutSubviews can fire between the tick-0 strip and now, creating
	// the eye with fallback constraints before the action exists. Drop it
	// so the refresh rebuilds it anchored to the action button.
	SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG, self);

	if ([SCIUtils getBoolPref:@"no_seen_receipt"]) {
		((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));
	}

	// --- Mentions button (tag 1345) ---
	// Anchored to eye/action when present, otherwise free-stands at the
	// default trailing slot. Visibility independent of the action button.
	((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButton));
	((void(*)(id, SEL))objc_msgSend)(self, @selector(sciKickMentionsRetryChain));
}

// MARK: - Action button menu-dismiss resume

%new
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context != kStoryActionHighlightContext) return;
	if (![keyPath isEqualToString:@"highlighted"]) return;

	BOOL highlighted = [change[NSKeyValueChangeNewKey] boolValue];
	if (!highlighted) sciResumeStoryPlayback(self);
}

// MARK: - Action button refresh

%new
- (void)sciRefreshStoryActionButton {
	SCIChromeButton *button = (SCIChromeButton *)[self viewWithTag:SCI_STORY_ACTION_TAG];
	if (!SCIStoryActionEnabled()) {
		if (button) {
			SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG, self);
			SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG, self);
		}
		return;
	}
	if (![button isKindOfClass:SCIChromeButton.class]) {
		((void(*)(id, SEL))objc_msgSend)(self, @selector(sciInstallStoryOverlayButtons));
		return;
	}
	NSString *currentAction = SCIStoryDefaultAction();
	NSString *oldAction = objc_getAssociatedObject(button, &kStoryActionDefaultKey);
	if (oldAction && [oldAction isEqualToString:currentAction]) return;
	SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG, self);
	SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG, self);
	SCIRemoveStoryButton(self, SCI_STORY_MENTIONS_TAG, self);
	((void(*)(id, SEL))objc_msgSend)(self, @selector(sciInstallStoryOverlayButtons));
	if ([SCIUtils getBoolPref:@"no_seen_receipt"]) {((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));}
}

// MARK: - Audio toggle

%new
- (void)sciStoryAudioToggleTapped:(SCIChromeButton *)sender {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	sciToggleStoryAudio();
	sender.symbolName = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
}

%new
- (void)sciRefreshStoryAudioButton {
	if (![SCIUtils getBoolPref:@"story_audio_toggle"]) {
		SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG, self);
		return;
	}

	SCIChromeButton *button = (SCIChromeButton *)[self viewWithTag:SCI_STORY_AUDIO_TAG];
	if (![button isKindOfClass:SCIChromeButton.class]) return;

	button.symbolName = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
}

// MARK: - Seen eye button

// Visible only when no_seen_receipt is on and the owner is not excluded.
%new
- (void)sciRefreshSeenButton {
	if (![SCIUtils getBoolPref:@"no_seen_receipt"]) {
		SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG, self);
		return;
	}

	NSDictionary *ownerInfo = sciOwnerInfoForView(self);
	NSString *ownerPK = ownerInfo[@"pk"] ?: @"";
	BOOL excluded = ownerPK.length && [SCIExcludedStoryUsers isUserPKExcluded:ownerPK];

	SCIChromeButton *existing = (SCIChromeButton *)[self viewWithTag:SCI_STORY_EYE_TAG];
	if (![existing isKindOfClass:SCIChromeButton.class]) existing = nil;

	if (excluded) {
		if (existing) [existing removeFromSuperview];
		return;
	}

	BOOL toggleMode = [[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"];
	NSString *symbol = @"eye";
	UIColor *tint = UIColor.whiteColor;

	if (toggleMode && sciStorySeenToggleEnabled) {
		symbol = @"eye.fill";
		tint = SCIUtils.SCIColor_Primary;
	}

	if (existing) {
		[existing setIconResource:symbol pointSize:18.0]; // IG-styled eye glyph
		existing.iconTint = tint;
		return;
	}

	SCIChromeButton *button = SCIStoryButton(@"", 18.0, 36.0, SCI_STORY_EYE_TAG);
	[button setIconResource:symbol pointSize:18.0];
	button.iconTint = tint;

	[button addTarget:self action:@selector(sciStorySeenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

	// Long-press → context menu. Menu is rebuilt each time so owner/exclusion is fresh.
	[button addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:(id<UIContextMenuInteractionDelegate>)self]];
	[self addSubview:button];

	UIView *anchor = [self viewWithTag:SCI_STORY_ACTION_TAG];

	if (anchor) {
		[NSLayoutConstraint activateConstraints:@[
			[button.centerYAnchor constraintEqualToAnchor:anchor.centerYAnchor],
			[button.trailingAnchor constraintEqualToAnchor:anchor.leadingAnchor constant:-10.0],
			[button.widthAnchor constraintEqualToConstant:36.0],
			[button.heightAnchor constraintEqualToConstant:36.0]
		]];
	} else {
		[NSLayoutConstraint activateConstraints:@[
			[button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
			[button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
			[button.widthAnchor constraintEqualToConstant:36.0],
			[button.heightAnchor constraintEqualToConstant:36.0]
		]];
	}
}

// MARK: - Mentions button

// Anchored to the overlay's own safe area + a computed trailing offset that
// steps past whichever of action/eye are present. Anchoring against sibling
// buttons silently broke when those got rebuilt mid-transition.
%new
- (void)sciRefreshStoryMentionsButton {
	BOOL hasContent = [SCIUtils getBoolPref:@"story_mentions_button"] && sciStoryHasMentionsOrShares(self);

	SCIChromeButton *existing = (SCIChromeButton *)[self viewWithTag:SCI_STORY_MENTIONS_TAG];
	if (![existing isKindOfClass:SCIChromeButton.class]) existing = nil;

	if (!hasContent) {
		if (existing) [existing removeFromSuperview];
		return;
	}

	// Open-from-tray transition uses a degenerate IGStoryFullscreenCell shell
	// (~4x10) that gets discarded once the real fullscreen cell zooms in.
	// Defer until the overlay reaches full width; layoutSubviews re-fires.
	if (self.window && self.bounds.size.width < self.window.bounds.size.width * 0.5) {
		if (existing) [existing removeFromSuperview];
		return;
	}

	BOOL hasEye = [self viewWithTag:SCI_STORY_EYE_TAG] != nil;
	BOOL hasAction = [self viewWithTag:SCI_STORY_ACTION_TAG] != nil;
	NSInteger neighbours = (hasEye ? 1 : 0) | (hasAction ? 2 : 0);
	NSNumber *prev = objc_getAssociatedObject(existing, &kStoryMentionsAnchorKey);
	if (existing && prev && prev.integerValue == neighbours) return;

	if (existing) [existing removeFromSuperview];

	// Stays SF — `at` deliberately absent from SCIIcon's map (matches the action-button menu).
	SCIChromeButton *button = SCIStoryButton(@"at", 18.0, 36.0, SCI_STORY_MENTIONS_TAG);
	[button addTarget:self action:@selector(sciStoryMentionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:button];
	objc_setAssociatedObject(button, &kStoryMentionsAnchorKey, @(neighbours), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	CGFloat trailingOffset = -12.0;
	if (hasAction) trailingOffset -= 36.0 + 10.0;
	if (hasEye)    trailingOffset -= 36.0 + 10.0;

	[NSLayoutConstraint activateConstraints:@[
		[button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
		[button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:trailingOffset],
		[button.widthAnchor constraintEqualToConstant:36.0],
		[button.heightAnchor constraintEqualToConstant:36.0]
	]];
}

// Pando lazy-loads `reel_mentions` / `story_feed_media`. Generation-tokened
// retry chain re-checks every 350ms until data lands or attempts exhaust.
%new
- (void)sciKickMentionsRetryChain {
	if (![SCIUtils getBoolPref:@"story_mentions_button"]) return;
	if ([self viewWithTag:SCI_STORY_MENTIONS_TAG]) return;

	NSInteger gen = [objc_getAssociatedObject(self, &kStoryMentionsRetryGenKey) integerValue] + 1;
	objc_setAssociatedObject(self, &kStoryMentionsRetryGenKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	((void(*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(self, @selector(sciScheduleMentionsRetryGeneration:remaining:), gen, 6);
}

%new
- (void)sciScheduleMentionsRetryGeneration:(NSInteger)gen remaining:(NSInteger)remaining {
	if (remaining <= 0) return;

	__weak __typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		__strong __typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.superview) return;

		NSInteger current = [objc_getAssociatedObject(strongSelf, &kStoryMentionsRetryGenKey) integerValue];
		if (current != gen) return;

		((void(*)(id, SEL))objc_msgSend)(strongSelf, @selector(sciRefreshStoryMentionsButton));
		if ([strongSelf viewWithTag:SCI_STORY_MENTIONS_TAG]) return;

		((void(*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(strongSelf, @selector(sciScheduleMentionsRetryGeneration:remaining:), gen, remaining - 1);
	});
}

%new
- (void)sciStoryMentionsButtonTapped:(SCIChromeButton *)sender {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	UIViewController *storyVC = sciFindVC(self, @"IGStoryViewerViewController");
	if (!storyVC) storyVC = sciActiveStoryViewerVC;
	if (!storyVC) return;

	sciPauseStoryPlayback(self);
	sciShowStoryMentions(storyVC, self);
}

// MARK: - Owner / audio / action refresh on layout

- (void)layoutSubviews {
	%orig;

	if (sciOverlayIsInDMContext(self)) {
		SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG, self);
		SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG, self);
		SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG, self);
		SCIRemoveStoryButton(self, SCI_STORY_MENTIONS_TAG, self);
		return;
	}

	((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryActionButton));
	((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButton));

	static char kLastPKKey;
	static char kLastExcludedKey;
	static char kLastAudioKey;

	if (![SCIUtils getBoolPref:@"story_audio_toggle"]) {
		SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG, self);
	} else {
		SCIChromeButton *audioButton = (SCIChromeButton *)[self viewWithTag:SCI_STORY_AUDIO_TAG];

		if ([audioButton isKindOfClass:SCIChromeButton.class]) {
			BOOL audioOn = sciIsStoryAudioEnabled();
			NSNumber *previousAudio = objc_getAssociatedObject(self, &kLastAudioKey);

			if (!previousAudio || previousAudio.boolValue != audioOn) {
				objc_setAssociatedObject(self, &kLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryAudioButton));
			}
		}
	}

	if (![SCIUtils getBoolPref:@"no_seen_receipt"]) {
		SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG, self);
		return;
	}

	NSDictionary *info = sciOwnerInfoForView(self);
	NSString *pk = info[@"pk"] ?: @"";
	BOOL excluded = pk.length && [SCIExcludedStoryUsers isUserPKExcluded:pk];

	NSString *previousPK = objc_getAssociatedObject(self, &kLastPKKey);
	NSNumber *previousExcluded = objc_getAssociatedObject(self, &kLastExcludedKey);
	BOOL changed = !previousPK || !previousExcluded || ![pk isEqualToString:previousPK] || previousExcluded.boolValue != excluded;

	if (!changed) return;

	objc_setAssociatedObject(self, &kLastPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
	objc_setAssociatedObject(self, &kLastExcludedKey, @(excluded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	((void(*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));
}

// MARK: - Seen button tap handlers

%new
- (void)sciStorySeenButtonTapped:(SCIChromeButton *)sender {
	if ([[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"]) {
		sciStorySeenToggleEnabled = !sciStorySeenToggleEnabled;
		[sender setIconResource:(sciStorySeenToggleEnabled ? @"eye.fill" : @"eye") pointSize:18.0];
		sender.iconTint = sciStorySeenToggleEnabled ? SCIUtils.SCIColor_Primary : UIColor.whiteColor;

		SCINotifySuccess(SCI_NOTIF_SEEN_STORY,
		                 sciStorySeenToggleEnabled ? SCILocalized(@"Story read receipts enabled") : SCILocalized(@"Story read receipts disabled"),
		                 nil);
		return;
	}

	((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciStoryMarkSeenTapped:), sender);
}

// Long-press menu — rebuilt per display so owner/exclusion is always fresh.
%new
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
	__weak __typeof(self) weakSelf = self;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggested) {
		__strong __typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) return nil;

		NSDictionary *ownerInfo = sciOwnerInfoForView(strongSelf);
		NSString *pk = ownerInfo[@"pk"];
		NSString *username = ownerInfo[@"username"] ?: @"";
		NSString *fullName = ownerInfo[@"fullName"] ?: @"";
		BOOL inList = pk && [SCIExcludedStoryUsers isInList:pk];
		BOOL blockSelected = [SCIExcludedStoryUsers isBlockSelectedMode];

		NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];

		[items addObject:[UIAction actionWithTitle:SCILocalized(@"Mark seen") image:[SCIIcon imageNamed:@"eye"] identifier:nil handler:^(__unused UIAction *action) {
			((void(*)(id, SEL, id))objc_msgSend)(strongSelf, @selector(sciStoryMarkSeenTapped:), nil);
		}]];

		if (pk) {
			NSString *title = inList ? (blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude story seen")) : (blockSelected ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude story seen"));
			NSString *image = inList ? @"minus.circle" : @"eye.slash";

			UIAction *exclude = [UIAction actionWithTitle:title image:[SCIIcon imageNamed:image] identifier:nil handler:^(__unused UIAction *action) {
				if (inList) {
					[SCIExcludedStoryUsers removePK:pk];
					SCINotifySuccess(blockSelected ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY,
					                 blockSelected ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded"), nil);

					if (blockSelected) {
						sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
					}
				} else {
					[SCIExcludedStoryUsers addOrUpdateEntry:@{ @"pk": pk, @"username": username, @"fullName": fullName }];
					SCINotifySuccess(blockSelected ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY,
					                 blockSelected ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded"), nil);

					if (!blockSelected) {
						sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
					}
				}

				sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
			}];

			if (inList) exclude.attributes = UIMenuElementAttributesDestructive;
			[items addObject:exclude];
		}

		return [UIMenu menuWithTitle:@"" children:items];
	}];
}

%new
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
	sciPauseStoryPlayback(self);
}

%new
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
	__weak __typeof(self) weakSelf = self;

	void (^resume)(void) = ^{
		__strong __typeof(weakSelf) strongSelf = weakSelf;
		if (strongSelf) sciResumeStoryPlayback(strongSelf);
	};

	if (animator) [animator addCompletion:resume];
	else resume();
}

%new
- (void)sciStoryMarkSeenTapped:(UIButton *)sender {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[haptic impactOccurred];

	if (sender) {
		[UIView animateWithDuration:0.1 animations:^{
			sender.transform = CGAffineTransformMakeScale(0.8, 0.8);
			sender.alpha = 0.6;
		} completion:^(__unused BOOL finished) {
			[UIView animateWithDuration:0.15 animations:^{
				sender.transform = CGAffineTransformIdentity;
				sender.alpha = 1.0;
			}];
		}];
	}

	@try {
		UIViewController *storyVC = sciFindVC(self, @"IGStoryViewerViewController");

		if (!storyVC) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"VC not found")];
			return;
		}

		id sectionController = sciFindSectionController(storyVC);
		id storyItem = sectionController ? sciCall(sectionController, NSSelectorFromString(@"currentStoryItem")) : nil;
		if (!storyItem) storyItem = sciGetCurrentStoryItem(self);

		IGMedia *media = (storyItem && [storyItem isKindOfClass:NSClassFromString(@"IGMedia")]) ? storyItem : sciExtractMediaFromItem(storyItem);

		if (!media) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find story media")];
			return;
		}

		sciAllowSeenForPK(media);
		sciSeenBypassActive = YES;

		SEL delegateSel = @selector(fullscreenSectionController:didMarkItemAsSeen:);

		if ([storyVC respondsToSelector:delegateSel]) {
			((void(*)(id, SEL, id, id))objc_msgSend)(storyVC, delegateSel, sectionController, media);
		}

		if (sectionController) {
			SEL markSel = NSSelectorFromString(@"markItemAsSeen:");

			if ([sectionController respondsToSelector:markSel]) {
				((SCIMsgSend1)objc_msgSend)(sectionController, markSel, media);
			}
		}

		id seenManager = sciCall(storyVC, @selector(viewingSessionSeenStateManager));
		id viewModel = sciCall(storyVC, @selector(currentViewModel));

		if (seenManager && viewModel) {
			SEL setSel = NSSelectorFromString(@"setSeenMediaId:forReelPK:");

			if ([seenManager respondsToSelector:setSel]) {
				id mediaPK = sciCall(media, @selector(pk));
				id reelPK = sciCall(viewModel, NSSelectorFromString(@"reelPK"));
				if (!reelPK) reelPK = sciCall(viewModel, @selector(pk));

				if (mediaPK && reelPK) {
					((void(*)(id, SEL, id, id))objc_msgSend)(seenManager, setSel, mediaPK, reelPK);
				}
			}
		}

		sciSeenBypassActive = NO;

		SCINotifySuccess(SCI_NOTIF_SEEN_STORY, SCILocalized(@"Story marked as seen"), nil);

		if (sender && [SCIUtils getBoolPref:@"advance_on_mark_seen"] && sectionController) {
			__weak __typeof(self) weakSelf = self;
			__block id weakSection = sectionController;

			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				sciAdvanceBypassActive = YES;

				SEL advanceSel = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
				if ([weakSection respondsToSelector:advanceSel]) {
					((void(*)(id, SEL, NSInteger))objc_msgSend)(weakSection, advanceSel, 1);
				}

				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					__strong __typeof(weakSelf) strongSelf = weakSelf;
					UIViewController *vc = strongSelf ? sciFindVC(strongSelf, @"IGStoryViewerViewController") : nil;
					id newSection = vc ? sciFindSectionController(vc) : nil;

					if (newSection) {
						SEL resumeSel = NSSelectorFromString(@"tryResumePlaybackWithReason:");

						if ([newSection respondsToSelector:resumeSel]) {
							((void(*)(id, SEL, NSInteger))objc_msgSend)(newSection, resumeSel, 0);
						}
					}

					sciAdvanceBypassActive = NO;
				});
			});
		}
	} @catch (NSException *exception) {
		sciSeenBypassActive = NO;
		sciAdvanceBypassActive = NO;

		[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"Error: %@"), exception.reason]];
	}
}

%end

// MARK: - Chrome alpha sync (story only)

static void sciSyncStoryButtonsAlpha(UIView *sourceView, CGFloat alpha) {
	Class overlayClass = NSClassFromString(@"IGStoryFullscreenOverlayView");
	if (!overlayClass) return;

	UIView *current = sourceView;

	while (current && current.superview) {
		for (UIView *sibling in current.superview.subviews) {
			if (![sibling isKindOfClass:overlayClass]) continue;

			UIView *seen = [sibling viewWithTag:SCI_STORY_EYE_TAG];
			UIView *action = [sibling viewWithTag:SCI_STORY_ACTION_TAG];
			UIView *audio = [sibling viewWithTag:SCI_STORY_AUDIO_TAG];
			UIView *mentions = [sibling viewWithTag:SCI_STORY_MENTIONS_TAG];

			if (seen) seen.alpha = alpha;
			if (action) action.alpha = alpha;
			if (audio) audio.alpha = alpha;
			if (mentions) mentions.alpha = alpha;
			return;
		}

		current = current.superview;
	}
}

%hook IGStoryFullscreenHeaderView

- (void)setAlpha:(CGFloat)alpha {
	%orig;
	sciSyncStoryButtonsAlpha((UIView *)self, alpha);
}

%end

// MARK: - Mentions refresh broadcast

// Per-overlay refresh + retry-kick across all live story overlays.
// Each overlay does its own per-cell media check, so this lands on the
// correct cells regardless of which is currently visible.
static void sciRefreshMentionsInVisibleOverlays(id storyVC) {
	if (![storyVC isKindOfClass:[UIViewController class]]) return;
	UIView *root = ((UIViewController *)storyVC).view;
	if (!root) return;
	Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
	if (!overlayCls) overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayMetalLayerView");
	if (!overlayCls) return;
	SEL refresh = @selector(sciRefreshStoryMentionsButton);
	SEL kick = @selector(sciKickMentionsRetryChain);
	NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
	while (stack.count) {
		UIView *v = stack.lastObject; [stack removeLastObject];
		if ([v isKindOfClass:overlayCls]) {
			if ([v respondsToSelector:refresh])
				((void(*)(id, SEL))objc_msgSend)(v, refresh);
			if ([v respondsToSelector:kick])
				((void(*)(id, SEL))objc_msgSend)(v, kick);
		}
		for (UIView *sub in v.subviews) [stack addObject:sub];
	}
}

// VC delegate callbacks fire AFTER the story content is loaded and visible —
// the canonical "story is now showing" events when Pando field data is bound.
%hook IGStoryViewerViewController

- (void)fullscreenSectionController:(id)sc didDisplayStoryModel:(id)model {
	%orig;
	if ([SCIUtils getBoolPref:@"story_mentions_button"])
		sciRefreshMentionsInVisibleOverlays(self);
}

- (void)fullscreenSectionController:(id)sc didStartToProgressWithStoryItem:(id)item {
	%orig;
	if ([SCIUtils getBoolPref:@"story_mentions_button"])
		sciRefreshMentionsInVisibleOverlays(self);
}

- (void)fullscreenSectionController:(id)sc didUpdateFromStoryModel:(id)fromModel toStoryModel:(id)toModel storyItem:(id)item {
	%orig;
	if ([SCIUtils getBoolPref:@"story_mentions_button"])
		sciRefreshMentionsInVisibleOverlays(self);
}

%end

%end // StoryOverlayGroup

%ctor {
	if (SCIStoryActionEnabled() ||
		[SCIUtils getBoolPref:@"story_audio_toggle"] ||
		[SCIUtils getBoolPref:@"no_seen_receipt"] ||
		[SCIUtils getBoolPref:@"story_mentions_button"]) {
		%init(StoryOverlayGroup);
	}
}