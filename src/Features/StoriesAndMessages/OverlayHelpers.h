// Shared helpers for StoryOverlayButtons.xm and DMOverlayButtons.xm.

#import "StoryHelpers.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"

// Disjoint tag spaces so viewWithTag: can't cross-hit between surfaces.
#define SCI_STORY_EYE_TAG       1339
#define SCI_STORY_ACTION_TAG    1340
#define SCI_STORY_AUDIO_TAG     1341
#define SCI_DM_ACTION_TAG       1342
#define SCI_DM_EYE_TAG          1343
#define SCI_DM_AUDIO_TAG        1344
#define SCI_STORY_MENTIONS_TAG  1345

#ifdef __cplusplus
extern "C" {
#endif

// From StoryAudioToggle.xm.
void sciToggleStoryAudio(void);
BOOL sciIsStoryAudioEnabled(void);
void sciInitStoryAudioState(void);

#ifdef __cplusplus
}
#endif
extern BOOL dmVisualMsgsViewedButtonEnabled;
#ifdef __cplusplus
extern "C" {
#endif

// Context detection / view lookup.
BOOL sciOverlayIsInDMContext(UIView *overlay);
UIView * _Nullable sciFindOverlayInView(UIView *root);

// DM disappearing-media actions.
NSURL * _Nullable sciDMMediaURL(UIViewController *dmVC, BOOL *outIsVideo);
void sciDMExpandMedia(UIViewController *dmVC);
void sciDMShareMedia(UIViewController *dmVC);
void sciDMDownloadMedia(UIViewController *dmVC);
void sciDMDownloadMediaToGallery(UIViewController *dmVC);
void sciDMMarkCurrentAsViewed(UIViewController *dmVC);

// DM message → save metadata (sender PK + username + profile pic via the
// shared user resolver).
SCIGallerySaveMetadata *sciDMMetadataFromMessage(id msg);
SCIGallerySaveMetadata *sciDMMetadataForVC(UIViewController *dmVC);

// Opens RyukGram settings on the Messages tab.
void sciOpenMessagesSettings(UIView *source);

// Story mentions sheet (StoryMentions.x).
void sciShowStoryMentions(UIViewController *presenter, UIView *anchor);
BOOL sciStoryHasMentionsOrShares(UIView *anchor);
NSInteger sciStoryMentionsCount(UIView *anchor);

#ifdef __cplusplus
}
#endif
