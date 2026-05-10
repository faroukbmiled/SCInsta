#import "SCIDeletedMessagesUserDetailViewController.h"
#import "../../UI/SCIPopupChrome.h"
#import "SCIDeletedMessagesStorage.h"
#import "SCIDeletedMessagesFilter.h"
#import "../../Utils.h"
#import "../../SCIURLOpener.h"
#import "../../UI/SCIScrollToTopButton.h"
#import "../../SCIImageCache.h"
#import "../../QuickLook.h"
#import "../../PhotoAlbum.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Localization/SCILocalization.h"
#import "SCIDeletedMessagesDate.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <QuickLook/QuickLook.h>
#import <objc/runtime.h>

#pragma mark - Adaptive message cell

static const CGFloat kSCIDMBubbleMaxWidth = 260.0;
static const CGFloat kSCIDMMediaSize       = 220.0;
static const CGFloat kSCIDMVoiceWidth        = 245.0;
static const CGFloat kSCIDMVoiceWidthPlaying = 295.0;
static const CGFloat kSCIDMBubbleCorner    = 18.0;

@interface SCIDMMessageCell : UITableViewCell

@property (nonatomic, strong) UIView   *bubble;
@property (nonatomic, strong) UILabel  *metaLabel;
@property (nonatomic, strong) UIView   *bubbleContent;
@property (nonatomic, strong) NSLayoutConstraint *bubbleMaxWidth;
@property (nonatomic, strong) NSLayoutConstraint *bubbleLeading;  // shifted right in selection mode

@property (nonatomic, copy) void (^onBubbleTap)(void);
@property (nonatomic, copy) void (^onVoicePlayTap)(void);
@property (nonatomic, copy) void (^onVoiceSeekTo)(double seconds);
@property (nonatomic, copy) void (^onCellTap)(void);

@property (nonatomic, copy)   NSString *messageId;
@property (nonatomic, assign) BOOL isVoicePlaying;
@property (nonatomic, assign) double voiceDuration;
@property (nonatomic, weak)   UISlider *voiceSlider;
@property (nonatomic, weak)   UILabel  *voiceDurationLabel;
@property (nonatomic, weak)   UIButton *voicePlayButton;
@property (nonatomic, strong) NSLayoutConstraint *voiceDurationLabelWidth;
@property (nonatomic, assign) CGFloat voiceDurationIdleWidth;
@property (nonatomic, assign) CGFloat voiceDurationPlayingWidth;

@property (nonatomic, strong) UIImageView *checkbox;
@property (nonatomic, assign) BOOL inSelectionMode;
@property (nonatomic, assign) BOOL isSelectedForBulk;
@property (nonatomic, assign) BOOL selectableForBulk;
- (void)applySelectionMode:(BOOL)on selected:(BOOL)selected selectable:(BOOL)selectable;

- (void)applyMessage:(SCIDeletedMessage *)m
              ownerPK:(NSString *)ownerPK
              playing:(BOOL)playing;

- (void)setVoiceProgressSeconds:(double)seconds;

+ (NSString *)shareTypeLabelForURL:(NSString * _Nullable)urlString fallbackKind:(SCIDeletedMessageKind)kind;
+ (BOOL)shareLabelIsNonUserCard:(NSString *)label;

@end

@implementation SCIDMMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.layoutMargins = UIEdgeInsetsMake(4, 16, 4, 16);

        _bubble = [UIView new];
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        _bubble.layer.cornerRadius = kSCIDMBubbleCorner;
        _bubble.layer.cornerCurve  = kCACornerCurveContinuous;
        _bubble.layer.masksToBounds = YES;
        _bubble.userInteractionEnabled = YES;
        [self.contentView addSubview:_bubble];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bubbleTapped)];
        [_bubble addGestureRecognizer:tap];

        UITapGestureRecognizer *cellTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                  action:@selector(contentTapped)];
        cellTap.cancelsTouchesInView = NO;
        [self.contentView addGestureRecognizer:cellTap];

        _checkbox = [UIImageView new];
        _checkbox.translatesAutoresizingMaskIntoConstraints = NO;
        _checkbox.contentMode = UIViewContentModeCenter;
        _checkbox.tintColor = [UIColor tertiaryLabelColor];
        _checkbox.alpha = 0;
        _checkbox.image = [UIImage systemImageNamed:@"circle"];
        [self.contentView addSubview:_checkbox];

        _metaLabel = [UILabel new];
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metaLabel.font = [UIFont systemFontOfSize:11];
        _metaLabel.textColor = [UIColor tertiaryLabelColor];
        [self.contentView addSubview:_metaLabel];

        UILayoutGuide *m = self.contentView.layoutMarginsGuide;
        _bubbleMaxWidth = [_bubble.widthAnchor constraintLessThanOrEqualToConstant:kSCIDMBubbleMaxWidth];
        _bubbleLeading  = [_bubble.leadingAnchor constraintEqualToAnchor:m.leadingAnchor];
        [NSLayoutConstraint activateConstraints:@[
            _bubbleLeading,
            [_bubble.topAnchor     constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_bubble.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor constant:-32],
            _bubbleMaxWidth,

            [_metaLabel.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:6],
            [_metaLabel.topAnchor     constraintEqualToAnchor:_bubble.bottomAnchor constant:4],
            [_metaLabel.bottomAnchor  constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],

            [_checkbox.leadingAnchor  constraintEqualToAnchor:m.leadingAnchor],
            [_checkbox.centerYAnchor  constraintEqualToAnchor:_bubble.centerYAnchor],
            [_checkbox.widthAnchor    constraintEqualToConstant:24],
            [_checkbox.heightAnchor   constraintEqualToConstant:24],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self resetBubble];
    self.metaLabel.text = nil;
    self.onBubbleTap = nil;
    self.onVoicePlayTap = nil;
    self.onVoiceSeekTo  = nil;
    self.onCellTap      = nil;
    self.isVoicePlaying = NO;
    self.messageId = nil;
}

- (void)resetBubble {
    if (self.bubbleContent) {
        [self.bubbleContent removeFromSuperview];
        self.bubbleContent = nil;
    }
    self.bubble.backgroundColor = [UIColor clearColor];
    self.bubbleMaxWidth.constant = kSCIDMBubbleMaxWidth;
    self.voiceDurationLabelWidth = nil;
}

- (void)bubbleTapped {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    if (self.onCellTap) { self.onCellTap(); return; }
    if (self.onBubbleTap) self.onBubbleTap();
}

- (void)contentTapped {
    if (!self.onCellTap) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    self.onCellTap();
}

#pragma mark - Apply

- (void)applyMessage:(SCIDeletedMessage *)m ownerPK:(NSString *)ownerPK playing:(BOOL)playing {
    [self resetBubble];
    self.messageId = m.messageId;
    self.isVoicePlaying = playing;

    NSString *kindName = SCIDeletedMessageKindLocalizedName(m.kind);
    NSString *time = [SCIDeletedMessagesDate stringForDate:(m.deletedAt ?: m.capturedAt ?: m.sentAt)];
    self.metaLabel.text = (kindName.length && time.length)
        ? [NSString stringWithFormat:@"%@ · %@", kindName, time]
        : (time.length ? time : kindName);

    if (m.kind == SCIDeletedMessageKindText && m.text.length) {
        [self installTextBubble:m.text];
    } else if (m.kind == SCIDeletedMessageKindVoice) {
        [self installVoiceBubble:m];
    } else if (m.kind == SCIDeletedMessageKindPhoto
               || m.kind == SCIDeletedMessageKindVideo
               || m.kind == SCIDeletedMessageKindGif) {
        [self installMediaBubble:m ownerPK:ownerPK];
    } else if (m.kind == SCIDeletedMessageKindSticker) {
        [self installStickerBubble:m ownerPK:ownerPK];
    } else if (m.kind == SCIDeletedMessageKindShare
               || m.kind == SCIDeletedMessageKindLink
               || m.kind == SCIDeletedMessageKindAudioShare) {
        [self installShareBubble:m ownerPK:ownerPK];
    } else {
        [self installPlaceholderBubble:m];
    }
}

#pragma mark - Variants

- (void)installTextBubble:(NSString *)text {
    self.bubble.backgroundColor = [UIColor secondarySystemBackgroundColor];
    UILabel *l = [UILabel new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    l.font = [UIFont systemFontOfSize:15.5];
    l.textColor = [UIColor labelColor];
    l.numberOfLines = 0;
    l.text = text;
    [self.bubble addSubview:l];
    self.bubbleContent = l;
    [NSLayoutConstraint activateConstraints:@[
        [l.topAnchor      constraintEqualToAnchor:self.bubble.topAnchor      constant:9],
        [l.bottomAnchor   constraintEqualToAnchor:self.bubble.bottomAnchor   constant:-9],
        [l.leadingAnchor  constraintEqualToAnchor:self.bubble.leadingAnchor  constant:14],
        [l.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-14],
    ]];
}

- (void)installMediaBubble:(SCIDeletedMessage *)m ownerPK:(NSString *)ownerPK {
    self.bubbleMaxWidth.constant = kSCIDMMediaSize;

    UIImageView *iv = [UIImageView new];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.layer.cornerRadius = kSCIDMBubbleCorner;
    iv.layer.masksToBounds = YES;
    iv.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [self.bubble addSubview:iv];
    self.bubbleContent = iv;

    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor      constraintEqualToAnchor:self.bubble.topAnchor],
        [iv.bottomAnchor   constraintEqualToAnchor:self.bubble.bottomAnchor],
        [iv.leadingAnchor  constraintEqualToAnchor:self.bubble.leadingAnchor],
        [iv.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor],
        [iv.widthAnchor    constraintEqualToConstant:kSCIDMMediaSize],
        [iv.heightAnchor   constraintEqualToConstant:kSCIDMMediaSize],
    ]];

    NSString *localPath = [SCIDeletedMessagesStorage absolutePathForRelativePath:(m.thumbnailPath ?: m.mediaPath) ownerPK:ownerPK];
    UIImage *local = localPath ? [UIImage imageWithContentsOfFile:localPath] : nil;
    if (local) {
        iv.image = local;
    } else if ((m.thumbnailURL ?: m.mediaURL).length) {
        __weak UIImageView *weakIV = iv;
        [SCIImageCache loadImageFromURL:[NSURL URLWithString:(m.thumbnailURL ?: m.mediaURL)]
                             completion:^(UIImage *img) {
            if (img) weakIV.image = img;
        }];
    }
    if (!local && !(m.thumbnailURL ?: m.mediaURL).length) {
        // No image bytes — render kind glyph placeholder.
        UIImageView *glyph = [UIImageView new];
        glyph.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:48 weight:UIImageSymbolWeightLight];
        glyph.image = [UIImage systemImageNamed:SCIDeletedMessageKindSymbol(m.kind) withConfiguration:cfg];
        glyph.tintColor = [UIColor tertiaryLabelColor];
        [iv addSubview:glyph];
        [NSLayoutConstraint activateConstraints:@[
            [glyph.centerXAnchor constraintEqualToAnchor:iv.centerXAnchor],
            [glyph.centerYAnchor constraintEqualToAnchor:iv.centerYAnchor],
        ]];
    }

    if (m.kind == SCIDeletedMessageKindVideo) {
        UIImageView *play = [UIImageView new];
        play.translatesAutoresizingMaskIntoConstraints = NO;
        play.tintColor = [UIColor whiteColor];
        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:48 weight:UIImageSymbolWeightSemibold];
        play.image = [UIImage systemImageNamed:@"play.circle.fill" withConfiguration:cfg];
        play.layer.shadowOpacity = 0.4;
        play.layer.shadowOffset = CGSizeMake(0, 1);
        play.layer.shadowRadius = 4;
        [iv addSubview:play];
        [NSLayoutConstraint activateConstraints:@[
            [play.centerXAnchor constraintEqualToAnchor:iv.centerXAnchor],
            [play.centerYAnchor constraintEqualToAnchor:iv.centerYAnchor],
        ]];
    }
}

- (void)installStickerBubble:(SCIDeletedMessage *)m ownerPK:(NSString *)ownerPK {
    self.bubbleMaxWidth.constant = 110;
    UIImageView *iv = [UIImageView new];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.layer.cornerRadius = 0;
    [self.bubble addSubview:iv];
    self.bubbleContent = iv;
    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor      constraintEqualToAnchor:self.bubble.topAnchor],
        [iv.bottomAnchor   constraintEqualToAnchor:self.bubble.bottomAnchor],
        [iv.leadingAnchor  constraintEqualToAnchor:self.bubble.leadingAnchor],
        [iv.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor],
        [iv.widthAnchor    constraintEqualToConstant:104],
        [iv.heightAnchor   constraintEqualToConstant:104],
    ]];
    NSString *localPath = [SCIDeletedMessagesStorage absolutePathForRelativePath:(m.thumbnailPath ?: m.mediaPath) ownerPK:ownerPK];
    UIImage *local = localPath ? [UIImage imageWithContentsOfFile:localPath] : nil;
    if (local) {
        iv.image = local;
    } else if ((m.thumbnailURL ?: m.mediaURL).length) {
        __weak UIImageView *weakIV = iv;
        [SCIImageCache loadImageFromURL:[NSURL URLWithString:(m.thumbnailURL ?: m.mediaURL)]
                             completion:^(UIImage *img) { if (img) weakIV.image = img; }];
    } else {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:40 weight:UIImageSymbolWeightLight];
        iv.image = [UIImage systemImageNamed:@"face.smiling.fill" withConfiguration:cfg];
        iv.tintColor = [UIColor systemTealColor];
    }
}

- (void)installVoiceBubble:(SCIDeletedMessage *)m {
    self.bubbleMaxWidth.constant = self.isVoicePlaying ? kSCIDMVoiceWidthPlaying : kSCIDMVoiceWidth;
    UIColor *primary = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];
    self.bubble.backgroundColor = [primary colorWithAlphaComponent:0.18];
    self.voiceDuration = m.durationSeconds;

    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bubble addSubview:row];
    self.bubbleContent = row;

    UIButton *playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    playBtn.translatesAutoresizingMaskIntoConstraints = NO;
    playBtn.tintColor = primary;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
    NSString *glyph = self.isVoicePlaying ? @"pause.circle.fill" : @"play.circle.fill";
    [playBtn setImage:[UIImage systemImageNamed:glyph withConfiguration:cfg] forState:UIControlStateNormal];
    [playBtn addTarget:self action:@selector(playButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:playBtn];
    self.voicePlayButton = playBtn;

    // Bars are visual; slider on top takes the touches.
    UIView *seekerStack = [UIView new];
    seekerStack.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:seekerStack];

    UIStackView *bars = [[UIStackView alloc] init];
    bars.translatesAutoresizingMaskIntoConstraints = NO;
    bars.axis = UILayoutConstraintAxisHorizontal;
    bars.alignment = UIStackViewAlignmentCenter;
    bars.distribution = UIStackViewDistributionFillEqually;
    bars.spacing = 2;
    bars.userInteractionEnabled = NO;
    [seekerStack addSubview:bars];

    UISlider *slider = [UISlider new];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = 0;
    slider.maximumValue = MAX(0.1, m.durationSeconds);
    slider.value = 0;
    UIImage *clearTrack = [SCIDMMessageCell clearTrackImage];
    [slider setMinimumTrackImage:clearTrack forState:UIControlStateNormal];
    [slider setMaximumTrackImage:clearTrack forState:UIControlStateNormal];
    [slider setThumbImage:[SCIDMMessageCell sliderThumbImageForColor:primary] forState:UIControlStateNormal];
    [slider addTarget:self action:@selector(sliderTouchBegan:) forControlEvents:UIControlEventTouchDown];
    [slider addTarget:self action:@selector(sliderTouchEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [slider addTarget:self action:@selector(sliderChanged:)    forControlEvents:UIControlEventValueChanged];
    [seekerStack addSubview:slider];
    self.voiceSlider = slider;

    UILabel *dur = [UILabel new];
    dur.translatesAutoresizingMaskIntoConstraints = NO;
    dur.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
    dur.textColor = primary;
    dur.numberOfLines = 1;
    dur.textAlignment = NSTextAlignmentRight;
    dur.lineBreakMode = NSLineBreakByClipping;
    NSString *idleText = [SCIDMMessageCell formatDuration:m.durationSeconds];
    NSString *playingText = [NSString stringWithFormat:@"%@ / %@",
        [SCIDMMessageCell formatDuration:0], idleText];
    dur.text = self.isVoicePlaying ? playingText : idleText;
    NSDictionary *attrs = @{NSFontAttributeName: dur.font};
    self.voiceDurationIdleWidth    = ceil([idleText    sizeWithAttributes:attrs].width) + 2;
    self.voiceDurationPlayingWidth = ceil([playingText sizeWithAttributes:attrs].width) + 2;
    [dur setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [dur setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [row addSubview:dur];
    self.voiceDurationLabel = dur;

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor      constraintEqualToAnchor:self.bubble.topAnchor      constant:8],
        [row.bottomAnchor   constraintEqualToAnchor:self.bubble.bottomAnchor   constant:-8],
        [row.leadingAnchor  constraintEqualToAnchor:self.bubble.leadingAnchor  constant:10],
        [row.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-12],
        [row.heightAnchor   constraintEqualToConstant:38],

        [playBtn.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [playBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [playBtn.widthAnchor   constraintEqualToConstant:34],
        [playBtn.heightAnchor  constraintEqualToConstant:34],

        [seekerStack.leadingAnchor  constraintEqualToAnchor:playBtn.trailingAnchor constant:6],
        [seekerStack.trailingAnchor constraintEqualToAnchor:dur.leadingAnchor      constant:-6],
        [seekerStack.topAnchor      constraintEqualToAnchor:row.topAnchor],
        [seekerStack.bottomAnchor   constraintEqualToAnchor:row.bottomAnchor],

        [bars.leadingAnchor  constraintEqualToAnchor:seekerStack.leadingAnchor],
        [bars.trailingAnchor constraintEqualToAnchor:seekerStack.trailingAnchor],
        [bars.topAnchor      constraintEqualToAnchor:seekerStack.topAnchor    constant:8],
        [bars.bottomAnchor   constraintEqualToAnchor:seekerStack.bottomAnchor constant:-8],

        [slider.leadingAnchor  constraintEqualToAnchor:seekerStack.leadingAnchor],
        [slider.trailingAnchor constraintEqualToAnchor:seekerStack.trailingAnchor],
        [slider.centerYAnchor  constraintEqualToAnchor:seekerStack.centerYAnchor],

        [dur.trailingAnchor  constraintEqualToAnchor:row.trailingAnchor],
        [dur.centerYAnchor   constraintEqualToAnchor:row.centerYAnchor],
    ]];
    self.voiceDurationLabelWidth = [dur.widthAnchor constraintEqualToConstant:
        (self.isVoicePlaying ? self.voiceDurationPlayingWidth : self.voiceDurationIdleWidth)];
    self.voiceDurationLabelWidth.active = YES;

    NSArray<NSNumber *> *raw = m.waveform.count ? m.waveform : nil;
    NSArray<NSNumber *> *samples = raw ? [SCIDMMessageCell resampleWaveform:raw to:42] : nil;
    NSInteger count = samples ? (NSInteger)samples.count : 32;
    UIColor *waveColor = [primary colorWithAlphaComponent:0.55];
    for (NSInteger i = 0; i < count; i++) {
        UIView *bar = [UIView new];
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        bar.backgroundColor = waveColor;
        bar.layer.cornerRadius = 1;
        CGFloat amp = samples ? MIN(1.0, MAX(0.08, samples[i].doubleValue)) : (0.25 + 0.7 * ((i % 7) / 7.0));
        [bars addArrangedSubview:bar];
        [bar.heightAnchor constraintEqualToAnchor:bars.heightAnchor multiplier:amp].active = YES;
        [bar.widthAnchor  constraintEqualToConstant:2.5].active = YES;
    }
}

// Clear 1×1 so the slider track doesn't cover the waveform bars.
+ (UIImage *)clearTrackImage {
    static UIImage *img;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1)];
        img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIColor clearColor] setFill];
            UIRectFill(CGRectMake(0, 0, 1, 1));
        }];
        img = [img resizableImageWithCapInsets:UIEdgeInsetsZero];
    });
    return img;
}

// Cached per color so cell reuse doesn't redraw.
+ (UIImage *)sliderThumbImageForColor:(UIColor *)color {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    NSString *key = color.description ?: @"default";
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    CGSize size = CGSizeMake(12, 12);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size.width, size.height)] fill];
    }];
    [cache setObject:img forKey:key];
    return img;
}

- (void)playButtonTapped {
    if (self.onVoicePlayTap) self.onVoicePlayTap();
}

#pragma mark - Voice slider plumbing

static char kSCIDMVoiceDraggingKey;

- (BOOL)voiceIsDragging { return [objc_getAssociatedObject(self, &kSCIDMVoiceDraggingKey) boolValue]; }
- (void)setVoiceIsDragging:(BOOL)v {
    objc_setAssociatedObject(self, &kSCIDMVoiceDraggingKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)sliderTouchBegan:(UISlider *)s { [self setVoiceIsDragging:YES]; }
- (void)sliderTouchEnded:(UISlider *)s {
    [self setVoiceIsDragging:NO];
    if (self.onVoiceSeekTo) self.onVoiceSeekTo((double)s.value);
}
- (void)sliderChanged:(UISlider *)s {
    self.voiceDurationLabel.text = [NSString stringWithFormat:@"%@ / %@",
        [SCIDMMessageCell formatDuration:s.value],
        [SCIDMMessageCell formatDuration:self.voiceDuration]];
}

- (void)setVoiceProgressSeconds:(double)seconds {
    if ([self voiceIsDragging]) return;
    if (!self.voiceSlider) return;
    self.voiceSlider.value = (float)MIN(self.voiceDuration, MAX(0, seconds));
    self.voiceDurationLabel.text = [NSString stringWithFormat:@"%@ / %@",
        [SCIDMMessageCell formatDuration:MAX(0, seconds)],
        [SCIDMMessageCell formatDuration:self.voiceDuration]];
}

- (void)applySelectionMode:(BOOL)on selected:(BOOL)selected selectable:(BOOL)selectable {
    self.inSelectionMode = on;
    self.isSelectedForBulk = selected;
    self.selectableForBulk = selectable;
    self.checkbox.alpha = on ? 1.0 : 0.0;
    self.bubbleLeading.constant = on ? 32.0 : 0.0;
    self.bubble.alpha = (on && !selectable) ? 0.45 : 1.0;
    UIImage *img;
    if (!selectable) {
        img = [UIImage systemImageNamed:@"minus.circle"];
        self.checkbox.tintColor = [UIColor tertiaryLabelColor];
    } else if (selected) {
        img = [UIImage systemImageNamed:@"checkmark.circle.fill"];
        self.checkbox.tintColor = [SCIUtils SCIColor_Primary] ?: [UIColor systemBlueColor];
    } else {
        img = [UIImage systemImageNamed:@"circle"];
        self.checkbox.tintColor = [UIColor tertiaryLabelColor];
    }
    self.checkbox.image = img;
}

- (void)setVoicePlayingFlag:(BOOL)playing {
    self.isVoicePlaying = playing;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
    NSString *glyph = playing ? @"pause.circle.fill" : @"play.circle.fill";
    [self.voicePlayButton setImage:[UIImage systemImageNamed:glyph withConfiguration:cfg]
                          forState:UIControlStateNormal];

    self.bubbleMaxWidth.constant = playing ? kSCIDMVoiceWidthPlaying : kSCIDMVoiceWidth;
    self.voiceDurationLabelWidth.constant =
        playing ? self.voiceDurationPlayingWidth : self.voiceDurationIdleWidth;
    if (!playing) {
        self.voiceDurationLabel.text = [SCIDMMessageCell formatDuration:self.voiceDuration];
    }
    [UIView animateWithDuration:0.18 animations:^{
        [self.contentView layoutIfNeeded];
    }];
}

// Type label derived from the share targetURL path.
+ (NSString *)shareTypeLabelForURL:(NSString *)urlString fallbackKind:(SCIDeletedMessageKind)kind {
    if (kind == SCIDeletedMessageKindAudioShare)        return SCILocalized(@"Audio");
    if (kind == SCIDeletedMessageKindLink && urlString.length) {
        NSURL *u = [NSURL URLWithString:urlString];
        NSString *host = u.host.lowercaseString ?: @"";
        if (![host containsString:@"instagram.com"]) return SCILocalized(@"Link");
    }
    NSString *lowerURL = urlString.lowercaseString ?: @"";
    NSString *path = [NSURL URLWithString:urlString].path.lowercaseString ?: @"";
    if ([lowerURL containsString:@"live_location"]
        || ([lowerURL containsString:@"latitude="] && [lowerURL containsString:@"longitude="]))
                                                      return SCILocalized(@"Live location");
    if ([path containsString:@"reels_audio_page"]
        || [path containsString:@"/audio_page"]
        || [path containsString:@"/audio/"])         return SCILocalized(@"Audio");
    if ([path containsString:@"/reel"])               return SCILocalized(@"Reel");
    if ([path containsString:@"/tv/"])                return SCILocalized(@"IGTV");
    if ([path containsString:@"/stories/"])           return SCILocalized(@"Story");
    if ([path containsString:@"/explore/locations/"]) return SCILocalized(@"Location");
    if ([path containsString:@"/explore/tags/"])      return SCILocalized(@"Hashtag");
    if ([path containsString:@"/p/"])                 return SCILocalized(@"Post");
    if (kind == SCIDeletedMessageKindLink)            return SCILocalized(@"Link");
    return SCILocalized(@"Post");
}

// Card types where the body is a title/subtitle pair, not a username.
+ (BOOL)shareLabelIsNonUserCard:(NSString *)label {
    return [label isEqualToString:SCILocalized(@"Audio")]
        || [label isEqualToString:SCILocalized(@"Location")]
        || [label isEqualToString:SCILocalized(@"Live location")]
        || [label isEqualToString:SCILocalized(@"Hashtag")];
}

- (void)installShareBubble:(SCIDeletedMessage *)m ownerPK:(NSString *)ownerPK {
    self.bubble.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.bubbleMaxWidth.constant = kSCIDMMediaSize;

    UIStackView *col = [[UIStackView alloc] init];
    col.translatesAutoresizingMaskIntoConstraints = NO;
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 0;
    col.alignment = UIStackViewAlignmentFill;
    [self.bubble addSubview:col];
    self.bubbleContent = col;
    [NSLayoutConstraint activateConstraints:@[
        [col.topAnchor      constraintEqualToAnchor:self.bubble.topAnchor],
        [col.bottomAnchor   constraintEqualToAnchor:self.bubble.bottomAnchor],
        [col.leadingAnchor  constraintEqualToAnchor:self.bubble.leadingAnchor],
        [col.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor],
    ]];

    UIImageView *thumb = [UIImageView new];
    thumb.translatesAutoresizingMaskIntoConstraints = NO;
    thumb.contentMode = UIViewContentModeScaleAspectFill;
    thumb.layer.masksToBounds = YES;
    thumb.backgroundColor = [UIColor tertiarySystemFillColor];
    [col addArrangedSubview:thumb];
    [thumb.heightAnchor constraintEqualToConstant:kSCIDMMediaSize].active = YES;

    NSString *thumbLocal = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.thumbnailPath ownerPK:ownerPK];
    UIImage *local = thumbLocal.length ? [UIImage imageWithContentsOfFile:thumbLocal] : nil;
    if (local) {
        thumb.image = local;
    } else if (m.thumbnailURL.length) {
        __weak UIImageView *weakThumb = thumb;
        [SCIImageCache loadImageFromURL:[NSURL URLWithString:m.thumbnailURL]
                             completion:^(UIImage *img) { if (img) weakThumb.image = img; }];
    } else {
        UIImageView *glyph = [UIImageView new];
        glyph.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:42 weight:UIImageSymbolWeightLight];
        glyph.image = [UIImage systemImageNamed:SCIDeletedMessageKindSymbol(m.kind) withConfiguration:cfg];
        glyph.tintColor = [UIColor tertiaryLabelColor];
        [thumb addSubview:glyph];
        [NSLayoutConstraint activateConstraints:@[
            [glyph.centerXAnchor constraintEqualToAnchor:thumb.centerXAnchor],
            [glyph.centerYAnchor constraintEqualToAnchor:thumb.centerYAnchor],
        ]];
    }

    UIStackView *footer = [[UIStackView alloc] init];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    footer.axis = UILayoutConstraintAxisVertical;
    footer.spacing = 2;
    footer.layoutMarginsRelativeArrangement = YES;
    footer.layoutMargins = UIEdgeInsetsMake(10, 12, 10, 12);
    [col addArrangedSubview:footer];

    NSString *typeLabel = [SCIDMMessageCell shareTypeLabelForURL:m.mediaURL fallbackKind:m.kind];
    NSString *body = m.text.length ? m.text : (m.previewText.length ? m.previewText : @"");
    NSArray<NSString *> *bodyLines = body.length
        ? [body componentsSeparatedByString:@"\n"]
        : @[];

    UILabel *titleL = [UILabel new];
    titleL.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    titleL.textColor = [UIColor labelColor];
    titleL.numberOfLines = 2;
    titleL.lineBreakMode = NSLineBreakByTruncatingTail;
    [footer addArrangedSubview:titleL];

    UILabel *hint = [UILabel new];
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = [UIColor secondaryLabelColor];
    hint.numberOfLines = 1;
    hint.lineBreakMode = NSLineBreakByTruncatingTail;
    [footer addArrangedSubview:hint];

    BOOL isNonUserCard = [SCIDMMessageCell shareLabelIsNonUserCard:typeLabel];
    BOOL isLiveLocation = [typeLabel isEqualToString:SCILocalized(@"Live location")];
    if (m.kind == SCIDeletedMessageKindLink || isNonUserCard) {
        NSString *headline = bodyLines.firstObject ?: typeLabel;
        titleL.text = headline;
        NSString *sub = nil;
        if (m.kind == SCIDeletedMessageKindLink) {
            NSString *host = [NSURL URLWithString:m.mediaURL].host;
            sub = host.length ? host : (bodyLines.count > 1 ? bodyLines[1] : nil);
        } else {
            sub = bodyLines.count > 1 ? bodyLines[1] : nil;
        }
        if (!m.mediaURL.length) {
            hint.text = SCILocalized(@"Content unavailable");
        } else if (m.kind == SCIDeletedMessageKindAudioShare) {
            hint.text = sub.length
                ? [NSString stringWithFormat:SCILocalized(@"Tap to play · %@"), sub]
                : SCILocalized(@"Tap to play");
        } else if (isLiveLocation) {
            hint.text = SCILocalized(@"Tap to open in Maps");
        } else {
            hint.text = sub.length
                ? [NSString stringWithFormat:@"%@ · %@", typeLabel, sub]
                : typeLabel;
        }
    } else {
        NSString *who = bodyLines.firstObject ?: @"";
        titleL.numberOfLines = 1;
        titleL.text = who.length
            ? [NSString stringWithFormat:@"%@ · @%@", typeLabel, who]
            : typeLabel;
        hint.text = m.mediaURL.length
            ? SCILocalized(@"Tap to open in Instagram")
            : SCILocalized(@"Content unavailable");
    }
}

- (void)installPlaceholderBubble:(SCIDeletedMessage *)m {
    self.bubble.backgroundColor = [UIColor secondarySystemBackgroundColor];

    UIStackView *row = [[UIStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.alignment = UIStackViewAlignmentCenter;
    [self.bubble addSubview:row];
    self.bubbleContent = row;

    UIImageView *icon = [UIImageView new];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    icon.image = [UIImage systemImageNamed:SCIDeletedMessageKindSymbol(m.kind) withConfiguration:cfg];
    icon.tintColor = [UIColor secondaryLabelColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [row addArrangedSubview:icon];

    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:14];
    l.textColor = [UIColor secondaryLabelColor];
    l.text = m.text.length ? m.text : SCIDeletedMessageKindLocalizedName(m.kind);
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [row addArrangedSubview:l];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor      constraintEqualToAnchor:self.bubble.topAnchor      constant:8],
        [row.bottomAnchor   constraintEqualToAnchor:self.bubble.bottomAnchor   constant:-8],
        [row.leadingAnchor  constraintEqualToAnchor:self.bubble.leadingAnchor  constant:12],
        [row.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-12],
    ]];
}

#pragma mark - Format helpers

+ (NSString *)formatDate:(NSDate *)d {
    if (!d) return @"";
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *today = [cal startOfDayForDate:[NSDate date]];
    if ([d compare:today] != NSOrderedAscending) {
        static NSDateFormatter *t;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            t = [NSDateFormatter new];
            t.dateStyle = NSDateFormatterNoStyle;
            t.timeStyle = NSDateFormatterShortStyle;
        });
        return [t stringFromDate:d];
    }
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [NSDateFormatter new];
        fmt.dateStyle = NSDateFormatterShortStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
    });
    return [fmt stringFromDate:d];
}

+ (NSString *)formatDuration:(double)seconds {
    if (seconds <= 0) return @"0:00";
    NSInteger s = (NSInteger)round(seconds);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(s / 60), (long)(s % 60)];
}

// Resample any waveform to a fixed bar count (avg down, nearest up).
+ (NSArray<NSNumber *> *)resampleWaveform:(NSArray<NSNumber *> *)src to:(NSInteger)bars {
    if (!src.count || bars <= 0) return @[];
    if ((NSInteger)src.count == bars) return src;
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:bars];
    if ((NSInteger)src.count > bars) {
        double step = (double)src.count / (double)bars;
        for (NSInteger i = 0; i < bars; i++) {
            NSInteger lo = (NSInteger)floor(i * step);
            NSInteger hi = (NSInteger)floor((i + 1) * step);
            if (hi <= lo) hi = lo + 1;
            if (hi > (NSInteger)src.count) hi = src.count;
            double sum = 0; NSInteger n = 0;
            for (NSInteger j = lo; j < hi; j++) { sum += [src[j] doubleValue]; n++; }
            [out addObject:@(n ? sum / n : 0)];
        }
    } else {
        double step = (double)src.count / (double)bars;
        for (NSInteger i = 0; i < bars; i++) {
            NSInteger idx = (NSInteger)floor(i * step);
            if (idx >= (NSInteger)src.count) idx = src.count - 1;
            [out addObject:src[idx]];
        }
    }
    return out;
}

@end

#pragma mark - Header view (user identity)

@interface SCIDMUserHeader : UIView
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@end

@implementation SCIDMUserHeader
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.layer.cornerRadius = 18;

        _avatar = [UIImageView new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.layer.cornerRadius = 36;
        _avatar.layer.masksToBounds = YES;
        _avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
        _avatar.tintColor = [UIColor systemGray3Color];
        _avatar.backgroundColor = [UIColor tertiarySystemBackgroundColor];
        [self addSubview:_avatar];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_nameLabel];

        _handleLabel = [UILabel new];
        _handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _handleLabel.font = [UIFont systemFontOfSize:14];
        _handleLabel.textColor = [UIColor secondaryLabelColor];
        _handleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_handleLabel];

        _summaryLabel = [UILabel new];
        _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _summaryLabel.font = [UIFont systemFontOfSize:13];
        _summaryLabel.textColor = [UIColor tertiaryLabelColor];
        _summaryLabel.numberOfLines = 0;
        _summaryLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_summaryLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_avatar.topAnchor       constraintEqualToAnchor:self.topAnchor constant:18],
            [_avatar.centerXAnchor   constraintEqualToAnchor:self.centerXAnchor],
            [_avatar.widthAnchor     constraintEqualToConstant:72],
            [_avatar.heightAnchor    constraintEqualToConstant:72],

            [_nameLabel.topAnchor       constraintEqualToAnchor:_avatar.bottomAnchor constant:10],
            [_nameLabel.leadingAnchor   constraintEqualToAnchor:self.leadingAnchor   constant:16],
            [_nameLabel.trailingAnchor  constraintEqualToAnchor:self.trailingAnchor  constant:-16],

            [_handleLabel.topAnchor       constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],
            [_handleLabel.leadingAnchor   constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_handleLabel.trailingAnchor  constraintEqualToAnchor:_nameLabel.trailingAnchor],

            [_summaryLabel.topAnchor       constraintEqualToAnchor:_handleLabel.bottomAnchor constant:10],
            [_summaryLabel.leadingAnchor   constraintEqualToAnchor:self.leadingAnchor  constant:20],
            [_summaryLabel.trailingAnchor  constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [_summaryLabel.bottomAnchor    constraintEqualToAnchor:self.bottomAnchor   constant:-16],
        ]];
    }
    return self;
}
@end

#pragma mark - VC

@interface SCIDeletedMessagesUserDetailViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, copy) NSString *senderPk;
@property (nonatomic, copy) NSString *ownerPK;
@property (nonatomic, strong) SCIDeletedMessageGroup *group;
@property (nonatomic, strong) NSArray<SCIDeletedMessage *> *visibleMessages;
@property (nonatomic, strong) SCIDeletedMessagesFilter *filter;

@property (nonatomic, strong) SCIDMUserHeader *headerView;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UIView      *bannerView;
@property (nonatomic, strong) UIImageView *bannerAvatar;
@property (nonatomic, strong) UILabel     *bannerNameLabel;
@property (nonatomic, strong) UILabel     *bannerSubLabel;
@property (nonatomic, strong) UIBarButtonItem *filterButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchCtl;
@property (nonatomic, strong) QuickLookDelegate *qlDelegate;

// Inline voice playback — one player at a time.
@property (nonatomic, strong) AVPlayer *audioPlayer;
@property (nonatomic, strong) id audioTimeObserver;
@property (nonatomic, copy)   NSString *playingMessageId;
@property (nonatomic, assign) double audioDuration;
@property (nonatomic, assign) BOOL   audioIsPlaying;

@property (nonatomic, assign) BOOL inSelectionMode;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedSids;
@property (nonatomic, strong) UIBarButtonItem *selectionSaveItem;
@property (nonatomic, strong) UIBarButtonItem *selectionShareItem;
@property (nonatomic, strong) UIBarButtonItem *selectionDeleteItem;
@property (nonatomic, strong) SCIScrollToTopButton *scrollToTopButton;
@end

@implementation SCIDeletedMessagesUserDetailViewController

- (instancetype)initWithGroup:(SCIDeletedMessageGroup *)group ownerPK:(NSString *)ownerPK {
    if ((self = [super init])) {
        _group = group;
        _senderPk = group.senderPk.copy;
        _ownerPK = ownerPK.copy;
        _filter = [SCIDeletedMessagesFilter new];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SCIPopupChrome backgroundColor];
    self.title = self.group.senderUsername.length ? [@"@" stringByAppendingString:self.group.senderUsername]
                                                  : SCILocalized(@"Deleted messages");

    [self installSearchController];
    [self installTable];
    self.tableView.tableHeaderView = [self buildBannerHeader];

    self.scrollToTopButton = [SCIScrollToTopButton new];
    [self.scrollToTopButton attachToScrollView:self.tableView inView:self.view bottomInset:24];

    UIBarButtonItem *menu = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                              menu:[self buildMenu]];
    UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
                                                                menu:[self buildFilterMenu]];
    self.filterButton = filter;
    [self refreshFilterButton];
    self.navigationItem.rightBarButtonItems = @[menu, filter]; // first = rightmost

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeChanged:)
                                                 name:SCIDeletedMessagesDidChangeNotification
                                               object:nil];
    [self refreshHeader];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIMenu *)buildMenu {
    __weak typeof(self) ws = self;
    UIAction *select = [UIAction actionWithTitle:SCILocalized(@"Select")
                                            image:[UIImage systemImageNamed:@"checkmark.circle"]
                                       identifier:nil
                                          handler:^(__kindof UIAction *_) {
        [ws enterSelectionMode];
    }];
    if (!self.group.messages.count) select.attributes = UIMenuElementAttributesDisabled;

    UIAction *clear = [UIAction actionWithTitle:SCILocalized(@"Clear from this user")
                                          image:[UIImage systemImageNamed:@"trash"]
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Clear log for this user?")
                                                                  message:SCILocalized(@"Removes every preserved deleted message from this sender.")
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear")  style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *_) {
            [SCIDeletedMessagesStorage deleteMessagesForSenderPK:self.senderPk ownerPK:self.ownerPK];
            [self.navigationController popViewControllerAnimated:YES];
        }]];
        [self presentViewController:a animated:YES completion:nil];
    }];
    clear.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithTitle:@"" children:@[
        [UIMenu menuWithTitle:@"" image:nil identifier:nil
                      options:UIMenuOptionsDisplayInline children:@[select]],
        clear
    ]];
}

#pragma mark - Bulk selection

- (void)enterSelectionMode {
    self.inSelectionMode = YES;
    if (!self.selectedSids) self.selectedSids = [NSMutableSet set];
    [self.selectedSids removeAllObjects];
    [self installSelectionToolbar];
    [self.tableView reloadData];

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                          target:self
                                                                          action:@selector(exitSelectionMode)];
    UIBarButtonItem *all  = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Select all")
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(selectAllSelectable)];
    self.navigationItem.rightBarButtonItems = @[done, all];
    [self refreshSelectionActionsEnabled];
}

- (void)exitSelectionMode {
    self.inSelectionMode = NO;
    [self.selectedSids removeAllObjects];
    [self.navigationController setToolbarHidden:YES animated:YES];
    [self.scrollToTopButton setBottomInset:24];
    [self.tableView reloadData];
    [self refreshHeader];

    UIBarButtonItem *menu = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                              menu:[self buildMenu]];
    self.navigationItem.rightBarButtonItems = self.filterButton ? @[menu, self.filterButton] : @[menu];
}

- (void)selectAllSelectable {
    for (SCIDeletedMessage *m in self.visibleMessages) {
        if (m.messageId.length) [self.selectedSids addObject:m.messageId];
    }
    [self.tableView reloadData];
    [self refreshSelectionCount];
}

- (BOOL)isMessageBulkSelectable:(SCIDeletedMessage *)m {
    // text rows selectable too (delete-only); save/share skip them.
    return YES;
}

- (void)refreshSelectionAppearanceAnimated:(BOOL)animated {
    void (^block)(void) = ^{
        for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
            if (ip.row >= (NSInteger)self.visibleMessages.count) continue;
            SCIDeletedMessage *m = self.visibleMessages[ip.row];
            SCIDMMessageCell *cell = [self.tableView cellForRowAtIndexPath:ip];
            if (![cell isKindOfClass:[SCIDMMessageCell class]]) continue;
            BOOL selectable = [self isMessageBulkSelectable:m];
            BOOL selected   = [self.selectedSids containsObject:m.messageId];
            [cell applySelectionMode:self.inSelectionMode selected:selected selectable:selectable];
        }
    };
    if (animated) [UIView animateWithDuration:0.20 animations:block];
    else block();
    [self refreshSelectionCount];
}

- (void)refreshSelectionCount {
    NSUInteger n = self.selectedSids.count;
    self.navigationItem.title = n == 0
        ? SCILocalized(@"Select")
        : [NSString stringWithFormat:SCILocalized(@"%lu selected"), (unsigned long)n];
    [self refreshSelectionActionsEnabled];
}

- (void)installSelectionToolbar {
    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(saveSelectedToGallery)];
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(shareSelected)];
    UIBarButtonItem *del = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(confirmDeleteSelected)];
    del.tintColor = [UIColor systemRedColor];

    UIBarButtonItem *(^flex)(void) = ^UIBarButtonItem *(void) {
        return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                             target:nil action:nil];
    };
    self.toolbarItems = @[save, flex(), share, flex(), del];

    self.selectionSaveItem   = save;
    self.selectionShareItem  = share;
    self.selectionDeleteItem = del;

    [self.navigationController setToolbarHidden:NO animated:YES];
    [self.scrollToTopButton setBottomInset:64];
    [self refreshSelectionCount];
}

- (void)refreshSelectionActionsEnabled {
    NSUInteger withFiles = [self selectedMessagesWithFiles].count;
    BOOL anySelected = self.selectedSids.count > 0;
    self.selectionSaveItem.enabled  = withFiles > 0;
    self.selectionShareItem.enabled = withFiles > 0;
    self.selectionDeleteItem.enabled = anySelected;
}

#pragma mark - Bulk save

- (NSArray<SCIDeletedMessage *> *)selectedMessagesWithFiles {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *sid in self.selectedSids) {
        for (SCIDeletedMessage *m in self.visibleMessages) {
            if (![m.messageId isEqualToString:sid]) continue;
            if (!m.mediaPath.length) continue;
            NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.mediaPath ownerPK:self.ownerPK];
            if (abs.length && [[NSFileManager defaultManager] fileExistsAtPath:abs]) {
                [out addObject:m];
            }
            break;
        }
    }
    return out;
}

- (SCIGallerySaveMetadata *)gallerySaveMetadataForMessage:(SCIDeletedMessage *)m {
    SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
    md.sourceUsername       = self.group.senderUsername;
    md.sourceUserPK         = self.group.senderPk;
    md.sourceProfileURLString = self.group.senderProfilePicURL;
    md.source               = SCIGallerySourceDMs;
    md.skipDedup            = YES;
    if (m.durationSeconds > 0) md.durationSeconds = m.durationSeconds;
    if (m.width  > 0) md.pixelWidth  = (int32_t)m.width;
    if (m.height > 0) md.pixelHeight = (int32_t)m.height;
    return md;
}

- (void)saveSelectedToGallery {
    NSArray<SCIDeletedMessage *> *msgs = [self selectedMessagesWithFiles];
    if (!msgs.count) {
        SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"Nothing to save"), nil);
        return;
    }
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSMutableArray<id> *meta = [NSMutableArray array];
    for (SCIDeletedMessage *m in msgs) {
        NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.mediaPath ownerPK:self.ownerPK];
        if (!abs.length) continue;
        [urls addObject:[NSURL fileURLWithPath:abs]];
        [meta addObject:[self gallerySaveMetadataForMessage:m]];
    }
    [SCIMediaActions bulkSaveFilesToGallery:urls perFileMetadata:meta defaultMetadata:nil];
    [self exitSelectionMode];
}

- (void)shareSelected {
    NSArray<SCIDeletedMessage *> *msgs = [self selectedMessagesWithFiles];
    if (!msgs.count) {
        SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"Nothing to share"), nil);
        return;
    }
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSMutableArray<SCIGallerySaveMetadata *> *metas = [NSMutableArray array];
    for (SCIDeletedMessage *m in msgs) {
        NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.mediaPath ownerPK:self.ownerPK];
        if (!abs.length) continue;
        [urls addObject:[NSURL fileURLWithPath:abs]];
        [metas addObject:[self gallerySaveMetadataForMessage:m]];
    }
    if (!urls.count) return;

    // Persist into gallery first, then arm the Photos watcher for the share sheet.
    if ([SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
        [SCIMediaActions bulkSaveFilesToGallery:urls perFileMetadata:metas defaultMetadata:nil];
    }
    [SCIPhotoAlbum armWatcherIfEnabled];

    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:urls
                                                                     applicationActivities:nil];
    if (av.popoverPresentationController) {
        UIView *anchor = self.navigationController.toolbar ?: self.view;
        av.popoverPresentationController.sourceView = anchor;
        av.popoverPresentationController.sourceRect = anchor.bounds;
    }
    __weak typeof(self) ws = self;
    av.completionWithItemsHandler = ^(UIActivityType _Nullable type, BOOL completed, NSArray *_Nullable items, NSError *_Nullable error) {
        if (completed) [ws exitSelectionMode];
    };
    [self presentViewController:av animated:YES completion:nil];
}

- (void)confirmDeleteSelected {
    if (!self.selectedSids.count) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SCILocalized(@"Delete")
                                                              message:SCILocalized(@"Removes every preserved deleted message and its captured media for the current account. This cannot be undone.")
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete") style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *_) {
        [self deleteSelected];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)deleteSelected {
    for (NSString *sid in [self.selectedSids allObjects]) {
        [SCIDeletedMessagesStorage deleteMessageId:sid forOwnerPK:self.ownerPK];
    }
    [self exitSelectionMode];
}

- (void)installSearchController {
    UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
    sc.searchResultsUpdater = self;
    sc.obscuresBackgroundDuringPresentation = NO;
    sc.hidesNavigationBarDuringPresentation = NO;
    sc.searchBar.placeholder = SCILocalized(@"Search messages");
    sc.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchCtl = sc;
    self.navigationItem.searchController = sc;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    // Force stacked placement so iOS 26's bottom-of-nav default doesn't apply.
    if (@available(iOS 16.0, *)) {
        self.navigationItem.preferredSearchBarPlacement = UINavigationItemSearchBarPlacementStacked;
    }
    self.definesPresentationContext = YES;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    self.filter.searchText = sc.searchBar.text;
    [self refilter];
}

- (UIView *)buildBannerHeader {
    UIView *banner = [UIView new];
    banner.frame = CGRectMake(0, 0, self.view.bounds.size.width, 64);
    banner.backgroundColor = [SCIPopupChrome backgroundColor];

    UIImageView *avatar = [UIImageView new];
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.layer.cornerRadius = 18;
    avatar.layer.masksToBounds = YES;
    avatar.image = [UIImage systemImageNamed:@"person.circle.fill"];
    avatar.tintColor = [UIColor systemGray3Color];
    avatar.backgroundColor = [UIColor secondarySystemBackgroundColor];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    [banner addSubview:avatar];

    UILabel *name = [UILabel new];
    name.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    name.textColor = [UIColor labelColor];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [banner addSubview:name];

    UILabel *sub = [UILabel new];
    sub.font = [UIFont systemFontOfSize:13];
    sub.textColor = [UIColor secondaryLabelColor];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [banner addSubview:sub];

    UIView *sep = [UIView new];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [UIColor separatorColor];
    [banner addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [avatar.leadingAnchor  constraintEqualToAnchor:banner.leadingAnchor constant:16],
        [avatar.centerYAnchor  constraintEqualToAnchor:banner.centerYAnchor],
        [avatar.widthAnchor    constraintEqualToConstant:36],
        [avatar.heightAnchor   constraintEqualToConstant:36],

        [name.leadingAnchor    constraintEqualToAnchor:avatar.trailingAnchor constant:10],
        [name.topAnchor        constraintEqualToAnchor:avatar.topAnchor constant:1],
        [name.trailingAnchor   constraintLessThanOrEqualToAnchor:banner.trailingAnchor constant:-16],

        [sub.leadingAnchor     constraintEqualToAnchor:name.leadingAnchor],
        [sub.bottomAnchor      constraintEqualToAnchor:avatar.bottomAnchor constant:-1],
        [sub.trailingAnchor    constraintEqualToAnchor:name.trailingAnchor],

        [sep.leadingAnchor     constraintEqualToAnchor:banner.leadingAnchor],
        [sep.trailingAnchor    constraintEqualToAnchor:banner.trailingAnchor],
        [sep.bottomAnchor      constraintEqualToAnchor:banner.bottomAnchor],
        [sep.heightAnchor      constraintEqualToConstant:1.0 / [UIScreen mainScreen].scale],
    ]];

    self.bannerView      = banner;
    self.bannerAvatar    = avatar;
    self.bannerNameLabel = name;
    self.bannerSubLabel  = sub;
    return banner;
}

- (void)installTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.backgroundColor = self.view.backgroundColor;
    [self.tableView registerClass:[SCIDMMessageCell class] forCellReuseIdentifier:@"msg"];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // tableHeaderView with manual frame needs reassignment on width change
    // to trigger UIKit's measurement pass.
    if (self.bannerView) {
        CGFloat w = self.tableView.bounds.size.width;
        if (w > 1 && fabs(self.bannerView.frame.size.width - w) > 0.5) {
            CGRect f = self.bannerView.frame;
            f.size.width = w;
            self.bannerView.frame = f;
            self.tableView.tableHeaderView = self.bannerView;
        }
    }
}

#pragma mark - Data

- (void)reload {
    NSArray<SCIDeletedMessage *> *all = [SCIDeletedMessagesStorage messagesForSenderPK:self.senderPk
                                                                              ownerPK:self.ownerPK];
    if (all.count) {
        SCIDeletedMessageGroup *g = [SCIDeletedMessageGroup new];
        g.senderPk            = self.senderPk;
        g.senderUsername      = all.firstObject.senderUsername;
        g.senderFullName      = all.firstObject.senderFullName;
        g.senderProfilePicURL = all.firstObject.senderProfilePicURL;
        g.messages            = all;
        self.group = g;
    }
    [self refreshHeader];
    [self refilter];
}

- (void)refilter {
    self.visibleMessages = [self.filter apply:self.group.messages];
    [self.tableView reloadData];
}

- (void)refreshHeader {
    NSString *fn = self.group.senderFullName.length ? self.group.senderFullName
        : (self.group.senderUsername.length ? self.group.senderUsername : SCILocalized(@"Unknown user"));
    self.title = self.group.senderUsername.length
        ? [@"@" stringByAppendingString:self.group.senderUsername]
        : fn;
    self.bannerNameLabel.text = fn;
    NSString *handle = self.group.senderUsername.length
        ? [NSString stringWithFormat:@"@%@ · ", self.group.senderUsername]
        : @"";
    self.bannerSubLabel.text = [NSString stringWithFormat:SCILocalized(@"%@%lu deleted"),
                                handle, (unsigned long)self.group.count];
    if (self.group.senderProfilePicURL.length) {
        __weak UIImageView *iv = self.bannerAvatar;
        [SCIImageCache loadImageFromURL:[NSURL URLWithString:self.group.senderProfilePicURL]
                             completion:^(UIImage *img) { if (img) iv.image = img; }];
    }
}

- (void)storeChanged:(NSNotification *)note {
    if (!self.isViewLoaded || !self.view.window) return;
    [self reload];
    if (!self.group.count) [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Filter menu (multi-select kinds + reset)

// Each inner array becomes one inline UIMenu section (separated visually).
static NSArray<NSArray<NSArray *> *> *sciFilterKindSections(void) {
    return @[
        @[@[SCILocalized(@"Photo"),   @(SCIDeletedMessageKindPhoto),   SCIDeletedMessageKindSymbol(SCIDeletedMessageKindPhoto)],
          @[SCILocalized(@"Video"),   @(SCIDeletedMessageKindVideo),   SCIDeletedMessageKindSymbol(SCIDeletedMessageKindVideo)],
          @[SCILocalized(@"GIF"),     @(SCIDeletedMessageKindGif),     SCIDeletedMessageKindSymbol(SCIDeletedMessageKindGif)],
          @[SCILocalized(@"Sticker"), @(SCIDeletedMessageKindSticker), SCIDeletedMessageKindSymbol(SCIDeletedMessageKindSticker)]],
        @[@[SCILocalized(@"Voice"),   @(SCIDeletedMessageKindVoice),       SCIDeletedMessageKindSymbol(SCIDeletedMessageKindVoice)],
          @[SCILocalized(@"Audio"),   @(SCIDeletedMessageKindAudioShare),  SCIDeletedMessageKindSymbol(SCIDeletedMessageKindAudioShare)]],
        @[@[SCILocalized(@"Share"),   @(SCIDeletedMessageKindShare),   SCIDeletedMessageKindSymbol(SCIDeletedMessageKindShare)],
          @[SCILocalized(@"Link"),    @(SCIDeletedMessageKindLink),    SCIDeletedMessageKindSymbol(SCIDeletedMessageKindLink)]],
        @[@[SCILocalized(@"Text"),    @(SCIDeletedMessageKindText),    SCIDeletedMessageKindSymbol(SCIDeletedMessageKindText)],
          @[SCILocalized(@"Other"),   @(SCIDeletedMessageKindOther),   SCIDeletedMessageKindSymbol(SCIDeletedMessageKindOther)]],
    ];
}

- (UIMenu *)buildFilterMenu {
    __weak typeof(self) ws = self;
    NSMutableArray<UIMenu *> *sections = [NSMutableArray array];
    for (NSArray<NSArray *> *group in sciFilterKindSections()) {
        NSMutableArray<UIAction *> *actions = [NSMutableArray array];
        for (NSArray *e in group) {
            SCIDeletedMessageKind k = [e[1] integerValue];
            UIAction *a = [UIAction actionWithTitle:e[0]
                                              image:[UIImage systemImageNamed:e[2]]
                                         identifier:nil
                                            handler:^(__kindof UIAction *_) {
                [ws.filter toggleKind:k];
                [ws refilter];
                [ws refreshFilterButton];
            }];
            a.state = [self.filter.kinds containsObject:@(k)] ? UIMenuElementStateOn : UIMenuElementStateOff;
            if (@available(iOS 17.0, *)) a.attributes |= UIMenuElementAttributesKeepsMenuPresented;
            [actions addObject:a];
        }
        [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
                                          options:UIMenuOptionsDisplayInline children:actions]];
    }

    UIAction *reset = [UIAction actionWithTitle:SCILocalized(@"Reset")
                                          image:[UIImage systemImageNamed:@"xmark.circle"]
                                     identifier:nil
                                        handler:^(__kindof UIAction *_) {
        [ws.filter clearKinds];
        [ws refilter];
        [ws refreshFilterButton];
    }];
    reset.attributes = UIMenuElementAttributesDestructive;
    [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
                                      options:UIMenuOptionsDisplayInline children:@[reset]]];

    NSUInteger n = self.filter.kinds.count;
    NSString *menuTitle = n > 0
        ? [NSString stringWithFormat:SCILocalized(@"Filter · %lu"), (unsigned long)n]
        : SCILocalized(@"Filter");
    return [UIMenu menuWithTitle:menuTitle children:sections];
}

- (void)refreshFilterButton {
    BOOL active = self.filter.hasKindFilter;
    self.filterButton.image = [UIImage systemImageNamed:
        active ? @"line.3.horizontal.decrease.circle.fill" : @"line.3.horizontal.decrease.circle"];
    self.filterButton.menu = [self buildFilterMenu];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.visibleMessages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SCIDMMessageCell *cell = [tv dequeueReusableCellWithIdentifier:@"msg" forIndexPath:ip];
    SCIDeletedMessage *m = self.visibleMessages[ip.row];
    BOOL playing = (m.kind == SCIDeletedMessageKindVoice)
                   && [self.playingMessageId isEqualToString:m.messageId]
                   && self.audioIsPlaying;
    [cell applyMessage:m ownerPK:self.ownerPK playing:playing];
    __weak typeof(self) ws = self;
    if (self.inSelectionMode) {
        cell.onCellTap   = ^{ [ws toggleSelectionForMessage:m]; };
        cell.onBubbleTap = nil;
    } else {
        cell.onCellTap   = nil;
        cell.onBubbleTap = ^{ [ws openMessage:m]; };
    }
    cell.onVoicePlayTap = ^{ [ws toggleVoicePlayback:m]; };
    cell.onVoiceSeekTo  = ^(double seconds) { [ws seekVoicePlayback:m to:seconds]; };
    if ([self.playingMessageId isEqualToString:m.messageId] && self.audioPlayer) {
        [cell setVoiceProgressSeconds:[self audioCurrentSeconds]];
    }
    [cell applySelectionMode:self.inSelectionMode
                    selected:[self.selectedSids containsObject:m.messageId]
                  selectable:[self isMessageBulkSelectable:m]];
    return cell;
}

- (void)toggleSelectionForMessage:(SCIDeletedMessage *)m {
    if (!self.inSelectionMode || !m.messageId.length) return;
    if (![self isMessageBulkSelectable:m]) return;
    if ([self.selectedSids containsObject:m.messageId]) [self.selectedSids removeObject:m.messageId];
    else                                                [self.selectedSids addObject:m.messageId];
    // Single-row refresh — full reload would jump scroll.
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        if (ip.row >= (NSInteger)self.visibleMessages.count) continue;
        if (self.visibleMessages[ip.row] != m) continue;
        SCIDMMessageCell *cell = [self.tableView cellForRowAtIndexPath:ip];
        if (![cell isKindOfClass:[SCIDMMessageCell class]]) break;
        [cell applySelectionMode:YES
                        selected:[self.selectedSids containsObject:m.messageId]
                      selectable:YES];
        break;
    }
    [self refreshSelectionCount];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv
     contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip
                                        point:(CGPoint)point {
    if (ip.row >= (NSInteger)self.visibleMessages.count) return nil;
    SCIDeletedMessage *m = self.visibleMessages[ip.row];
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *_) {
        return [ws contextMenuForMessage:m];
    }];
}

- (UIMenu *)contextMenuForMessage:(SCIDeletedMessage *)m {
    NSMutableArray<UIMenuElement *> *primary = [NSMutableArray array];
    __weak typeof(self) ws = self;

    BOOL hasText = m.text.length > 0;
    BOOL hasMedia = (m.kind == SCIDeletedMessageKindPhoto)
                  || (m.kind == SCIDeletedMessageKindVideo)
                  || (m.kind == SCIDeletedMessageKindGif)
                  || (m.kind == SCIDeletedMessageKindVoice)
                  || (m.kind == SCIDeletedMessageKindAudioShare)
                  || (m.kind == SCIDeletedMessageKindSticker);
    BOOL isAudioOnly = (m.kind == SCIDeletedMessageKindVoice)
                    || (m.kind == SCIDeletedMessageKindAudioShare);
    NSURL *fileURL = nil;
    NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.mediaPath ownerPK:self.ownerPK];
    if (abs.length && [[NSFileManager defaultManager] fileExistsAtPath:abs]) {
        fileURL = [NSURL fileURLWithPath:abs];
    }

    if (hasText) {
        [primary addObject:[UIAction actionWithTitle:SCILocalized(@"Copy text")
                                                image:[UIImage systemImageNamed:@"doc.on.doc"]
                                           identifier:nil
                                              handler:^(__kindof UIAction *_) {
            [UIPasteboard generalPasteboard].string = m.text;
            SCINotifySuccess(SCI_NOTIF_COPY_URL, SCILocalized(@"Copied"), nil);
        }]];
    }
    if (hasMedia) {
        [primary addObject:[UIAction actionWithTitle:(isAudioOnly
                                                       ? SCILocalized(@"Play")
                                                       : SCILocalized(@"View"))
                                                image:[UIImage systemImageNamed:(isAudioOnly
                                                                                 ? @"play.circle"
                                                                                 : @"arrow.up.left.and.arrow.down.right")]
                                           identifier:nil
                                              handler:^(__kindof UIAction *_) {
            [ws openMessage:m];
        }]];
    }

    NSMutableArray<UIMenuElement *> *saveSection = [NSMutableArray array];
    if (fileURL && hasMedia && !isAudioOnly) {
        // Photos rejects audio.
        [saveSection addObject:[UIAction actionWithTitle:SCILocalized(@"Save to Photos")
                                                   image:[UIImage systemImageNamed:@"photo.on.rectangle"]
                                              identifier:nil
                                                 handler:^(__kindof UIAction *_) {
            [SCIPhotoAlbum saveFileToAlbum:fileURL completion:^(BOOL ok, NSError *err) {
                if (ok) SCINotifySuccess(SCI_NOTIF_DOWNLOAD,   SCILocalized(@"Saved to Photos"), nil);
                else    SCINotifyError(SCI_NOTIF_DOWNLOAD,   SCILocalized(@"Save failed"), err.localizedDescription ?: @"");
            }];
        }]];
    }
    if (fileURL && hasMedia && [SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
        [saveSection addObject:[UIAction actionWithTitle:SCILocalized(@"Save to Gallery")
                                                   image:[UIImage systemImageNamed:@"square.stack.3d.up"]
                                              identifier:nil
                                                 handler:^(__kindof UIAction *_) {
            [SCIMediaActions bulkSaveFilesToGallery:@[fileURL] perFileMetadata:nil defaultMetadata:nil];
        }]];
    }
    if (fileURL) {
        [saveSection addObject:[UIAction actionWithTitle:SCILocalized(@"Share")
                                                   image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                              identifier:nil
                                                 handler:^(__kindof UIAction *_) {
            UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                                                              applicationActivities:nil];
            if (av.popoverPresentationController) {
                av.popoverPresentationController.sourceView = ws.view;
                av.popoverPresentationController.sourceRect = CGRectMake(ws.view.bounds.size.width / 2,
                                                                          ws.view.bounds.size.height / 2, 1, 1);
            }
            [ws presentViewController:av animated:YES completion:nil];
        }]];
    }
    if (m.mediaURL.length) {
        [saveSection addObject:[UIAction actionWithTitle:SCILocalized(@"Copy URL")
                                                   image:[UIImage systemImageNamed:@"link"]
                                              identifier:nil
                                                 handler:^(__kindof UIAction *_) {
            [UIPasteboard generalPasteboard].string = m.mediaURL;
            SCINotifySuccess(SCI_NOTIF_COPY_URL, SCILocalized(@"Copied"), nil);
        }]];
    }

    UIAction *del = [UIAction actionWithTitle:SCILocalized(@"Delete")
                                         image:[UIImage systemImageNamed:@"trash"]
                                    identifier:nil
                                       handler:^(__kindof UIAction *_) {
        [SCIDeletedMessagesStorage deleteMessageId:m.messageId forOwnerPK:ws.ownerPK];
    }];
    del.attributes = UIMenuElementAttributesDestructive;

    NSMutableArray<UIMenu *> *sections = [NSMutableArray array];
    if (primary.count) {
        [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
                                          options:UIMenuOptionsDisplayInline children:primary]];
    }
    if (saveSection.count) {
        [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
                                          options:UIMenuOptionsDisplayInline children:saveSection]];
    }
    [sections addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil
                                      options:UIMenuOptionsDisplayInline children:@[del]]];
    return [UIMenu menuWithTitle:@"" children:sections];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    SCIDeletedMessage *m = self.visibleMessages[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:SCILocalized(@"Delete")
                                                                    handler:^(UIContextualAction *a, __kindof UIView *src, void (^done)(BOOL)) {
        [SCIDeletedMessagesStorage deleteMessageId:m.messageId forOwnerPK:self.ownerPK];
        done(YES);
    }];
    del.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (void)openMessage:(SCIDeletedMessage *)m {
    if (m.kind == SCIDeletedMessageKindText && m.text.length) {
        [self presentTextMessage:m];
        return;
    }
    if (m.kind == SCIDeletedMessageKindVoice) {
        [self toggleVoicePlayback:m];
        return;
    }
    if (m.kind == SCIDeletedMessageKindAudioShare) {
        NSURL *url = nil;
        NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.mediaPath ownerPK:self.ownerPK];
        if (abs.length && [[NSFileManager defaultManager] fileExistsAtPath:abs])
            url = [NSURL fileURLWithPath:abs];
        else if (m.mediaURL.length)
            url = [NSURL URLWithString:m.mediaURL];
        if (!url) { [self presentInfoSheet:m]; return; }
        NSArray<NSString *> *parts = m.text.length ? [m.text componentsSeparatedByString:@"\n"] : @[];
        NSString *caption = parts.count >= 2
            ? [NSString stringWithFormat:@"%@ — %@", parts[0], parts[1]]
            : (parts.firstObject ?: @"");
        [SCIMediaViewer showItem:[SCIMediaViewerItem itemWithAudioURL:url caption:caption]];
        return;
    }
    if (m.kind == SCIDeletedMessageKindShare
        || m.kind == SCIDeletedMessageKindLink) {
        if (!m.mediaURL.length) { [self presentInfoSheet:m]; return; }
        NSURL *u = [NSURL URLWithString:m.mediaURL];
        if (!u) { [self presentInfoSheet:m]; return; }
        // Live location → Apple Maps via lat/lng query params.
        NSString *lower = m.mediaURL.lowercaseString;
        if ([lower containsString:@"live_location"]
            || ([lower containsString:@"latitude="] && [lower containsString:@"longitude="])) {
            NSURLComponents *comps = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
            NSString *lat = nil, *lng = nil;
            for (NSURLQueryItem *q in comps.queryItems) {
                if ([q.name isEqualToString:@"latitude"]) lat = q.value;
                else if ([q.name isEqualToString:@"longitude"]) lng = q.value;
            }
            if (lat.length && lng.length) {
                NSString *label = [m.text componentsSeparatedByString:@"\n"].firstObject ?: SCILocalized(@"Live location");
                NSString *q = [label stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
                NSURL *maps = [NSURL URLWithString:[NSString stringWithFormat:@"http://maps.apple.com/?ll=%@,%@&q=%@", lat, lng, q ?: @""]];
                [SCIURLOpener dismiss:self thenOpenURL:maps];
                return;
            }
        }
        [SCIURLOpener dismiss:self thenOpenURL:u];
        return;
    }
    NSURL *url = [self bestMediaURLForMessage:m];
    if (!url) { [self presentInfoSheet:m]; return; }

    NSString *caption = self.group.senderUsername.length
        ? [@"@" stringByAppendingString:self.group.senderUsername]
        : (self.group.senderFullName ?: @"");

    if (m.kind == SCIDeletedMessageKindGif) {
        [SCIMediaViewer showItem:[SCIMediaViewerItem itemWithAnimatedImageURL:url caption:caption]];
        return;
    }
    if (m.kind == SCIDeletedMessageKindVideo) {
        [SCIMediaViewer showWithVideoURL:url photoURL:nil caption:caption];
        return;
    }
    [SCIMediaViewer showWithVideoURL:nil photoURL:url caption:caption];
}

- (NSURL *)bestMediaURLForMessage:(SCIDeletedMessage *)m {
    NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.mediaPath ownerPK:self.ownerPK];
    if (abs.length && [[NSFileManager defaultManager] fileExistsAtPath:abs])
        return [NSURL fileURLWithPath:abs];
    if (m.mediaURL.length)     return [NSURL URLWithString:m.mediaURL];
    if (m.thumbnailURL.length) return [NSURL URLWithString:m.thumbnailURL];
    return nil;
}

#pragma mark - Voice playback

- (double)audioCurrentSeconds {
    if (!self.audioPlayer) return 0;
    CMTime t = self.audioPlayer.currentTime;
    if (CMTIME_IS_INDEFINITE(t)) return 0;
    return CMTimeGetSeconds(t);
}

- (void)toggleVoicePlayback:(SCIDeletedMessage *)m {
    if (!m.messageId.length) return;

    if ([self.playingMessageId isEqualToString:m.messageId] && self.audioPlayer) {
        if (self.audioIsPlaying) {
            [self.audioPlayer pause];
            self.audioIsPlaying = NO;
        } else {
            [self.audioPlayer play];
            self.audioIsPlaying = YES;
        }
        for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
            SCIDMMessageCell *cell = [self.tableView cellForRowAtIndexPath:ip];
            if (![cell isKindOfClass:[SCIDMMessageCell class]]) continue;
            if (![cell.messageId isEqualToString:m.messageId]) continue;
            [cell setVoicePlayingFlag:self.audioIsPlaying];
            break;
        }
        return;
    }

    [self stopVoicePlayback];

    NSURL *url = nil;
    NSString *abs = [SCIDeletedMessagesStorage absolutePathForRelativePath:m.mediaPath ownerPK:self.ownerPK];
    if (abs.length && [[NSFileManager defaultManager] fileExistsAtPath:abs]) {
        url = [NSURL fileURLWithPath:abs];
    } else if (m.mediaURL.length) {
        url = [NSURL URLWithString:m.mediaURL];
    }
    if (!url) {
        [self presentInfoSheet:m];
        return;
    }

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    AVPlayer *p = [AVPlayer playerWithURL:url];
    p.automaticallyWaitsToMinimizeStalling = YES;
    self.audioPlayer = p;
    self.playingMessageId = m.messageId;
    self.audioIsPlaying = YES;
    self.audioDuration = (m.durationSeconds > 0) ? m.durationSeconds : 0;

    __weak typeof(self) ws = self;
    self.audioTimeObserver = [p addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.1, 600)
                                                              queue:dispatch_get_main_queue()
                                                         usingBlock:^(CMTime _) {
        [ws audioProgressTick];
    }];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioDidFinish:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:p.currentItem];

    [p play];
    [self refreshVisibleVoiceCells];
}

- (void)stopVoicePlayback {
    if (self.audioTimeObserver) {
        [self.audioPlayer removeTimeObserver:self.audioTimeObserver];
        self.audioTimeObserver = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:nil];
    [self.audioPlayer pause];
    self.audioPlayer = nil;
    self.playingMessageId = nil;
    self.audioIsPlaying = NO;
    self.audioDuration = 0;
}

- (void)audioProgressTick {
    if (!self.audioPlayer || !self.playingMessageId.length) return;
    double t = [self audioCurrentSeconds];
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        SCIDMMessageCell *cell = [self.tableView cellForRowAtIndexPath:ip];
        if (![cell isKindOfClass:[SCIDMMessageCell class]]) continue;
        if (![cell.messageId isEqualToString:self.playingMessageId]) continue;
        [cell setVoiceProgressSeconds:t];
        break;
    }
}

- (void)audioDidFinish:(NSNotification *)note {
    [self stopVoicePlayback];
    [self refreshVisibleVoiceCells];
}

- (void)seekVoicePlayback:(SCIDeletedMessage *)m to:(double)seconds {
    if (![self.playingMessageId isEqualToString:m.messageId]) return;
    if (!self.audioPlayer) return;
    double clamped = MAX(0, seconds);
    [self.audioPlayer seekToTime:CMTimeMakeWithSeconds(clamped, 600)
                 toleranceBefore:kCMTimeZero
                  toleranceAfter:kCMTimeZero];
}

- (void)refreshVisibleVoiceCells {
    for (NSIndexPath *ip in self.tableView.indexPathsForVisibleRows) {
        if (ip.row >= (NSInteger)self.visibleMessages.count) continue;
        SCIDeletedMessage *m = self.visibleMessages[ip.row];
        if (m.kind != SCIDeletedMessageKindVoice) continue;
        SCIDMMessageCell *cell = [self.tableView cellForRowAtIndexPath:ip];
        if (![cell isKindOfClass:[SCIDMMessageCell class]]) continue;
        BOOL playing = [self.playingMessageId isEqualToString:m.messageId] && self.audioIsPlaying;
        [cell applyMessage:m ownerPK:self.ownerPK playing:playing];
        __weak typeof(self) ws = self;
        cell.onBubbleTap    = ^{ [ws openMessage:m]; };
        cell.onVoicePlayTap = ^{ [ws toggleVoicePlayback:m]; };
        cell.onVoiceSeekTo  = ^(double seconds) { [ws seekVoicePlayback:m to:seconds]; };
        if (playing) [cell setVoiceProgressSeconds:[self audioCurrentSeconds]];
    }
}

- (void)presentTextMessage:(SCIDeletedMessage *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SCIDeletedMessageKindLocalizedName(m.kind)
                                                              message:m.text
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy") style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [UIPasteboard generalPasteboard].string = m.text;
    }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Close") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)presentInfoSheet:(SCIDeletedMessage *)m {
    NSMutableString *body = [NSMutableString string];
    if (m.previewText.length) [body appendFormat:@"%@\n\n", m.previewText];
    [body appendFormat:SCILocalized(@"Kind: %@\n"), SCIDeletedMessageKindLocalizedName(m.kind)];
    if (m.deletedAt) [body appendFormat:SCILocalized(@"Deleted: %@\n"), m.deletedAt];
    if (m.mediaURL.length) [body appendString:SCILocalized(@"Source URL recorded but media not stored.\n")];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SCIDeletedMessageKindLocalizedName(m.kind)
                                                              message:body
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Close") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
