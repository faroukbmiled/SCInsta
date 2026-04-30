#import <substrate.h>
#import "InstagramHeaders.h"
#import "Tweak.h"
#import "Utils.h"
#import "Features/General/SCICacheManager.h"
#import "Features/General/SCIChangelog.h"
#include "../modules/fishhook/fishhook.h"

#define SCI_PREF(key) [SCIUtils getBoolPref:key]
#define SCI_SCREENSHOT_BLOCKED SCI_PREF(@"remove_screenshot_alert")
#define VOID_HANDLESCREENSHOT(orig) do { if (!SCI_SCREENSHOT_BLOCKED) { orig; } } while (0)
#define NONVOID_HANDLESCREENSHOT(orig) do { if (SCI_SCREENSHOT_BLOCKED) return nil; return orig; } while (0)
#define SCI_LG_BUTTONS SCI_PREF(@"liquid_glass_buttons")
#define SCI_LG_SURFACES SCI_PREF(@"liquid_glass_surfaces")

NSString *SCIVersionString = @"v1.2.2";
BOOL dmVisualMsgsViewedButtonEnabled = false;

static BOOL sciShouldHideMetaAIRecipient(id obj) {
	return SCI_PREF(@"hide_meta_ai") && ([[obj recipient] threadName] && [[[obj recipient] threadName] isEqualToString:@"Meta AI"]);
}

static BOOL sciStringEquals(NSString *a, NSString *b) {
	return a && [a isEqualToString:b];
}

static NSString *sciSafeValue(id obj, NSString *key) {
	@try { return [obj valueForKey:key]; } @catch (__unused id e) { return nil; }
}

%hook IGInstagramAppDelegate

- (_Bool)application:(UIApplication *)application willFinishLaunchingWithOptions:(id)arg2 {
	NSDictionary *sciDefaults = @{
		@"hide_ads": @YES, @"copy_description": @YES, @"profile_copy_button": @YES, @"detailed_color_picker": @YES,
		@"remove_screenshot_alert": @YES, @"voice_call_confirm": @NO, @"video_call_confirm": @NO, @"keep_deleted_message": @NO,
		@"hide_suggested_stories": @NO, @"profile_analyzer_accumulate": @NO, @"story_tray_actions": @NO,
		@"zoom_profile_photo": @NO, @"follow_indicator": @NO, @"profile_note_copy": @NO,
		@"disable_disappearing_mode_swipe": @NO, @"hide_voice_call_button": @NO, @"hide_video_call_button": @NO,
		@"fake_location_enabled": @NO, @"show_fake_location_map_button": @NO, @"fake_location_lat": @(48.8584),
		@"fake_location_lon": @(2.2945), @"fake_location_name": @"Eiffel Tower", @"fake_location_presets": @[],
		@"messages_only": @NO, @"messages_only_hide_tabbar": @NO, @"fake_follower_count": @NO, @"fake_following_count": @NO,
		@"fake_post_count": @NO, @"fake_verified": @NO, @"launch_tab": @"default", @"save_profile": @YES,
		@"feed_media_zoom": @NO, @"disable_bg_refresh": @NO, @"disable_home_refresh": @NO, @"disable_home_scroll": @NO,
		@"disable_reels_tab_refresh": @NO, @"dm_full_last_active": @NO, @"send_file": @NO, @"note_actions": @NO,
		@"note_copy_on_hold": @NO, @"feed_date_format": @"default", @"date_fmt_mixed": @YES,
		@"date_fmt_notes_comments_stories": @NO, @"date_fmt_dms": @NO, @"feed_action_button": @YES,
		@"feed_action_default": @"menu", @"reels_action_button": @YES, @"reels_action_default": @"menu",
		@"stories_action_button": @YES, @"stories_action_default": @"menu", @"dm_visual_action_button": @YES,
		@"dm_visual_action_default": @"menu", @"dm_visual_seen_button": @YES, @"dm_visual_audio_toggle": @NO,
		@"dw_legacy_gesture": @NO, @"dw_confirm": @NO, @"enhance_download_quality": @YES,
		@"default_video_quality": @"always_ask", @"default_photo_quality": @"high", @"ffmpeg_encoding_speed": @"ultrafast",
		@"unfollow_confirm": @NO, @"sticker_interact_confirm": @NO, @"sticker_interact_confirm_highlights": @NO,
		@"dw_save_action": @"share", @"dw_finger_count": @(3), @"dw_finger_duration": @(0.5),
		@"reels_tap_control": @"default", @"reels_photo_tap_mute": @NO, @"nav_icon_ordering": @"default",
		@"swipe_nav_tabs": @"default", @"enable_notes_customization": @YES, @"custom_note_themes": @YES,
		@"disable_auto_unmuting_reels": @NO, @"auto_scroll_reels_mode": @"off", @"settings_shortcut": @YES,
		@"doom_scrolling_reel_count": @(1), @"keep_seen_visual_local": @NO, @"send_audio_as_file": @YES,
		@"download_audio_message": @NO, @"save_to_ryukgram_album": @NO, @"unlock_password_reels": @YES,
		@"seen_mode": @"button", @"seen_auto_on_interact": @NO, @"seen_auto_on_typing": @NO,
		@"seen_on_story_like": @NO, @"seen_on_story_reply": @NO, @"advance_on_story_reply": @NO,
		@"advance_on_mark_seen": @NO, @"advance_on_story_like": @NO, @"indicate_unsent_messages": @NO,
		@"unsent_message_toast": @NO, @"warn_refresh_clears_preserved": @NO, @"enable_chat_exclusions": @YES,
		@"chat_blocking_mode": @"block_all", @"exclusions_default_keep_deleted": @NO, @"chat_quick_list_button": @YES,
		@"enable_story_user_exclusions": @YES, @"story_blocking_mode": @"block_all", @"story_excluded_show_unexclude_eye": @YES,
		@"story_seen_mode": @"button", @"story_audio_toggle": @NO, @"view_story_mentions": @YES,
		@"stories_show_quiz_answer": @NO, @"stories_show_poll_votes_count": @NO, @"reels_show_quiz_answer": @NO,
		@"reels_show_poll_votes_count": @NO, @"force_enable_quiz_sticker": @NO, @"settings_pause_playback": @YES,
		@"embed_links": @NO, @"embed_link_domain": @"kkinstagram.com", @"strip_tracking_params": @NO,
		@"download_highlight_cover": @YES, @"open_links_external": @NO, @"strip_browser_tracking": @NO,
		@"hide_feed_repost": @NO, @"copy_comment": @YES, @"download_gif_comment": @YES,
		@"cache_auto_clear_mode": @"off", @"cache_auto_check_size": @YES, @"sci_changelog_force_show": @NO,
		@"live_anonymous_view": @NO, @"live_hide_comments": @NO, @"hide_ui_on_capture": @NO,
		@"paste_link_from_search": @NO, @"sci_language": @"system", @"theme_force_dark": @NO,
		@"theme_full_oled": @NO, @"theme_oled_chat": @NO, @"theme_keyboard": @"off",
		@"igt_homecoming": @NO, @"igt_quicksnap": @NO, @"igt_prism": @NO, @"igt_directnotes_friendmap": @NO,
		@"igt_directnotes_audio_reply": @NO, @"igt_directnotes_avatar_reply": @NO,
		@"igt_directnotes_gifs_reply": @NO, @"igt_directnotes_photo_reply": @NO, @"sci_exp_warning_seen": @NO
	};

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults registerDefaults:sciDefaults];
	[SCIUtils setSciRegisteredDefaults:sciDefaults];
	[defaults setBool:SCI_LG_BUTTONS forKey:@"instagram.override.project.lucent.navigation"];
	return %orig;
}

- (_Bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)arg2 {
	BOOL result = %orig;
	BOOL openOnLaunch = SCI_PREF(@"tweak_settings_app_launch");
	double delay = openOnLaunch ? 0.0 : 5.0;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		BOOL firstRun = ![[[NSUserDefaults standardUserDefaults] objectForKey:@"SCInstaFirstRun"] isEqualToString:SCIVersionString];
		if (firstRun || SCI_PREF(@"tweak_settings_app_launch")) {
			NSLog(@"[SCInsta] First run — showing settings modal");
			[SCIUtils showSettingsVC:[self window]];
		}
	});

	if (SCI_PREF(@"flex_app_launch")) [[objc_getClass("FLEXManager") sharedManager] showExplorer];
	return result;
}

- (void)applicationDidBecomeActive:(id)arg1 {
	%orig;
	if (SCI_PREF(@"flex_app_start")) [[objc_getClass("FLEXManager") sharedManager] showExplorer];
}

- (void)applicationDidEnterBackground:(id)arg1 {
	%orig;
	[SCICacheManager runAutoClearIfDue];
}

%end

%hook IGTabBarController
- (void)viewDidAppear:(BOOL)animated {
	%orig;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ [SCIChangelog presentIfNewFromWindow:self.view.window]; });
}
%end

%hook IGDSLauncherConfig
- (_Bool)isLiquidGlassInAppNotificationEnabled { return [SCIUtils liquidGlassEnabledBool:%orig]; }
- (_Bool)isLiquidGlassContextMenuEnabled { return [SCIUtils liquidGlassEnabledBool:%orig]; }
- (_Bool)isLiquidGlassToastEnabled { return [SCIUtils liquidGlassEnabledBool:%orig]; }
- (_Bool)isLiquidGlassToastPeekEnabled { return [SCIUtils liquidGlassEnabledBool:%orig]; }
- (_Bool)isLiquidGlassAlertDialogEnabled { return [SCIUtils liquidGlassEnabledBool:%orig]; }
- (_Bool)isLiquidGlassIconBarButtonEnabled { return [SCIUtils liquidGlassEnabledBool:%orig]; }
%end

%hook IGWindow
- (void)showDebugMenu {}
%end

%hook IGBugReportUploader
- (id)initWithNetworker:(id)arg1 pandoGraphQLService:(id)arg2 analyticsLogger:(id)arg3 userDefaults:(id)arg4 launcherSetProvider:(id)arg5 shouldPersistLastBugReportId:(id)arg6 {
	return nil;
}
%end

%hook IGStoryViewerContainerView
- (void)setShouldBlockScreenshot:(BOOL)arg1 viewModel:(id)arg2 { VOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGDirectVisualMessageViewerSession
- (id)visualMessageViewerController:(id)arg1 didDetectScreenshotForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 { NONVOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGDirectVisualMessageReplayService
- (id)visualMessageViewerController:(id)arg1 didDetectScreenshotForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 { NONVOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGDirectVisualMessageReportService
- (id)visualMessageViewerController:(id)arg1 didDetectScreenshotForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 { NONVOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGDirectVisualMessageScreenshotSafetyLogger
- (id)initWithUserSession:(id)arg1 entryPoint:(NSInteger)arg2 {
	if (!SCI_SCREENSHOT_BLOCKED) return %orig;
	NSLog(@"[SCInsta] Disable visual message screenshot safety logger");
	return nil;
}
%end

%hook IGScreenshotObserver
- (id)initForController:(id)arg1 { NONVOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGScreenshotObserverDelegate
- (void)screenshotObserverDidSeeScreenshotTaken:(id)arg1 { VOID_HANDLESCREENSHOT(%orig); }
- (void)screenshotObserverDidSeeActiveScreenCapture:(id)arg1 event:(NSInteger)arg2 { VOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGDirectMediaViewerViewController
- (void)screenshotObserverDidSeeScreenshotTaken:(id)arg1 { VOID_HANDLESCREENSHOT(%orig); }
- (void)screenshotObserverDidSeeActiveScreenCapture:(id)arg1 event:(NSInteger)arg2 { VOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGStoryViewerViewController
- (void)screenshotObserverDidSeeScreenshotTaken:(id)arg1 { VOID_HANDLESCREENSHOT(%orig); }
- (void)screenshotObserverDidSeeActiveScreenCapture:(id)arg1 event:(NSInteger)arg2 { VOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGSundialFeedViewController
- (void)screenshotObserverDidSeeScreenshotTaken:(id)arg1 { VOID_HANDLESCREENSHOT(%orig); }
- (void)screenshotObserverDidSeeActiveScreenCapture:(id)arg1 event:(NSInteger)arg2 { VOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGDirectVisualMessageViewerController
- (void)screenshotObserverDidSeeScreenshotTaken:(id)arg1 { VOID_HANDLESCREENSHOT(%orig); }
- (void)screenshotObserverDidSeeActiveScreenCapture:(id)arg1 event:(NSInteger)arg2 { VOID_HANDLESCREENSHOT(%orig); }
%end

%hook IGDirectInboxSearchListAdapterDataSource
- (id)objectsForListAdapter:(id)arg1 {
	NSArray *items = %orig();
	BOOL hideMeta = SCI_PREF(@"hide_meta_ai"), hideChats = SCI_PREF(@"no_suggested_chats");
	if (!hideMeta && !hideChats) return items;

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
	for (id obj in items) {
		BOOL hide = NO;

		if ([obj isKindOfClass:%c(IGLabelItemViewModel)]) {
			NSString *uid = sciSafeValue(obj, @"uniqueIdentifier");
			NSString *title = sciSafeValue(obj, @"labelTitle");
			hide = (hideChats && sciStringEquals(uid, @"channels")) || (hideMeta && (sciStringEquals(title, @"Ask Meta AI") || sciStringEquals(title, @"AI")));
		}
		else if ([obj isKindOfClass:%c(IGDirectInboxSearchAIAgentsPillsSectionViewModel)] || [obj isKindOfClass:%c(IGDirectInboxSearchAIAgentsSuggestedPromptViewModel)] || [obj isKindOfClass:%c(IGDirectInboxSearchAIAgentsSuggestedPromptLoggingViewModel)]) {
			hide = hideMeta;
		}
		else if ([obj isKindOfClass:%c(IGDirectRecipientCellViewModel)]) {
			hide = (hideChats && [[obj recipient] isBroadcastChannel]) || (hideMeta && (([obj sectionType] == 20) || ([obj sectionType] == 18) || sciStringEquals([[obj recipient] threadName], @"Meta AI")));
		}

		if (!hide) [out addObject:obj];
	}

	return out.copy;
}
%end

%hook IGDirectThreadCreationViewController
- (id)objectsForListAdapter:(id)arg1 {
	NSArray *items = %orig();
	BOOL hideMeta = SCI_PREF(@"hide_meta_ai"), hideUsers = SCI_PREF(@"no_suggested_users");
	if (!hideMeta && !hideUsers) return items;

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
	for (id obj in items) {
		BOOL hide = NO;

		if (hideMeta && [obj isKindOfClass:%c(IGDirectCreateChatCellViewModel)]) hide = sciStringEquals(sciSafeValue(obj, @"title"), @"AI chats");
		else if (hideMeta && [obj isKindOfClass:%c(IGDirectRecipientCellViewModel)]) hide = sciStringEquals([[obj recipient] threadName], @"Meta AI");
		else if (hideUsers && [obj isKindOfClass:%c(IGContactInvitesSearchUpsellViewModel)]) hide = YES;

		if (!hide) [out addObject:obj];
	}

	return out.copy;
}
%end

%hook IGDirectInboxListAdapterDataSource
- (id)objectsForListAdapter:(id)arg1 {
	NSArray *items = %orig();
	BOOL hideUsers = SCI_PREF(@"no_suggested_users"), hideNotes = SCI_PREF(@"hide_notes_tray");
	if (!hideUsers && !hideNotes) return items;

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
	for (id obj in items) {
		BOOL hide = NO;

		if ([obj isKindOfClass:%c(IGDirectInboxHeaderCellViewModel)]) {
			NSString *title = [obj title];
			hide = hideUsers && (sciStringEquals(title, @"Suggestions") || [title hasPrefix:@"Accounts to"]);
		}
		else if ([obj isKindOfClass:%c(IGDirectInboxSuggestedThreadCellViewModel)]) hide = hideUsers;
		else if ([obj isKindOfClass:%c(IGDiscoverPeopleItemConfiguration)] || [obj isKindOfClass:%c(IGDiscoverPeopleConnectionItemConfiguration)]) hide = hideUsers;
		else if ([obj isKindOfClass:%c(IGDirectNotesTrayRowViewModel)]) hide = hideNotes;

		if (!hide) [out addObject:obj];
	}

	return out.copy;
}
%end

%hook IGSearchListKitDataSource
- (id)objectsForListAdapter:(id)arg1 {
	NSArray *items = %orig();
	BOOL hideMeta = SCI_PREF(@"hide_meta_ai"), hideUsers = SCI_PREF(@"no_suggested_users");
	if (!hideMeta && !hideUsers) return items;

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
	for (id obj in items) {
		BOOL hide = NO;

		if (hideMeta) {
			if ([obj isKindOfClass:%c(IGLabelItemViewModel)]) hide = sciStringEquals(sciSafeValue(obj, @"labelTitle"), @"Ask Meta AI");
			else if ([obj isKindOfClass:%c(IGSearchNullStateUpsellViewModel)] || [obj isKindOfClass:%c(IGSearchResultNestedGroupViewModel)]) hide = YES;
			else if ([obj isKindOfClass:%c(IGSearchResultViewModel)]) hide = ([obj itemType] == 6) || sciStringEquals([[obj title] string], @"meta.ai");
		}

		if (!hide && hideUsers) {
			if ([obj isKindOfClass:%c(IGLabelItemViewModel)]) hide = sciStringEquals(sciSafeValue(obj, @"labelTitle"), @"Suggested for you");
			else if ([obj isKindOfClass:%c(IGDiscoverPeopleItemConfiguration)]) hide = YES;
			else if ([obj isKindOfClass:%c(IGSeeAllItemConfiguration)] && ((IGSeeAllItemConfiguration *)obj).destination == 4) hide = YES;
		}

		if (!hide) [out addObject:obj];
	}

	return out.copy;
}
%end

%hook IGMainStoryTrayDataSource
- (id)allItemsForTrayUsingCachedValue:(BOOL)cached {
	NSArray *items = %orig(cached);
	BOOL hideUsers = SCI_PREF(@"no_suggested_users"), hideAds = SCI_PREF(@"hide_ads");
	if (!hideUsers && !hideAds) return items;

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
	for (IGStoryTrayViewModel *obj in items) {
		BOOL hide = NO;

		if ([obj isKindOfClass:%c(IGStoryTrayViewModel)]) {
			if (hideUsers) {
				NSNumber *type = [obj valueForKey:@"type"];
				hide = [type isEqual:@(8)] || [type isEqual:@(9)];
			}

			if (!hide && hideAds) hide = obj.isUnseenNux || [obj.pk isEqualToString:@"3538572169"];
		}

		if (!hide) [out addObject:obj];
	}

	return out.copy;
}
%end

%hook IGStoryTraySectionController
- (void)storyTrayControllerShowSUPOGEducationBump {
	if (!SCI_PREF(@"no_suggested_users")) %orig;
}
%end

%hook IGDSMenu
- (id)initWithMenuItems:(NSArray<IGDSMenuItem *> *)items edr:(BOOL)edr headerLabelText:(id)headerLabelText {
	BOOL hideMeta = SCI_PREF(@"hide_meta_ai");
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];

	for (id obj in items) {
		NSString *title = sciSafeValue(obj, @"title");
		BOOL hide = hideMeta && (sciStringEquals(title, @"AI images") || sciStringEquals(title, @"Meta AI"));
		if (!hide) [out addObject:obj];
	}

	extern NSArray *sciMaybeAppendStoryExcludeMenuItem(NSArray *);
	extern NSArray *sciMaybeAppendStoryAudioMenuItem(NSArray *);
	extern NSArray *sciMaybeAppendStoryMentionsMenuItem(NSArray *);

	NSArray *finalItems = sciMaybeAppendStoryExcludeMenuItem(out.copy);
	finalItems = sciMaybeAppendStoryAudioMenuItem(finalItems);
	finalItems = sciMaybeAppendStoryMentionsMenuItem(finalItems);
	return %orig(finalItems, edr, headerLabelText);
}
%end

%hook IGFeedItemUFICell
- (void)UFIButtonBarDidTapOnLike:(id)arg1 {
	if (!SCI_PREF(@"like_confirm")) return %orig;
	NSLog(@"[SCInsta] Confirm post like triggered");
	[SCIUtils showConfirmation:^{ %orig; }];
}

- (void)UFIButtonBarDidTapOnRepost:(id)arg1 {
	if (!SCI_PREF(@"repost_confirm")) return %orig;
	NSLog(@"[SCInsta] Confirm repost triggered");
	[SCIUtils showConfirmation:^{ %orig; }];
}

- (void)UFIButtonBarDidLongPressOnRepost:(id)arg1 {
	if (!SCI_PREF(@"repost_confirm")) return %orig;
	NSLog(@"[SCInsta] Confirm repost triggered (long press ignored)");
}

- (void)UFIButtonBarDidLongPressOnRepost:(id)arg1 withGestureRecognizer:(id)arg2 {
	if (!SCI_PREF(@"repost_confirm")) return %orig;
	NSLog(@"[SCInsta] Confirm repost triggered (long press ignored)");
}
%end

%hook IGUFIInteractionCountsView
- (void)updateUFIWithButtonsConfig:(id)config interactionCountProvider:(id)provider {
	%orig;
	if (!SCI_PREF(@"hide_feed_repost")) return;

	Ivar rv = class_getInstanceVariable(object_getClass(self), "_repostView");
	Ivar uv = class_getInstanceVariable(object_getClass(self), "_undoRepostButton");
	if (rv) [object_getIvar((id)self, rv) setHidden:YES];
	if (uv) [object_getIvar((id)self, uv) setHidden:YES];
}
%end

%hook IGSundialViewerVerticalUFI
- (void)_didTapLikeButton:(id)arg1 {
	if (!SCI_PREF(@"like_confirm_reels")) return %orig;
	NSLog(@"[SCInsta] Confirm reels like triggered");
	[SCIUtils showConfirmation:^{ %orig; }];
}

- (void)_didLongPressLikeButton:(id)arg1 {
	if (!SCI_PREF(@"like_confirm_reels")) return %orig;
	NSLog(@"[SCInsta] Confirm reels like long press ignored");
}

- (void)_didTapRepostButton {
	if (SCI_PREF(@"hide_reels_repost")) return;
	if (!SCI_PREF(@"repost_confirm")) return %orig;
	[SCIUtils showConfirmation:^{ %orig; }];
}

- (void)_didLongPressRepostButton:(id)arg1 {
	if (SCI_PREF(@"hide_reels_repost") || SCI_PREF(@"repost_confirm")) return;
	%orig;
}
%end

%hook IGSundialViewerUFIViewModel
- (BOOL)shouldShowRepostButton {
	return SCI_PREF(@"hide_reels_repost") ? NO : %orig;
}
%end

%hook IGRootViewController
- (void)viewDidLoad {
	%orig;

	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
	longPress.minimumPressDuration = 1.0;
	longPress.numberOfTouchesRequired = 5;
	[self.view addGestureRecognizer:longPress];
}

%new
- (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
	if (sender.state == UIGestureRecognizerStateBegan && SCI_PREF(@"flex_instagram")) {
		[[objc_getClass("FLEXManager") sharedManager] showExplorer];
	}
}
%end

%hook IGSafeModeChecker
- (id)initWithInstacrashCounterProvider:(void *)provider crashThreshold:(unsigned long long)threshold {
	return SCI_PREF(@"disable_safe_mode") ? nil : %orig(provider, threshold);
}

- (unsigned long long)crashCount {
	return SCI_PREF(@"disable_safe_mode") ? 0 : %orig;
}
%end

static BOOL (*orig_swizzleToggle_isEnabled)(id, SEL) = NULL;
static BOOL (*orig_expHelper_isEnabled)(id, SEL) = NULL;
static BOOL (*orig_expHelper_isHomeFeed)(id, SEL) = NULL;

static BOOL new_swizzleToggle_isEnabled(id self, SEL _cmd) {
	return SCI_LG_BUTTONS ? YES : (orig_swizzleToggle_isEnabled ? orig_swizzleToggle_isEnabled(self, _cmd) : NO);
}

static BOOL new_expHelper_isEnabled(id self, SEL _cmd) {
	return SCI_LG_BUTTONS ? YES : (orig_expHelper_isEnabled ? orig_expHelper_isEnabled(self, _cmd) : NO);
}

static BOOL new_expHelper_isHomeFeed(id self, SEL _cmd) {
	return SCI_LG_BUTTONS ? YES : (orig_expHelper_isHomeFeed ? orig_expHelper_isHomeFeed(self, _cmd) : NO);
}

static BOOL (*orig_IGFloatingTabBarEnabled)(void) = NULL;
static BOOL (*orig_IGTabBarDynamicSizingEnabled)(void) = NULL;
static BOOL (*orig_IGTabBarEnhancedDynamicSizingEnabled)(void) = NULL;
static BOOL (*orig_IGTabBarHomecomingWithFloatingTabEnabled)(void) = NULL;
static BOOL (*orig_IGTabBarViewPointFixEnabled)(void) = NULL;
static NSInteger (*orig_IGTabBarStyleForLauncherSet)(NSInteger) = NULL;

#define SCI_BOOL_FISHHOOK(name) static BOOL hook_##name(void) { return SCI_LG_SURFACES ? YES : (orig_##name ? orig_##name() : NO); }

SCI_BOOL_FISHHOOK(IGFloatingTabBarEnabled)
SCI_BOOL_FISHHOOK(IGTabBarDynamicSizingEnabled)
SCI_BOOL_FISHHOOK(IGTabBarEnhancedDynamicSizingEnabled)
SCI_BOOL_FISHHOOK(IGTabBarHomecomingWithFloatingTabEnabled)
SCI_BOOL_FISHHOOK(IGTabBarViewPointFixEnabled)

static NSInteger hook_IGTabBarStyleForLauncherSet(NSInteger set) {
	return SCI_LG_SURFACES ? 1 : (orig_IGTabBarStyleForLauncherSet ? orig_IGTabBarStyleForLauncherSet(set) : set);
}

%ctor {
	Class swizzleToggle = objc_getClass("IGLiquidGlassSwizzle.IGLiquidGlassSwizzleToggle");
	if (swizzleToggle) {
		MSHookMessageEx(swizzleToggle, @selector(isEnabled), (IMP)new_swizzleToggle_isEnabled, (IMP *)&orig_swizzleToggle_isEnabled);
	}

	Class expHelper = objc_getClass("IGLiquidGlassExperimentHelper.IGLiquidGlassNavigationExperimentHelper");
	if (expHelper) {
		MSHookMessageEx(expHelper, @selector(isEnabled), (IMP)new_expHelper_isEnabled, (IMP *)&orig_expHelper_isEnabled);
		MSHookMessageEx(expHelper, @selector(isHomeFeedHeaderEnabled), (IMP)new_expHelper_isHomeFeed, (IMP *)&orig_expHelper_isHomeFeed);
	}

	if (SCI_LG_SURFACES) {
		int result = rebind_symbols((struct rebinding[]){
			{"IGFloatingTabBarEnabled", (void *)hook_IGFloatingTabBarEnabled, (void **)&orig_IGFloatingTabBarEnabled},
			{"IGTabBarDynamicSizingEnabled", (void *)hook_IGTabBarDynamicSizingEnabled, (void **)&orig_IGTabBarDynamicSizingEnabled},
			{"IGTabBarEnhancedDynamicSizingEnabled", (void *)hook_IGTabBarEnhancedDynamicSizingEnabled, (void **)&orig_IGTabBarEnhancedDynamicSizingEnabled},
			{"IGTabBarHomecomingWithFloatingTabEnabled", (void *)hook_IGTabBarHomecomingWithFloatingTabEnabled, (void **)&orig_IGTabBarHomecomingWithFloatingTabEnabled},
			{"IGTabBarViewPointFixEnabled", (void *)hook_IGTabBarViewPointFixEnabled, (void **)&orig_IGTabBarViewPointFixEnabled},
			{"IGTabBarStyleForLauncherSet", (void *)hook_IGTabBarStyleForLauncherSet, (void **)&orig_IGTabBarStyleForLauncherSet},
		}, 6);

		NSLog(@"[SCInsta] Liquid glass fishhook result=%d floating=%p dynamic=%p enhanced=%p homecoming=%p viewpoint=%p style=%p",
			result, orig_IGFloatingTabBarEnabled, orig_IGTabBarDynamicSizingEnabled,
			orig_IGTabBarEnhancedDynamicSizingEnabled, orig_IGTabBarHomecomingWithFloatingTabEnabled,
			orig_IGTabBarViewPointFixEnabled, orig_IGTabBarStyleForLauncherSet);
	}
}