#import "SCIQualityPicker.h"
#import "SCIFFmpeg.h"
#import "Utils.h"
#import "InstagramHeaders.h"
#import "ActionButton/SCIMediaActions.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <objc/message.h>

static NSString * const kSCIQualityCellId = @"q";

static inline UIImageSymbolConfiguration *SCIQualityIconConfig(CGFloat size) {
	return [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium];
}

static inline UIImage *SCIQualityIcon(NSString *name, CGFloat size) {
	return [UIImage systemImageNamed:name withConfiguration:SCIQualityIconConfig(size)];
}

static inline NSString *SCIQualityBandwidth(NSInteger bandwidth) {
	return bandwidth > 1000000 ? [NSString stringWithFormat:@"%.1f Mbps", bandwidth / 1000000.0] : [NSString stringWithFormat:@"%ld Kbps", (long)(bandwidth / 1000)];
}

static inline NSString *SCIQualityCodec(NSString *codecs, NSString *fallback) {
	if (!codecs.length) return fallback;
	return [codecs componentsSeparatedByString:@"."].firstObject ?: codecs;
}

static inline void SCIRemoveTempFiles(NSArray<NSString *> *paths) {
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *path in paths) {
		if (path.length) [fm removeItemAtPath:path error:nil];
	}
}

@interface _SCIQualityCell : UITableViewCell
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation _SCIQualityCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleDefault;
	self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

	_playButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_playButton.tintColor = UIColor.labelColor;
	_playButton.translatesAutoresizingMaskIntoConstraints = NO;
	[_playButton setImage:SCIQualityIcon(@"play.fill", 18.0) forState:UIControlStateNormal];
	[self.contentView addSubview:_playButton];

	_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	_spinner.hidesWhenStopped = YES;
	_spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_spinner];

	_titleLabel = [UILabel new];
	_titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
	_titleLabel.textColor = UIColor.labelColor;
	_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_titleLabel];

	_subtitleLabel = [UILabel new];
	_subtitleLabel.font = [UIFont systemFontOfSize:11];
	_subtitleLabel.textColor = UIColor.secondaryLabelColor;
	_subtitleLabel.numberOfLines = 1;
	_subtitleLabel.adjustsFontSizeToFitWidth = YES;
	_subtitleLabel.minimumScaleFactor = 0.85;
	_subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_subtitleLabel];

	_menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_menuButton.tintColor = UIColor.secondaryLabelColor;
	_menuButton.translatesAutoresizingMaskIntoConstraints = NO;
	_menuButton.showsMenuAsPrimaryAction = YES;
	[_menuButton setImage:SCIQualityIcon(@"ellipsis.circle", 17.0) forState:UIControlStateNormal];
	[self.contentView addSubview:_menuButton];

	[NSLayoutConstraint activateConstraints:@[
		[_playButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
		[_playButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_playButton.widthAnchor constraintEqualToConstant:32.0],
		[_playButton.heightAnchor constraintEqualToConstant:32.0],

		[_spinner.centerXAnchor constraintEqualToAnchor:_playButton.centerXAnchor],
		[_spinner.centerYAnchor constraintEqualToAnchor:_playButton.centerYAnchor],

		[_menuButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],
		[_menuButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_menuButton.widthAnchor constraintEqualToConstant:32.0],
		[_menuButton.heightAnchor constraintEqualToConstant:32.0],

		[_titleLabel.leadingAnchor constraintEqualToAnchor:_playButton.trailingAnchor constant:12.0],
		[_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_menuButton.leadingAnchor constant:-8.0],
		[_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10.0],

		[_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
		[_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_menuButton.leadingAnchor constant:-8.0],
		[_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
		[_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8.0]
	]];

	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self setLoading:NO];
	self.playButton.hidden = NO;
	self.menuButton.hidden = NO;
	self.menuButton.menu = nil;
	self.playButton.tag = 0;
	self.accessoryType = UITableViewCellAccessoryNone;
	[self.playButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
}

- (void)setLoading:(BOOL)loading {
	self.playButton.hidden = loading;
	loading ? [self.spinner startAnimating] : [self.spinner stopAnimating];
}

@end

@interface _SCIQualitySheetVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSArray<SCIDashRepresentation *> *videoReps;
@property (nonatomic, strong) SCIDashRepresentation *audioRep;
@property (nonatomic, strong) NSURL *standardURL;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) id mediaRef;
@property (nonatomic, assign) DownloadAction saveAction;
@property (nonatomic, assign) BOOL hasAudio;
@property (nonatomic, copy) void (^onPickStandard)(void);
@property (nonatomic, copy) void (^onPickHD)(SCIDashRepresentation *video, SCIDashRepresentation *audio);
@end

@implementation _SCIQualitySheetVC

- (void)viewDidLoad {
	[super viewDidLoad];

	UIColor *sheetGrey = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
		return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:1.0] : [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
	}];

	self.view.backgroundColor = sheetGrey;
	self.view.opaque = YES;

	UIView *solidCard = [UIView new];
	solidCard.backgroundColor = sheetGrey;
	solidCard.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:solidCard];

	self.titleLabel = [UILabel new];
	self.titleLabel.text = SCILocalized(@"Download Quality");
	self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
	self.titleLabel.textColor = UIColor.labelColor;
	self.titleLabel.textAlignment = NSTextAlignmentCenter;
	self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.titleLabel];

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.backgroundColor = UIColor.clearColor;
	self.tableView.rowHeight = 56.0;
	self.tableView.sectionHeaderTopPadding = 8.0;
	[self.tableView registerClass:_SCIQualityCell.class forCellReuseIdentifier:kSCIQualityCellId];
	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
		[solidCard.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[solidCard.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[solidCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[solidCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

		[self.titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.titleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:26.0],

		[self.tableView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8.0],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
	]];
}

- (BOOL)_hasAudioSection {
	return self.audioRep.url != nil;
}

- (BOOL)_hasExtrasSection {
	return self.photoURL != nil;
}

- (BOOL)_isAudioSection:(NSInteger)section {
	return section == 2 && [self _hasAudioSection];
}

- (BOOL)_isExtrasSection:(NSInteger)section {
	return (section == 2 && ![self _hasAudioSection]) || section == 3;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2 + ([self _hasAudioSection] ? 1 : 0) + ([self _hasExtrasSection] ? 1 : 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 1;
	if (section == 1) return (NSInteger)self.videoReps.count;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return SCILocalized(@"Standard");
	if (section == 1) return @"HD";
	if ([self _isAudioSection:section]) return SCILocalized(@"Audio");
	return SCILocalized(@"Extras");
}

- (UIImage *)_playIconSilent:(BOOL)silent {
	return SCIQualityIcon(silent ? @"play.slash.fill" : @"play.fill", 18.0);
}

- (void)_configureStandardCell:(_SCIQualityCell *)cell {
	BOOL silent = !self.hasAudio;
	cell.titleLabel.text = SCILocalized(@"Standard");
	cell.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	cell.subtitleLabel.text = silent ? SCILocalized(@"720p • progressive • silent") : SCILocalized(@"720p • progressive • fastest");
	cell.playButton.hidden = self.standardURL == nil;
	cell.menuButton.hidden = self.standardURL == nil;
	cell.playButton.tag = -1;
	[cell.playButton setImage:[self _playIconSilent:silent] forState:UIControlStateNormal];
	[cell.playButton addTarget:self action:@selector(playStandardPreview:) forControlEvents:UIControlEventTouchUpInside];
	cell.menuButton.menu = [self menuForStandard];
}

- (void)_configureHDCell:(_SCIQualityCell *)cell row:(NSInteger)row {
	if (row < 0 || row >= (NSInteger)self.videoReps.count) return;

	BOOL silent = !self.hasAudio;
	SCIDashRepresentation *rep = self.videoReps[row];
	NSString *label = rep.qualityLabel ?: @"";

	if (rep.width > 0 && rep.height > 0) {
		NSInteger shortSide = MIN(rep.width, rep.height);
		if (shortSide > 0) label = [NSString stringWithFormat:@"%ldp", (long)shortSide];
	}

	NSMutableArray *parts = [NSMutableArray array];
	if (rep.width > 0 && rep.height > 0) [parts addObject:[NSString stringWithFormat:@"%ld×%ld", (long)rep.width, (long)rep.height]];
	if (rep.frameRate > 0) [parts addObject:[NSString stringWithFormat:@"%.0ffps", rep.frameRate]];
	if (rep.codecs.length) [parts addObject:SCIQualityCodec(rep.codecs, rep.codecs)];
	if (silent) [parts addObject:SCILocalized(@"silent")];

	cell.titleLabel.text = [NSString stringWithFormat:@"%@ • %@", label, SCIQualityBandwidth(rep.bandwidth)];
	cell.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
	cell.subtitleLabel.text = [parts componentsJoinedByString:@" • "];
	cell.playButton.tag = row;
	[cell.playButton setImage:[self _playIconSilent:silent] forState:UIControlStateNormal];
	[cell.playButton addTarget:self action:@selector(playPreview:) forControlEvents:UIControlEventTouchUpInside];
	cell.menuButton.menu = [self menuForRow:row videoRep:rep];
}

- (void)_configureAudioCell:(_SCIQualityCell *)cell {
	NSMutableArray *parts = [NSMutableArray array];
	NSString *codec = SCIQualityCodec(self.audioRep.codecs, @"m4a");
	NSString *bandwidth = self.audioRep.bandwidth > 0 ? SCIQualityBandwidth(self.audioRep.bandwidth) : nil;

	if (codec.length) [parts addObject:codec];
	if (bandwidth.length) [parts addObject:bandwidth];

	cell.titleLabel.text = SCILocalized(@"Audio only");
	cell.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	cell.subtitleLabel.text = parts.count ? [parts componentsJoinedByString:@" • "] : @"m4a";
	cell.menuButton.hidden = YES;
	[cell.playButton setImage:SCIQualityIcon(@"music.note", 18.0) forState:UIControlStateNormal];
}

- (void)_configurePhotoCell:(_SCIQualityCell *)cell {
	cell.titleLabel.text = SCILocalized(@"Photo");
	cell.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	cell.subtitleLabel.text = SCILocalized(@"Raw image (no audio, no video)");
	cell.menuButton.hidden = YES;
	[cell.playButton setImage:SCIQualityIcon(@"photo", 18.0) forState:UIControlStateNormal];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
	_SCIQualityCell *cell = [tableView dequeueReusableCellWithIdentifier:kSCIQualityCellId forIndexPath:ip];

	[cell setLoading:NO];
	cell.playButton.hidden = NO;
	cell.menuButton.hidden = NO;
	cell.accessoryType = UITableViewCellAccessoryNone;
	[cell.playButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];

	if (ip.section == 0) [self _configureStandardCell:cell];
	else if (ip.section == 1) [self _configureHDCell:cell row:ip.row];
	else if ([self _isAudioSection:ip.section]) [self _configureAudioCell:cell];
	else [self _configurePhotoCell:cell];

	return cell;
}

- (UIMenu *)menuForStandard {
	NSURL *url = self.standardURL;
	if (!url) return nil;

	UIAction *copy = [UIAction actionWithTitle:SCILocalized(@"Copy video URL") image:SCIQualityIcon(@"video.fill", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		UIPasteboard.generalPasteboard.string = url.absoluteString;
	}];

	return [UIMenu menuWithTitle:@"" children:@[copy]];
}

- (UIMenu *)menuForRow:(NSInteger)row videoRep:(SCIDashRepresentation *)videoRep {
	NSURL *videoURL = videoRep.url;
	NSURL *audioURL = self.audioRep.url;

	UIAction *copyVideo = [UIAction actionWithTitle:SCILocalized(@"Copy video URL") image:SCIQualityIcon(@"video.fill", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		if (videoURL) UIPasteboard.generalPasteboard.string = videoURL.absoluteString;
	}];

	NSMutableArray *items = [NSMutableArray arrayWithObject:copyVideo];

	if (audioURL) {
		UIAction *copyAudio = [UIAction actionWithTitle:SCILocalized(@"Copy audio URL") image:SCIQualityIcon(@"waveform", 18.0) identifier:nil handler:^(__unused UIAction *action) {
			UIPasteboard.generalPasteboard.string = audioURL.absoluteString;
		}];

		[items addObject:copyAudio];
	}

	UIAction *copyInfo = [UIAction actionWithTitle:SCILocalized(@"Copy quality info") image:SCIQualityIcon(@"info.circle", 18.0) identifier:nil handler:^(__unused UIAction *action) {
		NSString *info = [NSString stringWithFormat:@"%ldp — %ld×%ld — %.1f Mbps", (long)MIN(videoRep.width, videoRep.height), (long)videoRep.width, (long)videoRep.height, videoRep.bandwidth / 1000000.0];
		UIPasteboard.generalPasteboard.string = info;
	}];

	[items addObject:copyInfo];
	return [UIMenu menuWithTitle:@"" children:items];
}

- (void)playStandardPreview:(UIButton *)sender {
	NSURL *url = self.standardURL;
	if (!url) return;

	AVPlayerViewController *playerVC = [AVPlayerViewController new];
	playerVC.player = [AVPlayer playerWithURL:url];
	playerVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
	[self presentViewController:playerVC animated:YES completion:^{
		[playerVC.player play];
	}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tableView deselectRowAtIndexPath:ip animated:YES];

	[self dismissViewControllerAnimated:YES completion:^{
		if (ip.section == 0) {
			if (self.onPickStandard) self.onPickStandard();
			return;
		}

		if (ip.section == 1) {
			if (ip.row >= 0 && ip.row < (NSInteger)self.videoReps.count && self.onPickHD) {
				self.onPickHD(self.videoReps[ip.row], self.audioRep);
			}
			return;
		}

		if ([self _isAudioSection:ip.section]) [SCIMediaActions downloadAudioOnlyForMedia:self.mediaRef action:self.saveAction];
		else if (self.photoURL) [SCIMediaActions downloadPhotoOnlyForMedia:self.mediaRef action:self.saveAction];
	}];
}

- (void)playPreview:(UIButton *)sender {
	NSInteger idx = sender.tag;
	if (idx < 0 || idx >= (NSInteger)self.videoReps.count) return;

	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:idx inSection:1];
	[( _SCIQualityCell *)[self.tableView cellForRowAtIndexPath:indexPath] setLoading:YES];

	SCIDashRepresentation *videoRep = self.videoReps[idx];
	NSURL *videoURL = videoRep.url;
	NSURL *audioURL = self.audioRep.url;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *uuid = NSUUID.UUID.UUIDString;
		NSString *tmp = NSTemporaryDirectory();
		NSString *vPath = [tmp stringByAppendingPathComponent:[NSString stringWithFormat:@"sci_preview_v_%@.mp4", uuid]];
		NSString *aPath = [tmp stringByAppendingPathComponent:[NSString stringWithFormat:@"sci_preview_a_%@.m4a", uuid]];
		NSString *oPath = [tmp stringByAppendingPathComponent:[NSString stringWithFormat:@"sci_preview_%@.mp4", uuid]];

		NSData *videoData = [NSData dataWithContentsOfURL:videoURL];
		if (!videoData.length || ![videoData writeToFile:vPath atomically:YES]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self restorePlayButton:idx];
			});
			return;
		}

		NSString *cmd = nil;
		NSData *audioData = audioURL ? [NSData dataWithContentsOfURL:audioURL] : nil;

		if (audioData.length && [audioData writeToFile:aPath atomically:YES]) {
			cmd = [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 1M -probesize 1M -fflags +genpts -i '%@' -i '%@' -map 0:v:0 -map 1:a:0 -c:a copy -c:v h264_videotoolbox -b:v 8M -realtime 1 -allow_sw 1 -movflags +faststart -shortest '%@'", vPath, aPath, oPath];
		} else {
			cmd = [NSString stringWithFormat:@"-y -hide_banner -analyzeduration 1M -probesize 1M -fflags +genpts -i '%@' -c:v h264_videotoolbox -b:v 8M -realtime 1 -allow_sw 1 -movflags +faststart '%@'", vPath, oPath];
		}

		[SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
			SCIRemoveTempFiles(@[vPath, aPath]);

			dispatch_async(dispatch_get_main_queue(), ^{
				if (success && [NSFileManager.defaultManager fileExistsAtPath:oPath]) {
					AVPlayerViewController *playerVC = [AVPlayerViewController new];
					playerVC.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:oPath]];
					playerVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
					[self presentViewController:playerVC animated:YES completion:^{
						[playerVC.player play];
					}];
				}

				[self restorePlayButton:idx];
			});
		}];
	});
}

- (void)restorePlayButton:(NSInteger)idx {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSIndexPath *indexPath = [NSIndexPath indexPathForRow:idx inSection:1];
		[( _SCIQualityCell *)[self.tableView cellForRowAtIndexPath:indexPath] setLoading:NO];
	});
}

@end

@implementation SCIQualityPicker

+ (BOOL)pickQualityForMedia:(id)media fromView:(UIView *)sourceView action:(DownloadAction)action picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked fallback:(void(^)(void))fallback {
	if (!media) {
		if (fallback) fallback();
		return NO;
	}

	if (![SCIUtils getBoolPref:@"enhance_download_quality"] || ![SCIFFmpeg isAvailable]) {
		if (fallback) fallback();
		return NO;
	}

	if (![SCIUtils getVideoUrlForMedia:(IGMedia *)media]) {
		if (fallback) fallback();
		return NO;
	}

	NSString *manifest = [SCIDashParser dashManifestForMedia:media];
	if (!manifest.length) {
		if (fallback) fallback();
		return NO;
	}

	NSArray<SCIDashRepresentation *> *allReps = [SCIDashParser parseManifest:manifest];
	NSArray<SCIDashRepresentation *> *videoReps = [SCIDashParser videoRepresentations:allReps];
	SCIDashRepresentation *audioRep = [SCIDashParser bestAudioFromRepresentations:allReps];

	if (!videoReps.count) {
		if (fallback) fallback();
		return NO;
	}

	NSString *qualityPref = [SCIUtils getStringPref:@"default_video_quality"];
	if (!qualityPref.length) qualityPref = @"always_ask";

	if ([qualityPref isEqualToString:@"always_ask"]) {
		[self showSheetWithVideoReps:videoReps audioRep:audioRep standardURL:[SCIUtils getVideoUrlForMedia:(IGMedia *)media] media:media action:action picked:picked fallback:fallback];
		return YES;
	}

	SCIVideoQuality quality = SCIVideoQualityHighest;
	if ([qualityPref isEqualToString:@"medium"]) quality = SCIVideoQualityMedium;
	else if ([qualityPref isEqualToString:@"low"]) quality = SCIVideoQualityLowest;

	SCIDashRepresentation *videoRep = [SCIDashParser representationForQuality:quality fromRepresentations:allReps];
	if (picked) picked(videoRep, audioRep);
	return YES;
}

+ (void)showSheetWithVideoReps:(NSArray<SCIDashRepresentation *> *)videoReps audioRep:(SCIDashRepresentation *)audioRep standardURL:(NSURL *)standardURL media:(id)media action:(DownloadAction)action picked:(void(^)(SCIDashRepresentation *video, SCIDashRepresentation *audio))picked fallback:(void(^)(void))fallback {
	dispatch_async(dispatch_get_main_queue(), ^{
		_SCIQualitySheetVC *vc = [_SCIQualitySheetVC new];
		vc.videoReps = videoReps ?: @[];
		vc.audioRep = audioRep;
		vc.standardURL = standardURL;
		vc.mediaRef = media;
		vc.saveAction = action;
		vc.hasAudio = audioRep.url != nil;
		vc.photoURL = [SCIUtils getPhotoUrlForMedia:(IGMedia *)media];
		vc.onPickStandard = fallback;
		vc.onPickHD = picked;
		vc.modalPresentationStyle = UIModalPresentationPageSheet;

		UISheetPresentationController *sheetPC = vc.sheetPresentationController;
		sheetPC.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
		sheetPC.prefersGrabberVisible = YES;
		sheetPC.prefersScrollingExpandsWhenScrolledToEdge = YES;

		[topMostController() presentViewController:vc animated:YES completion:nil];
	});
}

@end