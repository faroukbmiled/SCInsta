#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIColorPickerSheet.h"
#import <objc/runtime.h>

// Notes bubble editor: paintbrush button (top-right) + long-press on the IG
// color palette open the shared color picker for background / text color.
// Gradient is unsupported by the schema — preset-only.

typedef NS_ENUM(NSInteger, SCINoteColorMode) {
    SCINoteColorModeBackground = 0,
    SCINoteColorModeText,
};

@interface _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController (SCINotes)
- (void)sciInstallThemeButton;
- (void)sciOpenThemeSheet:(id)sender;
- (void)sciOpenColorSheetMode:(SCINoteColorMode)mode;
@end

@interface _TtC26IGNotesBubbleCreationSwift41IGDirectNotesBubbleEditorColorPaletteView (SCINotes)
- (void)sciHandleLongPress:(UILongPressGestureRecognizer *)g;
@end

#pragma mark - Force-flip IG feature flags

%hook IGDirectNotesCreationView
- (id)initWithViewModel:(id)model
         featureSupport:(IGNotesCreationFeatureSupportModel *)support
  presentationAnimation:(id)animation
 composerUpdateListener:(id)listener
               delegate:(id)delegate
             layoutType:(long long)type
            userSession:(id)session
{
    if ([SCIUtils getBoolPref:@"enable_notes_customization"]) {
        @try { [support setValue:@(YES) forKey:@"enableAnimatedEmojisInCreation"]; }   @catch (__unused NSException *e) {}
        @try { [support setValue:@(YES) forKey:@"enableBubbleCustomization"]; }        @catch (__unused NSException *e) {}
        @try { [support setValue:@(YES) forKey:@"enableThemesEditButton"]; }           @catch (__unused NSException *e) {}
        @try { [support setValue:@(YES) forKey:@"enableThemesNavEntrypointButton"]; }  @catch (__unused NSException *e) {}
    }
    return %orig(model, support, animation, listener, delegate, type, session);
}
%end

#pragma mark - Helpers

static _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController *SCIBubbleEditorVCForView(UIView *v) {
    UIViewController *vc = [SCIUtils nearestViewControllerForView:v];
    while (vc) {
        if ([vc isKindOfClass:%c(_TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController)]) {
            return (id)vc;
        }
        vc = vc.parentViewController ?: vc.presentingViewController;
    }
    return nil;
}

static IGNotesCustomThemeCreationModel *SCIEnsureThemeModel(IGDirectNotesComposerViewController *composer) {
    IGNotesCustomThemeCreationModel *model = nil;
    @try { model = [composer valueForKey:@"_selectedCustomThemeCreationModel"]; } @catch (__unused NSException *e) {}
    if (!model) model = [[%c(IGNotesCustomThemeCreationModel) alloc] init];
    return model;
}

static void SCIEnableBottomButtons(UIViewController *parentVC) {
    for (UIView *v in parentVC.view.subviews) {
        if ([v isKindOfClass:%c(IGDSBottomButtonsView)]) {
            [(IGDSBottomButtonsView *)v setPrimaryButtonEnabled:YES];
            [(IGDSBottomButtonsView *)v setSecondaryButtonEnabled:YES];
        }
    }
}

static char kSCINoteBgColorKey;
static char kSCINoteTextColorKey;
static char kSCINoteThemeButtonKey;

#pragma mark - Bubble editor VC

%hook _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![SCIUtils getBoolPref:@"custom_note_themes"]) return;
    [self sciInstallThemeButton];
}

%new
- (void)sciInstallThemeButton {
    SCIChromeButton *existing = objc_getAssociatedObject(self, &kSCINoteThemeButtonKey);
    if (existing && existing.superview) return;

    SCIChromeButton *b = [[SCIChromeButton alloc] initWithSymbol:@"paintbrush.pointed.fill" pointSize:18 diameter:40];
    b.iconTint = [UIColor whiteColor];
    b.bubbleColor = [UIColor clearColor];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b addTarget:self action:@selector(sciOpenThemeSheet:) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:b];
    [NSLayoutConstraint activateConstraints:@[
        [b.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [b.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
    ]];
    objc_setAssociatedObject(self, &kSCINoteThemeButtonKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)sciOpenThemeSheet:(id)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Background color")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_a) { [self sciOpenColorSheetMode:SCINoteColorModeBackground]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Text color")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_a) { [self sciOpenColorSheetMode:SCINoteColorModeText]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
                                              style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        UIView *anchor = [sender isKindOfClass:[UIView class]] ? (UIView *)sender : self.view;
        sheet.popoverPresentationController.sourceView = anchor;
        sheet.popoverPresentationController.sourceRect = anchor.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

%new
- (void)sciOpenColorSheetMode:(SCINoteColorMode)mode {
    UIColor *saved = objc_getAssociatedObject(self,
        (mode == SCINoteColorModeText) ? &kSCINoteTextColorKey : &kSCINoteBgColorKey);
    UIColor *initial = saved ?: ((mode == SCINoteColorModeText) ? [UIColor whiteColor] : [UIColor systemPinkColor]);

    __weak typeof(self) weakSelf = self;
    SCIColorPickerSheet *picker = [SCIColorPickerSheet
        sheetWithMode:SCIColorPickerSheetModeSolid
           startColor:initial
             endColor:nil
         applyHandler:^(SCIColorPickerSheetMode m, UIColor *primary, UIColor *secondary) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !primary) return;

        IGDirectNotesComposerViewController *composer = [(id)self delegate];
        if (!composer) return;
        IGNotesCustomThemeCreationModel *model = SCIEnsureThemeModel(composer);
        if (!model) return;

        NSString *key = (mode == SCINoteColorModeText) ? @"secondaryTextColor" : @"backgroundColor";
        char *assocKey = (mode == SCINoteColorModeText) ? &kSCINoteTextColorKey : &kSCINoteBgColorKey;
        @try { [model setValue:primary forKey:key]; } @catch (__unused NSException *e) {}
        objc_setAssociatedObject(self, assocKey, primary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [composer notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:model];
        SCIEnableBottomButtons(self);
    }];
    [picker presentFromViewController:self];
}
%end

#pragma mark - Long-press shortcut on palette

%hook _TtC26IGNotesBubbleCreationSwift41IGDirectNotesBubbleEditorColorPaletteView
- (void)didMoveToWindow {
    %orig;
    if (![SCIUtils getBoolPref:@"custom_note_themes"]) return;
    if (!self.window) return;

    static char installedKey;
    if (objc_getAssociatedObject(self, &installedKey)) return;
    objc_setAssociatedObject(self, &installedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(sciHandleLongPress:)];
    lp.minimumPressDuration = 0.30;
    lp.cancelsTouchesInView = NO;
    [self addGestureRecognizer:lp];
}

%new
- (void)sciHandleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [SCIBubbleEditorVCForView(self) sciOpenThemeSheet:self];
}
%end
