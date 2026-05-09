#import "SCIActionCatalog.h"
#import "../Localization/SCILocalization.h"

// MARK: - Action ID constants

NSString *const SCIAID_Expand              = @"expand";
NSString *const SCIAID_ViewCover           = @"view_cover";
NSString *const SCIAID_Repost              = @"repost";
NSString *const SCIAID_CopyCaption         = @"copy_caption";
NSString *const SCIAID_CopyURL             = @"copy_url";
NSString *const SCIAID_DownloadShare       = @"download_share";
NSString *const SCIAID_DownloadSave        = @"download_save";
NSString *const SCIAID_DownloadGallery     = @"download_gallery";
NSString *const SCIAID_BulkCopyURLs        = @"bulk_copy_urls";
NSString *const SCIAID_BulkDownloadShare   = @"bulk_download_share";
NSString *const SCIAID_BulkDownloadSave    = @"bulk_download_save";
NSString *const SCIAID_BulkDownloadGallery = @"bulk_download_gallery";
NSString *const SCIAID_Settings            = @"settings";

NSString *const SCIAID_ViewMentions        = @"view_mentions";
NSString *const SCIAID_ToggleAudio         = @"toggle_audio";
NSString *const SCIAID_ExcludeUser         = @"exclude_user";

NSString *const SCIAID_DMMarkSeen          = @"dm_mark_seen";

NSString *const SCIAID_CopyInfo            = @"copy_info";
NSString *const SCIAID_ViewPicture         = @"view_picture";
NSString *const SCIAID_SharePicture        = @"share_picture";
NSString *const SCIAID_SavePictureGallery  = @"save_picture_gallery";
NSString *const SCIAID_ProfileSettings        = @"profile_settings";
NSString *const SCIAID_ProfileInfoPrivacy     = @"profile_info_privacy";
NSString *const SCIAID_ProfileInfoFollowers   = @"profile_info_followers";
NSString *const SCIAID_ProfileInfoFollowing   = @"profile_info_following";

NSString *const SCIAID_CopyID              = @"copy_id";
NSString *const SCIAID_CopyUsername        = @"copy_username";
NSString *const SCIAID_CopyName            = @"copy_name";
NSString *const SCIAID_CopyBio             = @"copy_bio";
NSString *const SCIAID_CopyLink            = @"copy_link";
NSString *const SCIAID_CopyAll             = @"copy_all";

// MARK: - Models

@implementation SCIActionDescriptor
+ (instancetype)descriptorWithID:(NSString *)identifier
                            title:(NSString *)title
                           iconSF:(NSString *)iconSF
              eligibleForDefaultTap:(BOOL)eligible
                  disabledByDefault:(BOOL)disabledByDefault {
    SCIActionDescriptor *d = [SCIActionDescriptor new];
    d->_identifier = [identifier copy];
    d->_title = [title copy];
    d->_iconSF = [iconSF copy];
    d->_eligibleForDefaultTap = eligible;
    d->_disabledByDefault = disabledByDefault;
    return d;
}
@end

@implementation SCIActionConfigSection
+ (instancetype)sectionWithID:(NSString *)identifier
                         title:(NSString *)title
                        iconSF:(NSString *)iconSF
                   collapsible:(BOOL)collapsible
                       actions:(NSArray<NSString *> *)actions {
    SCIActionConfigSection *s = [SCIActionConfigSection new];
    s.identifier = identifier;
    s.title = title ?: @"";
    s.iconSF = iconSF ?: @"";
    s.collapsible = collapsible;
    s.actionIDs = [(actions ?: @[]) mutableCopy];
    return s;
}
- (id)copyWithZone:(NSZone *)zone {
    return [SCIActionConfigSection sectionWithID:self.identifier
                                            title:self.title
                                           iconSF:self.iconSF
                                      collapsible:self.collapsible
                                          actions:self.actionIDs];
}
- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"id": self.identifier ?: @"",
        @"title": self.title ?: @"",
        @"icon": self.iconSF ?: @"",
        @"collapsible": @(self.collapsible),
        @"actions": [self.actionIDs copy] ?: @[],
    };
}
+ (instancetype)sectionFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSString *identifier = dict[@"id"];
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) return nil;
    NSString *title = [dict[@"title"] isKindOfClass:[NSString class]] ? dict[@"title"] : @"";
    NSString *icon  = [dict[@"icon"]  isKindOfClass:[NSString class]] ? dict[@"icon"]  : @"";
    BOOL collapsible = [dict[@"collapsible"] respondsToSelector:@selector(boolValue)]
                       ? [dict[@"collapsible"] boolValue] : NO;
    NSArray *actions = [dict[@"actions"] isKindOfClass:[NSArray class]] ? dict[@"actions"] : @[];
    NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:actions.count];
    for (id v in actions) if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) [cleaned addObject:v];
    return [SCIActionConfigSection sectionWithID:identifier title:title iconSF:icon collapsible:collapsible actions:cleaned];
}
@end

// MARK: - Catalog

static NSDictionary<NSNumber *, NSArray *> *gSCIActionCatalogCache = nil;

@implementation SCIActionCatalog

+ (void)initialize {
    if (self == [SCIActionCatalog class]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:@"SCILanguageDidChange"
                                                          object:nil queue:nil
                                                      usingBlock:^(NSNotification *_) {
            gSCIActionCatalogCache = nil;
        }];
    }
}

+ (NSString *)slugForSource:(SCIActionSource)source {
    switch (source) {
        case SCIActionSourceFeed: return @"feed";
        case SCIActionSourceReels: return @"reels";
        case SCIActionSourceStories: return @"stories";
        case SCIActionSourceDM: return @"dm";
        case SCIActionSourceProfile: return @"profile";
        case SCIActionSourceInstants: return @"instants";
        case SCIActionSourceCount: break;
    }
    return @"unknown";
}

+ (NSString *)displayNameForSource:(SCIActionSource)source {
    switch (source) {
        case SCIActionSourceFeed: return SCILocalized(@"Feed");
        case SCIActionSourceReels: return SCILocalized(@"Reels");
        case SCIActionSourceStories: return SCILocalized(@"Stories");
        case SCIActionSourceDM: return SCILocalized(@"DM disappearing media");
        case SCIActionSourceProfile: return SCILocalized(@"Profile");
        case SCIActionSourceInstants: return SCILocalized(@"Instants");
        case SCIActionSourceCount: break;
    }
    return @"";
}

+ (NSString *)prefKeyForSource:(SCIActionSource)source {
    return [NSString stringWithFormat:@"action_menu_cfg_%@", [self slugForSource:source]];
}

+ (NSString *)legacyDefaultTapPrefKeyForSource:(SCIActionSource)source {
    switch (source) {
        case SCIActionSourceFeed:    return @"feed_action_default";
        case SCIActionSourceReels:   return @"reels_action_default";
        case SCIActionSourceStories: return @"stories_action_default";
        case SCIActionSourceDM:      return @"dm_visual_action_default";
        case SCIActionSourceProfile: return @"action_button_profile_default_action";
        case SCIActionSourceInstants: return nil;  // new source, no legacy migration
        case SCIActionSourceCount: break;
    }
    return nil;
}

+ (NSString *)legacyDateTogglePrefKeyForSource:(SCIActionSource)source {
    switch (source) {
        case SCIActionSourceFeed:    return @"menu_date_feed";
        case SCIActionSourceReels:   return @"menu_date_reels";
        case SCIActionSourceStories: return @"menu_date_stories";
        default: return nil;
    }
}

+ (BOOL)sourceSupportsDate:(SCIActionSource)source {
    return [self legacyDateTogglePrefKeyForSource:source] != nil;
}

+ (BOOL)sourceSupportsDefaultTap:(SCIActionSource)source {
    // All sources support default tap selection.
    return source != SCIActionSourceCount;
}

+ (NSArray<SCIActionDescriptor *> *)descriptorsForSource:(SCIActionSource)source {
    if (!gSCIActionCatalogCache) {
        SCIActionDescriptor *(^d)(NSString *, NSString *, NSString *, BOOL) =
            ^(NSString *i, NSString *t, NSString *sf, BOOL eligible) {
                return [SCIActionDescriptor descriptorWithID:i title:t iconSF:sf
                                       eligibleForDefaultTap:eligible
                                           disabledByDefault:NO];
            };
        // Variant: ship off in fresh installs (gallery rows).
        SCIActionDescriptor *(^dOff)(NSString *, NSString *, NSString *, BOOL) =
            ^(NSString *i, NSString *t, NSString *sf, BOOL eligible) {
                return [SCIActionDescriptor descriptorWithID:i title:t iconSF:sf
                                       eligibleForDefaultTap:eligible
                                           disabledByDefault:YES];
            };

        // Feed
        NSArray *feed = @[
            d(SCIAID_Expand,              SCILocalized(@"Expand"),                 @"arrow.up.left.and.arrow.down.right", YES),
            d(SCIAID_ViewCover,           SCILocalized(@"View cover"),             @"photo",                              YES),
            d(SCIAID_Repost,              SCILocalized(@"Repost"),                 @"arrow.2.squarepath",                 YES),
            d(SCIAID_CopyCaption,         SCILocalized(@"Copy caption"),           @"text.quote",                         NO),
            d(SCIAID_CopyURL,             SCILocalized(@"Copy media URL"),         @"link",                               YES),
            d(SCIAID_DownloadShare,       SCILocalized(@"Download and share"),     @"square.and.arrow.up",                YES),
            d(SCIAID_DownloadSave,        SCILocalized(@"Download to Photos"),     @"square.and.arrow.down",              YES),
         dOff(SCIAID_DownloadGallery,     SCILocalized(@"Download to Gallery"),    @"photo.on.rectangle.angled",          YES),
            d(SCIAID_BulkCopyURLs,        SCILocalized(@"Copy all URLs"),          @"doc.on.doc",                         NO),
            d(SCIAID_BulkDownloadShare,   SCILocalized(@"Download and share all"), @"square.and.arrow.up.on.square",      NO),
            d(SCIAID_BulkDownloadSave,    SCILocalized(@"Download all to Photos"), @"square.and.arrow.down.on.square",    NO),
         dOff(SCIAID_BulkDownloadGallery, SCILocalized(@"Download all to Gallery"),@"square.stack.3d.down.right",         NO),
            d(SCIAID_Settings,            SCILocalized(@"Feed settings"),          @"gearshape",                          NO),
        ];

        // Reels — same as feed minus a few
        NSArray *reels = @[
            d(SCIAID_Expand,              SCILocalized(@"Expand"),                 @"arrow.up.left.and.arrow.down.right", YES),
            d(SCIAID_ViewCover,           SCILocalized(@"View cover"),             @"photo",                              YES),
            d(SCIAID_Repost,              SCILocalized(@"Repost"),                 @"arrow.2.squarepath",                 YES),
            d(SCIAID_CopyCaption,         SCILocalized(@"Copy caption"),           @"text.quote",                         NO),
            d(SCIAID_CopyURL,             SCILocalized(@"Copy media URL"),         @"link",                               YES),
            d(SCIAID_DownloadShare,       SCILocalized(@"Download and share"),     @"square.and.arrow.up",                YES),
            d(SCIAID_DownloadSave,        SCILocalized(@"Download to Photos"),     @"square.and.arrow.down",              YES),
         dOff(SCIAID_DownloadGallery,     SCILocalized(@"Download to Gallery"),    @"photo.on.rectangle.angled",          YES),
            d(SCIAID_Settings,            SCILocalized(@"Reels settings"),         @"gearshape",                          NO),
        ];

        // Stories
        NSArray *stories = @[
            d(SCIAID_Expand,              SCILocalized(@"Expand"),                 @"arrow.up.left.and.arrow.down.right", YES),
            d(SCIAID_Repost,              SCILocalized(@"Repost"),                 @"arrow.2.squarepath",                 YES),
            d(SCIAID_ViewMentions,        SCILocalized(@"View mentions"),          @"at",                                 YES),
            d(SCIAID_ToggleAudio,         SCILocalized(@"Mute / unmute audio"),    @"speaker.wave.2",                     NO),
            d(SCIAID_ExcludeUser,         SCILocalized(@"Exclude/include user"),   @"eye.slash",                          NO),
            d(SCIAID_CopyURL,             SCILocalized(@"Copy media URL"),         @"link",                               YES),
            d(SCIAID_DownloadShare,       SCILocalized(@"Download and share"),     @"square.and.arrow.up",                YES),
            d(SCIAID_DownloadSave,        SCILocalized(@"Download to Photos"),     @"square.and.arrow.down",              YES),
         dOff(SCIAID_DownloadGallery,     SCILocalized(@"Download to Gallery"),    @"photo.on.rectangle.angled",          YES),
            d(SCIAID_BulkCopyURLs,        SCILocalized(@"Copy all URLs"),          @"doc.on.doc",                         NO),
            d(SCIAID_BulkDownloadShare,   SCILocalized(@"Download and share all"), @"square.and.arrow.up.on.square",      NO),
            d(SCIAID_BulkDownloadSave,    SCILocalized(@"Download all to Photos"), @"square.and.arrow.down.on.square",    NO),
         dOff(SCIAID_BulkDownloadGallery, SCILocalized(@"Download all to Gallery"),@"square.stack.3d.down.right",         NO),
            d(SCIAID_Settings,            SCILocalized(@"Stories settings"),       @"gearshape",                          NO),
        ];

        // DM disappearing media
        NSArray *dm = @[
            d(SCIAID_Expand,              SCILocalized(@"Expand"),                 @"arrow.up.left.and.arrow.down.right", YES),
            d(SCIAID_DownloadShare,       SCILocalized(@"Download and share"),     @"square.and.arrow.up",                YES),
            d(SCIAID_DownloadSave,        SCILocalized(@"Download to Photos"),     @"square.and.arrow.down",              YES),
         dOff(SCIAID_DownloadGallery,     SCILocalized(@"Download to Gallery"),    @"photo.on.rectangle.angled",          YES),
            d(SCIAID_DMMarkSeen,          SCILocalized(@"Mark as viewed"),         @"eye",                                YES),
            d(SCIAID_Settings,            SCILocalized(@"Messages settings"),      @"gearshape",                          NO),
        ];

        // Profile
        NSArray *profile = @[
            d(SCIAID_CopyUsername,          SCILocalized(@"Copy username"),          @"at",                                 YES),
            d(SCIAID_CopyName,              SCILocalized(@"Copy name"),              @"text.cursor",                        YES),
            d(SCIAID_CopyBio,               SCILocalized(@"Copy bio"),               @"text.quote",                         YES),
            d(SCIAID_CopyLink,              SCILocalized(@"Copy profile link"),      @"link",                               YES),
            d(SCIAID_CopyID,                SCILocalized(@"Copy ID"),                @"number",                             YES),
            d(SCIAID_CopyAll,               SCILocalized(@"Copy all info"),          @"square.on.square",                   YES),
            d(SCIAID_ViewPicture,           SCILocalized(@"View picture"),           @"photo",                              YES),
            d(SCIAID_SharePicture,          SCILocalized(@"Share picture"),          @"square.and.arrow.up",                YES),
         dOff(SCIAID_SavePictureGallery,    SCILocalized(@"Save picture to Gallery"),@"photo.on.rectangle.angled",          YES),
            d(SCIAID_ProfileSettings,       SCILocalized(@"Profile settings"),       @"gearshape",                          YES),
            d(SCIAID_ProfileInfoPrivacy,    SCILocalized(@"Privacy"),                @"lock",                               NO),
            d(SCIAID_ProfileInfoFollowers,  SCILocalized(@"Followers"),              @"person.2",                           NO),
            d(SCIAID_ProfileInfoFollowing,  SCILocalized(@"Following"),              @"person.crop.circle.badge.plus",      NO),
        ];

        // Instants — reuses the standard download/share AIDs with Instants-
        // specific titles ("Save to Photos" rather than "Download to Photos").
        NSArray *instants = @[
            d(SCIAID_Expand,              SCILocalized(@"Expand"),               @"arrow.up.left.and.arrow.down.right", YES),
            d(SCIAID_DownloadSave,        SCILocalized(@"Save to Photos"),       @"square.and.arrow.down",              YES),
         dOff(SCIAID_DownloadGallery,     SCILocalized(@"Save to Gallery"),      @"photo.on.rectangle.angled",          YES),
            d(SCIAID_DownloadShare,       SCILocalized(@"Share"),                @"square.and.arrow.up",                YES),
            d(SCIAID_BulkDownloadSave,    SCILocalized(@"Save all to Photos"),   @"square.and.arrow.down.on.square",    NO),
         dOff(SCIAID_BulkDownloadGallery, SCILocalized(@"Save all to Gallery"),  @"rectangle.stack",                    NO),
        ];

        gSCIActionCatalogCache = @{
            @(SCIActionSourceFeed):     feed,
            @(SCIActionSourceReels):    reels,
            @(SCIActionSourceStories):  stories,
            @(SCIActionSourceDM):       dm,
            @(SCIActionSourceProfile):  profile,
            @(SCIActionSourceInstants): instants,
        };
    }
    return gSCIActionCatalogCache[@(source)] ?: @[];
}

+ (SCIActionDescriptor *)descriptorForActionID:(NSString *)actionID source:(SCIActionSource)source {
    if (!actionID.length) return nil;
    for (SCIActionDescriptor *d in [self descriptorsForSource:source]) {
        if ([d.identifier isEqualToString:actionID]) return d;
    }
    return nil;
}

+ (NSArray<SCIActionConfigSection *> *)defaultSectionsForSource:(SCIActionSource)source {
    SCIActionConfigSection *(^section)(NSString *, NSString *, NSString *, BOOL, NSArray *) =
        ^(NSString *identifier, NSString *title, NSString *icon, BOOL collapsible, NSArray *actions) {
            return [SCIActionConfigSection sectionWithID:identifier
                                                    title:title
                                                   iconSF:icon
                                              collapsible:collapsible
                                                  actions:actions];
        };

    switch (source) {
        case SCIActionSourceFeed:
            return @[
                section(@"navigation",
                        SCILocalized(@"Navigation"), @"square.grid.2x2", NO,
                        @[SCIAID_Expand, SCIAID_ViewCover, SCIAID_Repost, SCIAID_Settings]),
                section(@"copy",
                        SCILocalized(@"Copy"), @"doc.on.doc", NO,
                        @[SCIAID_CopyCaption, SCIAID_CopyURL]),
                section(@"download",
                        SCILocalized(@"Download"), @"arrow.down.circle", NO,
                        @[SCIAID_DownloadShare, SCIAID_DownloadSave, SCIAID_DownloadGallery]),
                section(@"bulk",
                        SCILocalized(@"Bulk download"), @"square.stack.3d.down.right", YES,
                        @[SCIAID_BulkCopyURLs, SCIAID_BulkDownloadShare, SCIAID_BulkDownloadSave, SCIAID_BulkDownloadGallery]),
            ];

        case SCIActionSourceReels:
            return @[
                section(@"navigation",
                        SCILocalized(@"Navigation"), @"square.grid.2x2", NO,
                        @[SCIAID_Expand, SCIAID_ViewCover, SCIAID_Repost, SCIAID_Settings]),
                section(@"copy",
                        SCILocalized(@"Copy"), @"doc.on.doc", NO,
                        @[SCIAID_CopyCaption, SCIAID_CopyURL]),
                section(@"download",
                        SCILocalized(@"Download"), @"arrow.down.circle", NO,
                        @[SCIAID_DownloadShare, SCIAID_DownloadSave, SCIAID_DownloadGallery]),
            ];

        case SCIActionSourceStories:
            return @[
                section(@"navigation",
                        SCILocalized(@"Navigation"), @"square.grid.2x2", NO,
                        @[SCIAID_Expand, SCIAID_Repost, SCIAID_ViewMentions, SCIAID_Settings]),
                section(@"audio",
                        SCILocalized(@"Audio & visibility"), @"slider.horizontal.3", NO,
                        @[SCIAID_ToggleAudio, SCIAID_ExcludeUser]),
                section(@"copy",
                        SCILocalized(@"Copy"), @"doc.on.doc", NO,
                        @[SCIAID_CopyURL]),
                section(@"download",
                        SCILocalized(@"Download"), @"arrow.down.circle", NO,
                        @[SCIAID_DownloadShare, SCIAID_DownloadSave, SCIAID_DownloadGallery]),
                section(@"bulk",
                        SCILocalized(@"Bulk download"), @"square.stack.3d.down.right", YES,
                        @[SCIAID_BulkCopyURLs, SCIAID_BulkDownloadShare, SCIAID_BulkDownloadSave, SCIAID_BulkDownloadGallery]),
            ];

        case SCIActionSourceDM:
            return @[
                section(@"navigation",
                        SCILocalized(@"Navigation"), @"square.grid.2x2", NO,
                        @[SCIAID_Expand, SCIAID_DMMarkSeen, SCIAID_Settings]),
                section(@"download",
                        SCILocalized(@"Download"), @"arrow.down.circle", NO,
                        @[SCIAID_DownloadShare, SCIAID_DownloadSave, SCIAID_DownloadGallery]),
            ];

        case SCIActionSourceProfile:
            return @[
                section(@"copy_info",
                        SCILocalized(@"Copy Info"), @"doc.on.doc", YES,
                        @[SCIAID_CopyUsername, SCIAID_CopyName, SCIAID_CopyBio, SCIAID_CopyLink, SCIAID_CopyID, SCIAID_CopyAll]),
                section(@"navigation",
                        SCILocalized(@"Profile"), @"square.grid.2x2", NO,
                        @[SCIAID_ViewPicture, SCIAID_SharePicture, SCIAID_SavePictureGallery, SCIAID_ProfileSettings]),
                section(@"info",
                        SCILocalized(@"Info"), @"info.circle", NO,
                        @[SCIAID_ProfileInfoPrivacy, SCIAID_ProfileInfoFollowers, SCIAID_ProfileInfoFollowing]),
            ];

        case SCIActionSourceInstants:
            return @[
                section(@"current",
                        SCILocalized(@"Current instant"), @"sparkles", NO,
                        @[SCIAID_Expand, SCIAID_DownloadSave, SCIAID_DownloadGallery, SCIAID_DownloadShare]),
                section(@"all",
                        SCILocalized(@"All loaded instants"), @"square.stack.3d.down.right", YES,
                        @[SCIAID_BulkDownloadSave, SCIAID_BulkDownloadGallery]),
            ];

        case SCIActionSourceCount: break;
    }
    return @[];
}

@end
