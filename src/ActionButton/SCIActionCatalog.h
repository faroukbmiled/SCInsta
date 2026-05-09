// SCIActionCatalog — registry of available action menu entries per source +
// the default section layout for each source. Used by SCIActionMenuConfig as
// the schema source of truth.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIActionSource) {
    SCIActionSourceFeed = 0,
    SCIActionSourceReels,
    SCIActionSourceStories,
    SCIActionSourceDM,
    SCIActionSourceProfile,
    SCIActionSourceInstants,
    SCIActionSourceCount
};

// MARK: - Action ID constants

// Common (Feed/Reels/Stories)
extern NSString *const SCIAID_Expand;
extern NSString *const SCIAID_ViewCover;        // Feed videos, Reels
extern NSString *const SCIAID_Repost;
extern NSString *const SCIAID_CopyCaption;
extern NSString *const SCIAID_CopyURL;
extern NSString *const SCIAID_DownloadShare;
extern NSString *const SCIAID_DownloadSave;     // to Photos
extern NSString *const SCIAID_DownloadGallery;  // to RyukGram Gallery (no-op until Phase 2)
extern NSString *const SCIAID_BulkCopyURLs;
extern NSString *const SCIAID_BulkDownloadShare;
extern NSString *const SCIAID_BulkDownloadSave;
extern NSString *const SCIAID_BulkDownloadGallery;
extern NSString *const SCIAID_Settings;

// Stories-only
extern NSString *const SCIAID_ViewMentions;
extern NSString *const SCIAID_ToggleAudio;
extern NSString *const SCIAID_ExcludeUser;

// DM-only
extern NSString *const SCIAID_DMMarkSeen;

// Profile-only
extern NSString *const SCIAID_CopyInfo;          // submenu (id/username/name/bio/link)
extern NSString *const SCIAID_ViewPicture;
extern NSString *const SCIAID_SharePicture;
extern NSString *const SCIAID_SavePictureGallery;
extern NSString *const SCIAID_ProfileSettings;
extern NSString *const SCIAID_ProfileInfoPrivacy;     // disabled info row: privacy
extern NSString *const SCIAID_ProfileInfoFollowers;   // disabled info row: follower count
extern NSString *const SCIAID_ProfileInfoFollowing;   // disabled info row: following count

// Profile copy-info sub-IDs (for default copy info pref)
extern NSString *const SCIAID_CopyID;
extern NSString *const SCIAID_CopyUsername;
extern NSString *const SCIAID_CopyName;
extern NSString *const SCIAID_CopyBio;
extern NSString *const SCIAID_CopyLink;
extern NSString *const SCIAID_CopyAll;       // Copies username/name/bio/link/ID as labeled lines

// MARK: - Models

@interface SCIActionDescriptor : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *title;       // localized fallback
@property (nonatomic, copy, readonly) NSString *iconSF;      // SF symbol fallback
@property (nonatomic, assign, readonly) BOOL eligibleForDefaultTap;
/// Off in fresh installs (still selectable in the configure screen).
@property (nonatomic, assign, readonly) BOOL disabledByDefault;
+ (instancetype)descriptorWithID:(NSString *)identifier
                            title:(NSString *)title
                           iconSF:(NSString *)iconSF
              eligibleForDefaultTap:(BOOL)eligible
                  disabledByDefault:(BOOL)disabledByDefault;
@end

@interface SCIActionConfigSection : NSObject <NSCopying>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconSF;
@property (nonatomic, assign) BOOL collapsible;
@property (nonatomic, strong) NSMutableArray<NSString *> *actionIDs;
+ (instancetype)sectionWithID:(NSString *)identifier
                         title:(NSString *)title
                        iconSF:(NSString *)iconSF
                   collapsible:(BOOL)collapsible
                       actions:(NSArray<NSString *> *)actions;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)sectionFromDictionary:(NSDictionary *)dict;
@end

@interface SCIActionCatalog : NSObject
+ (NSArray<SCIActionDescriptor *> *)descriptorsForSource:(SCIActionSource)source;
+ (nullable SCIActionDescriptor *)descriptorForActionID:(NSString *)actionID
                                                  source:(SCIActionSource)source;
+ (NSArray<SCIActionConfigSection *> *)defaultSectionsForSource:(SCIActionSource)source;
+ (BOOL)sourceSupportsDate:(SCIActionSource)source;
+ (BOOL)sourceSupportsDefaultTap:(SCIActionSource)source;
+ (NSString *)displayNameForSource:(SCIActionSource)source;
+ (NSString *)slugForSource:(SCIActionSource)source;   // "feed"/"reels"/...
+ (NSString *)prefKeyForSource:(SCIActionSource)source; // action_menu_cfg_<slug>
+ (NSString *)legacyDefaultTapPrefKeyForSource:(SCIActionSource)source;  // <slug>_action_default
+ (NSString *)legacyDateTogglePrefKeyForSource:(SCIActionSource)source;  // menu_date_<slug>, nil for DM/Profile

@end

NS_ASSUME_NONNULL_END
