#import "SCITrimViewController.h"
#import "Utils.h"

static const CGFloat kTrackHeight = 56.0;
static const CGFloat kTrackMargin = 24.0;
static const CGFloat kHandleWidth = 16.0;
static const CGFloat kHandleHitWidth = 48.0;
static const CGFloat kMinTrimDuration = 0.5;

@interface SCITrimViewController ()

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) id timeObserver;

@property (nonatomic, strong) UIView *previewContainer;
@property (nonatomic, strong) UIImageView *audioIconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *rangeLabel;

@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UIView *selectedRangeView;
@property (nonatomic, strong) UIView *leftHandle;
@property (nonatomic, strong) UIView *rightHandle;
@property (nonatomic, strong) UIView *playheadView;

@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *sendButton;

@property (nonatomic, assign) double totalDuration;
@property (nonatomic, assign) double startTime;
@property (nonatomic, assign) double endTime;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) CGFloat lastWaveformWidth;

@end

@implementation SCITrimViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];

	self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
	self.view.backgroundColor = [UIColor colorWithRed:0.055 green:0.055 blue:0.075 alpha:1.0];

	[self setupTimes];
	[self setupAudioSession];
	[self setupPlayer];
	[self setupViews];
	[self updateRangeUI];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	[self layoutViews];
	[self rebuildWaveformIfNeeded];
	[self updateRangeUI];

	if (self.playerLayer) {
		self.playerLayer.frame = self.previewContainer.bounds;
	}
}

- (void)dealloc {
	[self tearDownPlayer];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
	return UIStatusBarStyleLightContent;
}

#pragma mark - Setup

- (void)setupTimes {
	AVAsset *asset = [AVAsset assetWithURL:self.mediaURL];
	double duration = CMTimeGetSeconds(asset.duration);

	if (duration <= 0.0 || isnan(duration) || !isfinite(duration)) {
		duration = 1.0;
	}

	self.totalDuration = duration;
	self.startTime = 0.0;
	self.endTime = duration;

	if (self.maxDurationSecs > 0.0 && self.endTime > self.maxDurationSecs) {
		self.endTime = self.maxDurationSecs;
	}
}

- (void)setupAudioSession {
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];
}

- (void)setupPlayer {
	self.player = [AVPlayer playerWithURL:self.mediaURL];

	__weak typeof(self) weakSelf = self;
	self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.03, 600)
																  queue:dispatch_get_main_queue()
															 usingBlock:^(CMTime time) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !self.isPlaying) return;

		double current = CMTimeGetSeconds(time);
		if (current < 0.0 || isnan(current) || !isfinite(current)) return;

		if (current >= self.endTime) {
			[self pausePlayer];
			[self seekPlayerTo:self.endTime showPlayhead:YES];
			return;
		}

		[self movePlayheadTo:current];
	}];
}

- (void)setupViews {
	[self setupCloseButton];
	[self setupPreview];
	[self setupLabels];
	[self setupTrack];
	[self setupControls];
}

- (void)setupCloseButton {
	self.closeButton = [self roundButtonWithSymbol:@"xmark" pointSize:16.0 diameter:38.0 alpha:0.09];
	[self.closeButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.closeButton];
}

- (void)setupPreview {
	self.previewContainer = UIView.new;
	self.previewContainer.backgroundColor = UIColor.blackColor;
	self.previewContainer.layer.cornerRadius = 18.0;
	self.previewContainer.layer.cornerCurve = kCACornerCurveContinuous;
	self.previewContainer.layer.masksToBounds = YES;
	[self.view addSubview:self.previewContainer];

	if (self.isVideo) {
		self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
		self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
		[self.previewContainer.layer addSublayer:self.playerLayer];
		return;
	}

	self.previewContainer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.055];

	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:46.0 weight:UIImageSymbolWeightLight];
	self.audioIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"waveform" withConfiguration:cfg]];
	self.audioIconView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.55];
	self.audioIconView.contentMode = UIViewContentModeScaleAspectFit;
	[self.previewContainer addSubview:self.audioIconView];
}

- (void)setupLabels {
	self.titleLabel = [self labelWithFont:[UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular]
									color:[UIColor colorWithWhite:1.0 alpha:0.42]
								alignment:NSTextAlignmentCenter];
	self.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
	self.titleLabel.text = self.mediaURL.lastPathComponent ?: @"";
	[self.view addSubview:self.titleLabel];

	self.durationLabel = [self labelWithFont:[UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular]
									   color:[UIColor colorWithWhite:1.0 alpha:0.32]
								   alignment:NSTextAlignmentCenter];
	self.durationLabel.text = [NSString stringWithFormat:SCILocalized(@"Total: %@"), [self formatTime:self.totalDuration]];
	[self.view addSubview:self.durationLabel];

	self.rangeLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightMedium]
									color:UIColor.whiteColor
								alignment:NSTextAlignmentCenter];
	[self.view addSubview:self.rangeLabel];
}

- (void)setupTrack {
	self.trackView = UIView.new;
	self.trackView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
	self.trackView.layer.cornerRadius = 12.0;
	self.trackView.layer.cornerCurve = kCACornerCurveContinuous;
	self.trackView.layer.masksToBounds = YES;
	[self.view addSubview:self.trackView];

	self.selectedRangeView = UIView.new;
	self.selectedRangeView.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.28];
	self.selectedRangeView.userInteractionEnabled = NO;
	self.selectedRangeView.layer.cornerRadius = 12.0;
	self.selectedRangeView.layer.cornerCurve = kCACornerCurveContinuous;
	[self.trackView addSubview:self.selectedRangeView];

	self.leftHandle = [self handleViewWithLeftSide:YES];
	self.rightHandle = [self handleViewWithLeftSide:NO];

	[self.trackView addSubview:self.leftHandle];
	[self.trackView addSubview:self.rightHandle];

	[self.leftHandle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(leftHandlePan:)]];
	[self.rightHandle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(rightHandlePan:)]];

	self.playheadView = UIView.new;
	self.playheadView.backgroundColor = UIColor.whiteColor;
	self.playheadView.layer.cornerRadius = 1.5;
	self.playheadView.hidden = YES;
	[self.trackView addSubview:self.playheadView];
}

- (void)setupControls {
	self.playButton = [self roundButtonWithSymbol:@"play.fill" pointSize:22.0 diameter:58.0 alpha:0.11];
	[self.playButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.playButton];

	self.stopButton = [self roundButtonWithSymbol:@"stop.fill" pointSize:17.0 diameter:42.0 alpha:0.085];
	self.stopButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.72];
	[self.stopButton addTarget:self action:@selector(stopTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.stopButton];

	self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.sendButton.backgroundColor = UIColor.systemBlueColor;
	self.sendButton.layer.cornerRadius = 16.0;
	self.sendButton.layer.cornerCurve = kCACornerCurveContinuous;
	self.sendButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
	[self.sendButton setTitle:self.sendButtonTitle ?: SCILocalized(@"Send") forState:UIControlStateNormal];
	[self.sendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	[self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.sendButton];
}

#pragma mark - Layout

- (void)layoutViews {
	CGRect bounds = self.view.bounds;
	UIEdgeInsets safe = self.view.safeAreaInsets;

	CGFloat width = CGRectGetWidth(bounds);
	CGFloat height = CGRectGetHeight(bounds);
	CGFloat contentW = width - (kTrackMargin * 2.0);

	CGFloat sendH = 52.0;
	CGFloat sendY = height - safe.bottom - sendH - 14.0;

	self.closeButton.frame = CGRectMake(14.0, safe.top + 10.0, 38.0, 38.0);
	self.sendButton.frame = CGRectMake(kTrackMargin, sendY, contentW, sendH);

	CGFloat playSize = 58.0;
	CGFloat playY = CGRectGetMinY(self.sendButton.frame) - playSize - 18.0;
	self.playButton.frame = CGRectMake((width - playSize) * 0.5, playY, playSize, playSize);

	CGFloat stopSize = 42.0;
	self.stopButton.frame = CGRectMake(CGRectGetMaxX(self.playButton.frame) + 16.0,
									   CGRectGetMidY(self.playButton.frame) - (stopSize * 0.5),
									   stopSize,
									   stopSize);

	self.rangeLabel.frame = CGRectMake(kTrackMargin, playY - 38.0, contentW, 22.0);

	CGFloat trackY = CGRectGetMinY(self.rangeLabel.frame) - kTrackHeight - 20.0;
	self.trackView.frame = CGRectMake(kTrackMargin, trackY, contentW, kTrackHeight);

	self.durationLabel.frame = CGRectMake(kTrackMargin, trackY - 22.0, contentW, 16.0);
	self.titleLabel.frame = CGRectMake(kTrackMargin, trackY - 43.0, contentW, 18.0);

	CGFloat previewTop = safe.top + 62.0;
	CGFloat previewBottom = CGRectGetMinY(self.titleLabel.frame) - 20.0;
	CGFloat previewH = MAX(92.0, previewBottom - previewTop);

	if (self.isVideo) {
		self.previewContainer.frame = CGRectMake(kTrackMargin, previewTop, contentW, previewH);
	} else {
		CGFloat cardH = MIN(150.0, MAX(110.0, previewH));
		self.previewContainer.frame = CGRectMake(kTrackMargin, previewTop + ((previewH - cardH) * 0.5), contentW, cardH);
		self.audioIconView.frame = CGRectMake((CGRectGetWidth(self.previewContainer.bounds) - 72.0) * 0.5,
											  (CGRectGetHeight(self.previewContainer.bounds) - 72.0) * 0.5,
											  72.0,
											  72.0);
	}
}

#pragma mark - Views

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color alignment:(NSTextAlignment)alignment {
	UILabel *label = UILabel.new;
	label.font = font;
	label.textColor = color;
	label.textAlignment = alignment;
	label.numberOfLines = 1;
	return label;
}

- (UIButton *)roundButtonWithSymbol:(NSString *)symbol pointSize:(CGFloat)pointSize diameter:(CGFloat)diameter alpha:(CGFloat)alpha {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightMedium];

	button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:alpha];
	button.tintColor = UIColor.whiteColor;
	button.layer.cornerRadius = diameter * 0.5;
	button.layer.cornerCurve = kCACornerCurveContinuous;
	[button setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];

	return button;
}

- (UIView *)handleViewWithLeftSide:(BOOL)isLeft {
	UIView *hit = UIView.new;
	hit.backgroundColor = UIColor.clearColor;
	hit.userInteractionEnabled = YES;

	UIView *visual = UIView.new;
	visual.frame = CGRectMake((kHandleHitWidth - kHandleWidth) * 0.5, 0.0, kHandleWidth, kTrackHeight);
	visual.backgroundColor = UIColor.systemBlueColor;
	visual.layer.cornerRadius = 5.0;
	visual.layer.cornerCurve = kCACornerCurveContinuous;
	visual.layer.maskedCorners = isLeft
		? (kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner)
		: (kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner);
	visual.userInteractionEnabled = NO;

	UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(5.0, (kTrackHeight - 16.0) * 0.5, 6.0, 16.0)];
	grip.userInteractionEnabled = NO;

	for (NSInteger i = 0; i < 2; i++) {
		UIView *line = [[UIView alloc] initWithFrame:CGRectMake(i * 4.0, 0.0, 1.5, 16.0)];
		line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.72];
		line.layer.cornerRadius = 0.75;
		[grip addSubview:line];
	}

	[visual addSubview:grip];
	[hit addSubview:visual];

	return hit;
}

#pragma mark - Waveform

- (void)rebuildWaveformIfNeeded {
	CGFloat width = CGRectGetWidth(self.trackView.bounds);
	if (width <= 0.0 || fabs(width - self.lastWaveformWidth) < 1.0) return;

	self.lastWaveformWidth = width;

	NSMutableArray<UIView *> *oldBars = NSMutableArray.array;
	for (UIView *subview in self.trackView.subviews) {
		if (subview.tag == 8801) [oldBars addObject:subview];
	}
	[oldBars makeObjectsPerformSelector:@selector(removeFromSuperview)];

	NSInteger count = MAX(24, (NSInteger)(width / 4.0));
	CGFloat barW = 2.0;
	CGFloat gap = count > 1 ? (width - (count * barW)) / (count - 1) : 0.0;

	for (NSInteger i = 0; i < count; i++) {
		CGFloat normalized = 0.25 + ((CGFloat)arc4random_uniform(70) / 100.0);
		CGFloat barH = MAX(8.0, MIN(kTrackHeight - 14.0, normalized * (kTrackHeight - 8.0)));
		CGFloat x = i * (barW + gap);

		UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(x, (kTrackHeight - barH) * 0.5, barW, barH)];
		bar.tag = 8801;
		bar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
		bar.layer.cornerRadius = 1.0;
		[self.trackView insertSubview:bar atIndex:0];
	}

	[self.trackView bringSubviewToFront:self.selectedRangeView];
	[self.trackView bringSubviewToFront:self.leftHandle];
	[self.trackView bringSubviewToFront:self.rightHandle];
	[self.trackView bringSubviewToFront:self.playheadView];
}

#pragma mark - Time math

- (CGFloat)timeToX:(double)time {
	if (self.totalDuration <= 0.0) return 0.0;

	CGFloat width = CGRectGetWidth(self.trackView.bounds);
	return (CGFloat)(MAX(0.0, MIN(time, self.totalDuration)) / self.totalDuration) * width;
}

- (double)xToTime:(CGFloat)x {
	CGFloat width = CGRectGetWidth(self.trackView.bounds);
	if (width <= 0.0 || self.totalDuration <= 0.0) return 0.0;

	double time = (x / width) * self.totalDuration;
	return MAX(0.0, MIN(time, self.totalDuration));
}

- (NSString *)formatTime:(double)seconds {
	if (seconds < 0.0 || isnan(seconds) || !isfinite(seconds)) seconds = 0.0;

	NSInteger total = (NSInteger)floor(seconds);
	NSInteger minutes = total / 60;
	NSInteger secs = total % 60;

	return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)secs];
}

- (NSString *)formatDuration:(double)seconds {
	if (seconds < 0.0 || isnan(seconds) || !isfinite(seconds)) seconds = 0.0;

	if (seconds < 60.0) {
		return [NSString stringWithFormat:@"%.1fs", seconds];
	}

	NSInteger minutes = (NSInteger)(seconds / 60.0);
	NSInteger secs = (NSInteger)round(seconds - (minutes * 60.0));

	return [NSString stringWithFormat:@"%ldm %lds", (long)minutes, (long)secs];
}

#pragma mark - Range UI

- (void)updateRangeUI {
	if (!self.trackView) return;

	CGFloat leftX = [self timeToX:self.startTime];
	CGFloat rightX = [self timeToX:self.endTime];

	self.selectedRangeView.frame = CGRectMake(leftX, 0.0, MAX(0.0, rightX - leftX), kTrackHeight);
	self.leftHandle.frame = CGRectMake(leftX - (kHandleHitWidth * 0.5), 0.0, kHandleHitWidth, kTrackHeight);
	self.rightHandle.frame = CGRectMake(rightX - (kHandleHitWidth * 0.5), 0.0, kHandleHitWidth, kTrackHeight);

	double selected = MAX(0.0, self.endTime - self.startTime);
	self.rangeLabel.text = [NSString stringWithFormat:@"%@  —  %@   (%@)",
							[self formatTime:self.startTime],
							[self formatTime:self.endTime],
							[self formatDuration:selected]];

	[self movePlayheadTo:[self currentPlayerTime]];
}

- (void)movePlayheadTo:(double)time {
	double clamped = MAX(self.startTime, MIN(time, self.endTime));
	CGFloat x = [self timeToX:clamped];

	self.playheadView.frame = CGRectMake(x - 1.25, 3.0, 2.5, kTrackHeight - 6.0);
}

#pragma mark - Gestures

- (void)leftHandlePan:(UIPanGestureRecognizer *)pan {
	if (pan.state == UIGestureRecognizerStateBegan) {
		[self pausePlayer];
	}

	CGPoint translation = [pan translationInView:self.trackView];
	[pan setTranslation:CGPointZero inView:self.trackView];

	double newStart = [self xToTime:CGRectGetMidX(self.leftHandle.frame) + translation.x];
	newStart = MAX(0.0, MIN(newStart, self.endTime - kMinTrimDuration));

	if (self.maxDurationSecs > 0.0 && self.endTime - newStart > self.maxDurationSecs) {
		self.endTime = newStart + self.maxDurationSecs;
	}

	self.startTime = newStart;
	[self updateRangeUI];

	if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		[self seekPlayerTo:self.startTime showPlayhead:NO];
	}
}

- (void)rightHandlePan:(UIPanGestureRecognizer *)pan {
	if (pan.state == UIGestureRecognizerStateBegan) {
		[self pausePlayer];
	}

	CGPoint translation = [pan translationInView:self.trackView];
	[pan setTranslation:CGPointZero inView:self.trackView];

	double newEnd = [self xToTime:CGRectGetMidX(self.rightHandle.frame) + translation.x];
	newEnd = MIN(self.totalDuration, MAX(newEnd, self.startTime + kMinTrimDuration));

	if (self.maxDurationSecs > 0.0 && newEnd - self.startTime > self.maxDurationSecs) {
		newEnd = self.startTime + self.maxDurationSecs;
	}

	self.endTime = newEnd;
	[self updateRangeUI];

	if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		[self seekPlayerTo:self.startTime showPlayhead:NO];
	}
}

#pragma mark - Playback

- (double)currentPlayerTime {
	double time = CMTimeGetSeconds(self.player.currentTime);
	return (time >= 0.0 && !isnan(time) && isfinite(time)) ? time : self.startTime;
}

- (void)setPlayIcon:(NSString *)symbol {
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightMedium];
	[self.playButton setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
}

- (void)playPauseTapped {
	self.isPlaying ? [self pausePlayer] : [self playFromCurrentPosition];
}

- (void)playFromCurrentPosition {
	if (!self.player) return;

	double position = [self currentPlayerTime];
	if (position < self.startTime || position >= self.endTime - 0.05) {
		position = self.startTime;
	}

	self.isPlaying = YES;
	self.playheadView.hidden = NO;
	[self movePlayheadTo:position];
	[self setPlayIcon:@"pause.fill"];

	__weak typeof(self) weakSelf = self;
	[self.player seekToTime:CMTimeMakeWithSeconds(position, 600)
			toleranceBefore:CMTimeMakeWithSeconds(0.04, 600)
			 toleranceAfter:CMTimeMakeWithSeconds(0.04, 600)
		  completionHandler:^(BOOL finished) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !finished || !self.isPlaying) return;

		[self.player play];
	}];
}

- (void)pausePlayer {
	self.isPlaying = NO;
	[self.player pause];
	[self setPlayIcon:@"play.fill"];
}

- (void)stopTapped {
	[self pausePlayer];
	[self seekPlayerTo:self.startTime showPlayhead:NO];
	self.playheadView.hidden = YES;
}

- (void)seekPlayerTo:(double)time showPlayhead:(BOOL)show {
	if (!self.player) return;

	double clamped = MAX(self.startTime, MIN(time, self.endTime));
	if (show) {
		self.playheadView.hidden = NO;
		[self movePlayheadTo:clamped];
	}

	[self.player seekToTime:CMTimeMakeWithSeconds(clamped, 600)
			toleranceBefore:CMTimeMakeWithSeconds(0.04, 600)
			 toleranceAfter:CMTimeMakeWithSeconds(0.04, 600)];
}

#pragma mark - Actions

- (void)cancelTapped {
	[self tearDownPlayer];
	[self deletePreConvertedTempIfAny];

	void (^callback)(void) = self.onCancel;
	[self dismissViewControllerAnimated:YES completion:^{
		if (callback) callback();
	}];
}

- (void)sendTapped {
	double duration = self.endTime - self.startTime;

	if (duration < kMinTrimDuration) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Selection too short (min 0.5s)")];
		return;
	}

	CMTimeRange trimRange = CMTimeRangeMake(CMTimeMakeWithSeconds(self.startTime, 600),
											CMTimeMakeWithSeconds(duration, 600));

	void (^callback)(CMTimeRange) = self.onSend;

	[self tearDownPlayer];

	[self dismissViewControllerAnimated:YES completion:^{
		if (callback) callback(trimRange);
	}];
}

#pragma mark - Cleanup

- (void)tearDownPlayer {
	if (self.timeObserver && self.player) {
		[self.player removeTimeObserver:self.timeObserver];
	}

	self.timeObserver = nil;

	[self.player pause];
	self.player = nil;

	[self.playerLayer removeFromSuperlayer];
	self.playerLayer = nil;

	self.isPlaying = NO;

	[[AVAudioSession sharedInstance] setActive:NO
								   withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
										 error:nil];
}

- (void)deletePreConvertedTempIfAny {
	if (!self.mediaURL.isFileURL) return;

	NSString *name = self.mediaURL.lastPathComponent ?: @"";
	if (![name hasPrefix:@"rg_pre_"]) return;

	[NSFileManager.defaultManager removeItemAtURL:self.mediaURL error:nil];
}

@end