#import "SCIGalleryGridCell.h"
#import "SCIGalleryFile.h"
#import "SCIAssetUtils.h"
#import "../Utils.h"
#import "SCIGalleryShim.h"

@interface SCIGalleryGridCell ()

@property (nonatomic, strong) SCIGalleryFile *file;
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIImageView *videoBadge;
@property (nonatomic, strong) UIImageView *favoriteBadge;
@property (nonatomic, strong) UIImageView *selectionBadge;
@property (nonatomic, strong) NSLayoutConstraint *favoriteTrailingConstraint;

@property (nonatomic, strong) UIView *infoOverlay;
@property (nonatomic, strong) CAGradientLayer *infoGradient;
@property (nonatomic, strong) UIImageView *sourceIcon;
@property (nonatomic, strong) UILabel *infoLabel;

@end

@implementation SCIGalleryGridCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.clipsToBounds = YES;
        self.contentView.layer.cornerRadius = 6.0;
        self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];

        _thumbnailView = [UIImageView new];
        _thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnailView.clipsToBounds = YES;
        [self.contentView addSubview:_thumbnailView];

        // Bottom info overlay — gradient + source icon + label.
        _infoOverlay = [UIView new];
        _infoOverlay.translatesAutoresizingMaskIntoConstraints = NO;
        _infoOverlay.userInteractionEnabled = NO;
        _infoOverlay.hidden = YES;
        [self.contentView addSubview:_infoOverlay];

        _infoGradient = [CAGradientLayer layer];
        _infoGradient.colors = @[
            (id)[[UIColor clearColor] CGColor],
            (id)[[[UIColor blackColor] colorWithAlphaComponent:0.65] CGColor],
        ];
        _infoGradient.startPoint = CGPointMake(0.5, 0.0);
        _infoGradient.endPoint = CGPointMake(0.5, 1.0);
        [_infoOverlay.layer addSublayer:_infoGradient];

        _sourceIcon = [UIImageView new];
        _sourceIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _sourceIcon.contentMode = UIViewContentModeScaleAspectFit;
        _sourceIcon.tintColor = [UIColor whiteColor];
        [_infoOverlay addSubview:_sourceIcon];

        _infoLabel = [UILabel new];
        _infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _infoLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightSemibold];
        _infoLabel.textColor = [UIColor whiteColor];
        _infoLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _infoLabel.adjustsFontSizeToFitWidth = YES;
        _infoLabel.minimumScaleFactor = 0.85;
        _infoLabel.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        _infoLabel.shadowOffset = CGSizeMake(0, 0.5);
        [_infoOverlay addSubview:_infoLabel];

        _videoBadge = [UIImageView new];
        _videoBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _videoBadge.image = [UIImage systemImageNamed:@"video.fill"];
        _videoBadge.tintColor = [UIColor whiteColor];
        _videoBadge.contentMode = UIViewContentModeScaleAspectFit;
        _videoBadge.hidden = YES;
        [self.contentView addSubview:_videoBadge];

        _favoriteBadge = [UIImageView new];
        _favoriteBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _favoriteBadge.image = [UIImage systemImageNamed:@"heart.fill"];
        _favoriteBadge.contentMode = UIViewContentModeScaleAspectFit;
        _favoriteBadge.tintColor = [SCIUtils SCIColor_InstagramFavorite];
        _favoriteBadge.hidden = YES;
        [self.contentView addSubview:_favoriteBadge];

        _selectionBadge = [UIImageView new];
        _selectionBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _selectionBadge.contentMode = UIViewContentModeScaleAspectFit;
        _selectionBadge.tintColor = [UIColor whiteColor];
        _selectionBadge.hidden = YES;
        [self.contentView addSubview:_selectionBadge];

        _favoriteTrailingConstraint = [_favoriteBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6];

        [NSLayoutConstraint activateConstraints:@[
            [_thumbnailView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_thumbnailView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_thumbnailView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_thumbnailView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

            [_infoOverlay.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_infoOverlay.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_infoOverlay.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_infoOverlay.heightAnchor constraintEqualToConstant:26],

            [_sourceIcon.leadingAnchor constraintEqualToAnchor:_infoOverlay.leadingAnchor constant:5],
            [_sourceIcon.bottomAnchor constraintEqualToAnchor:_infoOverlay.bottomAnchor constant:-5],
            [_sourceIcon.widthAnchor constraintEqualToConstant:10],
            [_sourceIcon.heightAnchor constraintEqualToConstant:10],

            [_infoLabel.leadingAnchor constraintEqualToAnchor:_sourceIcon.trailingAnchor constant:3],
            [_infoLabel.trailingAnchor constraintEqualToAnchor:_infoOverlay.trailingAnchor constant:-5],
            [_infoLabel.centerYAnchor constraintEqualToAnchor:_sourceIcon.centerYAnchor],

            [_videoBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_videoBadge.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6],
            [_videoBadge.widthAnchor constraintEqualToConstant:14],
            [_videoBadge.heightAnchor constraintEqualToConstant:14],

            [_favoriteBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_favoriteBadge.widthAnchor constraintEqualToConstant:16],
            [_favoriteBadge.heightAnchor constraintEqualToConstant:16],

            [_selectionBadge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_selectionBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6],
            [_selectionBadge.widthAnchor constraintEqualToConstant:20],
            [_selectionBadge.heightAnchor constraintEqualToConstant:20],

            _favoriteTrailingConstraint,
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.infoGradient.frame = self.infoOverlay.bounds;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.file = nil;
    self.thumbnailView.image = nil;
    self.videoBadge.hidden = YES;
    self.favoriteBadge.hidden = YES;
    self.selectionBadge.hidden = YES;
    self.selectionBadge.image = nil;
    self.selectionBadge.alpha = 0.0;
    self.favoriteTrailingConstraint.constant = -6;
    self.infoOverlay.hidden = YES;
    self.sourceIcon.image = nil;
    self.infoLabel.text = nil;
}

- (UIImage *)selectionBadgeImageSelected:(BOOL)selected {
    return [UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"circle"];
}

- (void)configureWithGalleryFile:(SCIGalleryFile *)file
                 selectionMode:(BOOL)selectionMode
                      selected:(BOOL)selected {
    self.file = file;
    UIImage *thumb = [SCIGalleryFile loadThumbnailForFile:file];
    if (thumb) {
        self.thumbnailView.image = thumb;
    } else {
        self.thumbnailView.image = nil;
        __weak typeof(self) weakSelf = self;
        [SCIGalleryFile generateThumbnailForFile:file completion:^(BOOL success) {
            if (success && weakSelf && weakSelf.file == file) {
                UIImage *newThumb = [UIImage imageWithContentsOfFile:[file thumbnailPath]];
                if (newThumb) {
                    weakSelf.thumbnailView.image = newThumb;
                }
            }
        }];
    }

    BOOL isVideo = (file.mediaType == SCIGalleryMediaTypeVideo);
    BOOL isAudio = (file.mediaType == SCIGalleryMediaTypeAudio);
    BOOL isGIF = (file.mediaType == SCIGalleryMediaTypeGIF);
    if (isAudio) {
        self.videoBadge.hidden = NO;
        self.videoBadge.image = [UIImage systemImageNamed:@"waveform.circle.fill"];
    } else if (isGIF) {
        self.videoBadge.hidden = NO;
        self.videoBadge.image = [UIImage systemImageNamed:@"sparkles"];
    } else {
        self.videoBadge.hidden = !isVideo;
        self.videoBadge.image = [UIImage systemImageNamed:@"video.fill"];
    }
    self.favoriteBadge.hidden = !file.isFavorite;

    [self updateInfoOverlayForFile:file];

    [self setSelectionMode:selectionMode selected:selected animated:NO];
}

- (void)updateInfoOverlayForFile:(SCIGalleryFile *)file {
    SCIGallerySource source = (SCIGallerySource)file.source;
    NSString *username = file.sourceUsername;

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (source != SCIGallerySourceOther) {
        [parts addObject:[SCIGalleryFile shortLabelForSource:source]];
    }
    if (username.length) {
        [parts addObject:[@"@" stringByAppendingString:username]];
    }
    if (parts.count == 0) {
        self.infoOverlay.hidden = YES;
        return;
    }
    self.infoOverlay.hidden = NO;
    self.sourceIcon.image = [UIImage systemImageNamed:[self systemSymbolForSource:source]];
    self.infoLabel.text = [parts componentsJoinedByString:@" · "];
}

- (NSString *)systemSymbolForSource:(SCIGallerySource)source {
    switch (source) {
        case SCIGallerySourceFeed:      return @"rectangle.stack";
        case SCIGallerySourceStories:   return @"circle.dashed";
        case SCIGallerySourceReels:     return @"film";
        case SCIGallerySourceProfile:   return @"person.crop.circle";
        case SCIGallerySourceDMs:       return @"bubble.left.and.bubble.right";
        case SCIGallerySourceThumbnail: return @"photo.on.rectangle.angled";
        case SCIGallerySourceNotes:     return @"note.text";
        case SCIGallerySourceComments:  return @"text.bubble";
        case SCIGallerySourceInstants:  return @"square.dashed";
        case SCIGallerySourceOther:
        default:                        return @"photo";
    }
}

- (void)setSelectionMode:(BOOL)selectionMode selected:(BOOL)selected animated:(BOOL)animated {
    self.selectionBadge.image = selectionMode ? [self selectionBadgeImageSelected:selected] : nil;
    if (selectionMode) {
        self.selectionBadge.hidden = NO;
    }
    self.favoriteTrailingConstraint.constant = selectionMode ? -30.0 : -6.0;

    void (^applyState)(void) = ^{
        self.selectionBadge.alpha = selectionMode ? 1.0 : 0.0;
        [self.contentView layoutIfNeeded];
    };
    void (^finishState)(void) = ^{
        self.selectionBadge.hidden = !selectionMode;
    };

    if (animated) {
        [UIView animateWithDuration:0.22
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:applyState
                         completion:^(__unused BOOL finished) {
            finishState();
        }];
    } else {
        applyState();
        finishState();
    }
}

@end
