// Download voice messages from DMs
// Hooks IGDirectMessageMenuConfiguration to detect audio messages, then injects a "Download"
// item into the IGDSPrismMenuView long-press menu. Downloads the audio via the playbackURL
// on IGAudio (accessed through vm -> audio -> _server_audio), converts mp4 to m4a, and
// presents a share sheet.
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <AVFoundation/AVFoundation.h>
#import "../../Downloader/Download.h"

typedef id (*SCIMsgSendId)(id, SEL);
static inline id sciDAF(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((SCIMsgSendId)objc_msgSend)(obj, sel);
}

// Flag set by menuConfig hook when a voice_media menu is about to be created
static BOOL sciAudioMenuPending = NO;
static id sciLastAudioViewModel = nil;

#pragma mark - Detect audio message long-press

// Demangled: IGDirectMessageMenuConfiguration.IGDirectMessageMenuConfiguration
%hook _TtC32IGDirectMessageMenuConfiguration32IGDirectMessageMenuConfiguration

+ (id)menuConfigurationWithEligibleOptions:(id)options
                          messageViewModel:(id)arg2
                               contentType:(id)arg3
                                 isSticker:(_Bool)arg4
                            isMusicSticker:(_Bool)arg5
                          directNuxManager:(id)arg6
                       sessionUserDefaults:(id)arg7
                               launcherSet:(id)arg8
                               userSession:(id)arg9
                                tapHandler:(id)arg10
{
    if ([SCIUtils getBoolPref:@"download_audio_message"] &&
        [arg3 isKindOfClass:[NSString class]] && [arg3 isEqualToString:@"voice_media"]) {
        sciAudioMenuPending = YES;
        sciLastAudioViewModel = arg2;
    }
    return %orig;
}

%end

#pragma mark - Inject Download item into PrismMenu

// PrismMenu uses Swift classes — must use MSHookMessageEx with runtime class lookup
// (dot-notation names like liquid glass hooks in Tweak.x)

static id (*orig_prismMenuView_init3)(id, SEL, NSArray *, id, BOOL);

static id new_prismMenuView_init3(id self, SEL _cmd, NSArray *elements, id header, BOOL edr) {
    if (!sciAudioMenuPending) return orig_prismMenuView_init3(self, _cmd, elements, header, edr);
    sciAudioMenuPending = NO;

    if (![SCIUtils getBoolPref:@"download_audio_message"])
        return orig_prismMenuView_init3(self, _cmd, elements, header, edr);

    Class builderClass = NSClassFromString(@"IGDSPrismMenuItemBuilder");
    Class elementClass = NSClassFromString(@"IGDSPrismMenuElement");
    if (!builderClass || !elementClass || elements.count == 0)
        return orig_prismMenuView_init3(self, _cmd, elements, header, edr);

    typedef id (*InitFn)(id, SEL, id);
    typedef id (*WithFn)(id, SEL, id);
    typedef id (*BuildFn)(id, SEL);

    id capturedVM = sciLastAudioViewModel;
    void (^handler)(void) = ^{
        if (!capturedVM) return;

        // Audio URL path: vm -> audio (IGDirectAudio) -> _server_audio (IGAudio) -> playbackURL
        id directAudio = nil;
        @try { directAudio = [capturedVM valueForKey:@"audio"]; } @catch (NSException *e) {}
        if (!directAudio) {
            [SCIUtils showErrorHUDWithDescription:@"Could not get audio data. Try again after refreshing the chat."];
            return;
        }

        Ivar serverAudioIvar = class_getInstanceVariable([directAudio class], "_server_audio");
        id serverAudio = serverAudioIvar ? object_getIvar(directAudio, serverAudioIvar) : nil;
        if (!serverAudio) {
            [SCIUtils showErrorHUDWithDescription:@"Audio not loaded yet. Play the message first and try again."];
            return;
        }

        NSURL *playbackURL = sciDAF(serverAudio, @selector(playbackURL));
        if (!playbackURL) playbackURL = sciDAF(serverAudio, @selector(fallbackURL));
        if (!playbackURL) {
            [SCIUtils showErrorHUDWithDescription:@"No audio URL found. Try again after refreshing the chat."];
            return;
        }

        UIView *topView = [UIApplication sharedApplication].keyWindow;
        SCIDownloadPillView *pill = [[SCIDownloadPillView alloc] init];
        [pill setText:@"Downloading audio..."];
        [pill showInView:topView];

        NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
            downloadTaskWithURL:playbackURL
            completionHandler:^(NSURL *tempURL, NSURLResponse *response, NSError *error) {
            if (error || !tempURL) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [pill dismiss];
                    [SCIUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Download failed. Try again."];
                });
                return;
            }

            // Move downloaded file to named temp path
            NSString *mediaId = sciDAF(serverAudio, @selector(mediaId)) ?: @"voice_message";
            NSString *mp4Path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"tmp_%@.mp4", mediaId]];
            NSURL *mp4URL = [NSURL fileURLWithPath:mp4Path];
            [[NSFileManager defaultManager] removeItemAtURL:mp4URL error:nil];
            [[NSFileManager defaultManager] moveItemAtURL:tempURL toURL:mp4URL error:nil];

            // Convert mp4 container to m4a (AAC audio only)
            NSString *m4aPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"audio_%@.m4a", mediaId]];
            NSURL *m4aURL = [NSURL fileURLWithPath:m4aPath];
            [[NSFileManager defaultManager] removeItemAtURL:m4aURL error:nil];

            AVAsset *asset = [AVAsset assetWithURL:mp4URL];
            AVAssetExportSession *exp = [AVAssetExportSession
                exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
            exp.outputURL = m4aURL;
            exp.outputFileType = AVFileTypeAppleM4A;

            [exp exportAsynchronouslyWithCompletionHandler:^{
                [[NSFileManager defaultManager] removeItemAtURL:mp4URL error:nil];

                NSURL *finalURL = (exp.status == AVAssetExportSessionStatusCompleted) ? m4aURL : mp4URL;

                dispatch_async(dispatch_get_main_queue(), ^{
                    [pill setText:@"Done!"];
                    [pill dismissAfterDelay:0.5];

                    UIActivityViewController *shareVC = [[UIActivityViewController alloc]
                        initWithActivityItems:@[finalURL]
                        applicationActivities:nil];
                    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
                    while (top.presentedViewController) top = top.presentedViewController;
                    [top presentViewController:shareVC animated:YES completion:nil];
                });
            }];
        }];
        [task resume];
    };

    // Build menu item via IGDSPrismMenuItemBuilder
    id builder = ((InitFn)objc_msgSend)([builderClass alloc], @selector(initWithTitle:), @"Download");
    builder = ((WithFn)objc_msgSend)(builder, @selector(withImage:), [UIImage systemImageNamed:@"arrow.down.circle"]);
    builder = ((WithFn)objc_msgSend)(builder, @selector(withHandler:), handler);
    id menuItem = ((BuildFn)objc_msgSend)(builder, @selector(build));
    if (!menuItem) return orig_prismMenuView_init3(self, _cmd, elements, header, edr);

    // Wrap in IGDSPrismMenuElement (copy _subtype from existing element, set _item_menuItem)
    id templateEl = elements[0];
    id newElement = [[templateEl class] new];
    Ivar subtypeIvar = class_getInstanceVariable([templateEl class], "_subtype");
    Ivar itemIvar = class_getInstanceVariable([templateEl class], "_item_menuItem");
    if (!newElement || !subtypeIvar || !itemIvar)
        return orig_prismMenuView_init3(self, _cmd, elements, header, edr);

    ptrdiff_t offset = ivar_getOffset(subtypeIvar);
    *(uint64_t *)((uint8_t *)(__bridge void *)newElement + offset) =
        *(uint64_t *)((uint8_t *)(__bridge void *)templateEl + offset);
    object_setIvar(newElement, itemIvar, menuItem);

    NSMutableArray *newElements = [NSMutableArray arrayWithObject:newElement];
    [newElements addObjectsFromArray:elements];
    return orig_prismMenuView_init3(self, _cmd, newElements, header, edr);
}

%ctor {
    Class prismMenuView = objc_getClass("IGDSPrismMenu.IGDSPrismMenuView");
    if (prismMenuView) {
        SEL sel = @selector(initWithMenuElements:headerText:edrEnabled:);
        if ([prismMenuView instancesRespondToSelector:sel])
            MSHookMessageEx(prismMenuView, sel, (IMP)new_prismMenuView_init3, (IMP *)&orig_prismMenuView_init3);
    }
}
