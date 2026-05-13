// Story overlay buttons — action / audio / eye / mentions.
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

static const NSInteger kStoryMentionsCountTag = 13450;

static char kStoryActionDefaultKey;
static char kStoryReelItemsProviderKey;
static char kStoryMentionsAnchorKey;
static char kStoryMentionsCountKey;
static char kStoryMentionsRetryGenKey;
static char kStoryLastPKKey;
static char kStoryLastExcludedKey;
static char kStoryLastAudioKey;

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

static inline void SCIRemoveStoryButton(UIView *root, NSInteger tag) {
	[[root viewWithTag:tag] removeFromSuperview];
}

static void SCIRemoveAllStoryButtons(UIView *root) {
	SCIRemoveStoryButton(root, SCI_STORY_ACTION_TAG);
	SCIRemoveStoryButton(root, SCI_STORY_EYE_TAG);
	SCIRemoveStoryButton(root, SCI_STORY_AUDIO_TAG);
	SCIRemoveStoryButton(root, SCI_STORY_MENTIONS_TAG);
}

// MARK: - Live overlay table

static NSHashTable<UIView *> *sciLiveStoryOverlays(void) {
	static NSHashTable *table;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		table = [NSHashTable weakObjectsHashTable];
	});
	return table;
}

static void sciRegisterLiveStoryOverlay(UIView *overlay) {
	if (overlay && overlay.window && !sciOverlayIsInDMContext(overlay)) {
		[sciLiveStoryOverlays() addObject:overlay];
	}
}

// MARK: - Story VC helpers

static UIViewController *sciStoryVCForView(UIView *view) {
	UIViewController *vc = sciFindVC(view, @"IGStoryViewerViewController");
	return vc ?: sciActiveStoryViewerVC;
}

static id sciStorySectionController(UIViewController *storyVC) {
	if ([storyVC respondsToSelector:@selector(currentlyDisplayedSectionController)]) {
		return ((id (*)(id, SEL))objc_msgSend)(storyVC, @selector(currentlyDisplayedSectionController));
	}
	return sciFindSectionController(storyVC);
}

static id sciCurrentStoryItemFromVC(UIViewController *storyVC) {
	if ([storyVC respondsToSelector:@selector(currentStoryItem)]) {
		return ((id (*)(id, SEL))objc_msgSend)(storyVC, @selector(currentStoryItem));
	}
	return nil;
}

// MARK: - Playback control

static void sciPauseStoryPlayback(UIView *sourceView) {
	UIViewController *storyVC = sciStoryVCForView(sourceView);
	if ([storyVC respondsToSelector:@selector(pauseWithReason:)]) {
		((void (*)(id, SEL, NSInteger))objc_msgSend)(storyVC, @selector(pauseWithReason:), 10);
	}
}

static void sciResumeStoryPlayback(UIView *sourceView) {
	UIViewController *storyVC = sciStoryVCForView(sourceView);
	if ([storyVC respondsToSelector:@selector(tryResumePlayback)]) {
		((void (*)(id, SEL))objc_msgSend)(storyVC, @selector(tryResumePlayback));
	}
}

static id sciCurrentStoryMedia(UIView *sourceView) {
	UIViewController *storyVC = sciStoryVCForView(sourceView);
	id item = sciCurrentStoryItemFromVC(storyVC);
	if (!item) item = sciGetCurrentStoryItem(sourceView);

	if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) return item;

	id extracted = sciExtractMediaFromItem(item);
	return extracted ?: (id)kCFNull;
}

// Used by SCIMediaActions for "download all".
static NSArray *sciStoryReelItemsForSource(UIView *sourceView) {
	UIViewController *storyVC = sciStoryVCForView(sourceView);
	if (!storyVC) return nil;

	id viewModel = nil;
	if ([storyVC respondsToSelector:@selector(currentViewModel)]) {
		viewModel = ((id (*)(id, SEL))objc_msgSend)(storyVC, @selector(currentViewModel));
	}
	if (!viewModel) return nil;

	for (NSString *selName in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
		SEL sel = NSSelectorFromString(selName);
		if (![viewModel respondsToSelector:sel]) continue;

		@try {
			id value = ((id (*)(id, SEL))objc_msgSend)(viewModel, sel);
			if ([value isKindOfClass:NSArray.class] && [(NSArray *)value count] > 1) return value;
		} @catch (__unused id e) {}
	}

	return nil;
}

static void SCIConfigureStoryActionButton(SCIChromeButton *button) {
	if (!button) return;

	SCIActionMediaProvider provider = ^id (UIView *sourceView) {
		sciPauseStoryPlayback(sourceView);
		return sciCurrentStoryMedia(sourceView);
	};

	[SCIActionButton configureButton:button
							 context:SCIActionContextStories
							 prefKey:@"stories_action_default"
					   mediaProvider:provider];

	objc_setAssociatedObject(button, &kStoryReelItemsProviderKey, ^NSArray *(UIView *sourceView) {
		return sciStoryReelItemsForSource(sourceView);
	}, OBJC_ASSOCIATION_COPY_NONATOMIC);

	__weak SCIChromeButton *weakButton = button;
	objc_setAssociatedObject(button, kSCIDismissKey, ^{
		SCIChromeButton *strongButton = weakButton;
		if (strongButton) sciResumeStoryPlayback(strongButton);
	}, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

// MARK: - Mentions counter

static void sciApplyMentionsCounter(SCIChromeButton *button, NSInteger count) {
	if (!button) return;

	UILabel *label = (UILabel *)[button viewWithTag:kStoryMentionsCountTag];

	if (![SCIUtils getBoolPref:@"story_mentions_counter"] || count <= 0) {
		[label removeFromSuperview];
		objc_setAssociatedObject(button, &kStoryMentionsCountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	NSNumber *old = objc_getAssociatedObject(button, &kStoryMentionsCountKey);
	if (label && old && old.integerValue == count) return;

	if (!label) {
		label = [UILabel new];
		label.tag = kStoryMentionsCountTag;
		label.translatesAutoresizingMaskIntoConstraints = NO;
		label.textAlignment = NSTextAlignmentCenter;
		label.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
		label.textColor = UIColor.whiteColor;
		label.backgroundColor = UIColor.systemRedColor;
		label.layer.cornerRadius = 8.0;
		label.layer.masksToBounds = YES;
		label.adjustsFontSizeToFitWidth = YES;
		label.minimumScaleFactor = 0.7;
		label.userInteractionEnabled = NO;

		[button addSubview:label];

		[NSLayoutConstraint activateConstraints:@[
			[label.topAnchor constraintEqualToAnchor:button.topAnchor constant:-3.0],
			[label.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:3.0],
			[label.widthAnchor constraintGreaterThanOrEqualToConstant:16.0],
			[label.heightAnchor constraintEqualToConstant:16.0]
		]];
	}

	label.text = count > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)count];
	objc_setAssociatedObject(button, &kStoryMentionsCountKey, @(count), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// MARK: - Overlay hook

%group StoryOverlayGroup

%hook IGStoryFullscreenOverlayView

- (void)didMoveToWindow {
	%orig;

	if (!self.window) return;

	if (sciOverlayIsInDMContext(self)) {
		SCIRemoveAllStoryButtons(self);
		return;
	}

	sciRegisterLiveStoryOverlay((UIView *)self);

	dispatch_async(dispatch_get_main_queue(), ^{
		if (!self.window || sciOverlayIsInDMContext(self)) return;
		((void (*)(id, SEL))objc_msgSend)(self, @selector(sciInstallStoryOverlayButtons));
	});
}

- (void)didMoveToSuperview {
	%orig;

	if (!self.superview) return;

	if (sciOverlayIsInDMContext(self)) {
		SCIRemoveAllStoryButtons(self);
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		if (!self.superview || sciOverlayIsInDMContext(self)) return;
		((void (*)(id, SEL))objc_msgSend)(self, @selector(sciInstallStoryOverlayButtons));
	});
}

- (void)prepareForReuse {
	%orig;

	SCIRemoveAllStoryButtons(self);

	objc_setAssociatedObject(self, &kStoryMentionsRetryGenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastExcludedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastAudioKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dealloc {
	SCIRemoveAllStoryButtons(self);
	%orig;
}

%new
- (void)sciInstallStoryOverlayButtons {
	if (!self.superview || sciOverlayIsInDMContext(self)) return;

	// --- Action button ---
	SCIChromeButton *action = (SCIChromeButton *)[self viewWithTag:SCI_STORY_ACTION_TAG];

	if (!SCIStoryActionEnabled()) {
		if (action) {
			SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG);
			SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
			SCIRemoveStoryButton(self, SCI_STORY_MENTIONS_TAG);
		}
	} else {
		NSString *currentAction = SCIStoryDefaultAction() ?: @"";
		NSString *oldAction = objc_getAssociatedObject(action, &kStoryActionDefaultKey);

		if (![action isKindOfClass:SCIChromeButton.class] || (oldAction && ![oldAction isEqualToString:currentAction])) {
			SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG);
			SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
			SCIRemoveStoryButton(self, SCI_STORY_MENTIONS_TAG);

			action = SCIStoryButton(@"", 18.0, 36.0, SCI_STORY_ACTION_TAG);
			[self addSubview:action];

			[NSLayoutConstraint activateConstraints:@[
				[action.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
				[action.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
				[action.widthAnchor constraintEqualToConstant:36.0],
				[action.heightAnchor constraintEqualToConstant:36.0]
			]];

			[SCIActionIcon attachAutoUpdate:action pointSize:18.0 style:SCIActionIconStylePlain];
			SCIConfigureStoryActionButton(action);
			objc_setAssociatedObject(action, &kStoryActionDefaultKey, currentAction, OBJC_ASSOCIATION_COPY_NONATOMIC);
		}
	}

	// --- Audio toggle ---
	SCIChromeButton *audio = (SCIChromeButton *)[self viewWithTag:SCI_STORY_AUDIO_TAG];

	if (![SCIUtils getBoolPref:@"story_audio_toggle"]) {
		if (audio) SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG);
	} else if (![audio isKindOfClass:SCIChromeButton.class]) {
		sciInitStoryAudioState();

		audio = SCIStoryButton(sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash", 14.0, 28.0, SCI_STORY_AUDIO_TAG);
		[audio addTarget:self action:@selector(sciStoryAudioToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self addSubview:audio];

		[NSLayoutConstraint activateConstraints:@[
			[audio.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
			[audio.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
			[audio.widthAnchor constraintEqualToConstant:28.0],
			[audio.heightAnchor constraintEqualToConstant:28.0]
		]];
	}

	// --- Eye / mark-seen ---
	if ([SCIUtils getBoolPref:@"no_seen_receipt"]) {
		((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));
	} else {
		SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
	}

	// --- Mentions ---
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButton));
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciKickMentionsRetryChain));
}

// MARK: - Action button refresh

%new
- (void)sciRefreshStoryActionButton {
	SCIChromeButton *button = (SCIChromeButton *)[self viewWithTag:SCI_STORY_ACTION_TAG];

	if (!SCIStoryActionEnabled()) {
		if (button) {
			SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG);
			SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
			SCIRemoveStoryButton(self, SCI_STORY_MENTIONS_TAG);
		}
		return;
	}

	if (![button isKindOfClass:SCIChromeButton.class]) {
		((void (*)(id, SEL))objc_msgSend)(self, @selector(sciInstallStoryOverlayButtons));
		return;
	}

	NSString *currentAction = SCIStoryDefaultAction() ?: @"";
	NSString *oldAction = objc_getAssociatedObject(button, &kStoryActionDefaultKey);

	if (oldAction && [oldAction isEqualToString:currentAction]) return;

	SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG);
	SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
	SCIRemoveStoryButton(self, SCI_STORY_MENTIONS_TAG);

	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciInstallStoryOverlayButtons));
}

// MARK: - Audio toggle

%new
- (void)sciStoryAudioToggleTapped:(SCIChromeButton *)sender {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	sciToggleStoryAudio();
	sender.symbolName = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
	objc_setAssociatedObject(self, &kStoryLastAudioKey, @(sciIsStoryAudioEnabled()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)sciRefreshStoryAudioButton {
	if (![SCIUtils getBoolPref:@"story_audio_toggle"]) {
		SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG);
		return;
	}

	SCIChromeButton *button = (SCIChromeButton *)[self viewWithTag:SCI_STORY_AUDIO_TAG];
	if ([button isKindOfClass:SCIChromeButton.class]) {
		button.symbolName = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
	}
}

// MARK: - Seen eye button

%new
- (void)sciRefreshSeenButton {
	if (![SCIUtils getBoolPref:@"no_seen_receipt"]) {
		SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
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
		[existing setIconResource:symbol pointSize:18.0];
		existing.iconTint = tint;
		return;
	}

	SCIChromeButton *button = SCIStoryButton(@"", 18.0, 36.0, SCI_STORY_EYE_TAG);
	[button setIconResource:symbol pointSize:18.0];
	button.iconTint = tint;

	[button addTarget:self action:@selector(sciStorySeenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
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

%new
- (void)sciRefreshStoryMentionsButton {
	BOOL hasContent = [SCIUtils getBoolPref:@"story_mentions_button"] && sciStoryHasMentionsOrShares(self);

	SCIChromeButton *existing = (SCIChromeButton *)[self viewWithTag:SCI_STORY_MENTIONS_TAG];
	if (![existing isKindOfClass:SCIChromeButton.class]) existing = nil;

	if (!hasContent) {
		if (existing) [existing removeFromSuperview];
		return;
	}

	if (self.window && self.bounds.size.width < self.window.bounds.size.width * 0.5) {
		if (existing) [existing removeFromSuperview];
		return;
	}

	BOOL hasEye = [self viewWithTag:SCI_STORY_EYE_TAG] != nil;
	BOOL hasAction = [self viewWithTag:SCI_STORY_ACTION_TAG] != nil;
	NSInteger neighbours = (hasEye ? 1 : 0) | (hasAction ? 2 : 0);
	NSInteger count = [SCIUtils getBoolPref:@"story_mentions_counter"] ? sciStoryMentionsCount(self) : 0;

	NSNumber *prevAnchor = objc_getAssociatedObject(existing, &kStoryMentionsAnchorKey);
	NSNumber *prevCount = objc_getAssociatedObject(existing, &kStoryMentionsCountKey);

	if (existing && prevAnchor && prevAnchor.integerValue == neighbours) {
		if (prevCount.integerValue == count) return;
		sciApplyMentionsCounter(existing, count);
		return;
	}

	if (existing) [existing removeFromSuperview];

	SCIChromeButton *button = SCIStoryButton(@"at", 18.0, 36.0, SCI_STORY_MENTIONS_TAG);
	[button addTarget:self action:@selector(sciStoryMentionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:button];

	objc_setAssociatedObject(button, &kStoryMentionsAnchorKey, @(neighbours), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	CGFloat trailingOffset = -12.0;
	if (hasAction) trailingOffset -= 46.0;
	if (hasEye) trailingOffset -= 46.0;

	[NSLayoutConstraint activateConstraints:@[
		[button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
		[button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:trailingOffset],
		[button.widthAnchor constraintEqualToConstant:36.0],
		[button.heightAnchor constraintEqualToConstant:36.0]
	]];

	sciApplyMentionsCounter(button, count);
}

%new
- (void)sciKickMentionsRetryChain {
	if (![SCIUtils getBoolPref:@"story_mentions_button"]) return;
	if ([self viewWithTag:SCI_STORY_MENTIONS_TAG]) return;

	NSInteger gen = [objc_getAssociatedObject(self, &kStoryMentionsRetryGenKey) integerValue] + 1;
	objc_setAssociatedObject(self, &kStoryMentionsRetryGenKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	((void (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(self, @selector(sciScheduleMentionsRetryGeneration:remaining:), gen, 6);
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

		((void (*)(id, SEL))objc_msgSend)(strongSelf, @selector(sciRefreshStoryMentionsButton));
		if ([strongSelf viewWithTag:SCI_STORY_MENTIONS_TAG]) return;

		((void (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(strongSelf, @selector(sciScheduleMentionsRetryGeneration:remaining:), gen, remaining - 1);
	});
}

%new
- (void)sciStoryMentionsButtonTapped:(SCIChromeButton *)sender {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	UIViewController *storyVC = sciStoryVCForView(self);
	if (!storyVC) return;

	sciPauseStoryPlayback(self);
	sciShowStoryMentions(storyVC, self);
}

// MARK: - Owner / audio / action refresh on layout

- (void)layoutSubviews {
	%orig;

	if (sciOverlayIsInDMContext(self)) {
		SCIRemoveAllStoryButtons(self);
		return;
	}

	sciRegisterLiveStoryOverlay((UIView *)self);

	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryActionButton));
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButton));

	if (![SCIUtils getBoolPref:@"story_audio_toggle"]) {
		SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG);
	} else {
		SCIChromeButton *audioButton = (SCIChromeButton *)[self viewWithTag:SCI_STORY_AUDIO_TAG];

		if ([audioButton isKindOfClass:SCIChromeButton.class]) {
			BOOL audioOn = sciIsStoryAudioEnabled();
			NSNumber *previousAudio = objc_getAssociatedObject(self, &kStoryLastAudioKey);

			if (!previousAudio || previousAudio.boolValue != audioOn) {
				objc_setAssociatedObject(self, &kStoryLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryAudioButton));
			}
		}
	}

	if (![SCIUtils getBoolPref:@"no_seen_receipt"]) {
		SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
		return;
	}

	NSDictionary *info = sciOwnerInfoForView(self);
	NSString *pk = info[@"pk"] ?: @"";
	BOOL excluded = pk.length && [SCIExcludedStoryUsers isUserPKExcluded:pk];

	NSString *previousPK = objc_getAssociatedObject(self, &kStoryLastPKKey);
	NSNumber *previousExcluded = objc_getAssociatedObject(self, &kStoryLastExcludedKey);
	BOOL changed = !previousPK || !previousExcluded || ![pk isEqualToString:previousPK] || previousExcluded.boolValue != excluded;

	if (!changed) return;

	objc_setAssociatedObject(self, &kStoryLastPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastExcludedKey, @(excluded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));
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

	((void (*)(id, SEL, id))objc_msgSend)(self, @selector(sciStoryMarkSeenTapped:), sender);
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

		NSMutableArray<UIMenuElement *> *items = NSMutableArray.array;

		[items addObject:[UIAction actionWithTitle:SCILocalized(@"Mark seen") image:[SCIIcon imageNamed:@"eye"] identifier:nil handler:^(__unused UIAction *action) {
			((void (*)(id, SEL, id))objc_msgSend)(strongSelf, @selector(sciStoryMarkSeenTapped:), nil);
		}]];

		if (pk) {
			NSString *title = inList
				? (blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude story seen"))
				: (blockSelected ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude story seen"));

			UIAction *exclude = [UIAction actionWithTitle:title image:[SCIIcon imageNamed:(inList ? @"minus.circle" : @"eye.slash")] identifier:nil handler:^(__unused UIAction *action) {
				if (inList) {
					[SCIExcludedStoryUsers removePK:pk];
					SCINotifySuccess(blockSelected ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY,
									  blockSelected ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded"),
									  nil);

					if (blockSelected) sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
				} else {
					[SCIExcludedStoryUsers addOrUpdateEntry:@{ @"pk": pk, @"username": username, @"fullName": fullName }];
					SCINotifySuccess(blockSelected ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY,
									  blockSelected ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded"),
									  nil);

					if (!blockSelected) sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
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
		UIViewController *storyVC = sciStoryVCForView(self);

		if (!storyVC) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"VC not found")];
			return;
		}

		id sectionController = sciStorySectionController(storyVC);
		id storyItem = sciCurrentStoryItemFromVC(storyVC);
		if (!storyItem && sectionController) storyItem = sciCall(sectionController, NSSelectorFromString(@"currentStoryItem"));
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
			((void (*)(id, SEL, id, id))objc_msgSend)(storyVC, delegateSel, sectionController, media);
		}

		if (sectionController) {
			SEL markSel = NSSelectorFromString(@"markItemAsSeen:");

			if ([sectionController respondsToSelector:markSel]) {
				((SCIMsgSend1)objc_msgSend)(sectionController, markSel, media);
			}
		}

		id seenManager = nil;
		if ([storyVC respondsToSelector:@selector(viewingSessionSeenStateManager)]) {
			seenManager = ((id (*)(id, SEL))objc_msgSend)(storyVC, @selector(viewingSessionSeenStateManager));
		}

		id viewModel = nil;
		if ([storyVC respondsToSelector:@selector(currentViewModel)]) {
			viewModel = ((id (*)(id, SEL))objc_msgSend)(storyVC, @selector(currentViewModel));
		}

		if (seenManager && viewModel) {
			SEL setSel = NSSelectorFromString(@"setSeenMediaId:forReelPK:");

			if ([seenManager respondsToSelector:setSel]) {
				id mediaPK = sciCall(media, @selector(pk));
				id reelPK = sciCall(viewModel, NSSelectorFromString(@"reelPK"));
				if (!reelPK) reelPK = sciCall(viewModel, @selector(pk));

				if (mediaPK && reelPK) {
					((void (*)(id, SEL, id, id))objc_msgSend)(seenManager, setSel, mediaPK, reelPK);
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
					((void (*)(id, SEL, NSInteger))objc_msgSend)(weakSection, advanceSel, 1);
				}

				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					__strong __typeof(weakSelf) strongSelf = weakSelf;
					UIViewController *vc = strongSelf ? sciStoryVCForView(strongSelf) : nil;

					if ([vc respondsToSelector:@selector(tryResumePlayback)]) {
						((void (*)(id, SEL))objc_msgSend)(vc, @selector(tryResumePlayback));
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

// MARK: - Chrome alpha sync

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

static void sciRefreshMentionsInVisibleOverlays(id storyVC) {
	if (![SCIUtils getBoolPref:@"story_mentions_button"]) return;

	for (UIView *overlay in sciLiveStoryOverlays().allObjects) {
		if (!overlay.window || sciOverlayIsInDMContext(overlay)) continue;

		if ([overlay respondsToSelector:@selector(sciRefreshStoryMentionsButton)]) {
			((void (*)(id, SEL))objc_msgSend)(overlay, @selector(sciRefreshStoryMentionsButton));
		}

		if ([overlay respondsToSelector:@selector(sciKickMentionsRetryChain)]) {
			((void (*)(id, SEL))objc_msgSend)(overlay, @selector(sciKickMentionsRetryChain));
		}
	}
}

%hook IGStoryViewerViewController

- (void)fullscreenSectionController:(id)sc didDisplayStoryModel:(id)model {
	%orig;
	sciRefreshMentionsInVisibleOverlays(self);
}

- (void)fullscreenSectionController:(id)sc didStartToProgressWithStoryItem:(id)item {
	%orig;
	sciRefreshMentionsInVisibleOverlays(self);
}

- (void)fullscreenSectionController:(id)sc didUpdateFromStoryModel:(id)fromModel toStoryModel:(id)toModel storyItem:(id)item {
	%orig;
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