#import "SCIFFmpeg.h"
#import "ActionButton/SCIMediaActions.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <libkern/OSAtomic.h>

static Class FFmpegKitClass = nil;
static Class FFmpegSessionClass = nil;
static Class ReturnCodeClass = nil;
static BOOL sciFFmpegLoaded = NO;
static BOOL sciFFmpegChecked = NO;

// Cancellation state. All access to sciActiveURLSessions goes through sciCancelQueue.
static volatile int32_t sciCancelRequested = 0;
static NSHashTable<NSURLSession *> *sciActiveURLSessions = nil;

static dispatch_queue_t sciCancelQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.ryuk.scinsta.ffmpeg.cancel", DISPATCH_QUEUE_SERIAL);
        sciActiveURLSessions = [NSHashTable weakObjectsHashTable];
    });
    return q;
}

static void sciRegisterSession(NSURLSession *session) {
    if (!session) return;
    dispatch_queue_t q = sciCancelQueue();
    dispatch_sync(q, ^{ [sciActiveURLSessions addObject:session]; });
}

static void sciUnregisterSession(NSURLSession *session) {
    if (!session) return;
    dispatch_queue_t q = sciCancelQueue();
    dispatch_sync(q, ^{ [sciActiveURLSessions removeObject:session]; });
}

static NSArray<NSURLSession *> *sciActiveSessionsSnapshot(void) {
    __block NSArray *out = @[];
    dispatch_queue_t q = sciCancelQueue();
    dispatch_sync(q, ^{ out = [sciActiveURLSessions allObjects] ?: @[]; });
    return out;
}

// Resolve the directory our dylib lives in (works for any injection method)
static NSString *sciDylibDir(void) {
    Dl_info info;
    if (dladdr((void *)sciDylibDir, &info) && info.dli_fname) {
        NSString *path = [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
        return path;
    }
    return nil;
}

static void sciLoadFFmpegKit(void) {
    if (sciFFmpegChecked) return;
    sciFFmpegChecked = YES;

    NSMutableArray *paths = [NSMutableArray arrayWithArray:@[
        // Sideload (Feather): .bundle copied to app root
        [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"RyukGram.bundle/ffmpegkit.framework/ffmpegkit"],
        // Sideload (cyan): injected into Frameworks/
        [[[NSBundle mainBundle] privateFrameworksPath] stringByAppendingPathComponent:@"ffmpegkit.framework/ffmpegkit"],
        // Jailbreak rootless
        @"/var/jb/Library/Application Support/RyukGram.bundle/ffmpegkit.framework/ffmpegkit",
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries/ffmpegkit.framework/ffmpegkit",
        // Jailbreak rootful
        @"/Library/Application Support/RyukGram.bundle/ffmpegkit.framework/ffmpegkit",
        @"/Library/MobileSubstrate/DynamicLibraries/ffmpegkit.framework/ffmpegkit",
    ]];

    // Relative to our own dylib
    NSString *dylibDir = sciDylibDir();
    if (dylibDir) {
        [paths insertObject:[dylibDir stringByAppendingPathComponent:@"ffmpegkit.framework/ffmpegkit"] atIndex:0];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    void *handle = NULL;
    NSMutableArray *dlErrors = [NSMutableArray array];
    for (NSString *fwPath in paths) {
        if (![fm fileExistsAtPath:fwPath]) continue;

        // Preload deps (renamed _sci dir, original binary name)
        NSString *fwDir = [[fwPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSArray *deps = @[@"libavutil", @"libswresample", @"libswscale",
                          @"libavcodec", @"libavformat", @"libavfilter", @"libavdevice"];
        for (NSString *dep in deps) {
            // Try _sci first (sideload), then original (jailbreak)
            NSString *sciPath = [NSString stringWithFormat:@"%@/%@_sci.framework/%@", fwDir, dep, dep];
            NSString *origPath = [NSString stringWithFormat:@"%@/%@.framework/%@", fwDir, dep, dep];
            if ([fm fileExistsAtPath:sciPath]) dlopen(sciPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
            else if ([fm fileExistsAtPath:origPath]) dlopen(origPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
        }

        handle = dlopen(fwPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
        if (handle) {
            NSLog(@"[RyukGram] FFmpegKit loaded from %@", fwPath);
            break;
        }
        const char *err = dlerror();
        [dlErrors addObject:[NSString stringWithFormat:@"%@\n%s", [fwPath lastPathComponent], err ?: "unknown"]];
    }

    if (!handle) {
        NSLog(@"[RyukGram] FFmpegKit not available");
        for (NSString *e in dlErrors) NSLog(@"[RyukGram] dlopen: %@", e);

        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableString *msg = [NSMutableString stringWithString:@"dlopen errors:\n"];
            for (NSString *e in dlErrors) [msg appendFormat:@"%@\n\n", e];
            [msg appendString:@"\nTried paths:\n"];
            NSFileManager *fm2 = [NSFileManager defaultManager];
            for (NSString *p in paths) {
                BOOL exists = [fm2 fileExistsAtPath:p];
                [msg appendFormat:@"%@ %@\n", exists ? @"✓" : @"✗", [p lastPathComponent]];
                if (!exists) {
                    NSString *parent = [p stringByDeletingLastPathComponent];
                    NSString *grandparent = [parent stringByDeletingLastPathComponent];
                    [msg appendFormat:@"  dir: %@ %@\n  dir: %@ %@\n",
                        [fm2 fileExistsAtPath:parent] ? @"✓" : @"✗", [parent lastPathComponent],
                        [fm2 fileExistsAtPath:grandparent] ? @"✓" : @"✗", [grandparent lastPathComponent]];
                }
            }
            NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
            NSArray *rootContents = [fm2 contentsOfDirectoryAtPath:bundlePath error:nil];
            [msg appendString:@"\nApp bundle root:\n"];
            for (NSString *item in rootContents)
                if ([item containsString:@"RyukGram"] || [item containsString:@"ffmpeg"] || [item containsString:@".bundle"])
                    [msg appendFormat:@"  %@\n", item];
            NSString *fwPath = [[NSBundle mainBundle] privateFrameworksPath];
            NSArray *fwContents = [fm2 contentsOfDirectoryAtPath:fwPath error:nil];
            [msg appendString:@"\nFrameworks/:\n"];
            for (NSString *item in fwContents)
                if ([item containsString:@"ffmpeg"] || [item containsString:@"libav"] || [item containsString:@"libsw"] || [item containsString:@"RyukGram"])
                    [msg appendFormat:@"  %@\n", item];

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"FFmpegKit Debug")
                message:msg preferredStyle:UIAlertControllerStyleAlert];
            NSString *copyMsg = [msg copy];
            [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [UIPasteboard generalPasteboard].string = copyMsg;
                SCINotifySuccess(SCI_NOTIF_GENERIC, SCILocalized(@"FFmpeg log copied"), nil);
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
                while (root.presentedViewController) root = root.presentedViewController;
                [root presentViewController:alert animated:YES completion:nil];
            });
        });
        return;
    }

    FFmpegKitClass = NSClassFromString(@"FFmpegKit");
    FFmpegSessionClass = NSClassFromString(@"FFmpegSession");
    ReturnCodeClass = NSClassFromString(@"ReturnCode");

    if (FFmpegKitClass) {
        sciFFmpegLoaded = YES;
        NSLog(@"[RyukGram] FFmpegKit ready");
    } else {
        NSLog(@"[RyukGram] FFmpegKit classes not found after dlopen");
        dlclose(handle);
    }
}

@implementation SCIFFmpeg

+ (BOOL)isAvailable {
    sciLoadFFmpegKit();
    return sciFFmpegLoaded;
}

+ (BOOL)isCancelled {
    return sciCancelRequested == 1;
}

+ (void)cancelAll {
    OSAtomicCompareAndSwap32(0, 1, &sciCancelRequested);

    for (NSURLSession *s in sciActiveSessionsSnapshot()) {
        @try { [s invalidateAndCancel]; } @catch (__unused id e) {}
    }

    // Class-level cancel stops any running FFmpeg session.
    if (FFmpegKitClass) {
        SEL cancelSel = NSSelectorFromString(@"cancel");
        if ([FFmpegKitClass respondsToSelector:cancelSel]) {
            @try { ((void(*)(id, SEL))objc_msgSend)(FFmpegKitClass, cancelSel); }
            @catch (__unused id e) {}
        }
    }

    // Grace period so the next download can proceed.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        OSAtomicCompareAndSwap32(1, 0, &sciCancelRequested);
    });
}

+ (void)executeCommand:(NSString *)command
            completion:(void(^)(BOOL success, NSString *output))completion {
    if (![self isAvailable]) {
        if (completion) completion(NO, @"FFmpegKit not available");
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            SEL executeSel = NSSelectorFromString(@"execute:");
            if (![FFmpegKitClass respondsToSelector:executeSel]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(NO, @"FFmpegKit execute: not found");
                });
                return;
            }

            id session = ((id(*)(id, SEL, id))objc_msgSend)(FFmpegKitClass, executeSel, command);
            if (!session) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(NO, @"FFmpegKit session nil");
                });
                return;
            }

            id returnCode = nil;
            SEL rcSel = NSSelectorFromString(@"getReturnCode");
            if ([session respondsToSelector:rcSel]) {
                returnCode = ((id(*)(id, SEL))objc_msgSend)(session, rcSel);
            }

            BOOL success = NO;
            if (ReturnCodeClass && returnCode) {
                SEL isSuccessSel = NSSelectorFromString(@"isSuccess:");
                if ([ReturnCodeClass respondsToSelector:isSuccessSel]) {
                    success = ((BOOL(*)(id, SEL, id))objc_msgSend)(ReturnCodeClass, isSuccessSel, returnCode);
                }
            }

            NSString *output = nil;
            SEL outputSel = NSSelectorFromString(@"getOutput");
            if ([session respondsToSelector:outputSel]) {
                output = ((id(*)(id, SEL))objc_msgSend)(session, outputSel);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(success, output);
            });
        } @catch (NSException *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSString stringWithFormat:@"Exception: %@", e.reason]);
            });
        }
    });
}

+ (void)probeCommand:(NSString *)command
          completion:(void(^)(BOOL success, NSString *output))completion {
    if (![self isAvailable]) {
        if (completion) completion(NO, @"FFmpegKit not available");
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            Class probeClass = NSClassFromString(@"FFprobeKit");
            SEL executeSel = NSSelectorFromString(@"execute:");
            if (!probeClass || ![probeClass respondsToSelector:executeSel]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(NO, @"FFprobeKit not found");
                });
                return;
            }

            id session = ((id(*)(id, SEL, id))objc_msgSend)(probeClass, executeSel, command);
            NSString *output = nil;
            SEL outputSel = NSSelectorFromString(@"getOutput");
            if (session && [session respondsToSelector:outputSel]) {
                output = ((id(*)(id, SEL))objc_msgSend)(session, outputSel);
            }

            id returnCode = nil;
            SEL rcSel = NSSelectorFromString(@"getReturnCode");
            if (session && [session respondsToSelector:rcSel]) {
                returnCode = ((id(*)(id, SEL))objc_msgSend)(session, rcSel);
            }
            BOOL success = NO;
            if (ReturnCodeClass && returnCode) {
                SEL isSuccessSel = NSSelectorFromString(@"isSuccess:");
                if ([ReturnCodeClass respondsToSelector:isSuccessSel])
                    success = ((BOOL(*)(id, SEL, id))objc_msgSend)(ReturnCodeClass, isSuccessSel, returnCode);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(success, output);
            });
        } @catch (NSException *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, e.reason);
            });
        }
    });
}

+ (void)convertAudioAtPath:(NSString *)inputPath
                  toFormat:(NSString *)format
                   bitrate:(NSString *)bitrate
                completion:(void(^)(NSURL *outputURL, NSError *error))completion {
    if (![self isAvailable]) {
        if (completion) completion(nil, [NSError errorWithDomain:@"SCIFFmpeg" code:1
                                                       userInfo:@{NSLocalizedDescriptionKey: @"FFmpegKit not available"}]);
        return;
    }

    NSString *outputPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"sci_audio_%@.%@", [[NSUUID UUID] UUIDString], format]];

    NSString *codecFlag;
    if ([format isEqualToString:@"mp3"]) {
        codecFlag = [NSString stringWithFormat:@"-c:a libmp3lame -b:a %@", bitrate ?: @"192k"];
    } else {
        codecFlag = [NSString stringWithFormat:@"-c:a aac -b:a %@", bitrate ?: @"192k"];
    }

    NSString *cmd = [NSString stringWithFormat:
                     @"-y -hide_banner -loglevel error -i '%@' -vn -map a %@ '%@'",
                     inputPath, codecFlag, outputPath];

    [self executeCommand:cmd completion:^(BOOL success, NSString *output) {
        if (success && [[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
            if (completion) completion([NSURL fileURLWithPath:outputPath], nil);
        } else {
            if (completion) completion(nil, [NSError errorWithDomain:@"SCIFFmpeg" code:4
                userInfo:@{NSLocalizedDescriptionKey: output ?: @"Audio conversion failed"}]);
        }
    }];
}

+ (void)muxVideoURL:(NSURL *)videoURL
            audioURL:(NSURL *)audioURL
              preset:(NSString *)preset
            progress:(void(^)(float progress, NSString *stage))progressBlock
          completion:(void(^)(NSURL *outputURL, NSError *error))completion {
    [self muxVideoURL:videoURL audioURL:audioURL preset:preset
             progress:progressBlock completion:completion cancelOut:nil];
}

+ (void)muxVideoURL:(NSURL *)videoURL
            audioURL:(NSURL *)audioURL
              preset:(NSString *)preset
            progress:(void(^)(float progress, NSString *stage))progressBlock
          completion:(void(^)(NSURL *outputURL, NSError *error))completion
           cancelOut:(void(^)(void (^cancelBlock)(void)))cancelOut {
    if (![self isAvailable]) {
        if (completion) completion(nil, [NSError errorWithDomain:@"SCIFFmpeg" code:1
                                                       userInfo:@{NSLocalizedDescriptionKey: @"FFmpegKit not available"}]);
        return;
    }

    __block BOOL completionCalled = NO;
    void (^finish)(NSURL *, NSError *) = ^(NSURL *url, NSError *err) {
        if (completionCalled) return;
        completionCalled = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(url, err);
        });
    };

    // Per-call cancellation — scoped to this mux only.
    __block volatile int32_t thisCancelled = 0;
    __block NSURLSession *bgSessionRef = nil;
    __block long ffmpegSidRef = 0;
    BOOL (^isCancelledLocal)(void) = ^BOOL{ return thisCancelled == 1; };

    void (^cancelSelf)(void) = ^{
        OSAtomicCompareAndSwap32(0, 1, &thisCancelled);
        NSURLSession *s = bgSessionRef;
        if (s) { @try { [s invalidateAndCancel]; } @catch (__unused id e) {} }
        long sid = ffmpegSidRef;
        if (sid && FFmpegKitClass) {
            SEL cancelSel = NSSelectorFromString(@"cancel:");
            if ([FFmpegKitClass respondsToSelector:cancelSel]) {
                @try { ((void(*)(id, SEL, long))objc_msgSend)(FFmpegKitClass, cancelSel, sid); }
                @catch (__unused id e) {}
            }
        }
    };
    if (cancelOut) cancelOut(cancelSelf);

    void (^report)(float, NSString *) = ^(float p, NSString *s) {
        if (!progressBlock || isCancelledLocal()) return;
        dispatch_async(dispatch_get_main_queue(), ^{ progressBlock(p, s); });
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *tmpDir = NSTemporaryDirectory();
        // Intermediates stay UUID-named; the muxed output uses the stem.
        NSString *videoPath = [tmpDir stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"sci_video_%@.mp4", [[NSUUID UUID] UUIDString]]];
        NSString *audioPath = [tmpDir stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"sci_audio_%@.m4a", [[NSUUID UUID] UUIDString]]];
        NSString *outStem = [SCIMediaActions currentFilenameStem]
            ?: [NSString stringWithFormat:@"sci_muxed_%@", [[NSUUID UUID] UUIDString]];
        NSString *outputPath = [tmpDir stringByAppendingPathComponent:
                                [NSString stringWithFormat:@"%@.mp4", outStem]];

        NSError *(^cancelledError)(void) = ^NSError *{
            return [NSError errorWithDomain:@"SCIFFmpeg" code:NSUserCancelledError
                userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}];
        };

        void (^cleanupTmp)(void) = ^{
            NSFileManager *fm = [NSFileManager defaultManager];
            [fm removeItemAtPath:videoPath error:nil];
            [fm removeItemAtPath:audioPath error:nil];
            [fm removeItemAtPath:outputPath error:nil];
        };

        report(0.0, @"Downloading video...");

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSMutableData *videoAccum = [NSMutableData data];
        __block NSError *videoErr = nil;

        NSURLSession *bgSession = [NSURLSession sessionWithConfiguration:
            [NSURLSessionConfiguration ephemeralSessionConfiguration]];
        bgSessionRef = bgSession;
        sciRegisterSession(bgSession);

        NSURLSessionDownloadTask *videoTask = [bgSession downloadTaskWithURL:videoURL
            completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
                videoErr = err;
                if (loc) videoAccum = [[NSMutableData alloc] initWithContentsOfURL:loc];
                dispatch_semaphore_signal(sem);
            }];
        [videoTask resume];

        while (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC)) != 0) {
            if (isCancelledLocal()) {
                [videoTask cancel];
                break;
            }
            int64_t received = videoTask.countOfBytesReceived;
            int64_t expected = videoTask.countOfBytesExpectedToReceive;
            if (expected > 0) {
                float frac = (float)received / (float)expected;
                report(frac * 0.8f, @"Downloading video...");
            }
        }

        if (isCancelledLocal()) {
            sciUnregisterSession(bgSession);
            [bgSession invalidateAndCancel];
            cleanupTmp();
            finish(nil, cancelledError());
            return;
        }

        if (!videoAccum.length) {
            sciUnregisterSession(bgSession);
            [bgSession invalidateAndCancel];
            cleanupTmp();
            NSString *desc = videoErr ? videoErr.localizedDescription : @"Empty response";
            finish(nil, [NSError errorWithDomain:@"SCIFFmpeg" code:2
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Failed to download video: %@", desc]}]);
            return;
        }
        [videoAccum writeToFile:videoPath atomically:YES];

        report(0.8f, @"Downloading audio...");
        BOOL hasAudio = (audioURL != nil);
        if (hasAudio) {
            __block NSMutableData *audioAccum = nil;
            __block NSURLSessionDownloadTask *audioTask = nil;
            audioTask = [bgSession downloadTaskWithURL:audioURL
                completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
                    if (loc) audioAccum = [[NSMutableData alloc] initWithContentsOfURL:loc];
                    dispatch_semaphore_signal(sem);
                }];
            [audioTask resume];

            while (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC)) != 0) {
                if (isCancelledLocal()) { [audioTask cancel]; break; }
            }

            if (isCancelledLocal()) {
                sciUnregisterSession(bgSession);
                [bgSession invalidateAndCancel];
                cleanupTmp();
                finish(nil, cancelledError());
                return;
            }

            if (audioAccum.length) {
                [audioAccum writeToFile:audioPath atomically:YES];
            } else {
                hasAudio = NO;
            }
        }

        sciUnregisterSession(bgSession);
        [bgSession invalidateAndCancel];

        report(0.9f, @"Encoding...");

        // Encoding speed → videotoolbox bitrate
        NSString *encFlags;
        if ([preset isEqualToString:@"max"]) {
            encFlags = @"-b:v 50M -profile:v high -level 5.1 -coder cabac";
        } else if ([preset isEqualToString:@"fast"]) {
            encFlags = @"-b:v 20M";
        } else if ([preset isEqualToString:@"veryfast"]) {
            encFlags = @"-b:v 12M";
        } else {
            encFlags = @"-b:v 8M -realtime 1";
        }

        NSString *cmd;
        if (hasAudio) {
            cmd = [NSString stringWithFormat:
                   @"-y -hide_banner "
                   @"-analyzeduration 1M -probesize 1M -fflags +genpts "
                   @"-i '%@' -i '%@' "
                   @"-map 0:v:0 -map 1:a:0 "
                   @"-c:a copy -c:v h264_videotoolbox %@ -allow_sw 1 "
                   @"-movflags +faststart -shortest '%@'",
                   videoPath, audioPath, encFlags, outputPath];
        } else {
            cmd = [NSString stringWithFormat:
                   @"-y -hide_banner "
                   @"-analyzeduration 1M -probesize 1M -fflags +genpts "
                   @"-i '%@' "
                   @"-c:v h264_videotoolbox %@ -allow_sw 1 "
                   @"-movflags +faststart '%@'",
                   videoPath, encFlags, outputPath];
        }

        // executeAsync returns the session synchronously so we can capture its id
        // for per-session cancel.
        __block BOOL ffSuccess = NO;
        __block NSString *ffOutput = nil;
        dispatch_semaphore_t ffSem = dispatch_semaphore_create(0);

        id (^ffCallback)(id) = ^id(id session) {
            SEL rcSel = NSSelectorFromString(@"getReturnCode");
            if ([session respondsToSelector:rcSel]) {
                id rc = ((id(*)(id, SEL))objc_msgSend)(session, rcSel);
                if (ReturnCodeClass && rc) {
                    SEL isSuccessSel = NSSelectorFromString(@"isSuccess:");
                    if ([ReturnCodeClass respondsToSelector:isSuccessSel])
                        ffSuccess = ((BOOL(*)(id, SEL, id))objc_msgSend)(ReturnCodeClass, isSuccessSel, rc);
                }
            }
            SEL outSel = NSSelectorFromString(@"getOutput");
            if ([session respondsToSelector:outSel])
                ffOutput = ((id(*)(id, SEL))objc_msgSend)(session, outSel);
            dispatch_semaphore_signal(ffSem);
            return nil;
        };

        SEL asyncSel = NSSelectorFromString(@"executeAsync:withCompleteCallback:");
        if ([FFmpegKitClass respondsToSelector:asyncSel]) {
            id session = ((id(*)(id, SEL, id, id))objc_msgSend)(FFmpegKitClass, asyncSel, cmd, ffCallback);
            SEL sidSel = NSSelectorFromString(@"getSessionId");
            if (session && [session respondsToSelector:sidSel]) {
                ffmpegSidRef = ((long(*)(id, SEL))objc_msgSend)(session, sidSel);
            }
            dispatch_semaphore_wait(ffSem, DISPATCH_TIME_FOREVER);
        } else {
            // Fallback: synchronous execute (coarse cancel only).
            [SCIFFmpeg executeCommand:cmd completion:^(BOOL ok, NSString *out) {
                ffSuccess = ok; ffOutput = out; dispatch_semaphore_signal(ffSem);
            }];
            dispatch_semaphore_wait(ffSem, DISPATCH_TIME_FOREVER);
        }

        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:videoPath error:nil];
        [fm removeItemAtPath:audioPath error:nil];

        if (isCancelledLocal()) {
            [fm removeItemAtPath:outputPath error:nil];
            finish(nil, cancelledError());
            return;
        }

        if (ffSuccess && [fm fileExistsAtPath:outputPath]) {
            finish([NSURL fileURLWithPath:outputPath], nil);
        } else {
            [fm removeItemAtPath:outputPath error:nil];
            finish(nil, [NSError errorWithDomain:@"SCIFFmpeg" code:3
                userInfo:@{NSLocalizedDescriptionKey: ffOutput ?: @"FFmpeg mux failed"}]);
        }
    });
}

@end
