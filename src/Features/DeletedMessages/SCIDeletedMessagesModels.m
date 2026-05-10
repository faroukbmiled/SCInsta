#import "SCIDeletedMessagesModels.h"
#import "../../Localization/SCILocalization.h"

NSString *SCIDeletedMessageKindToString(SCIDeletedMessageKind kind) {
    switch (kind) {
        case SCIDeletedMessageKindText:    return @"text";
        case SCIDeletedMessageKindPhoto:   return @"photo";
        case SCIDeletedMessageKindVideo:   return @"video";
        case SCIDeletedMessageKindVoice:   return @"voice";
        case SCIDeletedMessageKindGif:     return @"gif";
        case SCIDeletedMessageKindSticker: return @"sticker";
        case SCIDeletedMessageKindShare:   return @"share";
        case SCIDeletedMessageKindLink:    return @"link";
        case SCIDeletedMessageKindAudioShare: return @"audio_share";
        case SCIDeletedMessageKindOther:   return @"other";
        case SCIDeletedMessageKindUnknown:
        default:                           return @"unknown";
    }
}

SCIDeletedMessageKind SCIDeletedMessageKindFromString(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return SCIDeletedMessageKindUnknown;
    if ([s isEqualToString:@"text"])    return SCIDeletedMessageKindText;
    if ([s isEqualToString:@"photo"])   return SCIDeletedMessageKindPhoto;
    if ([s isEqualToString:@"video"])   return SCIDeletedMessageKindVideo;
    if ([s isEqualToString:@"voice"])   return SCIDeletedMessageKindVoice;
    if ([s isEqualToString:@"gif"])     return SCIDeletedMessageKindGif;
    if ([s isEqualToString:@"sticker"]) return SCIDeletedMessageKindSticker;
    if ([s isEqualToString:@"share"])   return SCIDeletedMessageKindShare;
    if ([s isEqualToString:@"link"])    return SCIDeletedMessageKindLink;
    if ([s isEqualToString:@"audio_share"]) return SCIDeletedMessageKindAudioShare;
    if ([s isEqualToString:@"other"])   return SCIDeletedMessageKindOther;
    return SCIDeletedMessageKindUnknown;
}

NSString *SCIDeletedMessageKindLocalizedName(SCIDeletedMessageKind kind) {
    switch (kind) {
        case SCIDeletedMessageKindText:    return SCILocalized(@"Text");
        case SCIDeletedMessageKindPhoto:   return SCILocalized(@"Photo");
        case SCIDeletedMessageKindVideo:   return SCILocalized(@"Video");
        case SCIDeletedMessageKindVoice:   return SCILocalized(@"Voice");
        case SCIDeletedMessageKindGif:     return SCILocalized(@"GIF");
        case SCIDeletedMessageKindSticker: return SCILocalized(@"Sticker");
        case SCIDeletedMessageKindShare:   return SCILocalized(@"Share");
        case SCIDeletedMessageKindLink:    return SCILocalized(@"Link");
        case SCIDeletedMessageKindAudioShare: return SCILocalized(@"Audio");
        case SCIDeletedMessageKindOther:   return SCILocalized(@"Other");
        case SCIDeletedMessageKindUnknown:
        default:                           return SCILocalized(@"Unknown");
    }
}

NSString *SCIDeletedMessageKindSymbol(SCIDeletedMessageKind kind) {
    switch (kind) {
        case SCIDeletedMessageKindText:    return @"text.bubble.fill";
        case SCIDeletedMessageKindPhoto:   return @"photo.fill";
        case SCIDeletedMessageKindVideo:   return @"video.fill";
        case SCIDeletedMessageKindVoice:   return @"waveform";
        case SCIDeletedMessageKindGif:     return @"square.stack.fill";
        case SCIDeletedMessageKindSticker: return @"face.smiling.fill";
        case SCIDeletedMessageKindShare:   return @"arrowshape.turn.up.right.fill";
        case SCIDeletedMessageKindLink:    return @"link";
        case SCIDeletedMessageKindAudioShare: return @"music.note";
        case SCIDeletedMessageKindOther:   return @"bubble.left.fill";
        case SCIDeletedMessageKindUnknown:
        default:                           return @"bubble.left.fill";
    }
}

static NSDate *sciDateFromJSON(id v) {
    if ([v isKindOfClass:[NSNumber class]]) return [NSDate dateWithTimeIntervalSince1970:[v doubleValue]];
    return nil;
}
static NSNumber *sciDateToJSON(NSDate *d) {
    return d ? @(d.timeIntervalSince1970) : nil;
}
static NSString *sciStr(id v) {
    return [v isKindOfClass:[NSString class]] ? v : nil;
}
static double sciDouble(id v) {
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : 0;
}

@implementation SCIDeletedMessage

+ (instancetype)messageFromJSONDict:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    SCIDeletedMessage *m = [SCIDeletedMessage new];
    m.messageId            = sciStr(dict[@"message_id"]);
    m.threadId             = sciStr(dict[@"thread_id"]);
    m.threadTitle          = sciStr(dict[@"thread_title"]);
    m.senderPk             = sciStr(dict[@"sender_pk"]);
    m.senderUsername       = sciStr(dict[@"sender_username"]);
    m.senderFullName       = sciStr(dict[@"sender_full_name"]);
    m.senderProfilePicURL  = sciStr(dict[@"sender_profile_pic_url"]);
    m.sentAt               = sciDateFromJSON(dict[@"sent_at"]);
    m.capturedAt           = sciDateFromJSON(dict[@"captured_at"]);
    m.deletedAt            = sciDateFromJSON(dict[@"deleted_at"]);
    m.kind                 = SCIDeletedMessageKindFromString(sciStr(dict[@"kind"]));
    m.text                 = sciStr(dict[@"text"]);
    m.previewText          = sciStr(dict[@"preview"]);
    m.mediaURL             = sciStr(dict[@"media_url"]);
    m.mediaPath            = sciStr(dict[@"media_path"]);
    m.thumbnailURL         = sciStr(dict[@"thumbnail_url"]);
    m.thumbnailPath        = sciStr(dict[@"thumbnail_path"]);
    m.mediaMimeType        = sciStr(dict[@"media_mime"]);
    m.durationSeconds      = sciDouble(dict[@"duration"]);
    id wf = dict[@"waveform"];
    if ([wf isKindOfClass:[NSArray class]]) m.waveform = wf;
    m.width                = sciDouble(dict[@"width"]);
    m.height               = sciDouble(dict[@"height"]);
    m.replyToMessageId     = sciStr(dict[@"reply_to_id"]);
    if (!m.messageId.length || !m.senderPk.length) return nil;
    return m;
}

- (NSDictionary *)toJSONDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.messageId)            d[@"message_id"]            = self.messageId;
    if (self.threadId)             d[@"thread_id"]             = self.threadId;
    if (self.threadTitle.length)   d[@"thread_title"]          = self.threadTitle;
    if (self.senderPk)             d[@"sender_pk"]             = self.senderPk;
    if (self.senderUsername)       d[@"sender_username"]       = self.senderUsername;
    if (self.senderFullName)       d[@"sender_full_name"]      = self.senderFullName;
    if (self.senderProfilePicURL)  d[@"sender_profile_pic_url"]= self.senderProfilePicURL;
    if (self.sentAt)               d[@"sent_at"]               = sciDateToJSON(self.sentAt);
    if (self.capturedAt)           d[@"captured_at"]           = sciDateToJSON(self.capturedAt);
    if (self.deletedAt)            d[@"deleted_at"]            = sciDateToJSON(self.deletedAt);
    d[@"kind"]                     = SCIDeletedMessageKindToString(self.kind);
    if (self.text.length)          d[@"text"]                  = self.text;
    if (self.previewText.length)   d[@"preview"]               = self.previewText;
    if (self.mediaURL)             d[@"media_url"]             = self.mediaURL;
    if (self.mediaPath)            d[@"media_path"]            = self.mediaPath;
    if (self.thumbnailURL)         d[@"thumbnail_url"]         = self.thumbnailURL;
    if (self.thumbnailPath)        d[@"thumbnail_path"]        = self.thumbnailPath;
    if (self.mediaMimeType)        d[@"media_mime"]            = self.mediaMimeType;
    if (self.durationSeconds > 0)  d[@"duration"]              = @(self.durationSeconds);
    if (self.waveform.count)       d[@"waveform"]              = self.waveform;
    if (self.width > 0)            d[@"width"]                 = @(self.width);
    if (self.height > 0)           d[@"height"]                = @(self.height);
    if (self.replyToMessageId.length) d[@"reply_to_id"]        = self.replyToMessageId;
    return d;
}

@end

@implementation SCIDeletedMessageGroup

- (NSUInteger)count { return self.messages.count; }
- (NSDate *)lastDeletedAt { return self.latest.deletedAt ?: self.latest.capturedAt; }
- (SCIDeletedMessage *)latest { return self.messages.firstObject; }

@end
