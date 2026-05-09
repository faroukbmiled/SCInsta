#import <CoreData/CoreData.h>
#import <UIKit/UIKit.h>

#import "SCIGallerySaveMetadata.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int16_t, SCIGalleryMediaType) {
    SCIGalleryMediaTypeImage = 0,
    SCIGalleryMediaTypeVideo = 1,
    SCIGalleryMediaTypeAudio = 2,
    SCIGalleryMediaTypeGIF   = 3
};

FOUNDATION_EXPORT NSString *SCIFileNameForMedia(NSURL *originalURL, SCIGalleryMediaType mediaType, SCIGallerySaveMetadata * _Nullable metadata);

/// Lower-cased extension → mediaType. Returns Image as fallback for unknown.
FOUNDATION_EXPORT SCIGalleryMediaType SCIGalleryMediaTypeForExtension(NSString * _Nullable ext);

/// YES for audio extensions (m4a, aac, mp3, ogg, opus, wav, aiff, flac).
FOUNDATION_EXPORT BOOL SCIGalleryExtensionIsAudio(NSString * _Nullable ext);


typedef NS_ENUM(int16_t, SCIGallerySource) {
    SCIGallerySourceOther   = 0,
    SCIGallerySourceFeed    = 1,
    SCIGallerySourceStories = 2,
    SCIGallerySourceReels   = 3,
    SCIGallerySourceProfile = 4,
    SCIGallerySourceDMs     = 5,
    SCIGallerySourceThumbnail = 6,
    SCIGallerySourceNotes   = 7,
    SCIGallerySourceComments = 8,
    SCIGallerySourceInstants = 9
};

@interface SCIGalleryFile : NSManagedObject

@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, strong) NSString *relativePath;
@property (nonatomic) int16_t mediaType;
@property (nonatomic) int16_t source;
@property (nonatomic, strong) NSDate *dateAdded;
@property (nonatomic) int64_t fileSize;
@property (nonatomic) BOOL isFavorite;
@property (nonatomic, copy, nullable) NSString *folderPath;
@property (nonatomic, copy, nullable) NSString *customName;
@property (nonatomic, copy, nullable) NSString *sourceUsername;
@property (nonatomic, copy, nullable) NSString *sourceUserPK;
@property (nonatomic, copy, nullable) NSString *sourceProfileURLString;
@property (nonatomic, copy, nullable) NSString *sourceMediaPK;
@property (nonatomic, copy, nullable) NSString *sourceMediaCode;
@property (nonatomic, copy, nullable) NSString *sourceMediaURLString;
@property (nonatomic) int32_t pixelWidth;
@property (nonatomic) int32_t pixelHeight;
@property (nonatomic) double durationSeconds;

+ (nullable SCIGalleryFile *)saveFileToGallery:(NSURL *)fileURL
                                        source:(SCIGallerySource)source
                                     mediaType:(SCIGalleryMediaType)mediaType
                                         error:(NSError **)error;

/// Convenience: adds to gallery inside the given folder.
+ (nullable SCIGalleryFile *)saveFileToGallery:(NSURL *)fileURL
                                        source:(SCIGallerySource)source
                                     mediaType:(SCIGalleryMediaType)mediaType
                                    folderPath:(nullable NSString *)folderPath
                                         error:(NSError **)error;

/// When `metadata` is non-nil, its fields override `source` and populate list UI. File is probed for any missing dimensions/duration.
+ (nullable SCIGalleryFile *)saveFileToGallery:(NSURL *)fileURL
                                        source:(SCIGallerySource)source
                                     mediaType:(SCIGalleryMediaType)mediaType
                                    folderPath:(nullable NSString *)folderPath
                                      metadata:(nullable SCIGallerySaveMetadata *)metadata
                                         error:(NSError **)error;

- (BOOL)removeWithError:(NSError *_Nullable *_Nullable)error;

- (NSString *)filePath;
- (NSURL *)fileURL;
- (BOOL)fileExists;
- (NSString *)thumbnailPath;
- (BOOL)thumbnailExists;

/// User-facing display name — customName if set, else the portion of relativePath after the timestamp prefix.
- (NSString *)displayName;

/// Human-readable label for the source type.
- (NSString *)sourceLabel;

/// Short label for origin pill (e.g. Reel, Feed).
- (NSString *)shortSourceLabel;

/// Primary line in list mode: username when known, else `displayName`.
- (NSString *)listPrimaryTitle;

/// Second line: duration · size · resolution · bitrate (video), or size · resolution (image).
- (NSString *)listTechnicalLine;

/// Third line: human-readable download date (e.g. Apr 17 at 2:04 AM).
- (NSString *)listDownloadDateString;
- (nullable NSURL *)preferredProfileURL;
- (nullable NSURL *)preferredOriginalMediaURL;
- (BOOL)hasOpenableProfile;
- (BOOL)hasOpenableOriginalMedia;

+ (NSString *)shortLabelForSource:(SCIGallerySource)source;

+ (void)generateThumbnailForFile:(SCIGalleryFile *)file
                      completion:(void(^_Nullable)(BOOL success))completion;

+ (nullable UIImage *)loadThumbnailForFile:(SCIGalleryFile *)file;

/// Returns a human-readable label for the given source.
+ (NSString *)labelForSource:(SCIGallerySource)source;

/// Returns the symbol name for the given source.
+ (NSString *)symbolNameForSource:(SCIGallerySource)source;

@end

NS_ASSUME_NONNULL_END
