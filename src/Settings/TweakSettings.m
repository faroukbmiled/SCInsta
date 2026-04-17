#import "TweakSettings.h"
#import "SCISettingsBackup.h"
#import "SCIFakeLocationSettingsVC.h"
#import "SCIExcludedChatsViewController.h"
#import "../Features/StoriesAndMessages/SCIExcludedThreads.h"
#import "../Features/StoriesAndMessages/SCIExcludedStoryUsers.h"
#import "SCIExcludedStoryUsersViewController.h"
#import "SCIEmbedDomainViewController.h"
#import "SCIDateFormatPickerVC.h"
#import "../SCIFFmpeg.h"
#import <objc/runtime.h>

// Copies imported .strings into the writable override dir.
@interface SCILocImportHelper : NSObject <UIDocumentPickerDelegate>
@end
@implementation SCILocImportHelper
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!urls.count) return;
    NSURL *src = urls.firstObject;
    NSString *code = objc_getAssociatedObject(controller, "sci_lang");
    if (!code.length) return;

    // Validate it parses
    NSDictionary *test = [NSDictionary dictionaryWithContentsOfURL:src];
    if (!test.count) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Error"
            message:@"File is empty or not a valid .strings file." preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *top = controller.presentingViewController ?: UIApplication.sharedApplication.keyWindow.rootViewController;
        [top presentViewController:a animated:YES completion:nil];
        return;
    }

    // Write to the writable override dir (Library/RyukGram.bundle/<code>.lproj/).
    NSString *lproj = [NSString stringWithFormat:@"%@.lproj", code];
    NSString *dir = [SCILocalizationOverridePath() stringByAppendingPathComponent:lproj];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *dest = [dir stringByAppendingPathComponent:@"Localizable.strings"];
    [fm removeItemAtPath:dest error:nil];
    BOOL ok = [fm copyItemAtPath:src.path toPath:dest error:nil];

    NSString *msg = ok
        ? [NSString stringWithFormat:@"Updated %@ (%ld keys). Restart to apply.", code, (long)test.count]
        : @"Could not write file.";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:ok ? @"Done" : @"Error"
                                                               message:msg preferredStyle:UIAlertControllerStyleAlert];
    if (ok) {
        [a addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *x) { [SCIUtils showRestartConfirmation]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *top = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:a animated:YES completion:nil];
}
@end

@implementation SCITweakSettings

// MARK: - Sections

///
/// This returns an array of sections, with each section consisting of a dictionary
///
/// `"title"`: The section title (leave blank for no title)
///
/// `"rows"`: An array of **SCISetting** classes, potentially containing a "navigationCellWithTitle" initializer to allow for nested setting pages.
///
/// `"footer`: The section footer (leave blank for no footer)

+ (NSArray *)sections {
    return @[
        @{
            @"header": @"",
            @"rows": @[
                [SCISetting linkCellWithTitle:SCILocalized(@"RyukGram on GitHub") subtitle:[NSString stringWithFormat:SCILocalized(@"%@ — view source, report issues, see releases"), SCIVersionString] imageUrl:@"https://github.com/faroukbmiled.png" url:@"https://github.com/faroukbmiled/RyukGram"]
            ]
        },
        @{
            @"header": @"",
            @"rows": @[
                [SCISetting navigationCellWithTitle:SCILocalized(@"General")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"gear"]
                                        navSections:@[@{
                                            @"header": @"",
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide ads") subtitle:SCILocalized(@"Removes all ads from the Instagram app") defaultsKey:@"hide_ads"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide Meta AI") subtitle:SCILocalized(@"Hides the meta ai buttons/functionality within the app") defaultsKey:@"hide_meta_ai"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide metrics") subtitle:SCILocalized(@"Hides like/comment/share counts on posts and reels") defaultsKey:@"hide_metrics"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Do not save recent searches") subtitle:SCILocalized(@"Search bars will no longer save your recent searches") defaultsKey:@"no_recent_searches"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Copy description") subtitle:SCILocalized(@"Copy description text fields by long-pressing on them") defaultsKey:@"copy_description"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Use detailed color picker") subtitle:SCILocalized(@"Long press on the eyedropper tool in stories to customize the text color more precisely") defaultsKey:@"detailed_color_picker"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Date format"),
                                            @"footer": SCILocalized(@"Replace IG's relative timestamps (\"3d ago\") with a custom format. Toggle which surfaces it applies to inside the picker."),
                                            @"rows": @[
                                                [self dateFormatNavCell],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Browser"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Open links in external browser") subtitle:SCILocalized(@"Opens links in Safari instead of Instagram's in-app browser") defaultsKey:@"open_links_external"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Strip tracking from links") subtitle:SCILocalized(@"Removes Instagram tracking wrappers (l.instagram.com) and UTM/fbclid params from URLs") defaultsKey:@"strip_browser_tracking"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Sharing"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Replace domain in shared links") subtitle:SCILocalized(@"Rewrites copied/shared links to use an embed-friendly domain for previews in Discord, Telegram, etc.") defaultsKey:@"embed_links"],
                                                ({
                                                    SCISetting *s = [SCISetting buttonCellWithTitle:SCILocalized(@"Embed domain")
                                                                       subtitle:@""
                                                                           icon:[SCISymbol symbolWithName:@"globe"]
                                                                         action:^(void) {
                                                        UIWindow *win = nil;
                                                        for (UIWindow *w in [UIApplication sharedApplication].windows)
                                                            if (w.isKeyWindow) { win = w; break; }
                                                        UIViewController *top = win.rootViewController;
                                                        while (top.presentedViewController) top = top.presentedViewController;
                                                        if ([top isKindOfClass:[UINavigationController class]])
                                                            [(UINavigationController *)top pushViewController:[SCIEmbedDomainViewController new] animated:YES];
                                                        else if (top.navigationController)
                                                            [top.navigationController pushViewController:[SCIEmbedDomainViewController new] animated:YES];
                                                    }];
                                                    s.dynamicTitle = ^{ return [NSString stringWithFormat:SCILocalized(@"Embed domain: %@"), [SCIUtils getStringPref:@"embed_link_domain"] ?: @"kkinstagram.com"]; };
                                                    s;
                                                }),
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Strip tracking params") subtitle:SCILocalized(@"Removes igsh, utm_source, and other tracking parameters from shared links") defaultsKey:@"strip_tracking_params"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Comments"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Copy comment text") subtitle:SCILocalized(@"Adds a copy option to the comment long-press menu") defaultsKey:@"copy_comment"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Download GIF comments") subtitle:SCILocalized(@"Adds a download option for GIF comments") defaultsKey:@"download_gif_comment"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Notes"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide notes tray") subtitle:SCILocalized(@"Hides the notes tray in the DM inbox") defaultsKey:@"hide_notes_tray"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide friends map") subtitle:SCILocalized(@"Hides the friends map icon in the notes tray") defaultsKey:@"hide_friends_map"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Focus/distractions"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"No suggested users") subtitle:SCILocalized(@"Hides all suggested users for you to follow, outside your feed") defaultsKey:@"no_suggested_users"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"No suggested chats") subtitle:SCILocalized(@"Hides the suggested broadcast channels in direct messages") defaultsKey:@"no_suggested_chats"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide explore posts grid") subtitle:SCILocalized(@"Hides the grid of suggested posts on the explore/search tab") defaultsKey:@"hide_explore_grid"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide trending searches") subtitle:SCILocalized(@"Hides the trending searches under the explore search bar") defaultsKey:@"hide_trending_searches"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Experimental features"),
                                            @"footer": SCILocalized(@"These features rely on hidden Instagram flags and may not work on all accounts or versions.\nExperimental flags research by @euoradan (Radan)."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Enable liquid glass buttons") subtitle:SCILocalized(@"Enables experimental liquid glass buttons") defaultsKey:@"liquid_glass_buttons" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Enable liquid glass surfaces") subtitle:SCILocalized(@"Enables liquid glass tab bar, floating navigation, and other UI elements") defaultsKey:@"liquid_glass_surfaces" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Enable teen app icons") subtitle:SCILocalized(@"Hold down on the Instagram logo to change the app icon") defaultsKey:@"teen_app_icons" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable app haptics") subtitle:SCILocalized(@"Disables haptics/vibrations within the app") defaultsKey:@"disable_haptics"]
                                            ]
                                        }]
                ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Feed")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"rectangle.stack"]
                                        navSections:@[@{
                                            @"header": SCILocalized(@"Action button"),
                                            @"footer": SCILocalized(@"Adds a RyukGram action button under each feed post with download/share/copy/expand/repost entries. Tap opens the menu by default; change the tap behavior below."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Show action button") subtitle:SCILocalized(@"Inserts a button row below like/comment/share on each post") defaultsKey:@"feed_action_button"],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Default tap action") subtitle:SCILocalized(@"What happens on a single tap. Long-press always opens the full menu") menu:[self menus][@"feed_action_default"]],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Media"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Media zoom") subtitle:SCILocalized(@"Long press on media to expand in full-screen viewer") defaultsKey:@"feed_media_zoom"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable video autoplay") subtitle:SCILocalized(@"Prevents videos from playing automatically") defaultsKey:@"disable_feed_autoplay" requiresRestart:YES],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Stories tray"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Tray long-press actions") subtitle:SCILocalized(@"Adds 'View profile picture' and 'View cover' to story tray long-press menus") defaultsKey:@"story_tray_actions"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Hide"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide suggested stories") subtitle:SCILocalized(@"Removes suggested accounts from the stories tray") defaultsKey:@"hide_suggested_stories"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide stories tray") subtitle:SCILocalized(@"Hides the story tray at the top") defaultsKey:@"hide_stories_tray"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide entire feed") subtitle:SCILocalized(@"Removes all content from your home feed") defaultsKey:@"hide_entire_feed"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide repost button") subtitle:SCILocalized(@"Hides the repost button on feed posts") defaultsKey:@"hide_feed_repost" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"No suggested posts") subtitle:SCILocalized(@"Removes suggested posts") defaultsKey:@"no_suggested_post"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"No suggested for you") subtitle:SCILocalized(@"Hides suggested accounts") defaultsKey:@"no_suggested_account"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"No suggested reels") subtitle:SCILocalized(@"Hides suggested reels") defaultsKey:@"no_suggested_reels"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"No suggested threads") subtitle:SCILocalized(@"Hides suggested threads posts") defaultsKey:@"no_suggested_threads"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Refresh"),
                                            @"footer": SCILocalized(@"Controls when and how the feed refreshes. Background refresh occurs when returning to the app after ~10 minutes. Home button refresh occurs when tapping the Home tab while already on it."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable background refresh") subtitle:SCILocalized(@"Prevents feed from reloading when returning from background") defaultsKey:@"disable_bg_refresh" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable home button refresh") subtitle:SCILocalized(@"Scroll to top without refreshing when tapping Home") defaultsKey:@"disable_home_refresh"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable home button scroll") subtitle:SCILocalized(@"Tapping Home does nothing when already on feed") defaultsKey:@"disable_home_scroll"],
                                            ]
                                        }]
                ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Stories")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"circle.dashed"]
                                        navSections:@[@{
                                            @"header": SCILocalized(@"Action button"),
                                            @"footer": SCILocalized(@"Adds a RyukGram action button next to the eye button on stories with download/share/copy/expand/repost/view-mentions entries. Tap opens the menu by default; change the tap behavior below."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Show action button") subtitle:SCILocalized(@"Inserts a button next to the seen/eye button on story overlays") defaultsKey:@"stories_action_button"],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Default tap action") subtitle:SCILocalized(@"What happens on a single tap. Long-press always opens the full menu") menu:[self menus][@"stories_action_default"]],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Seen receipts"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable story seen receipt") subtitle:SCILocalized(@"Hides the notification for others when you view their story") defaultsKey:@"no_seen_receipt"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Keep stories visually seen locally") subtitle:SCILocalized(@"Marks stories as seen locally (grey ring) while still blocking the seen receipt on the server") defaultsKey:@"keep_seen_visual_local"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Mark seen on story like") subtitle:SCILocalized(@"Marks a story as seen the moment you tap the heart, even with seen blocking on") defaultsKey:@"seen_on_story_like"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Mark seen on story reply") subtitle:SCILocalized(@"Marks a story as seen when you send a reply or emoji reaction, even with seen blocking on") defaultsKey:@"seen_on_story_reply"],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Manual seen button mode") subtitle:SCILocalized(@"Button = single-tap mark seen. Toggle = tap toggles story read receipts on/off (eye fills blue when on)") menu:[self menus][@"story_seen_mode"]],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Playback"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Stop story auto-advance") subtitle:SCILocalized(@"Stories won't auto-skip to the next one when the timer ends. Tap to advance manually") defaultsKey:@"stop_story_auto_advance"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Advance when marking as seen") subtitle:SCILocalized(@"Tapping the eye button to mark a story as seen advances to the next story automatically") defaultsKey:@"advance_on_mark_seen"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Advance on story like") subtitle:SCILocalized(@"Liking a story automatically advances to the next one after a short delay") defaultsKey:@"advance_on_story_like"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Advance on story reply") subtitle:SCILocalized(@"Sending a reply or emoji reaction automatically advances to the next story") defaultsKey:@"advance_on_story_reply"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Story user list"),
                                            @"footer": SCILocalized(@"Block all: all stories blocked — listed users are exceptions.\nBlock selected: only listed users are blocked — everything else is normal.\nBoth lists are saved independently."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Enable story user list") subtitle:SCILocalized(@"Master toggle. When off, the list is ignored") defaultsKey:@"enable_story_user_exclusions"],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Blocking mode") subtitle:SCILocalized(@"Which stories get seen-receipt blocking") menu:[self menus][@"story_blocking_mode"]],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Quick list button in stories") subtitle:SCILocalized(@"Shows an eye button on stories to add/remove users from the list. Off = use the 3-dot menu or long-press only") defaultsKey:@"story_excluded_show_unexclude_eye"],
                                                ({
                                                    SCISetting *s = [SCISetting buttonCellWithTitle:SCILocalized(@"Manage list")
                                                                       subtitle:SCILocalized(@"Search, sort, swipe to remove")
                                                                           icon:[SCISymbol symbolWithName:@"list.bullet.rectangle"]
                                                                         action:^(void) {
                                                        UIWindow *win = nil;
                                                        for (UIWindow *w in [UIApplication sharedApplication].windows) {
                                                            if (w.isKeyWindow) { win = w; break; }
                                                        }
                                                        UIViewController *top = win.rootViewController;
                                                        while (top.presentedViewController) top = top.presentedViewController;
                                                        if ([top isKindOfClass:[UINavigationController class]]) {
                                                            [(UINavigationController *)top pushViewController:[SCIExcludedStoryUsersViewController new] animated:YES];
                                                        } else if (top.navigationController) {
                                                            [top.navigationController pushViewController:[SCIExcludedStoryUsersViewController new] animated:YES];
                                                        }
                                                    }];
                                                    s.dynamicTitle = ^{ return [NSString stringWithFormat:SCILocalized(@"Manage list (%lu)"), (unsigned long)[SCIExcludedStoryUsers count]]; };
                                                    s;
                                                }),
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Audio"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Story audio toggle") subtitle:SCILocalized(@"Adds a speaker button to the story overlay to unmute/mute audio. Also available in the 3-dot menu") defaultsKey:@"story_audio_toggle"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Other"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable instants creation") subtitle:SCILocalized(@"Hides the functionality to create/send instants") defaultsKey:@"disable_instants_creation" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"View story mentions") subtitle:SCILocalized(@"Show mentioned users in eye button and story menu") defaultsKey:@"view_story_mentions"]
                                            ]
                                        }]
                ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Reels")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"film.stack"]
                                        navSections:@[@{
                                            @"header": SCILocalized(@"Action button"),
                                            @"footer": SCILocalized(@"Adds a RyukGram action button above the reel sidebar with view-cover/download/share/copy/expand/repost entries. Tap opens the menu by default; change the tap behavior below."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Show action button") subtitle:SCILocalized(@"Places a button above the like/comment/share column on each reel") defaultsKey:@"reels_action_button"],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Default tap action") subtitle:SCILocalized(@"What happens on a single tap. Long-press always opens the full menu") menu:[self menus][@"reels_action_default"]],
                                            ]
                                        },
                                        @{
                                            @"header": @"",
                                            @"rows": @[
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Tap Controls") subtitle:SCILocalized(@"Change what happens when you tap on a reel") menu:[self menus][@"reels_tap_control"]],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Auto-scroll reels") subtitle:SCILocalized(@"IG default: native behavior. RyukGram: re-advances after swiping back.") menu:[self menus][@"auto_scroll_reels_mode"]],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Always show progress scrubber") subtitle:SCILocalized(@"Forces the progress bar to appear on every reel") defaultsKey:@"reels_show_scrubber"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable auto-unmuting reels") subtitle:SCILocalized(@"Prevents reels from unmuting when the volume/silent button is pressed") defaultsKey:@"disable_auto_unmuting_reels" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm reel refresh") subtitle:SCILocalized(@"Shows an alert when you trigger a reels refresh") defaultsKey:@"refresh_reel_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable tab button refresh") subtitle:SCILocalized(@"Tapping the Reels tab while on reels does nothing") defaultsKey:@"disable_reels_tab_refresh"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Unlock password-locked reels") subtitle:SCILocalized(@"Shows buttons to reveal and auto-fill the password on locked reels") defaultsKey:@"unlock_password_reels"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Hiding"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide reels header") subtitle:SCILocalized(@"Hides the top navigation bar when watching reels") defaultsKey:@"hide_reels_header"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide repost button") subtitle:SCILocalized(@"Hides the repost button on the reels sidebar") defaultsKey:@"hide_reels_repost" requiresRestart:YES]
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Limits"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable scrolling reels") subtitle:SCILocalized(@"Prevents reels from being scrolled to the next video") defaultsKey:@"disable_scrolling_reels" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Prevent doom scrolling") subtitle:SCILocalized(@"Limits the amount of reels available to scroll at any given time, and prevents refreshing") defaultsKey:@"prevent_doom_scrolling"],
                                                [SCISetting stepperCellWithTitle:SCILocalized(@"Doom scrolling limit") subtitle:SCILocalized(@"Only loads %@ %@") defaultsKey:@"doom_scrolling_reel_count" min:1 max:100 step:1 label:@"reels" singularLabel:@"reel"]
                                            ]
                                        }]
                ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Messages")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"bubble.left.and.bubble.right"]
                                        navSections:@[@{
                                            @"header": SCILocalized(@"Threads"),
                                            @"rows": @[
                                                [SCISetting navigationCellWithTitle:SCILocalized(@"Read receipts")
                                                                           subtitle:SCILocalized(@"Control when messages are marked as seen")
                                                                               icon:nil
                                                                        navSections:@[@{
                                                                            @"header": @"",
                                                                            @"rows": @[
                                                                                [SCISetting switchCellWithTitle:SCILocalized(@"Manually mark messages as seen") subtitle:SCILocalized(@"Adds a button to DM threads to mark messages as seen") defaultsKey:@"remove_lastseen"],
                                                                                [SCISetting menuCellWithTitle:SCILocalized(@"Read receipt mode") subtitle:SCILocalized(@"How the seen button behaves") menu:[self menus][@"seen_mode"]],
                                                                                [SCISetting switchCellWithTitle:SCILocalized(@"Auto mark seen on interact") subtitle:SCILocalized(@"Marks messages as seen when you send any message") defaultsKey:@"seen_auto_on_interact"],
                                                                                [SCISetting switchCellWithTitle:SCILocalized(@"Auto mark seen on typing") subtitle:SCILocalized(@"Marks messages as seen when you start typing") defaultsKey:@"seen_auto_on_typing"],
                                                                            ]
                                                                        }]
                                                ],
                                                [SCISetting navigationCellWithTitle:SCILocalized(@"Keep deleted messages")
                                                                           subtitle:SCILocalized(@"Preserve messages that others unsend")
                                                                               icon:nil
                                                                        navSections:@[@{
                                                                            @"header": @"",
                                                                            @"footer": SCILocalized(@"⚠️ Pull-to-refresh in the DMs tab clears all preserved messages. Enable the warning below to get a confirmation dialog."),
                                                                            @"rows": @[
                                                                                [SCISetting switchCellWithTitle:SCILocalized(@"Keep deleted messages") subtitle:SCILocalized(@"Preserves messages that others unsend") defaultsKey:@"keep_deleted_message"],
                                                                                [SCISetting switchCellWithTitle:SCILocalized(@"Indicate unsent messages") subtitle:SCILocalized(@"Shows an \"Unsent\" label on preserved messages") defaultsKey:@"indicate_unsent_messages"],
                                                                                [SCISetting switchCellWithTitle:SCILocalized(@"Unsent message notification") subtitle:SCILocalized(@"Shows a notification pill when a message is unsent") defaultsKey:@"unsent_message_toast"],
                                                                                [SCISetting switchCellWithTitle:SCILocalized(@"Warn before clearing on refresh") subtitle:SCILocalized(@"Confirmation dialog before clearing preserved messages") defaultsKey:@"warn_refresh_clears_preserved"],
                                                                            ]
                                                                        }]
                                                ],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable typing status") subtitle:SCILocalized(@"Hides typing indicator from others") defaultsKey:@"disable_typing_status"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable disappearing mode swipe") subtitle:SCILocalized(@"Prevents accidental swipe-up activation of disappearing mode") defaultsKey:@"disable_disappearing_mode_swipe"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide voice call button") subtitle:SCILocalized(@"Removes the audio call button from DM thread header") defaultsKey:@"hide_voice_call_button"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide video call button") subtitle:SCILocalized(@"Removes the video call button from DM thread header") defaultsKey:@"hide_video_call_button"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide reels blend button") subtitle:SCILocalized(@"Hides the blend button in DMs") defaultsKey:@"hide_reels_blend"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Chat list"),
                                            @"footer": SCILocalized(@"Block all: all chats blocked — listed chats are exceptions.\nBlock selected: only listed chats are blocked — everything else is normal.\nBoth lists are saved independently. Long-press a chat in the inbox to add or remove."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Enable chat list") subtitle:SCILocalized(@"Master toggle. When off, the list is ignored") defaultsKey:@"enable_chat_exclusions"],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Blocking mode") subtitle:SCILocalized(@"Which chats get read-receipt blocking") menu:[self menus][@"chat_blocking_mode"]],
                                                ({
    SCISetting *s = [SCISetting switchCellWithTitle:@"" subtitle:@"" defaultsKey:@"exclusions_default_keep_deleted"];
    s.dynamicTitle = ^{
        BOOL bs = [[SCIUtils getStringPref:@"chat_blocking_mode"] isEqualToString:@"block_selected"];
        return bs ? SCILocalized(@"Block keep-deleted for unlisted chats")
                  : SCILocalized(@"Block keep-deleted for excluded chats");
    };
    s.subtitle = @"Each chat can override this in the list";
    s;
}),
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Quick list button in chats") subtitle:SCILocalized(@"Shows a button in DM threads to add/remove chats from the list. Long-press for more options") defaultsKey:@"chat_quick_list_button"],
                                                ({
                                                    SCISetting *s = [SCISetting buttonCellWithTitle:SCILocalized(@"Manage list")
                                                                       subtitle:SCILocalized(@"Search, sort, swipe to remove or toggle keep-deleted")
                                                                           icon:[SCISymbol symbolWithName:@"list.bullet.rectangle"]
                                                                         action:^(void) {
                                                        UIWindow *win = nil;
                                                        for (UIWindow *w in [UIApplication sharedApplication].windows) {
                                                            if (w.isKeyWindow) { win = w; break; }
                                                        }
                                                        UIViewController *top = win.rootViewController;
                                                        while (top.presentedViewController) top = top.presentedViewController;
                                                        if ([top isKindOfClass:[UINavigationController class]]) {
                                                            [(UINavigationController *)top pushViewController:[SCIExcludedChatsViewController new] animated:YES];
                                                        } else if (top.navigationController) {
                                                            [top.navigationController pushViewController:[SCIExcludedChatsViewController new] animated:YES];
                                                        }
                                                    }];
                                                    s.dynamicTitle = ^{ return [NSString stringWithFormat:SCILocalized(@"Manage list (%lu)"), (unsigned long)[SCIExcludedThreads count]]; };
                                                    s;
                                                }),
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Activity"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Full last active date") subtitle:SCILocalized(@"Show full date instead of \"Active 2h ago\"") defaultsKey:@"dm_full_last_active"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Files"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Send files (experimental)") subtitle:SCILocalized(@"Adds a 'Send File' option to the plus menu in DMs. Supported file types may be limited by Instagram") defaultsKey:@"send_file"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Voice messages"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Send audio as file") subtitle:SCILocalized(@"Adds an 'Audio File' option to the plus menu in DMs to send audio files as voice messages") defaultsKey:@"send_audio_as_file"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Download voice messages") subtitle:SCILocalized(@"Adds a 'Download' option to the long-press menu on voice messages to save them as M4A audio") defaultsKey:@"download_audio_message"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Notes"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Note actions") subtitle:SCILocalized(@"Adds copy text, download GIF/audio to the note long-press menu") defaultsKey:@"note_actions"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Copy text on hold") subtitle:SCILocalized(@"Copies note text directly on long press without opening the menu") defaultsKey:@"note_copy_on_hold"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Enable note theming") subtitle:SCILocalized(@"Enables the notes theme picker") defaultsKey:@"enable_notes_customization"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Custom note themes") subtitle:SCILocalized(@"Custom emojis and background/text colors") defaultsKey:@"custom_note_themes"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Visual messages"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Unlimited replay of visual messages") subtitle:SCILocalized(@"Replay visual messages without expiring. Toggle in the eye button menu, or as a standalone button when the eye button is disabled") defaultsKey:@"unlimited_replay"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable view-once limitations") subtitle:SCILocalized(@"Makes view-once messages behave like normal visual messages (loopable/pauseable)") defaultsKey:@"disable_view_once_limitations"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable screenshot detection") subtitle:SCILocalized(@"Removes the screenshot-prevention features for visual messages in DMs") defaultsKey:@"remove_screenshot_alert"],
                                            ]
                                        }]
                ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Profile")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"person.crop.circle"]
                                        navSections:@[@{
                                            @"header": @"",
                                            @"footer": SCILocalized(@"Long-press gestures on profile elements — kept separate from the per-feature action buttons."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Zoom profile photo") subtitle:SCILocalized(@"Long press a profile picture to open it in full-screen with zoom, share, and save") defaultsKey:@"zoom_profile_photo"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Save profile picture") subtitle:SCILocalized(@"Long press to download directly (ignored when zoom is on)") defaultsKey:@"save_profile"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"View highlight cover") subtitle:SCILocalized(@"Adds a view option to the highlight long-press menu to open the cover in full-screen") defaultsKey:@"download_highlight_cover"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Profile copy button") subtitle:SCILocalized(@"Adds a button next to the burger menu on profiles to copy username, name or bio") defaultsKey:@"profile_copy_button"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Follow indicator") subtitle:SCILocalized(@"Shows whether the profile user follows you") defaultsKey:@"follow_indicator"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Copy note on long press") subtitle:SCILocalized(@"Long press the note bubble on a profile to copy the text") defaultsKey:@"profile_note_copy"],
                                            ]
                                        }]
                ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Navigation")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"hand.draw.fill"]
                                        navSections:@[@{
                                            @"header": @"",
                                            @"rows": @[
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Icon order") subtitle:SCILocalized(@"The order of the icons on the bottom navigation bar") menu:[self menus][@"nav_icon_ordering"]],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Swipe between tabs") subtitle:SCILocalized(@"Lets you swipe to switch between navigation bar tabs") menu:[self menus][@"swipe_nav_tabs"]],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Launch tab") subtitle:SCILocalized(@"Tab the app opens to. Ignored when Messages-only is on") menu:[self menus][@"launch_tab"]],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Hiding tabs"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide feed tab") subtitle:SCILocalized(@"Hides the feed/home tab on the bottom navigation bar") defaultsKey:@"hide_feed_tab" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide explore tab") subtitle:SCILocalized(@"Hides the explore/search tab on the bottom navigation bar") defaultsKey:@"hide_explore_tab" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide reels tab") subtitle:SCILocalized(@"Hides the reels tab on the bottom navigation bar") defaultsKey:@"hide_reels_tab" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide create tab") subtitle:SCILocalized(@"Hides the create tab on the bottom navigation bar") defaultsKey:@"hide_create_tab" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Hide messages tab") subtitle:SCILocalized(@"Hides the direct messages tab on the bottom navigation bar") defaultsKey:@"hide_messages_tab" requiresRestart:YES]
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Messages-only mode"),
                                            @"footer": SCILocalized(@"Hides every tab except DM inbox + profile and forces launch into the inbox. Settings shortcut moves to long-press on the inbox tab."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Messages only") subtitle:SCILocalized(@"Turn IG into a DM-only client") defaultsKey:@"messages_only" requiresRestart:YES],
                                            ]
                                        }]
                ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Saving")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"tray.and.arrow.down"]
                                        navSections:@[@{
                                            @"header": SCILocalized(@"Downloads"),
                                            @"footer": SCILocalized(@"When \"Save to RyukGram album\" is on, downloads and share-sheet \"Save to Photos\" picks are routed into a dedicated \"RyukGram\" album in your Photos library."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm before download") subtitle:SCILocalized(@"Show a confirmation dialog before starting a download") defaultsKey:@"dw_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Save to RyukGram album") subtitle:SCILocalized(@"Route saves into a dedicated album in Photos instead of the camera roll root") defaultsKey:@"save_to_ryukgram_album"]
                                            ]
                                        },
                                        [self enhancedDownloadsSection],
                                        @{
                                            @"header": SCILocalized(@"Legacy long-press gesture"),
                                            @"footer": SCILocalized(@"Deprecated. The RyukGram action button (configured per feature in Feed/Reels/Stories) is the new way to download media. Enable this master toggle only if you prefer the old multi-finger long-press directly on the media."),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Enable long-press gesture") subtitle:SCILocalized(@"Master toggle for the deprecated gesture workflow (off by default)") defaultsKey:@"dw_legacy_gesture"],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Save action") subtitle:SCILocalized(@"What happens after the gesture downloads") menu:[self menus][@"dw_save_action"]],
                                                [SCISetting stepperCellWithTitle:SCILocalized(@"Finger count for long-press") subtitle:SCILocalized(@"Downloads with %@ %@") defaultsKey:@"dw_finger_count" min:1 max:5 step:1 label:@"fingers" singularLabel:@"finger"],
                                                [SCISetting stepperCellWithTitle:SCILocalized(@"Long-press hold time") subtitle:SCILocalized(@"Press finger(s) for %@ %@") defaultsKey:@"dw_finger_duration" min:0 max:10 step:0.25 label:@"sec" singularLabel:@"sec"]
                                            ]
                                        }]
                ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Confirm actions")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"checkmark"]
                                        navSections:@[@{
                                            @"header": @"",
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm like: Posts") subtitle:SCILocalized(@"Shows an alert when you click the like button on posts to confirm the like") defaultsKey:@"like_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm like: Reels") subtitle:SCILocalized(@"Shows an alert when you click the like button on reels to confirm the like") defaultsKey:@"like_confirm_reels"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm story like") subtitle:SCILocalized(@"Shows an alert when you click the like button on stories to confirm the like") defaultsKey:@"story_like_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm story emoji reaction") subtitle:SCILocalized(@"Shows an alert before sending an emoji reaction on a story") defaultsKey:@"emoji_reaction_confirm"]
                                            ]
                                        },
                                        @{
                                            @"header": @"",
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm follow") subtitle:SCILocalized(@"Shows an alert when you click the follow button to confirm the follow") defaultsKey:@"follow_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm unfollow") subtitle:SCILocalized(@"Shows an alert when you click the unfollow button to confirm") defaultsKey:@"unfollow_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm repost") subtitle:SCILocalized(@"Shows an alert when you click the repost button to confirm before resposting") defaultsKey:@"repost_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm call") subtitle:SCILocalized(@"Shows an alert when you click the audio/video call button to confirm before calling") defaultsKey:@"call_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm voice messages") subtitle:SCILocalized(@"Shows an alert to confirm before sending a voice message") defaultsKey:@"voice_message_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm follow requests") subtitle:SCILocalized(@"Shows an alert when you accept/decline a follow request") defaultsKey:@"follow_request_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm shh mode") subtitle:SCILocalized(@"Shows an alert to confirm before toggling disappearing messages") defaultsKey:@"shh_mode_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm posting comment") subtitle:SCILocalized(@"Shows an alert when you click the post comment button to confirm") defaultsKey:@"post_comment_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm changing theme") subtitle:SCILocalized(@"Shows an alert when you change a chat theme to confirm") defaultsKey:@"change_direct_theme_confirm"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Confirm sticker interaction") subtitle:SCILocalized(@"Shows an alert when you click a sticker on someone's story to confirm the action") defaultsKey:@"sticker_interact_confirm"]
                                            ]
                                        }]
                ]
            ]
        },
        @{
            @"header": @"",
            @"rows": @[
                [SCISetting navigationCellWithTitle:SCILocalized(@"Fake location")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"location.fill.viewfinder"]
                                     viewController:[[SCIFakeLocationSettingsVC alloc] init]],
            ]
        },
        @{
            @"header": @"",
            @"rows": @[
                [SCISetting navigationCellWithTitle:SCILocalized(@"Backup & Restore")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"arrow.up.arrow.down.square"]
                                        navSections:@[@{
                                            @"header": @"",
                                            @"footer": SCILocalized(@"Export your RyukGram settings to a JSON file and import them later. Importing resets all settings to defaults before applying the imported values, and shows a preview before anything changes."),
                                            @"rows": @[
                                                [SCISetting buttonCellWithTitle:SCILocalized(@"Export settings")
                                                                       subtitle:SCILocalized(@"Save settings as a JSON file")
                                                                           icon:[SCISymbol symbolWithName:@"square.and.arrow.up"]
                                                                         action:^(void) { [SCISettingsBackup presentExport]; }
                                                ],
                                                [SCISetting buttonCellWithTitle:SCILocalized(@"Import settings")
                                                                       subtitle:SCILocalized(@"Load settings from a JSON file")
                                                                           icon:[SCISymbol symbolWithName:@"square.and.arrow.down"]
                                                                         action:^(void) { [SCISettingsBackup presentImport]; }
                                                ],
                                                [SCISetting buttonCellWithTitle:SCILocalized(@"Reset to defaults")
                                                                       subtitle:SCILocalized(@"Revert every RyukGram preference")
                                                                           icon:[SCISymbol symbolWithName:@"arrow.counterclockwise.circle"]
                                                                         action:^(void) { [SCISettingsBackup presentReset]; }
                                                ]
                                            ]
                                        }]
                ],
                // [SCISetting navigationCellWithTitle:SCILocalized(@"Experimental")
                //                            subtitle:@""
                //                                icon:[SCISymbol symbolWithName:@"testtube.2"]
                //                         navSections:@[@{
                //                             @"header": SCILocalized(@"Warning"),
                //                             @"footer": SCILocalized(@"These features are unstable and cause the Instagram app to crash unexpectedly.\n\nUse at your own risk!")
                //                         },
                //                         @{
                //                             @"header": @"",
                //                             @"rows": @[

                //                             ]
                //                         }
                //                         ]
                // ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Advanced")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"gearshape.2"]
                                        navSections:@[@{
                                            @"header": SCILocalized(@"Settings"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Enable tweak settings quick-access") subtitle:SCILocalized(@"Hold on the home tab to open RyukGram settings") defaultsKey:@"settings_shortcut" requiresRestart:YES],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Show tweak settings on app launch") subtitle:SCILocalized(@"Automatically opens settings when the app launches") defaultsKey:@"tweak_settings_app_launch"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Pause playback when opening settings") subtitle:SCILocalized(@"Pauses any playing video/audio when settings opens") defaultsKey:@"settings_pause_playback"],
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"Instagram"),
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Disable safe mode") subtitle:SCILocalized(@"Prevents Instagram from resetting settings after crashes (at your own risk)") defaultsKey:@"disable_safe_mode"],
                                                [SCISetting buttonCellWithTitle:SCILocalized(@"Reset onboarding state")
                                                                           subtitle:@""
                                                                               icon:nil
                                                                             action:^(void) { [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"SCInstaFirstRun"]; [SCIUtils showRestartConfirmation];}
                                                ],
                                            ]
                                        }]
                ],
                [SCISetting navigationCellWithTitle:SCILocalized(@"Debug")
                                           subtitle:@""
                                               icon:[SCISymbol symbolWithName:@"ladybug"]
                                        navSections:@[@{
                                            @"header": SCILocalized(@"Localization"),
                                            @"footer": SCILocalized(@"Import a .strings file to update a translation. Pick a language, select the file, restart."),
                                            @"rows": @[
                                                [SCISetting buttonCellWithTitle:SCILocalized(@"Update localization file")
                                                                       subtitle:SCILocalized(@"Import a .strings file for a language")
                                                                           icon:[SCISymbol symbolWithName:@"square.and.arrow.down"]
                                                                         action:^(void) { [self presentLocalizationImport]; }
                                                ],
                                                [SCISetting buttonCellWithTitle:SCILocalized(@"Export English strings")
                                                                       subtitle:SCILocalized(@"Share the base English .strings file for translating")
                                                                           icon:[SCISymbol symbolWithName:@"square.and.arrow.up"]
                                                                         action:^(void) { [self exportEnglishStrings]; }
                                                ],
                                            ]
                                        },
                                        @{
                                            @"header": @"FLEX",
                                            @"rows": @[
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Enable FLEX gesture") subtitle:SCILocalized(@"Hold 5 fingers on the screen to open FLEX") defaultsKey:@"flex_instagram"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Open FLEX on app launch") subtitle:SCILocalized(@"Opens FLEX when the app launches") defaultsKey:@"flex_app_launch"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Open FLEX on app focus") subtitle:SCILocalized(@"Opens FLEX when the app is focused") defaultsKey:@"flex_app_start"]
                                            ]
                                        },
                                        @{
                                            @"header": SCILocalized(@"_ Example"),
                                            @"rows": @[
                                                [SCISetting staticCellWithTitle:SCILocalized(@"Static Cell") subtitle:@"" icon:[SCISymbol symbolWithName:@"tablecells"]],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Switch Cell") subtitle:SCILocalized(@"Tap the switch") defaultsKey:@"test_switch_cell"],
                                                [SCISetting switchCellWithTitle:SCILocalized(@"Switch Cell (Restart)") subtitle:SCILocalized(@"Tap the switch") defaultsKey:@"test_switch_cell_restart" requiresRestart:YES],
                                                [SCISetting stepperCellWithTitle:SCILocalized(@"Stepper cell") subtitle:SCILocalized(@"I have %@%@") defaultsKey:@"test_stepper_cell" min:-10 max:1000 step:5.5 label:@"$" singularLabel:@"$"],
                                                [SCISetting linkCellWithTitle:SCILocalized(@"Link Cell") subtitle:SCILocalized(@"Using icon") icon:[SCISymbol symbolWithName:@"link" color:[UIColor systemTealColor] size:20.0] url:@"https://google.com"],
                                                [SCISetting linkCellWithTitle:SCILocalized(@"Link Cell") subtitle:SCILocalized(@"Using image") imageUrl:@"https://i.imgur.com/c9CbytZ.png" url:@"https://google.com"],
                                                [SCISetting buttonCellWithTitle:SCILocalized(@"Button Cell")
                                                                           subtitle:@""
                                                                               icon:[SCISymbol symbolWithName:@"oval.inset.filled"]
                                                                             action:^(void) { [SCIUtils showConfirmation:^(void){}]; }
                                                ],
                                                [SCISetting menuCellWithTitle:SCILocalized(@"Menu Cell") subtitle:SCILocalized(@"Change the value on the right") menu:[self menus][@"test"]],
                                                [SCISetting navigationCellWithTitle:SCILocalized(@"Navigation Cell")
                                                                           subtitle:@""
                                                                               icon:[SCISymbol symbolWithName:@"rectangle.stack"]
                                                                        navSections:@[@{
                                                                            @"header": @"",
                                                                            @"rows": @[]
                                                                        }]
                                                ]
                                            ],
                                            @"footer": SCILocalized(@"_ Example")
                                        }
                                        ]
                ]
            ]
        },
        @{
            @"header": SCILocalized(@"Credits"),
            @"rows": @[
                [SCISetting linkCellWithTitle:SCILocalized(@"Ryuk") subtitle:SCILocalized(@"Developer") imageUrl:@"https://github.com/faroukbmiled.png" url:@"https://github.com/faroukbmiled"],
                [SCISetting linkCellWithTitle:SCILocalized(@"View Repo") subtitle:SCILocalized(@"View the source code on GitHub") imageUrl:@"https://i.imgur.com/BBUNzeP.png" url:@"https://github.com/faroukbmiled/RyukGram"],
                [SCISetting linkCellWithTitle:SCILocalized(@"SoCuul") subtitle:SCILocalized(@"Original SCInsta developer") imageUrl:@"https://i.imgur.com/c9CbytZ.png" url:@"https://github.com/SoCuul/SCInsta"],
                [SCISetting linkCellWithTitle:SCILocalized(@"Donate to SoCuul") subtitle:SCILocalized(@"Support the original developer") icon:[SCISymbol symbolWithName:@"heart.circle.fill" color:[UIColor systemPinkColor] size:20.0] url:@"https://ko-fi.com/SoCuul"]
            ],
            @"footer": [NSString stringWithFormat:SCILocalized(@"RyukGram %@\n\nInstagram v%@\n\nBased on SCInsta by SoCuul"), SCIVersionString, [SCIUtils IGVersionString]]
        }
    ];
}


// MARK: - Enhanced downloads section

+ (NSDictionary *)enhancedDownloadsSection {
    BOOL ffmpegAvailable = [SCIFFmpeg isAvailable];
    BOOL disabled = !ffmpegAvailable;

    NSString *footer = ffmpegAvailable
        ? SCILocalized(@"Downloads HD video via DASH streams and encodes to H.264. Requires FFmpegKit.")
        : SCILocalized(@"FFmpegKit is not available. Install the sideloaded IPA or the _ffmpeg .deb variant to enable.");

    SCISetting *toggle = [SCISetting switchCellWithTitle:SCILocalized(@"Enhanced downloads")
                                               subtitle:SCILocalized(@"Download video at the highest available quality")
                                            defaultsKey:@"enhance_download_quality"];
    toggle.disabled = disabled;

    SCISetting *videoQuality = [SCISetting menuCellWithTitle:SCILocalized(@"Video quality")
                                                   subtitle:SCILocalized(@"Which quality to download")
                                                       menu:[self menus][@"default_video_quality"]];
    videoQuality.disabled = disabled;

    SCISetting *photoQuality = [SCISetting menuCellWithTitle:SCILocalized(@"Photo quality")
                                                   subtitle:SCILocalized(@"Use highest resolution available")
                                                       menu:[self menus][@"default_photo_quality"]];
    photoQuality.disabled = disabled;

    SCISetting *encodingSpeed = [SCISetting menuCellWithTitle:SCILocalized(@"Encoding speed")
                                                    subtitle:SCILocalized(@"Faster = lower quality")
                                                        menu:[self menus][@"ffmpeg_encoding_speed"]];
    encodingSpeed.disabled = disabled;

    return @{
        @"header": SCILocalized(@"Enhanced downloads"),
        @"footer": footer,
        @"rows": @[toggle, videoQuality, photoQuality, encodingSpeed]
    };
}


// MARK: - Date format

+ (SCISetting *)dateFormatNavCell {
    SCISetting *cell = [SCISetting navigationCellWithTitle:SCILocalized(@"Date format")
                                                 subtitle:@""
                                                     icon:nil
                                           viewController:[[SCIDateFormatPickerVC alloc] init]];
    cell.dynamicTitle = ^{
        NSString *ex = [SCIDateFormatPickerVC currentFormatExample];
        return [NSString stringWithFormat:SCILocalized(@"Date format — %@"), ex];
    };
    return cell;
}

// MARK: - Title

///
/// This is the title displayed on the initial settings page view controller
///

+ (NSString *)title {
    return SCILocalized(@"settings.title");
}

// MARK: - Localization import

static UIViewController *sciTopVC(void) {
    UIViewController *top = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (!w.isKeyWindow) continue;
        top = w.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
    }
    return top;
}


+ (void)exportEnglishStrings {
    NSBundle *res = SCILocalizationBundle();
    NSString *path = [res pathForResource:@"en" ofType:@"lproj"];
    if (path) path = [path stringByAppendingPathComponent:@"Localizable.strings"];
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [SCIUtils showErrorHUDWithDescription:@"English .strings file not found"];
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    UIActivityViewController *ac = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    UIViewController *top = sciTopVC();
    if (!top) return;
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        ac.popoverPresentationController.sourceView = top.view;
        ac.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
    }
    [top presentViewController:ac animated:YES completion:nil];
}

+ (void)presentLocalizationImport {
    NSArray *langs = SCIAvailableLanguages();

    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Update localization"
                                                                    message:@"Pick a language to update, or add a new one"
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *lang in langs) {
        NSString *code = lang[@"code"];
        if ([code isEqualToString:@"system"]) continue;
        NSString *title = [NSString stringWithFormat:@"%@ (%@)", lang[@"native"], code];
        [picker addAction:[UIAlertAction actionWithTitle:title
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(__unused UIAlertAction *a) {
            [self importStringsForLanguage:code];
        }]];
    }

    [picker addAction:[UIAlertAction actionWithTitle:@"+ Add new language"
                                               style:UIAlertActionStyleDefault
                                             handler:^(__unused UIAlertAction *a) {
        [self promptNewLanguageCode];
    }]];
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [sciTopVC() presentViewController:picker animated:YES completion:nil];
}

+ (void)promptNewLanguageCode {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add language"
                                                                   message:@"Enter the language code (e.g. fr, de, ja)"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"fr"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Next" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        NSString *code = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (code.length < 2 || code.length > 5) return;
        [self importStringsForLanguage:code];
    }]];
    [sciTopVC() presentViewController:alert animated:YES completion:nil];
}

+ (void)importStringsForLanguage:(NSString *)langCode {
    UIViewController *top = sciTopVC();
    if (!top) return;

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *dp = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.plain-text", @"com.apple.xcode.strings-text", @"public.data"] inMode:UIDocumentPickerModeImport];
    #pragma clang diagnostic pop

    dp.allowsMultipleSelection = NO;
    dp.delegate = (id<UIDocumentPickerDelegate>)[self sharedImportHelper];
    objc_setAssociatedObject(dp, "sci_lang", [langCode copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    [top presentViewController:dp animated:YES completion:nil];
}

+ (id)sharedImportHelper {
    static id helper = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        helper = [SCILocImportHelper new];
    });
    return helper;
}

// MARK: - Menus

///
/// This returns a dictionary where each key corresponds to a certain menu that can be displayed.
/// Each "propertyList"  item is an NSDictionary containing the following items:
///
/// `"defaultsKey"`: The key to save the selected value under in NSUserDefaults
///
/// `"value"`: A unique string corresponding to the menu item which is selected
///
/// `"requiresRestart"`: (optional) Causes a popup to appear detailing you have to restart to use these features
///

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

// Builds the default-tap-action picker menu for a given action button context.
// Adding a new tap action = one entry here. Order: actions first, downloads last.
+ (UIMenu *)defaultTapMenuForKey:(NSString *)key context:(NSString *)ctx {
    // { value, title, contexts ("all" or csv of feed,reels,stories) }
    NSArray *entries = @[
        @[@"menu",           SCILocalized(@"Open menu"),          @"all"],
        @[@"expand",         SCILocalized(@"Expand"),             @"all"],
        @[@"repost",         SCILocalized(@"Repost"),             @"all"],
        @[@"view_mentions",  SCILocalized(@"View mentions"),      @"stories"],
        @[@"copy_link",      SCILocalized(@"Copy download URL"),  @"all"],
        @[@"download_share", SCILocalized(@"Download and share"), @"all"],
        @[@"download_photos",SCILocalized(@"Download to Photos"), @"all"],
    ];
    NSMutableArray *children = [NSMutableArray array];
    for (NSArray *e in entries) {
        NSString *contexts = e[2];
        if (![contexts isEqualToString:@"all"] && ![contexts containsString:ctx]) continue;
        [children addObject:[UICommand commandWithTitle:e[1] image:nil
                                                 action:@selector(menuChanged:)
                                           propertyList:@{@"defaultsKey": key, @"value": e[0]}]];
    }
    return [UIMenu menuWithChildren:children];
}

+ (NSDictionary *)menus {
    return @{
        @"chat_blocking_mode": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Block all")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{ @"defaultsKey": @"chat_blocking_mode", @"value": @"block_all" }
            ],
            [UICommand commandWithTitle:SCILocalized(@"Block selected")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{ @"defaultsKey": @"chat_blocking_mode", @"value": @"block_selected" }
            ]
        ]],

        @"story_blocking_mode": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Block all")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{ @"defaultsKey": @"story_blocking_mode", @"value": @"block_all" }
            ],
            [UICommand commandWithTitle:SCILocalized(@"Block selected")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{ @"defaultsKey": @"story_blocking_mode", @"value": @"block_selected" }
            ]
        ]],

        @"story_seen_mode": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Button")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{
                                @"defaultsKey": @"story_seen_mode",
                                @"value": @"button"
                            }
            ],
            [UICommand commandWithTitle:SCILocalized(@"Toggle")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{
                                @"defaultsKey": @"story_seen_mode",
                                @"value": @"toggle"
                            }
            ]
        ]],

        @"seen_mode": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Button")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{
                                @"defaultsKey": @"seen_mode",
                                @"value": @"button"
                            }
            ],
            [UICommand commandWithTitle:SCILocalized(@"Toggle")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{
                                @"defaultsKey": @"seen_mode",
                                @"value": @"toggle"
                            }
            ]
        ]],

        @"dw_save_action": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Share sheet")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{
                                @"defaultsKey": @"dw_save_action",
                                @"value": @"share"
                            }
            ],
            [UICommand commandWithTitle:SCILocalized(@"Save to Photos")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{
                                @"defaultsKey": @"dw_save_action",
                                @"value": @"photos"
                            }
            ]
        ]],

        @"feed_action_default":    [self defaultTapMenuForKey:@"feed_action_default"    context:@"feed"],
        @"reels_action_default":   [self defaultTapMenuForKey:@"reels_action_default"   context:@"reels"],
        @"stories_action_default": [self defaultTapMenuForKey:@"stories_action_default" context:@"stories"],

        @"default_video_quality": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Always ask") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"default_video_quality", @"value": @"always_ask"}],
            [UICommand commandWithTitle:SCILocalized(@"High") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"default_video_quality", @"value": @"high"}],
            [UICommand commandWithTitle:SCILocalized(@"Medium") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"default_video_quality", @"value": @"medium"}],
            [UICommand commandWithTitle:SCILocalized(@"Low") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"default_video_quality", @"value": @"low"}],
        ]],
        @"default_photo_quality": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"High") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"default_photo_quality", @"value": @"high"}],
            [UICommand commandWithTitle:SCILocalized(@"Standard") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"default_photo_quality", @"value": @"standard"}],
        ]],
        @"ffmpeg_encoding_speed": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Fast") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"ffmpeg_encoding_speed", @"value": @"ultrafast"}],
            [UICommand commandWithTitle:SCILocalized(@"Balanced") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"ffmpeg_encoding_speed", @"value": @"veryfast"}],
            [UICommand commandWithTitle:SCILocalized(@"Quality") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"ffmpeg_encoding_speed", @"value": @"fast"}],
            [UICommand commandWithTitle:SCILocalized(@"Max") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"ffmpeg_encoding_speed", @"value": @"max"}],
        ]],

        @"reels_tap_control": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Default")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{
                                @"defaultsKey": @"reels_tap_control",
                                @"value": @"default",
                                @"requiresRestart": @YES
                            }
            ],
            [UIMenu menuWithTitle:@""
                            image:nil
                        identifier:nil
                            options:UIMenuOptionsDisplayInline
                            children:@[
                                [UICommand commandWithTitle:SCILocalized(@"Pause/Play")
                                                        image:nil
                                                        action:@selector(menuChanged:)
                                                propertyList:@{
                                                    @"defaultsKey": @"reels_tap_control",
                                                    @"value": @"pause",
                                                    @"requiresRestart": @YES
                                                }
                                ],
                                [UICommand commandWithTitle:SCILocalized(@"Mute/Unmute")
                                                        image:nil
                                                        action:@selector(menuChanged:)
                                                propertyList:@{
                                                    @"defaultsKey": @"reels_tap_control",
                                                    @"value": @"mute",
                                                    @"requiresRestart": @YES
                                                }
                                ]
                            ]
            ]
        ]],

        @"auto_scroll_reels_mode": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Off") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"auto_scroll_reels_mode", @"value": @"off"}],
            [UICommand commandWithTitle:SCILocalized(@"IG default") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"auto_scroll_reels_mode", @"value": @"ig"}],
            [UICommand commandWithTitle:SCILocalized(@"RyukGram") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"auto_scroll_reels_mode", @"value": @"custom"}],
        ]],

        @"launch_tab": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Default") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"default"}],
            [UICommand commandWithTitle:SCILocalized(@"Feed") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"feed"}],
            [UICommand commandWithTitle:SCILocalized(@"Explore") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"explore"}],
            [UICommand commandWithTitle:SCILocalized(@"Reels") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"reels"}],
            [UICommand commandWithTitle:SCILocalized(@"Inbox") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"inbox"}],
            [UICommand commandWithTitle:SCILocalized(@"Profile") image:nil action:@selector(menuChanged:)
                           propertyList:@{@"defaultsKey": @"launch_tab", @"value": @"profile"}],
        ]],
        @"nav_icon_ordering": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Default")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{
                                @"defaultsKey": @"nav_icon_ordering",
                                @"value": @"default",
                                @"requiresRestart": @YES
                            }
            ],
            [UIMenu menuWithTitle:@""
                            image:nil
                        identifier:nil
                            options:UIMenuOptionsDisplayInline
                            children:@[
                                [UICommand commandWithTitle:SCILocalized(@"Classic")
                                                        image:nil
                                                        action:@selector(menuChanged:)
                                                propertyList:@{
                                                    @"defaultsKey": @"nav_icon_ordering",
                                                    @"value": @"classic",
                                                    @"requiresRestart": @YES
                                                }
                                ],
                                [UICommand commandWithTitle:SCILocalized(@"Standard")
                                                        image:nil
                                                        action:@selector(menuChanged:)
                                                propertyList:@{
                                                    @"defaultsKey": @"nav_icon_ordering",
                                                    @"value": @"standard",
                                                    @"requiresRestart": @YES
                                                }
                                ],
                                [UICommand commandWithTitle:SCILocalized(@"Alternate")
                                                        image:nil
                                                        action:@selector(menuChanged:)
                                                propertyList:@{
                                                    @"defaultsKey": @"nav_icon_ordering",
                                                    @"value": @"alternate",
                                                    @"requiresRestart": @YES
                                                }
                                ]
                            ]
            ]
        ]],
        @"swipe_nav_tabs": [UIMenu menuWithChildren:@[
            [UICommand commandWithTitle:SCILocalized(@"Default")
                                    image:nil
                                    action:@selector(menuChanged:)
                            propertyList:@{
                                @"defaultsKey": @"swipe_nav_tabs",
                                @"value": @"default",
                                @"requiresRestart": @YES
                            }
            ],
            [UIMenu menuWithTitle:@""
                            image:nil
                        identifier:nil
                            options:UIMenuOptionsDisplayInline
                            children:@[
                                [UICommand commandWithTitle:SCILocalized(@"Enabled")
                                                        image:nil
                                                        action:@selector(menuChanged:)
                                                propertyList:@{
                                                    @"defaultsKey": @"swipe_nav_tabs",
                                                    @"value": @"enabled",
                                                    @"requiresRestart": @YES
                                                }
                                ],
                                [UICommand commandWithTitle:SCILocalized(@"Disabled")
                                                        image:nil
                                                        action:@selector(menuChanged:)
                                                propertyList:@{
                                                    @"defaultsKey": @"swipe_nav_tabs",
                                                    @"value": @"disabled",
                                                    @"requiresRestart": @YES
                                                }
                                ]
                            ]
            ]
        ]],

        @"test": [UIMenu menuWithChildren:@[
            [UIMenu menuWithTitle:@""
                            image:nil
                        identifier:nil
                            options:UIMenuOptionsDisplayInline
                            children:@[
                                [UICommand commandWithTitle:@"ABC"
                                                        image:nil
                                                        action:@selector(menuChanged:)
                                                propertyList:@{
                                                    @"defaultsKey": @"test_menu_cell",
                                                    @"value": @"abc"
                                                }
                                ],
                                [UICommand commandWithTitle:@"123"
                                                        image:nil
                                                        action:@selector(menuChanged:)
                                                propertyList:@{
                                                    @"defaultsKey": @"test_menu_cell",
                                                    @"value": @"123"
                                                }
                                ]
                            ]
            ],
            [UICommand commandWithTitle:SCILocalized(@"Requires restart")
                                  image:nil
                                 action:@selector(menuChanged:)
                           propertyList:@{
                               @"defaultsKey": @"test_menu_cell",
                               @"value": @"requires_restart",
                               @"requiresRestart": @YES
                           }
            ],
        ]]
    };
}

#pragma clang diagnostic pop

@end
