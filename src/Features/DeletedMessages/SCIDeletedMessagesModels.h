#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIDeletedMessageKind) {
    SCIDeletedMessageKindUnknown = 0,
    SCIDeletedMessageKindText,
    SCIDeletedMessageKindPhoto,
    SCIDeletedMessageKindVideo,
    SCIDeletedMessageKindVoice,
    SCIDeletedMessageKindGif,
    SCIDeletedMessageKindSticker,
    SCIDeletedMessageKindShare,
    SCIDeletedMessageKindLink,
    SCIDeletedMessageKindAudioShare,
    SCIDeletedMessageKindOther,
};

FOUNDATION_EXPORT NSString *SCIDeletedMessageKindToString(SCIDeletedMessageKind kind);
FOUNDATION_EXPORT SCIDeletedMessageKind SCIDeletedMessageKindFromString(NSString * _Nullable s);
FOUNDATION_EXPORT NSString *SCIDeletedMessageKindLocalizedName(SCIDeletedMessageKind kind);
FOUNDATION_EXPORT NSString *SCIDeletedMessageKindSymbol(SCIDeletedMessageKind kind);

@interface SCIDeletedMessage : NSObject

@property (nonatomic, copy)   NSString *messageId;
@property (nonatomic, copy)   NSString *threadId;
@property (nonatomic, copy, nullable) NSString *threadTitle;

@property (nonatomic, copy)   NSString *senderPk;
@property (nonatomic, copy, nullable) NSString *senderUsername;
@property (nonatomic, copy, nullable) NSString *senderFullName;
@property (nonatomic, copy, nullable) NSString *senderProfilePicURL;

@property (nonatomic, strong) NSDate   *sentAt;
@property (nonatomic, strong) NSDate   *capturedAt;
@property (nonatomic, strong) NSDate   *deletedAt;

@property (nonatomic, assign) SCIDeletedMessageKind kind;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *previewText;

@property (nonatomic, copy, nullable) NSString *mediaURL;
@property (nonatomic, copy, nullable) NSString *mediaPath;       // relative under media root
@property (nonatomic, copy, nullable) NSString *thumbnailURL;
@property (nonatomic, copy, nullable) NSString *thumbnailPath;
@property (nonatomic, copy, nullable) NSString *mediaMimeType;

@property (nonatomic, assign) double   durationSeconds;          // voice/video
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *waveform;
@property (nonatomic, assign) CGFloat  width;
@property (nonatomic, assign) CGFloat  height;

// Server id of the message this one was a reply to (when applicable).
// Captured best-effort from metadata / KVC probes.
@property (nonatomic, copy, nullable) NSString *replyToMessageId;

+ (instancetype)messageFromJSONDict:(NSDictionary *)dict;
- (NSDictionary *)toJSONDict;

@end

// Convenience aggregate built on read for the top VC.
@interface SCIDeletedMessageGroup : NSObject
@property (nonatomic, copy) NSString *senderPk;
@property (nonatomic, copy, nullable) NSString *senderUsername;
@property (nonatomic, copy, nullable) NSString *senderFullName;
@property (nonatomic, copy, nullable) NSString *senderProfilePicURL;
@property (nonatomic, strong) NSArray<SCIDeletedMessage *> *messages; // newest-first
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly, nullable) NSDate *lastDeletedAt;
@property (nonatomic, readonly, nullable) SCIDeletedMessage *latest;
@end

NS_ASSUME_NONNULL_END
