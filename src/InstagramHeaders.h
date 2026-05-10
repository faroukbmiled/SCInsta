#import <Foundation/Foundation.h>
#include <objc/NSObject.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
#define _Bool bool
#endif

@interface NSURL ()
- (id)normalizedURL; // method provided by Instagram app
@end

@interface IGActionableConfirmationToastViewModel : NSObject {
    NSString *_text_annotatedTitleText;
    NSString *_text_annotatedSubtitleText;
}
@end

@interface IGActionableConfirmationToastPresenter : NSObject
- (void)showAlertWithViewModel:(id)model isAnimated:(_Bool)animated animationDuration:(double)duration presentationPriority:(long long)priority tapActionBlock:(id)tap presentedHandler:(id)presented dismissedHandler:(id)dismissed;
- (void)hideAlert;
@end

@interface IGRootViewController : UIViewController
- (IGActionableConfirmationToastPresenter *)toastPresenter;

- (void)addHandleLongPress; // new
- (void)handleLongPress:(UILongPressGestureRecognizer *)sender; // new
@end

@interface IGViewController : UIViewController
- (void)_superPresentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(id)completion;
@end

@interface IGMainFeedAppHeaderController : UIViewController
- (void)_superPresentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(id)completion; // new
@end

@interface IGShimmeringGridView : UIView
@end

@interface IGExploreGridViewController : IGViewController
@end

@interface IGExploreViewController : IGViewController
@end

@interface IGExploreSearchTitleView : UIView
@end

@interface UIImage ()
- (NSString *)ig_imageName;
@end

@interface IGProfileMenuSheetViewController :  IGViewController
@end

@interface IGTabBar: UIView
@end

@interface IGTabBarController : UIViewController
@end

@interface IGTableViewCell: UITableViewCell
- (id)initWithReuseIdentifier:(NSString *)identifier;
@end

@interface IGProfileSheetTableViewCell : IGTableViewCell
@end

@interface IGTallNavigationBarView : UIView
@end

@interface UIView (RCTViewUnmounting)
@property(retain, nonatomic) UIViewController *viewController;
- (UIView *)_rootView;
@end

@interface IGImageSpecifier : NSObject
@property(readonly, nonatomic) NSURL *url;
@end

@interface IGVideo : NSObject
- (id)sortedVideoURLsBySize; // Before Instagram v398
- (id)allVideoURLs; // After Instagram v398
@end

@interface IGPhoto : NSObject
- (id)imageURLForWidth:(CGFloat)width;
@end

@interface IGBaseMedia : NSObject
@property (retain, nonatomic) id explorePostInFeed;
@end

@interface IGMedia : IGBaseMedia
@property(readonly) IGVideo *video;
@property(readonly) IGPhoto *photo;
- (id)mediaOverlay;
@end

// Sensitive-content cover cell (hosts a Bloks template).
@interface IGMediaOverlayCell : UICollectionViewCell
@end

@interface IGPostItem : NSObject
@property(readonly) IGVideo *video;
@property(readonly) IGPhoto *photo;
@end

@interface IGPageMediaView : UIView
@property(readonly) NSMutableArray <IGPostItem *> *items;
- (IGPostItem *)currentMediaItem;
@end

@interface IGFeedItem : NSObject
@property long long likeCount;
@property(readonly) IGVideo *video;
- (BOOL)isSponsored;
- (BOOL)isSponsoredApp;
@end

@interface IGImageView : UIImageView
@property(retain, nonatomic) IGImageSpecifier *imageSpecifier;
@end

@interface IGFeedItemPagePhotoCell : UICollectionViewCell
@property (nonatomic, strong) id post;
@property (nonatomic, strong) IGPostItem *pagePhotoPost;
@end

@interface IGProfilePicturePreviewViewController : UIViewController
{
    IGImageView *_profilePictureView;
}
- (void)addHandleLongPress; // new
- (void)handleLongPress:(UILongPressGestureRecognizer *)sender; // new
@end

@interface IGFeedItemMediaCell : UICollectionViewCell
@property(retain, nonatomic) IGMedia *post;
- (UIImage *)mediaCellCurrentlyDisplayedImage;
@end

@interface IGFeedItemPhotoCell : IGFeedItemMediaCell
@end

@interface IGFeedItemPhotoCellConfiguration : NSObject
@end

@interface IGFeedPhotoView : UIView
@property (nonatomic, strong) id delegate;

- (void)addLongPressGestureRecognizer; // new
- (void)sciAddDownloadButton; // new
- (void)handleLongPress:(UILongPressGestureRecognizer *)sender; // new
@end

@interface IGModernFeedVideoCell : UIView
- (id)mediaCellFeedItem;
- (void)addLongPressGestureRecognizer; // new
- (void)sciAddDownloadButton; // new
- (void)handleLongPress:(UILongPressGestureRecognizer *)sender; // new
@end

@interface IGSundialViewerVideoCell : UIView
@property(readonly, nonatomic) IGMedia *video;

- (void)addLongPressGestureRecognizer; // new
@end

@interface IGSundialViewerPhotoView : UIView
- (void)addLongPressGestureRecognizer; // new
@end

@interface IGSundialViewerPhotoCell : UIView
@end

@interface IGSundialViewerCarouselPhotoCell : UIView
@end

@interface IGSundialViewerCarouselCell : UIView
@end

@interface IGImageProgressView : UIView
@property(retain, nonatomic) IGImageSpecifier *imageSpecifier;
@end

@interface IGStatefulVideoPlayer : NSObject
@end

@interface IGStoryPhotoView : UIView
- (id)item;

- (void)addLongPressGestureRecognizer; // new
@end

@interface IGStoryFullscreenSectionController : NSObject
@property (nonatomic, strong, readwrite) IGMedia *currentStoryItem;
@end

@interface IGStoryVideoView : UIView
@property (nonatomic, readonly) IGMedia *item;
@property (readonly, nonatomic) IGMedia *videoURLProvider;
@property (nonatomic, weak, readwrite) IGStoryFullscreenSectionController *captionDelegate;

- (void)addLongPressGestureRecognizer; // new
@end

@interface IGStoryModernVideoView : UIView
@property (nonatomic, readonly) IGMedia *item;

- (void)addLongPressGestureRecognizer; // new
@end

@interface IGStoryFullscreenOverlayView : UIView
@property (nonatomic, weak, readwrite) id gestureDelegate;
- (id)gestureDelegate;
- (void)addLongPressGestureRecognizer; // new
- (BOOL)isSecretStoryCurrentlyBlurred;
- (void)showSecretStoryBlur:(BOOL)show animated:(BOOL)animated;
@end

@interface IGDirectVisualMessageViewerController : UIViewController
@end

@interface IGDirectVisualMessageViewerViewModeAwareDataSource : NSObject
@end

@interface IGDirectVisualMessage : NSObject
- (id)rawVideo;
@end

@interface IGUser : NSObject
@property NSInteger followStatus;
@property(copy) NSString *username;
@property BOOL followsCurrentUser;
@end

@interface IGFollowController : NSObject 
@property IGUser *user;
@end

@interface IGCoreTextView : UIView
@property(nonatomic, strong) NSString *text;
- (void)addHandleLongPress; // new
- (void)handleLongPress:(UILongPressGestureRecognizer *)sender; // new
@end

@interface IGUserSession : NSObject
@property (readonly, nonatomic) IGUser *user;
@end

@interface IGWindow : UIWindow
@property (nonatomic) __weak IGUserSession *userSession;
@end

@interface IGShakeWindow : UIWindow
@property (nonatomic) __weak IGUserSession *userSession;
@end

@interface IGStyledString : NSObject
@property (retain, nonatomic) NSMutableAttributedString *attributedString;
- (void)appendString:(id)arg1;
@end

@interface IGInstagramAppDelegate : NSObject <UIApplicationDelegate>
@end

@interface IGDirectInboxSearchAIAgentsPillsContainerCell : UIView
@end

@interface IGTapButton : UIButton
@end

@interface IGLabel : UILabel
@end

@interface IGLabelItemViewModel : NSObject
- (id)labelTitle;
- (id)uniqueIdentifier;
@end

@interface IGDirectInboxSuggestedThreadCellViewModel : NSObject
@end

@interface IGDirectInboxHeaderCellViewModel : NSObject
- (id)title;
@end

@interface IGSearchResultViewModel : NSObject
- (id)title;
- (NSUInteger)itemType;
@end

@interface IGDirectShareRecipient : NSObject
- (NSString *)threadName;
- (BOOL)isBroadcastChannel;
- (NSString *)threadID; // new
@end

@interface IGDirectRecipientCellViewModel : NSObject
- (id)recipient;
- (NSInteger)sectionType;
@end

// Share-sheet recipient list view controller — hosts the IGListAdapter.
@interface IGDirectRecipientListViewController : UIViewController
@end

@interface IGDirectInboxSearchAIAgentsSuggestedPromptRowCell : UIView
@end

// IG inbox top nav header (Swift class, demangled name).
@interface IGDirectInboxNavigationHeaderView : UIView
@end

// Share-sheet "Send to group chat" facepile button + its bottom-buttons container.
@interface _TtC12IGShareSheet45IGShareSheetCreateOrSendToGroupFacepileButton : UIView
@end
@interface _TtC12IGShareSheet38IGShareSheetBottomButtonsViewContainer : UIView
@end

// Reels: friends-tab avatar bubbles + floating social-context overlay.
@interface _TtC32IGSundialFriendsLaneEntryPointUI30IGFriendsLaneEntryPointTabView : UIControl
@end
@interface IGStoryFacepileView : UIView
@end
@interface _TtC25IGFloatingSocialContextUI39IGFloatingSocialContextMediaOverlayView : UIView
@end

@interface IGDSSegmentedPillBarView : UIView
- (id)delegate;
@end

@interface IGImageWithAccessoryButton : IGTapButton
- (void)addLongPressGestureRecognizer; // new
- (void)handleLongPress:(UILongPressGestureRecognizer *)gr; // new
@end

@interface IGHomeFeedHeaderView : UIView
@end

@interface IGHomeFeedHeaderViewController : UIViewController
- (void)headerDidLongPressLogo:(id)arg1;
@end

// Trailing-cluster button (+, heart, DM) in IGHomeFeedHeaderView.
@interface IGBadgeButton : UIControl
@end

// IG's NSMutableURLRequest subclass.
@interface IGURLRequest : NSMutableURLRequest
@end

@interface IGSearchBarDonutButton : UIView
@end

@interface IGAnimatablePlaceholderTextField : UITextField
@end

@interface IGDirectCommandSystemViewModel : NSObject
- (id)row;
@end

@interface IGDirectCommandSystemRow : NSObject
@end

@interface IGDirectCommandSystemResult : NSObject
- (id)title;
- (id)commandString;
@end

@interface IGGrowingTextView : UIView
- (id)placeholderText;
- (void)setPlaceholderText:(id)arg1;
@end

@interface IGUnifiedVideoCollectionView : UIScrollView
@end

@interface IGBadgedNavigationButton : UIView
- (void)addLongPressGestureRecognizer; // new
@end

@interface IGSearchBar : UIView
- (NSObject *)sanitizePlaceholderForConfig:(NSObject *)config; // new
@end

@interface IGSearchBarConfig : NSObject
@end

@interface IGDirectComposer : UIView
- (NSObject *)patchConfig:(NSObject *)config; // new
@end

@interface IGDirectComposerConfig : NSObject
@end

@interface IGAnimatablePlaceholderTextFieldContainer : UIView
@end

@interface IGDirectInboxConfig : NSObject
@end

@interface IGDirectMediaPickerConfig : NSObject
@end

@interface IGDirectMediaPickerGalleryConfig : NSObject
@end

@interface IGStoryEyedropperToggleButton : UIControl
@property (nonatomic, strong, readwrite) UIColor *color;

- (void)setPushedDown:(BOOL)pushedDown;

- (void)addLongPressGestureRecognizer; // new
@end

@interface IGStoryTextEntryViewController : UIViewController
- (void)textViewControllerDidUpdateWithColor:(id)color colorSource:(NSInteger)source;
@end

@interface IGStoryColorPaletteView : UIView
@end

// Color wheel button on music + lyric sticker editors.
@interface IGStoryColorPaletteWheel : UIControl
- (void)addLongPressGestureRecognizer; // new
@end

@interface IGProfilePictureImageView : UIView
@property (nonatomic, readonly) IGUser *userGQL;

- (void)addLongPressGestureRecognizer; // new
@end

@interface IGImageRequest : NSObject
- (id)url;
@end

@interface IGDiscoveryGridItem : NSObject
- (id)model;
@end

@interface IGStoryTextEntryControlsOverlayView : UIView

@property (readonly, nonatomic) NSMutableArray *animationTypes;
@property (readonly, nonatomic) NSMutableArray *effectTypes;

- (void)reloadData;

@end

@interface _TtC27IGGalleryDestinationToolbar31IGGalleryDestinationToolbarView : UIView
@property(nonatomic, copy, readwrite) NSArray *tools;
@end

// Swift classes: IGSundialPlaybackToggle.IGSundialPlaybackToggleView
//                IGSundialClearMode.IGSundialClearedOverlayView
// Hooked via %hook with mangled names — see EnhancedPlayback.xm

@interface IGSundialViewerVerticalUFI : UIView
- (void)_didTapLikeButton:(id)arg1;
- (void)_didTapRepostButton:(id)arg1;
@end

@interface IGMainAppSurfaceIntent : NSObject
- (id)tabStringFromSurfaceIntent;
@end

@interface IGSundialViewerVideoSectionController : NSObject
@end

@interface IGSundialFeedViewController : UIViewController
- (void)refreshControlDidEndFinishLoadingAnimation:(id)arg1;
@end

@interface IGRefreshControl : UIControl
@end

@interface IGDirectThreadViewDrawingViewController : UIViewController
- (void)drawingControls:controls didSelectColor:color;
@end

// DM thread title view — hosts username + "Active …" subtitle.
@interface IGDirectLeftAlignedTitleView : UIView
@end

@interface IGSundialViewerNavigationBarOld : UIView
@end

@interface IGMediaOverlayProfileWithPasswordView : UIView
- (void)sciAddButtons;
- (void)sciUnlockTapped;
- (void)sciShowPasswordTapped;
@end

@interface IGUFIInteractionCountsView : UIView
@end

@interface IGUFIButtonBarView : UIView
@end

@interface IGFeedItemUFICell : UIView
- (void)UFIButtonBarDidTapOnRepost:(id)arg1;
@end

@interface IGNotesCreationFeatureSupportModel : NSObject
@end

// Pando-backed immutable on v423+ — mutate via the all-fields init only.
@interface IGNotesCustomThemeCreationModel : NSObject
- (instancetype)initWithBackgroundColor:(UIColor *)backgroundColor
               gradientBackgroundColors:(NSArray *)gradientBackgroundColors
                              textColor:(UIColor *)textColor
                     secondaryTextColor:(UIColor *)secondaryTextColor
                            customEmoji:(id)customEmoji
                        customizationId:(NSString *)customizationId
                     usedGeneratedTheme:(BOOL)usedGeneratedTheme
                         activationType:(NSInteger)activationType;
@property (nonatomic, readonly) UIColor *backgroundColor;
@property (nonatomic, readonly) NSArray *gradientBackgroundColors;
@property (nonatomic, readonly) UIColor *textColor;
@property (nonatomic, readonly) UIColor *secondaryTextColor;
@property (nonatomic, readonly) id customEmoji;
@property (nonatomic, readonly) NSString *customizationId;
@property (nonatomic, readonly) BOOL usedGeneratedTheme;
@property (nonatomic, readonly) NSInteger activationType;
@end

@interface IGDirectNotesComposerViewController : UIViewController
- (void)notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:(id)model;
@end

@interface _TtC26IGNotesBubbleCreationSwift41IGDirectNotesBubbleEditorColorPaletteView : UIView
@end

@interface _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController : UIViewController
@property (nonatomic) IGDirectNotesComposerViewController *delegate;
@end

@interface IGDSBottomButtonsView : UIView
- (void)setPrimaryButtonEnabled:(BOOL)enabled;
- (void)setSecondaryButtonEnabled:(BOOL)enabled;
@end

@interface IGStoryTrayViewModel : NSObject
@property (nonatomic, readonly) NSString *pk;
@property (nonatomic, readonly) BOOL isUnseenNux;
@end

@interface _TtC32IGSundialOrganicCTAContainerView32IGSundialOrganicCTAContainerView : UIView
@end

@interface IGCommentThreadViewController : UIViewController
@end

// Comment composer input bar — found via IG strings scan ("IGCommentComposerView", "commentComposerView:didTapStickerEntryButton:")
@interface IGCommentComposerView : UIView
@end

@interface IGSeeAllItemConfiguration : NSObject
@property (readonly, nonatomic) long long destination;
@end

@interface IGCommentThreadConfiguration : NSObject
@end

@interface IGDSMenuItem : NSObject
@end

@interface IGDirectAudioWaveform : NSObject
- (id)initWithVolumeRecordingInterval:(double)interval averageVolume:(NSArray *)volumes;
+ (NSArray *)generateWaveformDataFromAudioFile:(NSURL *)url maxLength:(NSInteger)maxLength;
+ (NSArray *)scaledArrayOfNumbers:(NSArray *)numbers;
@end

@interface IGDirectThreadViewController : UIViewController
- (void)markLastMessageAsSeen;
- (id)voiceController;
- (id)messageSenderFeatureController;
@end

@interface IGDirectMessageSenderFeatureController : NSObject
@end

@interface MDCoreDelta : NSObject
@end

@interface IGTabBarButton : UIButton
- (void)addHandleLongPress; // new
@end

@interface IGStoryFullscreenDefaultFooterView : NSObject
@end

@interface IGDirectThreadThemePickerOption : NSObject
@end

@interface IGCreationActionBarButton : UIButton
@end

@interface IGCreationActionBarLabeledButton : NSObject
@property (readonly, nonatomic) IGCreationActionBarButton *button;
@end

// Call buttons in DM thread header. Coordinator owns _audioCallButton / _videoCallButton
// (both IGDirectCallButton) and forwards taps to _didTapAudioButton: / _didTapVideoButton:.
// Discovered by dumping the thread VC view hierarchy for IGDirectCallButton.
@interface IGDirectThreadCallButtonsCoordinator : NSObject @end
@interface IGDirectCallButton : UIView @end

// IG's UINavigationBar subclass — hosts the iOS 26 liquid-glass platter layout.
@interface IGNavigationBar : UINavigationBar @end

// DM thread background + message bubble views — OLED chat theme.
@interface IGDirectThreadBackgroundImageView : UIImageView @end
@interface IGDirectMessageBubbleView : UIView @end

// UIKit-private keyboard classes — OLED keyboard theme.
@interface UIKBBackdropView : UIView @end
@interface UIKBKeyplaneChargedView : UIView @end

// IGListKit adapter — used across feed tray, share sheet, etc.
@interface IGListAdapter : NSObject
- (void)performUpdatesAnimated:(BOOL)animated completion:(void (^)(BOOL))completion;
- (id)objectAtSection:(NSInteger)section; // new
- (id)dataSource; // new
@end

// Reels/feed video cell — used for long-press zoom gesture attachment.
@interface IGFeedItemPageVideoCell : UICollectionViewCell @end

// Profile page view controller — `user` is the IGUser being displayed.
@interface IGProfileViewController : UIViewController
@property (nonatomic, strong) id user;
@end

// Notes thought-bubble view on profiles — the note's touch target.
@interface IGDirectNotesThoughtBubbleView : UIView @end



/////////////////////////////////////////////////////////////////////////////



static BOOL is_iPad() {
    if ([(NSString *)[UIDevice currentDevice].model hasPrefix:@"iPad"]) {
        return YES;
    }
    return NO;
}



/////////////////////////////////////////////////////////////////////////////



static UIViewController * _Nullable _topMostController(UIViewController * _Nonnull cont) {
    UIViewController *topController = cont;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    if ([topController isKindOfClass:[UINavigationController class]]) {
        UIViewController *visible = ((UINavigationController *)topController).visibleViewController;
        if (visible) {
            topController = visible;
        }
    }
    return (topController != cont ? topController : nil);
}
static UIViewController * _Nonnull topMostController() {
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    UIViewController *next = nil;
    while ((next = _topMostController(topController)) != nil) {
        topController = next;
    }
    return topController;
}

@class FLEXAlert, FLEXAlertAction;

typedef void (^FLEXAlertReveal)(void);
typedef void (^FLEXAlertBuilder)(FLEXAlert *make);
typedef FLEXAlert * _Nonnull (^FLEXAlertStringProperty)(NSString * _Nullable);
typedef FLEXAlert * _Nonnull (^FLEXAlertStringArg)(NSString * _Nullable);
typedef FLEXAlert * _Nonnull (^FLEXAlertTextField)(void(^configurationHandler)(UITextField *textField));
typedef FLEXAlertAction * _Nonnull (^FLEXAlertAddAction)(NSString *title);
typedef FLEXAlertAction * _Nonnull (^FLEXAlertActionStringProperty)(NSString * _Nullable);
typedef FLEXAlertAction * _Nonnull (^FLEXAlertActionProperty)(void);
typedef FLEXAlertAction * _Nonnull (^FLEXAlertActionBOOLProperty)(BOOL);
typedef FLEXAlertAction * _Nonnull (^FLEXAlertActionHandler)(void(^handler)(NSArray<NSString *> *strings));

@interface FLEXAlert : NSObject

// Shows a simple alert with one button which says "Dismiss"
+ (void)showAlert:(NSString * _Nullable)title message:(NSString * _Nullable)message from:(UIViewController *)viewController;

// Shows a simple alert with no buttons and only a title, for half a second
+ (void)showQuickAlert:(NSString *)title from:(UIViewController *)viewController;

// Construct and display an alert
+ (void)makeAlert:(FLEXAlertBuilder)block showFrom:(UIViewController *)viewController;
// Construct and display an action sheet-style alert
+ (void)makeSheet:(FLEXAlertBuilder)block
         showFrom:(UIViewController *)viewController
           source:(id)viewOrBarItem;

// Construct an alert
+ (UIAlertController *)makeAlert:(FLEXAlertBuilder)block;
// Construct an action sheet-style alert
+ (UIAlertController *)makeSheet:(FLEXAlertBuilder)block;

// Set the alert's title.
///
// Call in succession to append strings to the title.
@property (nonatomic, readonly) FLEXAlertStringProperty title;
// Set the alert's message.
///
// Call in succession to append strings to the message.
@property (nonatomic, readonly) FLEXAlertStringProperty message;
// Add a button with a given title with the default style and no action.
@property (nonatomic, readonly) FLEXAlertAddAction button;
// Add a text field with the given (optional) placeholder text.
@property (nonatomic, readonly) FLEXAlertStringArg textField;
// Add and configure the given text field.
///
// Use this if you need to more than set the placeholder, such as
// supply a delegate, make it secure entry, or change other attributes.
@property (nonatomic, readonly) FLEXAlertTextField configuredTextField;

@end

@interface FLEXAlertAction : NSObject

// Set the action's title.
///
// Call in succession to append strings to the title.
@property (nonatomic, readonly) FLEXAlertActionStringProperty title;
// Make the action destructive. It appears with red text.
@property (nonatomic, readonly) FLEXAlertActionProperty destructiveStyle;
// Make the action cancel-style. It appears with a bolder font.
@property (nonatomic, readonly) FLEXAlertActionProperty cancelStyle;
// Enable or disable the action. Enabled by default.
@property (nonatomic, readonly) FLEXAlertActionBOOLProperty enabled;
// Give the button an action. The action takes an array of text field strings.
@property (nonatomic, readonly) FLEXAlertActionHandler handler;
// Access the underlying UIAlertAction, should you need to change it while
// the encompassing alert is being displayed. For example, you may want to
// enable or disable a button based on the input of some text fields in the alert.
// Do not call this more than once per instance.
@property (nonatomic, readonly) UIAlertAction *action;

@end
@interface FLEXManager : NSObject
+ (instancetype)sharedManager;
- (void)showExplorer;
- (void)hideExplorer;
- (void)toggleExplorer;
@end

// IGLive classes — discovered via runtime ivar/method dump.
@interface IGLiveFeedbackController : NSObject
- (void)start;
- (void)stop;
@end

@interface IGLiveCommentsContainerViewController : UIViewController
- (void)setIsHidden:(BOOL)hidden;
- (void)setDisabled:(BOOL)disabled;
@end

// Story/reel sticker views — data accessors resolved at runtime.
@interface IGQuizStickerView : UIView
@end

@interface IGPollStickerView : UIView
@end

@interface IGPollStickerV2View : UIView
@end

@interface IGSliderStickerView : UIView
@end

// Photo sticker picker — preferredMediaTypes is an array of PHAssetMediaType numbers.
@interface IGStickerGalleryViewController : UIViewController
@end

// Composer sticker tray data source — hooked to inject the quiz model.
@interface IGStoryStickerDataSourceImpl : NSObject
- (NSArray *)items;
@end

@interface IGQuizStickerTrayModel : NSObject
@property (nonatomic) BOOL isBoostEligible;
@property (nonatomic, copy) id stickerSection;
@property (nonatomic, copy) NSArray *prompts;
@end

// Reveal/Secret sticker — blur story until viewer DMs the author.
@interface IGSecretStickerTrayModel : NSObject
@property (nonatomic, copy) id stickerSection;
@end

// Swift class _TtC15IGSecretSticker26IGSecretStickerOverlayView — bound at runtime.
@interface IGSecretStickerOverlayView : UIView
- (void)setPreviewBlurEnabled:(BOOL)enabled;
@end

// Swift class _TtC25IGMagicModExperimentation30IGGenAIRestyleExperimentHelper.
@interface IGGenAIRestyleExperimentHelper : NSObject
+ (BOOL)isRevealStickerEnabledWithLauncherSet:(id)set;
+ (BOOL)isRevealStickerConsumptionEnabledWithLauncherSet:(id)set;
@end

// Reels audio detail. Swift class _TtC16IGAudioPageSwift26IGAudioPageHeaderActionBar — share/save header bar.
@interface IGAudioPageHeaderActionBar : UIView
@end

// Reels audio detail VC — owns _audioAsset / _music / _originalAudio.
@interface IGAudioPageViewController : UIViewController
@end

// Quick-reaction emoji button under an Instant. UIControl with a `text` ivar
// holding the emoji glyph. Found via runtime view dump.
@interface IGBouncyTextButton : UIControl
@end

// Bloks-rendered netego feed cell (e.g. "Try free AI creation tools").
@interface IGBloksFeedCell : UICollectionViewCell
@property (nonatomic, strong) id bloksFeedUnitModel;
@end

// IGListKit section controller backing IGBloksFeedCell.
@interface IGBloksNetegoSectionController : NSObject
- (NSInteger)numberOfItems;
- (CGSize)sizeForItemAtIndex:(NSInteger)index;
@end