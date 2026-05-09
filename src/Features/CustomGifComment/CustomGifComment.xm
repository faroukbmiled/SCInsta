// Custom GIF in comments — long-press the comments composer GIF button to
// paste a Giphy URL/ID and post it as a sticker comment.

#import <UIKit/UIKit.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static char kSCIGifLPKey;

@interface SCIGifCommentTarget : NSObject
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr;
@end

#pragma mark - Helpers

static UIView *sci_findGifButton(UIView *root) {
    if ([root.accessibilityIdentifier isEqualToString:@"gif-button"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *r = sci_findGifButton(sub);
        if (r) return r;
    }
    return nil;
}

static UIViewController *sci_findHostVC(UIView *view) {
    UIResponder *r = view;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) return (UIViewController *)r;
        r = [r nextResponder];
    }
    return nil;
}

// giphy.com/gifs/slug-ID, giphy.com/clips/ID, media.giphy.com/media/ID/...,
// or a raw alphanumeric ID.
static NSString *sci_extractGiphyId(NSString *input) {
    NSString *s = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length) return nil;

    NSURL *u = [NSURL URLWithString:s];
    NSString *path = u.path;
    if (!path.length) {
        NSCharacterSet *invalid = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
        if ([s rangeOfCharacterFromSet:invalid].location == NSNotFound && s.length >= 5)
            return s;
        return nil;
    }

    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (NSString *p in parts) if (p.length) [clean addObject:p];
    if (!clean.count) return nil;

    NSUInteger mediaIdx = [clean indexOfObject:@"media"];
    if (mediaIdx != NSNotFound && mediaIdx + 1 < clean.count) {
        return clean[mediaIdx + 1];
    }
    NSString *last = clean.lastObject;
    NSRange dot = [last rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location != NSNotFound) last = [last substringToIndex:dot.location];
    NSRange dash = [last rangeOfString:@"-" options:NSBackwardsSearch];
    if (dash.location != NSNotFound) last = [last substringFromIndex:dash.location + 1];
    NSCharacterSet *invalid = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    if ([last rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
    if (last.length < 5) return nil;
    return last;
}

#pragma mark - IG viewmodel

static id sci_buildModeConfig(Class cfgCls, NSString *urlStr) {
    if (!cfgCls) return nil;
    id cfg = ((id(*)(id, SEL))objc_msgSend)([cfgCls alloc], @selector(init));
    Ivar uIvar = class_getInstanceVariable(cfgCls, "_url");
    if (uIvar) object_setIvar(cfg, uIvar, urlStr);
    return cfg;
}

// Mirrors the shape IG's native picker emits.
static id sci_buildViewModel(NSString *giphyId) {
    Class cfgCls = NSClassFromString(@"IGGiphyGIFModelModeConfig");
    Class imgCls = NSClassFromString(@"IGGiphyImageModel");
    Class vmCls  = NSClassFromString(@"IGDirectAnimatedMediaViewModel");
    if (!cfgCls || !imgCls || !vmCls) return nil;

    NSString *gifURL  = [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.gif",  giphyId];
    NSString *mp4URL  = [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.mp4",  giphyId];
    NSString *webpURL = [NSString stringWithFormat:@"https://media.giphy.com/media/%@/giphy.webp", giphyId];

    id gifCfg  = sci_buildModeConfig(cfgCls, gifURL);
    id mp4Cfg  = sci_buildModeConfig(cfgCls, mp4URL);
    id webpCfg = sci_buildModeConfig(cfgCls, webpURL);

    id imgModel = nil;
    SEL imgInit = @selector(initWithGifConfig:mp4Config:webpConfig:width:height:);
    if ([imgCls instancesRespondToSelector:imgInit]) {
        imgModel = ((id(*)(id, SEL, id, id, id, double, double))objc_msgSend)(
            [imgCls alloc], imgInit, gifCfg, mp4Cfg, webpCfg, 200.0, 200.0);
    } else {
        imgModel = ((id(*)(id, SEL))objc_msgSend)([imgCls alloc], @selector(init));
        Ivar i;
        if ((i = class_getInstanceVariable(imgCls, "_gifConfig")))  object_setIvar(imgModel, i, gifCfg);
        if ((i = class_getInstanceVariable(imgCls, "_mp4Config")))  object_setIvar(imgModel, i, mp4Cfg);
        if ((i = class_getInstanceVariable(imgCls, "_webpConfig"))) object_setIvar(imgModel, i, webpCfg);
        @try { [imgModel setValue:@(200.0) forKey:@"width"]; }  @catch (__unused id e) {}
        @try { [imgModel setValue:@(200.0) forKey:@"height"]; } @catch (__unused id e) {}
    }

    id vm = ((id(*)(id, SEL))objc_msgSend)([vmCls alloc], @selector(init));
    Ivar i;
    if ((i = class_getInstanceVariable(vmCls, "_pk")))              object_setIvar(vm, i, [giphyId copy]);
    if ((i = class_getInstanceVariable(vmCls, "_url")))             object_setIvar(vm, i, [NSURL URLWithString:mp4URL]);
    if ((i = class_getInstanceVariable(vmCls, "_cacheIdentifier"))) object_setIvar(vm, i, [mp4URL copy]);
    if ((i = class_getInstanceVariable(vmCls, "_imageModel")))      object_setIvar(vm, i, imgModel);
    if ((i = class_getInstanceVariable(vmCls, "_altText")))         object_setIvar(vm, i, @"");
    @try { [vm setValue:@(200.0) forKey:@"width"]; }  @catch (__unused id e) {}
    @try { [vm setValue:@(200.0) forKey:@"height"]; } @catch (__unused id e) {}
    return vm;
}

#pragma mark - Long-press handler

@implementation SCIGifCommentTarget

+ (instancetype)shared {
    static SCIGifCommentTarget *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [SCIGifCommentTarget new]; });
    return t;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;

    UIView *btn = gr.view;
    UIView *composerView = btn;
    Class composerCls = NSClassFromString(@"IGCommentComposerView");
    while (composerView && ![composerView isKindOfClass:composerCls]) {
        composerView = composerView.superview;
    }
    if (!composerView) return;

    id composerCtrl = nil;
    @try { composerCtrl = [composerView valueForKey:@"delegate"]; } @catch (__unused id e) {}
    if (!composerCtrl) return;

    UIViewController *host = sci_findHostVC(composerView);
    if (!host) return;

    UIAlertController *prompt = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"Paste Giphy Link")
                         message:SCILocalized(@"Paste a giphy.com URL or media ID")
                  preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"https://giphy.com/gifs/...";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        NSString *clip = [UIPasteboard generalPasteboard].string;
        if ([clip rangeOfString:@"giphy" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            tf.text = clip;
        }
    }];
    [prompt addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Send")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *_) {
        NSString *gid = sci_extractGiphyId(prompt.textFields.firstObject.text);
        if (!gid) {
            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Invalid Giphy URL")];
            return;
        }
        SEL sel = @selector(gifSelectionViewController:didSelectGIFAnimatedViewModel:);
        if (![composerCtrl respondsToSelector:sel]) {
            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Composer doesn't accept GIFs")];
            return;
        }
        id vm = sci_buildViewModel(gid);
        if (!vm) {
            [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Failed to build GIF model")];
            return;
        }
        ((void(*)(id, SEL, id, id))objc_msgSend)(composerCtrl, sel, nil, vm);
        SCINotifySuccess(SCI_NOTIF_GIF_SENT, SCILocalized(@"GIF inserted"), nil);
    }]];
    [prompt addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    [host presentViewController:prompt animated:YES completion:nil];
}

@end

#pragma mark - Hook

static void sci_attachLongPress(UIView *composerView) {
    if (![SCIUtils getBoolPref:@"custom_gif_comment"]) return;
    UIView *btn = sci_findGifButton(composerView);
    if (!btn) return;
    if (objc_getAssociatedObject(btn, &kSCIGifLPKey)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[SCIGifCommentTarget shared]
                action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.45;
    [btn addGestureRecognizer:lp];
    objc_setAssociatedObject(btn, &kSCIGifLPKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook IGCommentComposerView
- (void)layoutSubviews {
    %orig;
    sci_attachLongPress(self);
}
%end
