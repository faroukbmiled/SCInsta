#import <substrate.h>
#import "InstagramHeaders.h"
#import "Tweak.h"
#import "Utils.h"
#include "../modules/fishhook/fishhook.h"

///////////////////////////////////////////////////////////

// Screenshot handlers

#define VOID_HANDLESCREENSHOT(orig) [SCIUtils getBoolPref:@"remove_screenshot_alert"] ? nil : orig;
#define NONVOID_HANDLESCREENSHOT(orig) return VOID_HANDLESCREENSHOT(orig)

///////////////////////////////////////////////////////////

// * Tweak version *
NSString *SCIVersionString = @"v1.2.1";

// Variables that work across features
BOOL dmVisualMsgsViewedButtonEnabled = false;

// Tweak first-time setup
%hook IGInstagramAppDelegate
- (_Bool)application:(UIApplication *)application willFinishLaunchingWithOptions:(id)arg2 {
    // Default SCInsta config
    NSDictionary *sciDefaults = @{
        @"hide_ads": @(YES),
        @"copy_description": @(YES),
        @"profile_copy_button": @(YES),
        @"detailed_color_picker": @(YES),
        @"remove_screenshot_alert": @(YES),
        @"call_confirm": @(YES),
        @"keep_deleted_message": @(NO),
        @"hide_suggested_stories": @(NO),
        @"story_tray_actions": @(NO),
        @"zoom_profile_photo": @(NO),
        @"follow_indicator": @(NO),
        @"profile_note_copy": @(NO),
        @"disable_disappearing_mode_swipe": @(NO),
        @"hide_voice_call_button": @(NO),
        @"hide_video_call_button": @(NO),
        @"fake_location_enabled": @(NO),
        @"show_fake_location_map_button": @(NO),
        @"fake_location_lat": @(48.8584),
        @"fake_location_lon": @(2.2945),
        @"fake_location_name": @"Eiffel Tower",
        @"fake_location_presets": @[],
        @"messages_only": @(NO),
        @"launch_tab": @"default",
        @"save_profile": @(YES),
        // Per-context action buttons (new in 1.1.6)
        @"feed_media_zoom": @(NO),
        @"disable_bg_refresh": @(NO),
        @"disable_home_refresh": @(NO),
        @"disable_home_scroll": @(NO),
        @"disable_reels_tab_refresh": @(NO),
        @"dm_full_last_active": @(NO),
        @"send_file": @(NO),
        @"note_actions": @(NO),
        @"note_copy_on_hold": @(NO),
        @"feed_date_format": @"default",
        // Per-surface date format toggles (see SCIDateFormatEntries.h)
        @"date_fmt_mixed": @(YES),
        @"date_fmt_notes_comments_stories": @(NO),
        @"date_fmt_dms": @(NO),
        @"feed_action_button": @(YES),
        @"feed_action_default": @"menu",
        @"reels_action_button": @(YES),
        @"reels_action_default": @"menu",
        @"stories_action_button": @(YES),
        @"stories_action_default": @"menu",
        // Legacy long-press gesture (off by default — kept for users who prefer it)
        @"dw_legacy_gesture": @(NO),
        @"dw_confirm": @(NO),
        @"enhance_download_quality": @(YES),
        @"default_video_quality": @"always_ask",
        @"default_photo_quality": @"high",
        @"ffmpeg_encoding_speed": @"ultrafast",
        @"unfollow_confirm": @(NO),
        @"dw_save_action": @"share",
        @"dw_finger_count": @(3),
        @"dw_finger_duration": @(0.5),
        @"reels_tap_control": @"default",
        @"nav_icon_ordering": @"default",
        @"swipe_nav_tabs": @"default",
        @"enable_notes_customization": @(YES),
        @"custom_note_themes": @(YES),
        @"disable_auto_unmuting_reels": @(NO),
        @"auto_scroll_reels_mode": @"off",
        @"settings_shortcut": @(YES),
        @"doom_scrolling_reel_count": @(1),
        @"keep_seen_visual_local": @(NO),
        @"send_audio_as_file": @(YES),
        @"download_audio_message": @(NO),
        @"save_to_ryukgram_album": @(NO),
        @"unlock_password_reels": @(YES),
        @"seen_mode": @"button",
        @"seen_auto_on_interact": @(NO),
        @"seen_auto_on_typing": @(NO),
        @"seen_on_story_like": @(NO),
        @"seen_on_story_reply": @(NO),
        @"advance_on_story_reply": @(NO),
        @"advance_on_mark_seen": @(NO),
        @"advance_on_story_like": @(NO),
        @"indicate_unsent_messages": @(NO),
        @"unsent_message_toast": @(NO),
        @"warn_refresh_clears_preserved": @(NO),
        @"enable_chat_exclusions": @(YES),
        @"chat_blocking_mode": @"block_all",
        @"exclusions_default_keep_deleted": @(NO),
        @"chat_quick_list_button": @(YES),
        @"enable_story_user_exclusions": @(YES),
        @"story_blocking_mode": @"block_all",
        @"story_excluded_show_unexclude_eye": @(YES),
        @"story_seen_mode": @"button",
        @"story_audio_toggle": @(NO),
        @"view_story_mentions": @(YES),
        @"settings_pause_playback": @(YES),
        @"embed_links": @(NO),
        @"embed_link_domain": @"kkinstagram.com",
        @"strip_tracking_params": @(NO),
        @"download_highlight_cover": @(YES),
        @"open_links_external": @(NO),
        @"strip_browser_tracking": @(NO),
        @"hide_feed_repost": @(NO),
        @"copy_comment": @(YES),
        @"download_gif_comment": @(YES),
        @"sci_language": @"system"
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:sciDefaults];
    [SCIUtils setSciRegisteredDefaults:sciDefaults];
    
    // Override instagram defaults
    if ([SCIUtils getBoolPref:@"liquid_glass_buttons"]) {
        [[NSUserDefaults standardUserDefaults] setValue:@(YES) forKey:@"instagram.override.project.lucent.navigation"];
    }
    else {
        [[NSUserDefaults standardUserDefaults] setValue:@(NO) forKey:@"instagram.override.project.lucent.navigation"];
    }

    return %orig;
}
- (_Bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)arg2 {
    %orig;

    // Open settings for first-time users
    double openDelay = [SCIUtils getBoolPref:@"tweak_settings_app_launch"] ? 0.0 : 5.0;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(openDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (
            ![[[NSUserDefaults standardUserDefaults] objectForKey:@"SCInstaFirstRun"] isEqualToString:SCIVersionString]
            || [SCIUtils getBoolPref:@"tweak_settings_app_launch"]
        ) {
            NSLog(@"[SCInsta] First run, initializing");

            // Display settings modal on screen
            NSLog(@"[SCInsta] Displaying RyukGram first-time settings modal");
            [SCIUtils showSettingsVC:[self window]];
        }
    });

    NSLog(@"[SCInsta] Cleaning cache...");
    [SCIUtils cleanCache];

    if ([SCIUtils getBoolPref:@"flex_app_launch"]) {
        [[objc_getClass("FLEXManager") sharedManager] showExplorer];
    }

    return true;
}

- (void)applicationDidBecomeActive:(id)arg1 {
    %orig;

    if ([SCIUtils getBoolPref:@"flex_app_start"]) {
        [[objc_getClass("FLEXManager") sharedManager] showExplorer];
    }

}
%end

%hook IGDSLauncherConfig
- (_Bool)isLiquidGlassInAppNotificationEnabled {
    return [SCIUtils liquidGlassEnabledBool:%orig];
}
- (_Bool)isLiquidGlassContextMenuEnabled {
    return [SCIUtils liquidGlassEnabledBool:%orig];
}
- (_Bool)isLiquidGlassToastEnabled {
    return [SCIUtils liquidGlassEnabledBool:%orig];
}
- (_Bool)isLiquidGlassToastPeekEnabled {
    return [SCIUtils liquidGlassEnabledBool:%orig];
}
- (_Bool)isLiquidGlassAlertDialogEnabled {
    return [SCIUtils liquidGlassEnabledBool:%orig];
}
- (_Bool)isLiquidGlassIconBarButtonEnabled {
    return [SCIUtils liquidGlassEnabledBool:%orig];
}
%end


// Disable sending modded insta bug reports
%hook IGWindow
- (void)showDebugMenu {
    return;
}
%end

%hook IGBugReportUploader
- (id)initWithNetworker:(id)arg1
         pandoGraphQLService:(id)arg2
             analyticsLogger:(id)arg3
                userDefaults:(id)arg4
         launcherSetProvider:(id)arg5
shouldPersistLastBugReportId:(id)arg6
{
    return nil;
}
%end

// Disable anti-screenshot feature on visual messages
%hook IGStoryViewerContainerView
- (void)setShouldBlockScreenshot:(BOOL)arg1 viewModel:(id)arg2 { VOID_HANDLESCREENSHOT(%orig); }
%end

// Disable screenshot logging/detection
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
    if ([SCIUtils getBoolPref:@"remove_screenshot_alert"]) {
        NSLog(@"[SCInsta] Disable visual message screenshot safety logger");
        return nil;
    }

    return %orig;
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

/////////////////////////////////////////////////////////////////////////////

// Hide items

// Direct suggested chats (in search bar)
%hook IGDirectInboxSearchListAdapterDataSource
- (id)objectsForListAdapter:(id)arg1 {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        // Section header 
        if ([obj isKindOfClass:%c(IGLabelItemViewModel)]) {

            // Broadcast channels
            if ([[obj valueForKey:@"uniqueIdentifier"] isEqualToString:@"channels"]) {
                if ([SCIUtils getBoolPref:@"no_suggested_chats"]) {
                    NSLog(@"[SCInsta] Hiding suggested chats (header)");

                    shouldHide = YES;
                }
            }

            // Ask Meta AI
            else if ([[obj valueForKey:@"labelTitle"] isEqualToString:@"Ask Meta AI"]) {
                if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
                    NSLog(@"[SCInsta] Hiding meta ai suggested chats (header)");

                    shouldHide = YES;
                }
            }

            // AI
            else if ([[obj valueForKey:@"labelTitle"] isEqualToString:@"AI"]) {
                if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
                    NSLog(@"[SCInsta] Hiding ai suggested chats (header)");

                    shouldHide = YES;
                }
            }
            
        }

        // AI agents section
        else if (
            [obj isKindOfClass:%c(IGDirectInboxSearchAIAgentsPillsSectionViewModel)]
         || [obj isKindOfClass:%c(IGDirectInboxSearchAIAgentsSuggestedPromptViewModel)]
         || [obj isKindOfClass:%c(IGDirectInboxSearchAIAgentsSuggestedPromptLoggingViewModel)]
        ) {

            if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
                NSLog(@"[SCInsta] Hiding suggested chats (ai agents)");

                shouldHide = YES;
            }

        }

        // Recipients list
        else if ([obj isKindOfClass:%c(IGDirectRecipientCellViewModel)]) {

            // Broadcast channels
            if ([[obj recipient] isBroadcastChannel]) {
                if ([SCIUtils getBoolPref:@"no_suggested_chats"]) {
                    NSLog(@"[SCInsta] Hiding suggested chats (broadcast channels recipient)");

                    shouldHide = YES;
                }
            }
            
            // Meta AI (special section types)
            else if (([obj sectionType] == 20) || [obj sectionType] == 18) {
                if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
                    NSLog(@"[SCInsta] Hiding meta ai suggested chats (meta ai recipient)");

                    shouldHide = YES;
                }
            }

            // Meta AI (catch-all)
            else if ([[[obj recipient] threadName] isEqualToString:@"Meta AI"]) {
                if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
                    NSLog(@"[SCInsta] Hiding meta ai suggested chats (meta ai recipient)");

                    shouldHide = YES;
                }
            }
        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }

    }

    return [filteredObjs copy];
}
%end

// Direct suggested chats (thread creation view)
%hook IGDirectThreadCreationViewController
- (id)objectsForListAdapter:(id)arg1 {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        // Meta AI suggested user in direct new message view
        if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
            
            if ([obj isKindOfClass:%c(IGDirectCreateChatCellViewModel)]) {

                // "AI Chats"
                if ([[obj valueForKey:@"title"] isEqualToString:@"AI chats"]) {
                    NSLog(@"[SCInsta] Hiding meta ai: direct thread creation ai chats section");

                    shouldHide = YES;
                }

            }

            else if ([obj isKindOfClass:%c(IGDirectRecipientCellViewModel)]) {

                // Meta AI suggested user
                if ([[[obj recipient] threadName] isEqualToString:@"Meta AI"]) {
                    NSLog(@"[SCInsta] Hiding meta ai: direct thread creation ai suggestion");

                    shouldHide = YES;
                }

            }
            
        }

        // Invite friends to insta contacts upsell
        if ([SCIUtils getBoolPref:@"no_suggested_users"]) {
            if ([obj isKindOfClass:%c(IGContactInvitesSearchUpsellViewModel)]) {
                NSLog(@"[SCInsta] Hiding suggested users: invite contacts upsell");

                shouldHide = YES;
            }
        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }
    }

    return [filteredObjs copy];
}
%end

// Direct suggested chats (inbox view)
%hook IGDirectInboxListAdapterDataSource
- (id)objectsForListAdapter:(id)arg1 {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        // Section header
        if ([obj isKindOfClass:%c(IGDirectInboxHeaderCellViewModel)]) {
            
            // "Suggestions" header
            if ([[obj title] isEqualToString:@"Suggestions"]) {
                if ([SCIUtils getBoolPref:@"no_suggested_users"]) {
                    NSLog(@"[SCInsta] Hiding suggested chats (header: messages tab)");

                    shouldHide = YES;
                }
            }

            // "Accounts to follow/message" header
            else if ([[obj title] hasPrefix:@"Accounts to"]) {
                if ([SCIUtils getBoolPref:@"no_suggested_users"]) {
                    NSLog(@"[SCInsta] Hiding suggested users: (header: inbox view)");

                    shouldHide = YES;
                }
            }

        }

        // Suggested recipients
        else if ([obj isKindOfClass:%c(IGDirectInboxSuggestedThreadCellViewModel)]) {
            if ([SCIUtils getBoolPref:@"no_suggested_users"]) {
                NSLog(@"[SCInsta] Hiding suggested chats (recipients: channels tab)");

                shouldHide = YES;
            }
        }

        // "Accounts to follow" recipients
        else if ([obj isKindOfClass:%c(IGDiscoverPeopleItemConfiguration)] || [obj isKindOfClass:%c(IGDiscoverPeopleConnectionItemConfiguration)]) {
            if ([SCIUtils getBoolPref:@"no_suggested_users"]) {
                NSLog(@"[SCInsta] Hiding suggested chats: (recipients: inbox view)");

                shouldHide = YES;
            }
        }

        // Hide notes tray
        else if ([obj isKindOfClass:%c(IGDirectNotesTrayRowViewModel)]) {
            if ([SCIUtils getBoolPref:@"hide_notes_tray"]) {
                NSLog(@"[SCInsta] Hiding notes tray");

                shouldHide = YES;
            }
        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }

    }

    return [filteredObjs copy];
}
%end

// Explore page results
%hook IGSearchListKitDataSource
- (id)objectsForListAdapter:(id)arg1 {
    NSArray *originalObjs = %orig();
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        // Meta AI
        if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {

            // Section header 
            if ([obj isKindOfClass:%c(IGLabelItemViewModel)]) {

                // "Ask Meta AI" search results header
                if ([[obj valueForKey:@"labelTitle"] isEqualToString:@"Ask Meta AI"]) {
                    shouldHide = YES;
                }

            }

            // Empty search bar upsell view
            else if ([obj isKindOfClass:%c(IGSearchNullStateUpsellViewModel)]) {
                shouldHide = YES;
            }

            // Meta AI search suggestions
            else if ([obj isKindOfClass:%c(IGSearchResultNestedGroupViewModel)]) {
                shouldHide = YES;
            }

            // Meta AI suggested search results
            else if ([obj isKindOfClass:%c(IGSearchResultViewModel)]) {

                // itemType 6 is meta ai suggestions
                if ([obj itemType] == 6) {
                    if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
                        shouldHide = YES;
                    }
                    
                }

                // Meta AI user account in search results
                else if ([[[obj title] string] isEqualToString:@"meta.ai"]) {
                    if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
                        shouldHide = YES;
                    }
                }

            }
            
        }

        // No suggested users
        if ([SCIUtils getBoolPref:@"no_suggested_users"]) {

            // Section header 
            if ([obj isKindOfClass:%c(IGLabelItemViewModel)]) {

                // "Suggested for you" search results header
                if ([[obj valueForKey:@"labelTitle"] isEqualToString:@"Suggested for you"]) {
                    shouldHide = YES;
                }

            }

            // Instagram users
            else if ([obj isKindOfClass:%c(IGDiscoverPeopleItemConfiguration)]) {
                shouldHide = YES;
            }

            // See all suggested users
            else if ([obj isKindOfClass:%c(IGSeeAllItemConfiguration)] && ((IGSeeAllItemConfiguration *)obj).destination == 4) {
                shouldHide = YES;
            }

        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }

    }

    return [filteredObjs copy];
}
%end

// Story tray
%hook IGMainStoryTrayDataSource
- (id)allItemsForTrayUsingCachedValue:(BOOL)cached {
    NSArray *originalObjs = %orig(cached);
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (IGStoryTrayViewModel *obj in originalObjs) {
        BOOL shouldHide = NO;

        if ([SCIUtils getBoolPref:@"no_suggested_users"]) {
            if ([obj isKindOfClass:%c(IGStoryTrayViewModel)]) {
                NSNumber *type = [((IGStoryTrayViewModel *)obj) valueForKey:@"type"];
                
                // 8/9 looks to be the types for recommended stories
                if ([type isEqual:@(8)] || [type isEqual:@(9)]) {
                    NSLog(@"[SCInsta] Hiding suggested users: story tray");

                    shouldHide = YES;

                }
            }
        }

        if ([SCIUtils getBoolPref:@"hide_ads"]) {
            // "New!" account id is 3538572169
            if ([obj isKindOfClass:%c(IGStoryTrayViewModel)] && (obj.isUnseenNux == YES || [obj.pk isEqualToString:@"3538572169"])) {
                NSLog(@"[SCInsta] Removing ads: story tray");

                shouldHide = YES;
            }
        }

        // Populate new objs array
        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }
    }

    return [filteredObjs copy];
}
%end

// Story tray expanded footer (Suggested accounts to follow)
%hook IGStoryTraySectionController
- (void)storyTrayControllerShowSUPOGEducationBump {
    if ([SCIUtils getBoolPref:@"no_suggested_users"]) return;

    return %orig();
}
%end

// Modern IGDS app menus
%hook IGDSMenu
- (id)initWithMenuItems:(NSArray<IGDSMenuItem *> *)originalObjs edr:(BOOL)edr headerLabelText:(id)headerLabelText {
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        NSString *itemTitle = nil;
        @try { itemTitle = [obj valueForKey:@"title"]; } @catch (__unused id e) {}

        // Meta AI
        if ([itemTitle isEqualToString:@"AI images"] || [itemTitle isEqualToString:@"Meta AI"]) {
            if ([SCIUtils getBoolPref:@"hide_meta_ai"]) {
                shouldHide = YES;
            }
        }

        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }
    }

    extern NSArray *sciMaybeAppendStoryExcludeMenuItem(NSArray *);
    extern NSArray *sciMaybeAppendStoryAudioMenuItem(NSArray *);
    extern NSArray *sciMaybeAppendStoryMentionsMenuItem(NSArray *);
    NSArray *finalObjs = sciMaybeAppendStoryExcludeMenuItem([filteredObjs copy]);
    finalObjs = sciMaybeAppendStoryAudioMenuItem(finalObjs);
    finalObjs = sciMaybeAppendStoryMentionsMenuItem(finalObjs);
    return %orig(finalObjs, edr, headerLabelText);
}
%end

/////////////////////////////////////////////////////////////////////////////

// Confirm buttons

%hook IGFeedItemUFICell
- (void)UFIButtonBarDidTapOnLike:(id)arg1 {
    if ([SCIUtils getBoolPref:@"like_confirm"]) {
        NSLog(@"[SCInsta] Confirm post like triggered");

        [SCIUtils showConfirmation:^(void) { %orig; }];
    }
    else {
        return %orig;
    }  
}

- (void)UFIButtonBarDidTapOnRepost:(id)arg1 {
    if ([SCIUtils getBoolPref:@"repost_confirm"]) {
        NSLog(@"[SCInsta] Confirm repost triggered");

        [SCIUtils showConfirmation:^(void) { %orig; }];
    }
    else {
        return %orig;
    }
}

- (void)UFIButtonBarDidLongPressOnRepost:(id)arg1 {
    if ([SCIUtils getBoolPref:@"repost_confirm"]) {
        NSLog(@"[SCInsta] Confirm repost triggered (long press ignored)");
    }
    else {
        return %orig;
    }
}
- (void)UFIButtonBarDidLongPressOnRepost:(id)arg1 withGestureRecognizer:(id)arg2 {
    if ([SCIUtils getBoolPref:@"repost_confirm"]) {
        NSLog(@"[SCInsta] Confirm repost triggered (long press ignored)");
    }
    else {
        return %orig;
    }
}
%end

// Hide repost button in feed (requires restart)
%hook IGUFIInteractionCountsView
- (void)updateUFIWithButtonsConfig:(id)config interactionCountProvider:(id)provider {
    %orig;
    if (![SCIUtils getBoolPref:@"hide_feed_repost"]) return;
    Ivar rv = class_getInstanceVariable(object_getClass(self), "_repostView");
    if (rv) [object_getIvar((id)self, rv) setHidden:YES];
    Ivar uv = class_getInstanceVariable(object_getClass(self), "_undoRepostButton");
    if (uv) [object_getIvar((id)self, uv) setHidden:YES];
}
%end


%hook IGSundialViewerVerticalUFI
- (void)_didTapLikeButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"like_confirm_reels"]) {
        NSLog(@"[SCInsta] Confirm reels like triggered");

        [SCIUtils showConfirmation:^(void) { %orig; }];
    }
    else {
        return %orig;
    }
}

- (void)_didLongPressLikeButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"like_confirm_reels"]) {
        NSLog(@"[SCInsta] Confirm repost triggered (long press ignored)");
    }
    else {
        return %orig;
    }
}

- (void)_didTapRepostButton {
    if ([SCIUtils getBoolPref:@"hide_reels_repost"]) return;
    if ([SCIUtils getBoolPref:@"repost_confirm"]) {
        [SCIUtils showConfirmation:^(void) { %orig; }];
    }
    else {
        %orig;
    }
}

- (void)_didLongPressRepostButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_reels_repost"]) return;
    if ([SCIUtils getBoolPref:@"repost_confirm"]) return;
    %orig;
}
%end

// Hide repost button at the view model level so IG's layout handles the gap
%hook IGSundialViewerUFIViewModel
- (BOOL)shouldShowRepostButton {
    if ([SCIUtils getBoolPref:@"hide_reels_repost"]) return NO;
    return %orig;
}
%end

/////////////////////////////////////////////////////////////////////////////

// FLEX explorer gesture handler
%hook IGRootViewController
- (void)viewDidLoad {
    %orig;
    
    // Recognize 5-finger long press
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 1;
    longPress.numberOfTouchesRequired = 5;
    [self.view addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    if ([SCIUtils getBoolPref:@"flex_instagram"]) {
        [[objc_getClass("FLEXManager") sharedManager] showExplorer];
    }
}
%end

// Disable safe mode (defaults reset upon subsequent crashes)
%hook IGSafeModeChecker
- (id)initWithInstacrashCounterProvider:(void *)provider crashThreshold:(unsigned long long)threshold {
    if ([SCIUtils getBoolPref:@"disable_safe_mode"]) return nil;

    return %orig(provider, threshold);
}
- (unsigned long long)crashCount {
    if ([SCIUtils getBoolPref:@"disable_safe_mode"]) {
        return 0;
    }

    return %orig;
}
%end

// liquid glass Swift class hooks
static BOOL (*orig_swizzleToggle_isEnabled)(id, SEL) = NULL;
static BOOL new_swizzleToggle_isEnabled(id self, SEL _cmd) {
    if ([SCIUtils getBoolPref:@"liquid_glass_buttons"]) return YES;
    return orig_swizzleToggle_isEnabled(self, _cmd);
}

static BOOL (*orig_expHelper_isEnabled)(id, SEL) = NULL;
static BOOL new_expHelper_isEnabled(id self, SEL _cmd) {
    if ([SCIUtils getBoolPref:@"liquid_glass_buttons"]) return YES;
    return orig_expHelper_isEnabled(self, _cmd);
}

static BOOL (*orig_expHelper_isHomeFeed)(id, SEL) = NULL;
static BOOL new_expHelper_isHomeFeed(id self, SEL _cmd) {
    if ([SCIUtils getBoolPref:@"liquid_glass_buttons"]) return YES;
    return orig_expHelper_isHomeFeed(self, _cmd);
}

// Liquid glass tab bar — C function hooks via fishhook
// Credits: @euoradan (Radan) for discovering these flags
static BOOL (*orig_IGFloatingTabBarEnabled)(void) = NULL;
static BOOL (*orig_IGTabBarDynamicSizingEnabled)(void) = NULL;
static BOOL (*orig_IGTabBarEnhancedDynamicSizingEnabled)(void) = NULL;
static BOOL (*orig_IGTabBarHomecomingWithFloatingTabEnabled)(void) = NULL;
static BOOL (*orig_IGTabBarViewPointFixEnabled)(void) = NULL;
static NSInteger (*orig_IGTabBarStyleForLauncherSet)(NSInteger) = NULL;

static BOOL hook_IGFloatingTabBarEnabled(void) {
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) return YES;
    return orig_IGFloatingTabBarEnabled ? orig_IGFloatingTabBarEnabled() : NO;
}
static BOOL hook_IGTabBarDynamicSizingEnabled(void) {
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) return YES;
    return orig_IGTabBarDynamicSizingEnabled ? orig_IGTabBarDynamicSizingEnabled() : NO;
}
static BOOL hook_IGTabBarEnhancedDynamicSizingEnabled(void) {
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) return YES;
    return orig_IGTabBarEnhancedDynamicSizingEnabled ? orig_IGTabBarEnhancedDynamicSizingEnabled() : NO;
}
static BOOL hook_IGTabBarHomecomingWithFloatingTabEnabled(void) {
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) return YES;
    return orig_IGTabBarHomecomingWithFloatingTabEnabled ? orig_IGTabBarHomecomingWithFloatingTabEnabled() : NO;
}
static BOOL hook_IGTabBarViewPointFixEnabled(void) {
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) return YES;
    return orig_IGTabBarViewPointFixEnabled ? orig_IGTabBarViewPointFixEnabled() : NO;
}
static NSInteger hook_IGTabBarStyleForLauncherSet(NSInteger set) {
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) return 1;
    return orig_IGTabBarStyleForLauncherSet ? orig_IGTabBarStyleForLauncherSet(set) : set;
}

%ctor {
    // ObjC hooks for liquid glass buttons
    Class swizzleToggle = objc_getClass("IGLiquidGlassSwizzle.IGLiquidGlassSwizzleToggle");
    if (swizzleToggle) {
        MSHookMessageEx(swizzleToggle, @selector(isEnabled),
                        (IMP)new_swizzleToggle_isEnabled, (IMP *)&orig_swizzleToggle_isEnabled);
    }

    Class expHelper = objc_getClass("IGLiquidGlassExperimentHelper.IGLiquidGlassNavigationExperimentHelper");
    if (expHelper) {
        MSHookMessageEx(expHelper, @selector(isEnabled),
                        (IMP)new_expHelper_isEnabled, (IMP *)&orig_expHelper_isEnabled);
        MSHookMessageEx(expHelper, @selector(isHomeFeedHeaderEnabled),
                        (IMP)new_expHelper_isHomeFeed, (IMP *)&orig_expHelper_isHomeFeed);
    }

    // C function hooks for liquid glass tab bar / surfaces (fishhook)
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) {
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
