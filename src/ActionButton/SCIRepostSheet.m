#import "SCIRepostSheet.h"
#import "../Utils.h"
#import "../SCIURLOpener.h"
#import "../Downloader/Download.h"
#import "../PhotoAlbum.h"
#import <Photos/Photos.h>

@implementation SCIRepostSheet

+ (void)repostWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL {
    NSURL *url = videoURL ?: photoURL;
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No media URL")]; return; }

    BOOL isVideo = (videoURL != nil);

    SCIDownloadPillView *pill = [SCIDownloadPillView shared];
    [pill resetState];
    [pill setText:SCILocalized(@"Preparing repost...")];
    [pill setSubtitle:nil];
    UIView *hostView = [UIApplication sharedApplication].keyWindow ?: topMostController().view;
    if (hostView) [pill showInView:hostView];

    NSString *ext = [[url lastPathComponent] pathExtension];
    if (!ext.length) ext = isVideo ? @"mp4" : @"jpg";
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"repost_%@.%@", [[NSUUID UUID] UUIDString], ext]];
    NSURL *fileURL = [NSURL fileURLWithPath:tmp];

    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
        downloadTaskWithURL:url completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        if (err || !loc || status >= 400) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [pill showError:SCILocalized(@"Download failed")];
                [pill dismissAfterDelay:2.0];
            });
            return;
        }

        NSError *mv = nil;
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:loc toURL:fileURL error:&mv];
        unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:nil] fileSize];
        if (mv || size == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [pill showError:SCILocalized(@"Save failed")];
                [pill dismissAfterDelay:2.0];
            });
            return;
        }

        [self saveToPhotosAndOpenCreation:fileURL isVideo:isVideo pill:pill];
    }];
    [task resume];
}

+ (void)saveToPhotosAndOpenCreation:(NSURL *)fileURL isVideo:(BOOL)isVideo pill:(SCIDownloadPillView *)pill {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [pill showError:SCILocalized(@"Photos access denied")];
                [pill dismissAfterDelay:2.0];
            });
            return;
        }

        __block NSString *localId = nil;

        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
            PHAssetResourceCreationOptions *opts = [PHAssetResourceCreationOptions new];
            // Copy so the share-sheet fallback below still has a readable file.
            opts.shouldMoveFile = NO;
            [req addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto)
                             fileURL:fileURL
                             options:opts];
            req.creationDate = [NSDate date];
            localId = req.placeholderForCreatedAsset.localIdentifier;
        } completionHandler:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!success || !localId.length) {
                    NSLog(@"[RyukGram][Repost] performChanges failed success=%d err=%@", success, error);
                    [pill showError:SCILocalized(@"Failed to save")];
                    [pill dismissAfterDelay:2.0];
                    return;
                }

                if ([SCIUtils getBoolPref:@"save_to_ryukgram_album"]) {
                    [SCIPhotoAlbum addAssetWithLocalIdentifier:localId completion:nil];
                }

                [pill showSuccess:SCILocalized(@"Opening creator...")];
                [pill dismissAfterDelay:1.0];

                NSString *urlStr = [NSString stringWithFormat:@"instagram://library?LocalIdentifier=%@",
                                    [localId stringByAddingPercentEncodingWithAllowedCharacters:
                                     [NSCharacterSet URLQueryAllowedCharacterSet]]];
                NSURL *igURL = [NSURL URLWithString:urlStr];
                if (igURL && [[UIApplication sharedApplication] canOpenURL:igURL]) {
                    [SCIURLOpener openURL:igURL];
                } else {
                    [SCIUtils showShareVC:fileURL];
                }
            });
        }];
    }];
}

@end
