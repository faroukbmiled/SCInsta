// Send-from-gallery for Instants/QuickSnap.
//
// Adds a gallery button on the Instants surface. Picked image goes through a
// square cropper, then drives IG's pipeline: we wrap AVCaptureVideoDataOutput's
// delegate and substitute every frame with one rendered from the image. IG's
// native upload + optimistic UI + store insert run unchanged on top.

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Accelerate/Accelerate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../Utils.h"
#import "SCIInstantsPath.h"
#import "../../Gallery/SCIGalleryViewController.h"
#import "../../Gallery/SCIGalleryFile.h"


// ============================================================================
// Frame substitution
// ============================================================================

static UIImage *sci_pendingImage = nil;

// Cached pixel buffer keyed on (image, dims, format) so per-frame cost is a
// sub-millisecond CMSampleBuffer wrap.
static CVPixelBufferRef sci_cachedPb = NULL;
static __weak UIImage *sci_cachedFor = nil;
static int32_t sci_cachedW = 0, sci_cachedH = 0;
static OSType sci_cachedPix = 0;

static void sci_clearCache(void) {
    if (sci_cachedPb) { CVPixelBufferRelease(sci_cachedPb); sci_cachedPb = NULL; }
    sci_cachedFor = nil;
    sci_cachedW = sci_cachedH = 0;
    sci_cachedPix = 0;
}

// Render the source into a CVPixelBuffer matching the camera's format. Source
// draws into the centered square (IG crops the rest for instants). Supports
// 32BGRA and 420v/420f bi-planar YUV.
static CVPixelBufferRef sci_renderImageToPixelBuffer(UIImage *image,
                                                     int32_t width, int32_t height,
                                                     OSType pix) CF_RETURNS_RETAINED;
static CVPixelBufferRef sci_renderImageToPixelBuffer(UIImage *image,
                                                     int32_t width, int32_t height,
                                                     OSType pix) {
    if (!image.CGImage) return NULL;
    NSDictionary *attrs = @{
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferOpenGLESCompatibilityKey: @YES,
    };
    CVPixelBufferRef pb = NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            pix, (__bridge CFDictionaryRef)attrs, &pb) != kCVReturnSuccess
        || !pb) {
        return NULL;
    }

    CGFloat visSide = MIN((CGFloat)width, (CGFloat)height);
    CGRect drawRect = CGRectMake((width  - visSide) / 2.0,
                                  (height - visSide) / 2.0,
                                  visSide, visSide);

    BOOL ok = NO;
    if (pix == kCVPixelFormatType_32BGRA) {
        CVPixelBufferLockBaseAddress(pb, 0);
        void *base = CVPixelBufferGetBaseAddress(pb);
        size_t bpr = CVPixelBufferGetBytesPerRow(pb);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(base, width, height, 8, bpr, cs,
            kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        if (ctx) {
            CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);
            CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
            CGContextDrawImage(ctx, drawRect, image.CGImage);
            CGContextRelease(ctx);
            ok = YES;
        }
        CGColorSpaceRelease(cs);
        CVPixelBufferUnlockBaseAddress(pb, 0);
    } else if (pix == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
               pix == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        size_t bpr = ((width * 4 + 63) / 64) * 64;
        void *bgra = calloc(bpr * height, 1);
        if (bgra) {
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(bgra, width, height, 8, bpr, cs,
                kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
            if (ctx) {
                CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);
                CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
                CGContextDrawImage(ctx, drawRect, image.CGImage);
                CGContextRelease(ctx);
                if (CVPixelBufferLockBaseAddress(pb, 0) == kCVReturnSuccess) {
                    void *yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
                    void *cbcrBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
                    if (yBase && cbcrBase) {
                        vImage_Buffer src = { bgra, (vImagePixelCount)height, (vImagePixelCount)width, bpr };
                        vImage_Buffer yPlane = { yBase,
                            CVPixelBufferGetHeightOfPlane(pb, 0),
                            CVPixelBufferGetWidthOfPlane(pb, 0),
                            CVPixelBufferGetBytesPerRowOfPlane(pb, 0) };
                        vImage_Buffer cbcrPlane = { cbcrBase,
                            CVPixelBufferGetHeightOfPlane(pb, 1),
                            CVPixelBufferGetWidthOfPlane(pb, 1),
                            CVPixelBufferGetBytesPerRowOfPlane(pb, 1) };
                        BOOL fullRange = (pix == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
                        vImage_YpCbCrPixelRange range = fullRange
                            ? (vImage_YpCbCrPixelRange){ 0, 128, 255, 255, 255, 1, 255, 0 }
                            : (vImage_YpCbCrPixelRange){ 16, 128, 235, 240, 235, 16, 240, 16 };
                        vImage_ARGBToYpCbCr info;
                        if (vImageConvert_ARGBToYpCbCr_GenerateConversion(
                                kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4, &range, &info,
                                kvImageARGB8888, kvImage420Yp8_CbCr8, kvImageNoFlags) == kvImageNoError) {
                            const uint8_t permute[4] = {3, 2, 1, 0};
                            if (vImageConvert_ARGB8888To420Yp8_CbCr8(
                                    &src, &yPlane, &cbcrPlane, &info, permute, kvImageNoFlags) == kvImageNoError) {
                                ok = YES;
                            }
                        }
                    }
                    CVPixelBufferUnlockBaseAddress(pb, 0);
                }
            }
            CGColorSpaceRelease(cs);
            free(bgra);
        }
    }
    if (!ok) { CVPixelBufferRelease(pb); return NULL; }
    return pb;
}

static CMSampleBufferRef sci_makeSampleBufferFromImage(UIImage *image,
                                                       CMSampleBufferRef tmpl)
    CF_RETURNS_RETAINED;
static CMSampleBufferRef sci_makeSampleBufferFromImage(UIImage *image,
                                                       CMSampleBufferRef tmpl) {
    if (!image.CGImage || !tmpl) return NULL;
    CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(tmpl);
    if (!fmt) return NULL;
    CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(fmt);
    OSType pix = CMFormatDescriptionGetMediaSubType(fmt);

    if (sci_cachedPb == NULL ||
        sci_cachedFor != image ||
        sci_cachedW != dims.width ||
        sci_cachedH != dims.height ||
        sci_cachedPix != pix) {
        sci_clearCache();
        CVPixelBufferRef pb = sci_renderImageToPixelBuffer(image, dims.width, dims.height, pix);
        if (!pb) return NULL;
        sci_cachedPb = pb;
        sci_cachedFor = image;
        sci_cachedW = dims.width;
        sci_cachedH = dims.height;
        sci_cachedPix = pix;
    }

    CMVideoFormatDescriptionRef newFmt = NULL;
    if (CMVideoFormatDescriptionCreateForImageBuffer(
            kCFAllocatorDefault, sci_cachedPb, &newFmt) != noErr || !newFmt) {
        return NULL;
    }
    CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeZero, kCMTimeInvalid};
    CMSampleBufferGetSampleTimingInfo(tmpl, 0, &timing);

    CMSampleBufferRef out = NULL;
    CMSampleBufferCreateForImageBuffer(
        kCFAllocatorDefault, sci_cachedPb, true, NULL, NULL, newFmt, &timing, &out);
    CFRelease(newFmt);
    return out;
}


// ============================================================================
// AVCapture delegate wrapper
// ============================================================================

@interface SCIVideoBufferInjector : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id realDelegate;
@end

@implementation SCIVideoBufferInjector

- (BOOL)respondsToSelector:(SEL)sel {
    return [super respondsToSelector:sel] || [self.realDelegate respondsToSelector:sel];
}

- (id)forwardingTargetForSelector:(SEL)sel { return self.realDelegate; }

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    id real = self.realDelegate;
    if (!real) return;
    if (sci_pendingImage) {
        CMSampleBufferRef fake = sci_makeSampleBufferFromImage(sci_pendingImage, sampleBuffer);
        if (fake) {
            [(id<AVCaptureVideoDataOutputSampleBufferDelegate>)real
                captureOutput:output didOutputSampleBuffer:fake fromConnection:connection];
            CFRelease(fake);
            return;
        }
    }
    [(id<AVCaptureVideoDataOutputSampleBufferDelegate>)real
        captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
}

@end


// ============================================================================
// Helpers
// ============================================================================

static const void *kSCIVideoInjectorKey = &kSCIVideoInjectorKey;
static const void *kSCIInstantsGalleryButtonKey = &kSCIInstantsGalleryButtonKey;
static const void *kSCIInstantsGalleryAnchorKey = &kSCIInstantsGalleryAnchorKey;
static const void *kSCIInstantsGalleryConstraintsKey = &kSCIInstantsGalleryConstraintsKey;

static UIViewController *sci_topPresenter(void) {
    UIViewController *vc = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) { vc = w.rootViewController; break; }
        }
        if (vc) break;
    }
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}


// ============================================================================
// Crop / position picker — full-screen, image pannable + zoomable, squircle
// preview window centered, dim outside.
// ============================================================================

@interface SCIInstantsCropController : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, copy) void (^onConfirm)(UIImage *cropped);
@end

@implementation SCIInstantsCropController {
    UIScrollView *_scroll;
    UIImageView *_imageView;
    UIView *_cropOverlay;
    CAShapeLayer *_dimLayer;
    CAShapeLayer *_borderLayer;
    UIButton *_cancelBtn;
    UIButton *_useBtn;
    CGFloat _cropSide;
    BOOL _configured;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.modalPresentationStyle = UIModalPresentationFullScreen;

    _scroll = [UIScrollView new];
    _scroll.delegate = self;
    _scroll.bouncesZoom = YES;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.clipsToBounds = YES;
    _scroll.backgroundColor = [UIColor blackColor];
    [self.view addSubview:_scroll];

    _imageView = [[UIImageView alloc] initWithImage:_sourceImage];
    _imageView.contentMode = UIViewContentModeScaleToFill;
    [_scroll addSubview:_imageView];

    _cropOverlay = [UIView new];
    _cropOverlay.userInteractionEnabled = NO;
    _cropOverlay.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_cropOverlay];

    // Dim layer: full bounds with the squircle hole punched out (even-odd).
    _dimLayer = [CAShapeLayer layer];
    _dimLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.55].CGColor;
    _dimLayer.fillRule = kCAFillRuleEvenOdd;
    [_cropOverlay.layer addSublayer:_dimLayer];

    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = [UIColor clearColor].CGColor;
    _borderLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
    _borderLayer.lineWidth = 1;
    [_cropOverlay.layer addSublayer:_borderLayer];

    _cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelBtn setTitle:SCILocalized(@"Cancel") forState:UIControlStateNormal];
    _cancelBtn.tintColor = [UIColor whiteColor];
    _cancelBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    [_cancelBtn addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelBtn];

    _useBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_useBtn setTitle:SCILocalized(@"Use") forState:UIControlStateNormal];
    _useBtn.tintColor = [UIColor whiteColor];
    _useBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_useBtn addTarget:self action:@selector(useTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_useBtn];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGSize bs = self.view.bounds.size;
    if (bs.width <= 0 || bs.height <= 0) return;
    if (!_sourceImage || !_sourceImage.CGImage) return;

    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGSize cancelSz = [_cancelBtn intrinsicContentSize];
    CGSize useSz    = [_useBtn intrinsicContentSize];
    CGFloat buttonRowH = MAX(cancelSz.height, useSz.height) + 32;

    CGFloat imgY = safe.top;
    CGFloat imgH = bs.height - safe.top - safe.bottom - buttonRowH;
    CGFloat imgW = bs.width;
    _scroll.frame = CGRectMake(0, imgY, imgW, imgH);
    _cropOverlay.frame = _scroll.frame;

    _cropSide = MIN(imgW, imgH) - 56;
    CGFloat cropX = (imgW - _cropSide) / 2.0;
    CGFloat cropY = (imgH - _cropSide) / 2.0;
    CGRect cropRect = CGRectMake(cropX, cropY, _cropSide, _cropSide);

    UIBezierPath *squircle = SCIInstantsSquirclePathInRect(cropRect);
    UIBezierPath *dim = [UIBezierPath bezierPathWithRect:_cropOverlay.bounds];
    [dim appendPath:squircle];
    dim.usesEvenOddFillRule = YES;

    _dimLayer.frame = _cropOverlay.bounds;
    _dimLayer.path  = dim.CGPath;
    _borderLayer.frame = _cropOverlay.bounds;
    _borderLayer.path  = squircle.CGPath;

    CGFloat bottomY = bs.height - safe.bottom - 16;
    _cancelBtn.frame = CGRectMake(safe.left + 24, bottomY - cancelSz.height,
                                  cancelSz.width, cancelSz.height);
    _useBtn.frame    = CGRectMake(bs.width - safe.right - 24 - useSz.width,
                                  bottomY - useSz.height,
                                  useSz.width, useSz.height);

    if (_configured) return;
    CGSize imgSize = _sourceImage.size;
    if (imgSize.width <= 0 || imgSize.height <= 0) return;
    _configured = YES;

    _imageView.frame = (CGRect){CGPointZero, imgSize};
    _scroll.contentSize = imgSize;

    CGFloat minZoom = MAX(_cropSide / imgSize.width, _cropSide / imgSize.height);
    _scroll.minimumZoomScale = minZoom;
    _scroll.maximumZoomScale = MAX(minZoom * 4, 1.0);
    _scroll.zoomScale = minZoom;

    _scroll.contentInset = UIEdgeInsetsMake(cropY, cropX, cropY, cropX);

    CGFloat displayedW = imgSize.width  * minZoom;
    CGFloat displayedH = imgSize.height * minZoom;
    _scroll.contentOffset = CGPointMake((displayedW - imgW) / 2.0,
                                        (displayedH - imgH) / 2.0);
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)sv { return _imageView; }

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)useTapped {
    UIImage *cropped = [self computeCroppedImage];
    void (^cb)(UIImage *) = self.onConfirm;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb && cropped) cb(cropped);
    }];
}

// Map the squircle's bounding rect through scroll → content → image pixels.
- (UIImage *)computeCroppedImage {
    UIImage *src = _sourceImage;
    if (!src.CGImage) return src;

    CGFloat zoom = _scroll.zoomScale;
    CGPoint offset = _scroll.contentOffset;
    CGFloat cropX = (_scroll.bounds.size.width  - _cropSide) / 2.0;
    CGFloat cropY = (_scroll.bounds.size.height - _cropSide) / 2.0;

    CGFloat xInContent = cropX + offset.x;
    CGFloat yInContent = cropY + offset.y;
    CGRect visiblePts = CGRectMake(xInContent / zoom, yInContent / zoom,
                                    _cropSide / zoom, _cropSide / zoom);

    UIGraphicsBeginImageContextWithOptions(src.size, NO, src.scale);
    [src drawInRect:(CGRect){CGPointZero, src.size}];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!normalized.CGImage) normalized = src;

    CGFloat px = normalized.scale;
    CGRect pixelRect = CGRectMake(visiblePts.origin.x * px,
                                   visiblePts.origin.y * px,
                                   visiblePts.size.width * px,
                                   visiblePts.size.height * px);

    CGImageRef cg = CGImageCreateWithImageInRect(normalized.CGImage, pixelRect);
    if (!cg) return src;
    UIImage *out = [UIImage imageWithCGImage:cg scale:normalized.scale orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return out;
}

@end


// ============================================================================
// PHPicker proxy → crop controller → set pending image
// ============================================================================

@interface SCIInstantsGalleryPickerProxy : NSObject <PHPickerViewControllerDelegate>
- (void)sci_presentCropForImage:(UIImage *)image;
@end

@implementation SCIInstantsGalleryPickerProxy

+ (instancetype)shared {
    static SCIInstantsGalleryPickerProxy *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [SCIInstantsGalleryPickerProxy new]; });
    return p;
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:^{
        if (results.count == 0) return;
        PHPickerResult *r = results.firstObject;
        if (![r.itemProvider canLoadObjectOfClass:[UIImage class]]) return;

        [r.itemProvider loadObjectOfClass:[UIImage class]
                        completionHandler:^(__kindof id<NSItemProviderReading> obj, NSError *err) {
            UIImage *image = [obj isKindOfClass:[UIImage class]] ? (UIImage *)obj : nil;
            if (!image || err) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sci_presentCropForImage:image];
            });
        }];
    }];
}

- (void)sci_presentCropForImage:(UIImage *)image {
    if (!image) return;
    SCIInstantsCropController *crop = [SCIInstantsCropController new];
    crop.sourceImage = image;
    crop.onConfirm = ^(UIImage *cropped) {
        sci_pendingImage = cropped;
        // Drop after 30s if the user never taps capture.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (sci_pendingImage == cropped) {
                sci_pendingImage = nil;
                sci_clearCache();
            }
        });
    };
    [sci_topPresenter() presentViewController:crop animated:YES completion:nil];
}

@end


// ============================================================================
// Hooks (gated by the pref at app launch — see %ctor)
// ============================================================================

%group SCIInstantsGalleryGroup

%hook _TtC29IGQuickSnapCreationController23IGQuickSnapCreationView

- (void)layoutSubviews {
    %orig;

    UIView *self_ = (UIView *)self;
    UIButton *btn = objc_getAssociatedObject(self_, kSCIInstantsGalleryButtonKey);
    if (!btn) {
        btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
            configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
        UIImage *img = [[UIImage systemImageNamed:@"photo.on.rectangle.angled" withConfiguration:cfg]
                        imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [btn setImage:img forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.layer.shadowColor = [UIColor blackColor].CGColor;
        btn.layer.shadowOffset = CGSizeMake(0, 1);
        btn.layer.shadowOpacity = 0.55;
        btn.layer.shadowRadius = 3;
        [btn addTarget:self action:@selector(sci_instantsGalleryTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self_ addSubview:btn];
        objc_setAssociatedObject(self_, kSCIInstantsGalleryButtonKey, btn, OBJC_ASSOCIATION_ASSIGN);
    }

    UIView *bar = nil, *friends = nil;
    for (UIView *sv in self_.subviews) {
        if (sv == btn) continue;
        NSString *cls = NSStringFromClass([sv class]);
        if (!bar && [cls containsString:@"CameraControlView"]) bar = sv;
        if (!friends && ([cls containsString:@"Friend"]
                      || [cls containsString:@"Audience"]
                      || [cls containsString:@"AudienceButton"])) friends = sv;
    }

    UIView *anchor = friends ?: bar;
    UIView *prevAnchor = objc_getAssociatedObject(btn, kSCIInstantsGalleryAnchorKey);
    if (anchor != prevAnchor) {
        // Constraints (vs. setting a frame) so UIKit interpolates the button
        // smoothly during IG's capture animation instead of snapping.
        NSArray *old = objc_getAssociatedObject(btn, kSCIInstantsGalleryConstraintsKey);
        if (old) [NSLayoutConstraint deactivateConstraints:old];

        NSArray *cs = nil;
        if (friends) {
            CGFloat side = MAX(36, friends.bounds.size.height ?: 44);
            cs = @[
                [btn.widthAnchor    constraintEqualToConstant:side],
                [btn.heightAnchor   constraintEqualToConstant:side],
                [btn.centerYAnchor  constraintEqualToAnchor:friends.centerYAnchor],
                [btn.trailingAnchor constraintEqualToAnchor:friends.leadingAnchor constant:-12],
            ];
        } else if (bar) {
            cs = @[
                [btn.widthAnchor   constraintEqualToConstant:44],
                [btn.heightAnchor  constraintEqualToConstant:44],
                [btn.topAnchor     constraintEqualToAnchor:bar.bottomAnchor constant:16],
                [btn.leadingAnchor constraintEqualToAnchor:self_.leadingAnchor constant:24],
            ];
        } else {
            cs = @[
                [btn.widthAnchor    constraintEqualToConstant:44],
                [btn.heightAnchor   constraintEqualToConstant:44],
                [btn.bottomAnchor   constraintEqualToAnchor:self_.safeAreaLayoutGuide.bottomAnchor constant:-24],
                [btn.leadingAnchor  constraintEqualToAnchor:self_.leadingAnchor constant:24],
            ];
        }
        [NSLayoutConstraint activateConstraints:cs];
        objc_setAssociatedObject(btn, kSCIInstantsGalleryConstraintsKey, cs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(btn, kSCIInstantsGalleryAnchorKey, anchor, OBJC_ASSOCIATION_ASSIGN);
    }

    [self_ bringSubviewToFront:btn];
}

%new
- (void)sci_instantsGalleryTapped:(UIButton *)sender {
    void (^presentPHPicker)(void) = ^{
        PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
        cfg.filter = [PHPickerFilter imagesFilter];
        cfg.selectionLimit = 1;
        cfg.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
        PHPickerViewController *pc = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        pc.delegate = [SCIInstantsGalleryPickerProxy shared];
        pc.modalPresentationStyle = UIModalPresentationFullScreen;
        [sci_topPresenter() presentViewController:pc animated:YES completion:nil];
    };

    if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
        presentPHPicker();
        return;
    }

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"Pick from")
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction
        actionWithTitle:SCILocalized(@"In-app Gallery")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction *a) {
        [SCIGalleryViewController
            presentPickerWithMediaTypes:@[@(SCIGalleryMediaTypeImage)]
                                  title:SCILocalized(@"Send from gallery")
                                 fromVC:sci_topPresenter()
                             completion:^(NSURL *pickedURL, SCIGalleryFile *pickedFile) {
            if (!pickedURL) return;
            UIImage *img = [UIImage imageWithContentsOfFile:pickedURL.path];
            if (!img) return;
            [[SCIInstantsGalleryPickerProxy shared] sci_presentCropForImage:img];
        }];
    }]];

    [sheet addAction:[UIAlertAction
        actionWithTitle:SCILocalized(@"Photos library")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction *a) { presentPHPicker(); }]];

    [sheet addAction:[UIAlertAction
        actionWithTitle:SCILocalized(@"Cancel")
                  style:UIAlertActionStyleCancel
                handler:nil]];

    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;
    [sci_topPresenter() presentViewController:sheet animated:YES completion:nil];
}

// Clear the pending image when leaving the QuickSnap surface so other camera
// surfaces (stories, reels) aren't hijacked.
- (void)willMoveToWindow:(UIWindow *)window {
    if (window == nil && sci_pendingImage) {
        sci_pendingImage = nil;
        sci_clearCache();
    }
    %orig;
}

%end


%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {
    if (delegate && ![delegate isKindOfClass:[SCIVideoBufferInjector class]]) {
        SCIVideoBufferInjector *wrap = [SCIVideoBufferInjector new];
        wrap.realDelegate = delegate;
        // AVCapture holds delegates weakly — retain ours for the output's lifetime.
        objc_setAssociatedObject(self, kSCIVideoInjectorKey, wrap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig(wrap, queue);
        return;
    }
    %orig;
}

%end

%end // group


%ctor {
    if ([SCIUtils getBoolPref:@"instants_send_from_gallery"]) {
        %init(SCIInstantsGalleryGroup);
    }
}
