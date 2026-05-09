// Send audio/video files as voice messages in DMs.
// Injects an Upload Audio item into the DM plus menu, runs the file through a
// trim UI, transcodes to AAC m4a (or passes formats IG accepts as-is), then
// hands the URL to IG's native voice pipeline.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIFFmpeg.h"
#import "../../SCITrimViewController.h"
#import "../../Tweak.h"
#import "../../Gallery/SCIGalleryViewController.h"
#import "../../Gallery/SCIGalleryFile.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>

typedef id (*SCIMsgSend)(id, SEL);
static inline id sciAF(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((SCIMsgSend)objc_msgSend)(obj, sel);
}

static __weak UIViewController *sciAudioThreadVC = nil;
static BOOL sciDMMenuPending = NO;

#pragma mark - Send audio through IG pipeline

static NSSet<NSString *> *sciPassthroughAudioExts(void);

static void sciSendAudioFile(NSURL *audioURL, UIViewController *threadVC) {
    AVAsset *asset = [AVAsset assetWithURL:audioURL];
    double duration = CMTimeGetSeconds(asset.duration);
    // AVFoundation returns 0/NaN for containers it can't parse (e.g. Ogg).
    if (duration <= 0 || isnan(duration)) duration = 1.0;

    id voiceController = sciAF(threadVC, @selector(voiceController));
    id voiceRecordVC = nil;
    if (voiceController) {
        Ivar vrIvar = class_getInstanceVariable([voiceController class], "_voiceRecordViewController");
        voiceRecordVC = vrIvar ? object_getIvar(voiceController, vrIvar) : nil;
    }

    id waveform = nil;
    Class wfClass = NSClassFromString(@"IGDirectAudioWaveform");
    NSMutableArray *fallbackArr = [NSMutableArray array];
    for (int i = 0; i < MAX(10, MIN((int)(duration * 10), 300)); i++)
        [fallbackArr addObject:@(0.1 + arc4random_uniform(80) / 100.0)];

    if (wfClass) {
        NSArray *rawData = nil;
        SEL genSel = @selector(generateWaveformDataFromAudioFile:maxLength:);
        if ([wfClass respondsToSelector:genSel]) {
            typedef id (*GenFn)(id, SEL, id, NSInteger);
            rawData = ((GenFn)objc_msgSend)(wfClass, genSel, audioURL, (NSInteger)(duration * 10));
        }
        if (!rawData) rawData = fallbackArr;

        SEL scaleSel = @selector(scaledArrayOfNumbers:);
        if ([wfClass respondsToSelector:scaleSel]) {
            typedef id (*ScaleFn)(id, SEL, id);
            NSArray *scaled = ((ScaleFn)objc_msgSend)(wfClass, scaleSel, rawData);
            if (scaled) rawData = scaled;
        }

        SEL initWF = @selector(initWithVolumeRecordingInterval:averageVolume:);
        if ([wfClass instancesRespondToSelector:initWF]) {
            typedef id (*InitFn)(id, SEL, double, id);
            waveform = ((InitFn)objc_msgSend)([wfClass alloc], initWF, 0.1, rawData);
        }
        if (!waveform) {
            waveform = [[wfClass alloc] init];
            for (NSString *n in @[@"_averageVolume", @"_waveformData", @"_data", @"_volumes"]) {
                Ivar iv = class_getInstanceVariable(wfClass, [n UTF8String]);
                if (iv) { object_setIvar(waveform, iv, rawData); break; }
            }
        }
    }
    if (!waveform) waveform = fallbackArr;

    @try {
        SEL vmSel = @selector(visualMessageViewerPresentationManagerDidRecordAudioClipWithURL:waveform:duration:entryPoint:toReplyToMessageWithID:);
        if ([threadVC respondsToSelector:vmSel]) {
            typedef void (*Fn)(id, SEL, id, id, double, NSInteger, id);
            ((Fn)objc_msgSend)(threadVC, vmSel, audioURL, waveform, duration, (NSInteger)2, nil);
            SCINotifySuccess(SCI_NOTIF_VOICE_SEND, SCILocalized(@"Audio sent"), nil);
            return;
        }
        SEL s7 = @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:aiVoiceEffectApplied:sendButtonTypeTapped:);
        if ([threadVC respondsToSelector:s7]) {
            typedef void (*Fn)(id, SEL, id, id, id, CGFloat, NSInteger, id, id);
            ((Fn)objc_msgSend)(threadVC, s7, voiceRecordVC, audioURL, waveform, (CGFloat)duration, (NSInteger)2, nil, nil);
            SCINotifySuccess(SCI_NOTIF_VOICE_SEND, SCILocalized(@"Audio sent"), nil);
            return;
        }
        SEL s5 = @selector(voiceRecordViewController:didRecordAudioClipWithURL:waveform:duration:entryPoint:);
        if ([threadVC respondsToSelector:s5]) {
            typedef void (*Fn)(id, SEL, id, id, id, CGFloat, NSInteger);
            ((Fn)objc_msgSend)(threadVC, s5, voiceRecordVC, audioURL, waveform, (CGFloat)duration, (NSInteger)2);
            SCINotifySuccess(SCI_NOTIF_VOICE_SEND, SCILocalized(@"Audio sent"), nil);
            return;
        }
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No voice send method found")];
    } @catch (NSException *e) {
        [SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"Send failed: %@"), e.reason]];
    }
}

#pragma mark - Audio conversion with optional trim

// Failure alert — offers raw send + link to open a format-support issue.
static void sciShowUnsupportedAlert(NSURL *url, NSString *reason, UIViewController *threadVC) {
    NSString *fileExt = [[url pathExtension] lowercaseString];
    NSString *displayExt = (fileExt.length > 0) ? [NSString stringWithFormat:@".%@", fileExt] : SCILocalized(@"This file");
    NSString *title = [NSString stringWithFormat:SCILocalized(@"%@ can't be converted"), displayExt];
    NSString *body = [NSString stringWithFormat:
        SCILocalized(@"iOS audio APIs couldn't process this file%@%@\n\nYou can try sending it to Instagram as-is — IG's server may accept it, or it may silently fail.\n\nTo request native support, open an issue:"),
        reason.length > 0 ? @":\n" : @".",
        reason.length > 0 ? reason : @""];
    NSString *msg = [NSString stringWithFormat:@"%@\n%@", body, SCIRepoIssuesURL];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak UIViewController *weakVC = threadVC;
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Send anyway") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        sciSendAudioFile(url, weakVC);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Open GitHub") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [[UIApplication sharedApplication]
            openURL:[NSURL URLWithString:SCIRepoIssuesURL]
            options:@{} completionHandler:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *presenter = threadVC ?: [UIApplication sharedApplication].keyWindow.rootViewController;
    [presenter presentViewController:alert animated:YES completion:nil];
}

// AVFoundation path — handles iOS-native formats including xHE-AAC which
// ffmpeg-kit 6.0 can't decode. onFailure lets the caller fall back.
static void sciAVFoundationConvertAndSend(NSURL *url, UIViewController *threadVC, CMTimeRange trimRange, void(^onFailure)(NSError *error)) {
    BOOL hasTrim = CMTIMERANGE_IS_VALID(trimRange) && !CMTIMERANGE_IS_EMPTY(trimRange) &&
                   CMTimeGetSeconds(trimRange.duration) > 0;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        AVAsset *asset = [AVAsset assetWithURL:url];
        if (![[asset tracksWithMediaType:AVMediaTypeAudio] firstObject]) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (onFailure) onFailure(nil); });
            return;
        }

        NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"rg_exp_%u.m4a", arc4random()]];
        [[NSFileManager defaultManager] removeItemAtPath:out error:nil];

        AVAssetExportSession *exp = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
        exp.outputURL = [NSURL fileURLWithPath:out];
        exp.outputFileType = AVFileTypeAppleM4A;
        if (hasTrim) exp.timeRange = trimRange;

        [exp exportAsynchronouslyWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (exp.status == AVAssetExportSessionStatusCompleted) {
                    sciSendAudioFile([NSURL fileURLWithPath:out], threadVC);
                } else {
                    if (onFailure) onFailure(exp.error);
                }
            });
        }];
    });
}

// FFmpeg path — fallback for formats AVFoundation won't touch (Opus, Ogg, etc.)
static void sciFFmpegConvertAndSend(NSURL *url, UIViewController *threadVC, CMTimeRange trimRange) {
    BOOL hasTrim = CMTIMERANGE_IS_VALID(trimRange) && !CMTIMERANGE_IS_EMPTY(trimRange) &&
                   CMTimeGetSeconds(trimRange.duration) > 0;

    NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"rg_ffaudio_%u.m4a", arc4random()]];
    [[NSFileManager defaultManager] removeItemAtPath:out error:nil];

    NSMutableString *cmd = [NSMutableString stringWithFormat:@"-y -i \"%@\"", url.path];
    if (hasTrim) {
        double ss = CMTimeGetSeconds(trimRange.start);
        double dur = CMTimeGetSeconds(trimRange.duration);
        [cmd appendFormat:@" -ss %.3f -t %.3f", ss, dur];
    }
    [cmd appendFormat:@" -vn -c:a aac -b:a 128k -ar 44100 -ac 1 \"%@\"", out];

    [SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success && [[NSFileManager defaultManager] fileExistsAtPath:out]) {
                sciSendAudioFile([NSURL fileURLWithPath:out], threadVC);
            } else {
                sciShowUnsupportedAlert(url, SCILocalized(@"FFmpeg conversion failed"), threadVC);
            }
        });
    }];
}

static void sciExportAndSend(NSURL *url, UIViewController *threadVC, BOOL isVideo, CMTimeRange trimRange) {
    BOOL hasTrim = CMTIMERANGE_IS_VALID(trimRange) && !CMTIMERANGE_IS_EMPTY(trimRange) &&
                   CMTimeGetSeconds(trimRange.duration) > 0;

    NSString *ext = [[url pathExtension] lowercaseString];
    if (!isVideo && !hasTrim && [sciPassthroughAudioExts() containsObject:ext]) {
        sciSendAudioFile(url, threadVC);
        return;
    }

    SCINotifyInfo(SCI_NOTIF_AUDIO_EXTRACT, isVideo ? SCILocalized(@"Extracting audio...") : SCILocalized(@"Converting..."), nil);

    // AVFoundation first, FFmpeg as fallback.
    sciAVFoundationConvertAndSend(url, threadVC, trimRange, ^(NSError *avError) {
        if ([SCIFFmpeg isAvailable]) {
            sciFFmpegConvertAndSend(url, threadVC, trimRange);
            return;
        }
        if (!isVideo && [sciPassthroughAudioExts() containsObject:ext]) {
            sciSendAudioFile(url, threadVC);
            return;
        }
        sciShowUnsupportedAlert(url, avError.localizedDescription ?: SCILocalized(@"no audio track could be read"), threadVC);
    });
}

// Formats IG accepts as-is (no conversion).
static NSSet<NSString *> *sciPassthroughAudioExts(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"m4a", @"aac", @"ogg", @"opus"]];
    });
    return set;
}

static void sciConvertAndSend(NSURL *url, UIViewController *threadVC, BOOL isVideo) {
    NSString *ext = [[url pathExtension] lowercaseString];
    if (!isVideo && [sciPassthroughAudioExts() containsObject:ext]) {
        sciSendAudioFile(url, threadVC);
        return;
    }
    sciExportAndSend(url, threadVC, isVideo, kCMTimeRangeInvalid);
}


static void sciShowTrimVC(NSURL *url, BOOL isVideo, UIViewController *threadVC) {
    SCITrimViewController *trimVC = [[SCITrimViewController alloc] init];
    trimVC.mediaURL = url;
    trimVC.isVideo = isVideo;
    trimVC.sendButtonTitle = SCILocalized(@"Send Audio");
    trimVC.modalPresentationStyle = UIModalPresentationFullScreen;
    __weak UIViewController *weakThread = threadVC;
    trimVC.onSend = ^(CMTimeRange trimRange) {
        UIViewController *tvc = weakThread;
        if (tvc) sciExportAndSend(url, tvc, isVideo, trimRange);
    };
    [threadVC presentViewController:trimVC animated:YES completion:nil];
}

#pragma mark - Show picker options

// Forward decl: defined inside the IGDirectThreadViewController %hook below.
static void sciPrepareAndShowTrim(NSURL *url, UIViewController *threadVC);

static void sciShowUploadAudioOptions(UIViewController *threadVC) {
    sciAudioThreadVC = threadVC;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Upload Audio")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    __weak UIViewController *weakVC = threadVC;

    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Audio/Video from Files") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIViewController *vc = weakVC;
        if (!vc) return;
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray *types = [SCIFFmpeg isAvailable]
            ? @[@"public.audio", @"public.audiovisual-content"]
            : @[@"public.audio", @"public.mpeg-4-audio", @"public.mp3", @"com.microsoft.waveform-audio",
                @"public.aiff-audio", @"com.apple.m4a-audio",
                @"public.movie", @"public.mpeg-4", @"com.apple.quicktime-movie"];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
        #pragma clang diagnostic pop
        picker.delegate = (id<UIDocumentPickerDelegate>)vc;
        [vc presentViewController:picker animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Video from Library") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIViewController *vc = weakVC;
        if (!vc) return;
        UIImagePickerController *imgPicker = [[UIImagePickerController alloc] init];
        imgPicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        imgPicker.mediaTypes = @[@"public.movie"];
        imgPicker.delegate = (id<UINavigationControllerDelegate, UIImagePickerControllerDelegate>)vc;
        imgPicker.videoExportPreset = AVAssetExportPresetPassthrough;
        imgPicker.allowsEditing = YES; // enables built-in video trimming
        [vc presentViewController:imgPicker animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Audio from RyukGram Gallery") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIViewController *vc = weakVC;
        if (!vc) return;
        [SCIGalleryViewController presentPickerWithMediaTypes:@[@(SCIGalleryMediaTypeAudio)]
                                                        title:SCILocalized(@"Pick audio")
                                                       fromVC:vc
                                                   completion:^(NSURL *pickedURL, SCIGalleryFile *pickedFile) {
            if (!pickedURL) return;
            UIViewController *threadVC = sciAudioThreadVC ?: vc;
            if (threadVC) sciPrepareAndShowTrim(pickedURL, threadVC);
        }];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [threadVC presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Hook IGDSMenu to inject native menu item

%hook IGDSMenu

- (id)initWithMenuItems:(NSArray *)items edr:(BOOL)edr headerLabelText:(id)header {
    if (![SCIUtils getBoolPref:@"send_audio_as_file"]) return %orig;

    // Gate on the DM composer — sciDMMenuPending is flipped by the overflow hook.
    if (!sciDMMenuPending) return %orig;
    sciDMMenuPending = NO;

    NSString *uploadTitle = SCILocalized(@"Upload Audio");
    for (id item in items) {
        id title = sciAF(item, @selector(title));
        if ([title isKindOfClass:[NSString class]] && [title isEqualToString:uploadTitle]) return %orig;
    }

    Class itemClass = NSClassFromString(@"IGDSMenuItem");
    if (!itemClass) return %orig;

    UIImage *img = [[UIImage systemImageNamed:@"waveform"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

    void (^handler)(void) = ^{
        UIViewController *threadVC = sciAudioThreadVC;
        if (threadVC) sciShowUploadAudioOptions(threadVC);
    };

    SEL initSel = @selector(initWithTitle:image:handler:);
    if (![itemClass instancesRespondToSelector:initSel]) return %orig;

    typedef id (*InitFn)(id, SEL, id, id, id);
    id audioItem = ((InitFn)objc_msgSend)([itemClass alloc], initSel, uploadTitle, img, handler);
    if (!audioItem) return %orig;

    NSMutableArray *newItems = [NSMutableArray arrayWithObject:audioItem];
    [newItems addObjectsFromArray:items];

    return %orig(newItems, edr, header);
}

%end

#pragma mark - Camera-button long-press → Upload Audio

// Fallback entry point — IG hides the + button while replying. The delegate
// allows simultaneous recognition so we coexist with IG's own long-press.
static const void *kSCICameraLongPressAttached = &kSCICameraLongPressAttached;

@interface SCICameraLPDelegate : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@end
@implementation SCICameraLPDelegate
+ (instancetype)shared {
    static SCICameraLPDelegate *p; static dispatch_once_t o;
    dispatch_once(&o, ^{ p = [SCICameraLPDelegate new]; });
    return p;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
@end

static BOOL sciButtonIsCamera(UIButton *btn) {
    return [NSStringFromClass([btn class]) isEqualToString:@"IGDirectComposerButton"]
        && [btn.accessibilityIdentifier isEqualToString:@"Camera-Button"];
}

static UIViewController *sciThreadVCForView(UIView *v) {
    UIResponder *r = v;
    while (r) {
        if ([r isKindOfClass:NSClassFromString(@"IGDirectThreadViewController")]) return (UIViewController *)r;
        r = r.nextResponder;
    }
    return sciAudioThreadVC;
}

static void sciAttachCameraLongPress(UIButton *btn) {
    if (!btn || objc_getAssociatedObject(btn, kSCICameraLongPressAttached)) return;
    UIViewController *threadVC = sciThreadVCForView((UIView *)btn);
    if (!threadVC) return;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:threadVC action:@selector(sciCameraLongPressForUploadAudio:)];
    lp.minimumPressDuration = 0.45;
    lp.cancelsTouchesInView = NO;
    lp.delegate = (id<UIGestureRecognizerDelegate>)[SCICameraLPDelegate shared];
    [btn addGestureRecognizer:lp];
    objc_setAssociatedObject(btn, kSCICameraLongPressAttached, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook IGDirectComposerButton
- (void)setAccessibilityIdentifier:(NSString *)axId {
    %orig;
    if (![SCIUtils getBoolPref:@"send_audio_as_file"]) return;
    if (![axId isEqualToString:@"Camera-Button"]) return;
    sciAttachCameraLongPress((UIButton *)self);
}
- (void)didMoveToWindow {
    %orig;
    if (![SCIUtils getBoolPref:@"send_audio_as_file"]) return;
    if (!sciButtonIsCamera((UIButton *)self)) return;
    sciAttachCameraLongPress((UIButton *)self);
}
%end

#pragma mark - Hook IGDirectThreadViewController

%hook IGDirectThreadViewController

- (void)composerOverflowButtonMenuWillPrepareExpandWithPlusButton:(id)plusButton {
    %orig;
    if (![SCIUtils getBoolPref:@"send_audio_as_file"]) return;
    sciAudioThreadVC = self;
    sciDMMenuPending = YES;
}

%new - (void)sciCameraLongPressForUploadAudio:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    sciAudioThreadVC = self;
    sciShowUploadAudioOptions(self);
}

// Pre-convert to clean AAC M4A so the trim UI always plays a known format.
// Exotic codecs (xHE-AAC etc.) stall AVPlayer seeks otherwise.
static NSString *sciTempM4APath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"rg_pre_%u.m4a", arc4random()]];
}

static void sciFFmpegPreConvert(NSURL *url, UIViewController *threadVC) {
    NSString *out = sciTempM4APath();
    [[NSFileManager defaultManager] removeItemAtPath:out error:nil];
    NSString *cmd = [NSString stringWithFormat:@"-y -i \"%@\" -vn -c:a aac -b:a 128k -ar 44100 \"%@\"", url.path, out];
    [SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success && [[NSFileManager defaultManager] fileExistsAtPath:out]) {
                sciShowTrimVC([NSURL fileURLWithPath:out], NO, threadVC);
            } else {
                sciShowUnsupportedAlert(url, SCILocalized(@"FFmpeg conversion failed"), threadVC);
            }
        });
    }];
}

static void sciPrepareAndShowTrim(NSURL *url, UIViewController *threadVC) {
    SCINotifyInfo(SCI_NOTIF_AUDIO_EXTRACT, SCILocalized(@"Converting..."), nil);

    AVAsset *asset = [AVAsset assetWithURL:url];
    double dur = CMTimeGetSeconds(asset.duration);
    BOOL avCanRead = dur > 0 && !isnan(dur) && [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];

    if (!avCanRead) {
        if ([SCIFFmpeg isAvailable]) { sciFFmpegPreConvert(url, threadVC); return; }
        sciShowUnsupportedAlert(url, SCILocalized(@"Format not supported without FFmpegKit"), threadVC);
        return;
    }

    NSString *out = sciTempM4APath();
    [[NSFileManager defaultManager] removeItemAtPath:out error:nil];
    AVAssetExportSession *exp = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    exp.outputURL = [NSURL fileURLWithPath:out];
    exp.outputFileType = AVFileTypeAppleM4A;
    [exp exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (exp.status == AVAssetExportSessionStatusCompleted) {
                sciShowTrimVC([NSURL fileURLWithPath:out], NO, threadVC);
            } else if ([SCIFFmpeg isAvailable]) {
                sciFFmpegPreConvert(url, threadVC);
            } else {
                sciShowUnsupportedAlert(url, exp.error.localizedDescription ?: SCILocalized(@"no audio track could be read"), threadVC);
            }
        });
    }];
}

// File picker delegate
%new - (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    sciPrepareAndShowTrim(url, self);
}

%new - (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    if (!url) return;
    sciPrepareAndShowTrim(url, self);
}

%new - (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {}

// video picker delegate — UIImagePickerController with allowsEditing handles trimming
%new - (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSURL *videoURL = info[UIImagePickerControllerMediaURL];
    if (!videoURL) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract video URL")];
        return;
    }
    // Already trimmed by UIImagePickerController's built-in editor.
    sciConvertAndSend(videoURL, self, YES);
}

%new - (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

%end
