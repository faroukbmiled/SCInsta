#import "Download.h"
#import "../PhotoAlbum.h"
#import <Photos/Photos.h>

static inline UIImage *SCIIcon(NSString *name, CGFloat size, UIImageSymbolWeight weight) {
	return [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
}

static inline float SCIClampProgress(float progress) {
	return MAX(0.0f, MIN(progress, 1.0f));
}

@interface SCIDownloadSlot : NSObject
@property (nonatomic, copy) NSString *ticketId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) float progress;
@property (nonatomic, copy) void (^onCancel)(void);
@property (nonatomic, assign) BOOL finished;
@end

@implementation SCIDownloadSlot
@end

@interface SCIDownloadPillView ()
@property (nonatomic, strong) NSMutableArray<SCIDownloadSlot *> *slots;
@property (nonatomic, strong) UIStackView *textStack;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *tintView;
@property (nonatomic, strong) UIView *iconPlateView;
@end

@implementation SCIDownloadPillView

+ (instancetype)shared {
	static SCIDownloadPillView *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [[SCIDownloadPillView alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super initWithFrame:CGRectZero];
	if (!self) return nil;

	_slots = [NSMutableArray array];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_sciAppDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_sciAppDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];

	self.alpha = 0.0;
	self.clipsToBounds = NO;
	self.translatesAutoresizingMaskIntoConstraints = NO;
	self.layer.cornerRadius = 14.0;
	self.layer.cornerCurve = kCACornerCurveContinuous;
	self.layer.borderWidth = 0.6;
	self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
	self.layer.shadowColor = UIColor.blackColor.CGColor;
	self.layer.shadowOpacity = 0.16;
	self.layer.shadowRadius = 12.0;
	self.layer.shadowOffset = CGSizeMake(0.0, 5.0);

	_blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
	_blurView.translatesAutoresizingMaskIntoConstraints = NO;
	_blurView.clipsToBounds = YES;
	_blurView.layer.cornerRadius = 14.0;
	_blurView.layer.cornerCurve = kCACornerCurveContinuous;
	[self addSubview:_blurView];

	_tintView = [UIView new];
	_tintView.translatesAutoresizingMaskIntoConstraints = NO;
	_tintView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.035];
	[_blurView.contentView addSubview:_tintView];

	_iconPlateView = [UIView new];
	_iconPlateView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconPlateView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
	_iconPlateView.layer.cornerRadius = 15.0;
	_iconPlateView.layer.cornerCurve = kCACornerCurveContinuous;
	[_blurView.contentView addSubview:_iconPlateView];

	_iconView = [UIImageView new];
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconView.tintColor = UIColor.whiteColor;
	_iconView.contentMode = UIViewContentModeScaleAspectFit;
	_iconView.image = SCIIcon(@"arrow.down.circle.fill", 16.0, UIImageSymbolWeightSemibold);
	[_iconPlateView addSubview:_iconView];

	_textLabel = [UILabel new];
	_textLabel.text = SCILocalized(@"Downloading...");
	_textLabel.textColor = UIColor.whiteColor;
	_textLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
	_textLabel.textAlignment = NSTextAlignmentCenter;
	_textLabel.numberOfLines = 1;
	_textLabel.adjustsFontSizeToFitWidth = YES;
	_textLabel.minimumScaleFactor = 0.80;

	_subtitleLabel = [UILabel new];
	_subtitleLabel.text = SCILocalized(@"Tap to cancel");
	_subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.68];
	_subtitleLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
	_subtitleLabel.textAlignment = NSTextAlignmentCenter;
	_subtitleLabel.numberOfLines = 1;
	_subtitleLabel.adjustsFontSizeToFitWidth = YES;
	_subtitleLabel.minimumScaleFactor = 0.80;

	_textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_textLabel, _subtitleLabel]];
	_textStack.axis = UILayoutConstraintAxisVertical;
	_textStack.alignment = UIStackViewAlignmentFill;
	_textStack.distribution = UIStackViewDistributionFill;
	_textStack.spacing = 0.0;
	_textStack.translatesAutoresizingMaskIntoConstraints = NO;
	[_blurView.contentView addSubview:_textStack];

	_progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
	_progressBar.translatesAutoresizingMaskIntoConstraints = NO;
	_progressBar.progressTintColor = UIColor.systemBlueColor;
	_progressBar.trackTintColor = [UIColor colorWithWhite:1.0 alpha:0.10];
	_progressBar.clipsToBounds = YES;
	_progressBar.layer.cornerRadius = 1.25;
	_progressBar.layer.masksToBounds = YES;
	[_blurView.contentView addSubview:_progressBar];

	[self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)]];

	[NSLayoutConstraint activateConstraints:@[
		[_blurView.topAnchor constraintEqualToAnchor:self.topAnchor],
		[_blurView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		[_blurView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[_blurView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

		[_tintView.topAnchor constraintEqualToAnchor:_blurView.contentView.topAnchor],
		[_tintView.bottomAnchor constraintEqualToAnchor:_blurView.contentView.bottomAnchor],
		[_tintView.leadingAnchor constraintEqualToAnchor:_blurView.contentView.leadingAnchor],
		[_tintView.trailingAnchor constraintEqualToAnchor:_blurView.contentView.trailingAnchor],

		[_iconPlateView.leadingAnchor constraintEqualToAnchor:_blurView.contentView.leadingAnchor constant:11.0],
		[_iconPlateView.centerYAnchor constraintEqualToAnchor:_blurView.contentView.centerYAnchor constant:-2.0],
		[_iconPlateView.widthAnchor constraintEqualToConstant:30.0],
		[_iconPlateView.heightAnchor constraintEqualToConstant:30.0],

		[_iconView.centerXAnchor constraintEqualToAnchor:_iconPlateView.centerXAnchor],
		[_iconView.centerYAnchor constraintEqualToAnchor:_iconPlateView.centerYAnchor],
		[_iconView.widthAnchor constraintEqualToConstant:16.0],
		[_iconView.heightAnchor constraintEqualToConstant:16.0],

		[_textStack.centerXAnchor constraintEqualToAnchor:_blurView.contentView.centerXAnchor],
		[_textStack.centerYAnchor constraintEqualToAnchor:_blurView.contentView.centerYAnchor constant:-2.0],
		[_textStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_iconPlateView.trailingAnchor constant:8.0],
		[_textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_blurView.contentView.trailingAnchor constant:-12.0],

		[_progressBar.leadingAnchor constraintEqualToAnchor:_blurView.contentView.leadingAnchor constant:14.0],
		[_progressBar.trailingAnchor constraintEqualToAnchor:_blurView.contentView.trailingAnchor constant:-14.0],
		[_progressBar.bottomAnchor constraintEqualToAnchor:_blurView.contentView.bottomAnchor constant:-7.0],
		[_progressBar.heightAnchor constraintEqualToConstant:2.5],

		[self.heightAnchor constraintEqualToConstant:56.0]
	]];

	return self;
}

- (void)_setIcon:(NSString *)name tint:(UIColor *)tint plate:(UIColor *)plate {
	self.iconView.image = SCIIcon(name, 16.0, UIImageSymbolWeightSemibold);
	self.iconView.tintColor = tint;
	self.iconPlateView.backgroundColor = plate;
}

- (void)_resetVisualState {
	[self _setIcon:@"arrow.down.circle.fill" tint:UIColor.whiteColor plate:[UIColor colorWithWhite:1.0 alpha:0.08]];
	self.textLabel.text = SCILocalized(@"Downloading...");
	self.subtitleLabel.text = SCILocalized(@"Tap to cancel");
	self.subtitleLabel.hidden = NO;
	self.progressBar.hidden = NO;
	[self.progressBar setProgress:0.0 animated:NO];
}

- (void)handleTap {
	SCIDownloadSlot *slot = self.slots.lastObject;
	void (^callback)(void) = slot ? slot.onCancel : self.onCancel;

	if (slot) slot.onCancel = nil;
	else self.onCancel = nil;

	if (callback) callback();
}

- (void)resetState {
	[self _resetVisualState];
}

- (void)showInView:(UIView *)view {
	[self removeFromSuperview];

	self.alpha = 0.0;
	self.transform = CGAffineTransformMakeScale(0.96, 0.96);
	self.translatesAutoresizingMaskIntoConstraints = NO;
	[view addSubview:self];

	[NSLayoutConstraint activateConstraints:@[
		[self.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:8.0],
		[self.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
		[self.widthAnchor constraintGreaterThanOrEqualToConstant:205.0],
		[self.widthAnchor constraintLessThanOrEqualToConstant:285.0]
	]];

	[UIView animateWithDuration:0.28 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.45 options:UIViewAnimationOptionCurveEaseOut animations:^{
		self.alpha = 1.0;
		self.transform = CGAffineTransformIdentity;
	} completion:nil];
}

- (void)dismiss {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.slots.count > 0) return;
		if (self.alpha <= 0.01 && !self.superview) return;

		self.onCancel = nil;

		[UIView animateWithDuration:0.22 animations:^{
			self.alpha = 0.0;
			self.transform = CGAffineTransformMakeScale(0.92, 0.92);
		} completion:^(__unused BOOL finished) {
			[self removeFromSuperview];
			self.transform = CGAffineTransformIdentity;
		}];
	});
}

- (void)dismissAfterDelay:(NSTimeInterval)delay {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self dismiss];
	});
}

- (void)setProgress:(float)progress {
	self.progressBar.hidden = NO;
	[self.progressBar setProgress:SCIClampProgress(progress) animated:YES];
}

- (void)setText:(NSString *)text {
	self.textLabel.text = text ?: @"";
}

- (void)setSubtitle:(NSString *)text {
	self.subtitleLabel.text = text ?: @"";
	self.subtitleLabel.hidden = text.length == 0;
}

- (void)showSuccess:(NSString *)text {
	[self _setIcon:@"checkmark.circle.fill" tint:UIColor.systemGreenColor plate:[UIColor.systemGreenColor colorWithAlphaComponent:0.18]];
	self.textLabel.text = text ?: SCILocalized(@"Done");
	self.subtitleLabel.hidden = YES;
	self.progressBar.hidden = YES;
	self.onCancel = nil;
}

- (void)showError:(NSString *)text {
	[self _setIcon:@"xmark.circle.fill" tint:UIColor.systemRedColor plate:[UIColor.systemRedColor colorWithAlphaComponent:0.18]];
	self.textLabel.text = text ?: SCILocalized(@"Failed");
	self.subtitleLabel.hidden = YES;
	self.progressBar.hidden = YES;
	self.onCancel = nil;
}

- (void)showBulkProgress:(NSUInteger)completed total:(NSUInteger)total {
	NSUInteger safeTotal = MAX(total, 1);

	self.textLabel.text = [NSString stringWithFormat:@"Downloading %lu of %lu", (unsigned long)MIN(completed + 1, safeTotal), (unsigned long)safeTotal];
	self.subtitleLabel.text = SCILocalized(@"Tap to cancel");
	self.subtitleLabel.hidden = NO;
	self.progressBar.hidden = NO;

	[self.progressBar setProgress:SCIClampProgress((float)completed / (float)safeTotal) animated:YES];
}

- (void)_onMain:(dispatch_block_t)block {
	if (!block) return;
	if (NSThread.isMainThread) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}

- (SCIDownloadSlot *)_slotForId:(NSString *)ticketId {
	if (!ticketId.length) return nil;

	for (SCIDownloadSlot *slot in self.slots) {
		if ([slot.ticketId isEqualToString:ticketId]) return slot;
	}

	return nil;
}

- (void)_renderTop {
	SCIDownloadSlot *top = self.slots.lastObject;
	if (!top) return;

	[self _setIcon:@"arrow.down.circle.fill" tint:UIColor.whiteColor plate:[UIColor colorWithWhite:1.0 alpha:0.08]];
	self.textLabel.text = top.title ?: SCILocalized(@"Downloading...");
	self.subtitleLabel.hidden = NO;
	self.subtitleLabel.text = self.slots.count > 1 ? [NSString stringWithFormat:@"%lu active • tap to cancel", (unsigned long)self.slots.count] : SCILocalized(@"Tap to cancel");
	self.progressBar.hidden = NO;

	[self.progressBar setProgress:SCIClampProgress(top.progress) animated:YES];
}

- (NSString *)beginTicketWithTitle:(NSString *)title onCancel:(void (^)(void))cancel {
	NSString *ticketId = NSUUID.UUID.UUIDString;
	void (^cancelCopy)(void) = [cancel copy];

	[self _onMain:^{
		SCIDownloadSlot *slot = [SCIDownloadSlot new];
		slot.ticketId = ticketId;
		slot.title = title ?: SCILocalized(@"Downloading...");
		slot.progress = 0.0f;
		slot.onCancel = cancelCopy;

		[self.slots addObject:slot];

		self.alpha = 1.0;
		self.transform = CGAffineTransformIdentity;

		if (!self.superview) {
			UIWindow *window = UIApplication.sharedApplication.keyWindow;
			UIView *host = window ?: topMostController().view;
			if (host) [self showInView:host];
		}

		[self _renderTop];
	}];

	return ticketId;
}

- (void)_sciAppDidBecomeActive {
	[self _onMain:^{
		if (self.slots.count > 0) {
			[self _renderTop];
			return;
		}

		if (self.superview || self.alpha > 0.01) {
			self.alpha = 0.0;
			self.transform = CGAffineTransformIdentity;
			[self removeFromSuperview];
		}
	}];
}

- (void)_sciAppDidEnterBackground {
	[self _onMain:^{
		for (SCIDownloadSlot *slot in self.slots.copy) {
			void (^callback)(void) = slot.onCancel;
			slot.onCancel = nil;
			if (callback) callback();
		}
	}];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateTicket:(NSString *)ticketId progress:(float)progress {
	[self _onMain:^{
		SCIDownloadSlot *slot = [self _slotForId:ticketId];
		if (!slot || slot.finished) return;

		slot.progress = SCIClampProgress(progress);
		if (self.slots.lastObject == slot) [self.progressBar setProgress:slot.progress animated:YES];
	}];
}

- (void)updateTicket:(NSString *)ticketId text:(NSString *)text {
	[self _onMain:^{
		SCIDownloadSlot *slot = [self _slotForId:ticketId];
		if (!slot || slot.finished) return;

		if (text.length) slot.title = text;
		if (self.slots.lastObject == slot) self.textLabel.text = slot.title;
	}];
}

- (void)_removeSlot:(SCIDownloadSlot *)slot finalText:(NSString *)finalText finalIcon:(NSString *)finalIcon iconColor:(UIColor *)iconColor {
	if (!slot || slot.finished) return;

	slot.finished = YES;
	slot.onCancel = nil;
	[self.slots removeObject:slot];

	if (self.slots.count > 0) {
		[self _renderTop];
		return;
	}

	[self _setIcon:finalIcon tint:iconColor plate:[iconColor colorWithAlphaComponent:0.18]];
	self.textLabel.text = finalText;
	self.subtitleLabel.hidden = YES;
	self.progressBar.hidden = YES;

	[self dismissAfterDelay:1.2];
}

- (void)finishTicket:(NSString *)ticketId successMessage:(NSString *)message {
	[self _onMain:^{
		[self _removeSlot:[self _slotForId:ticketId] finalText:message ?: SCILocalized(@"Done") finalIcon:@"checkmark.circle.fill" iconColor:UIColor.systemGreenColor];
	}];
}

- (void)finishTicket:(NSString *)ticketId errorMessage:(NSString *)message {
	[self _onMain:^{
		[self _removeSlot:[self _slotForId:ticketId] finalText:message ?: SCILocalized(@"Failed") finalIcon:@"xmark.circle.fill" iconColor:UIColor.systemRedColor];
	}];
}

- (void)finishTicket:(NSString *)ticketId cancelled:(NSString *)message {
	[self _onMain:^{
		[self _removeSlot:[self _slotForId:ticketId] finalText:message ?: SCILocalized(@"Cancelled") finalIcon:@"xmark.circle.fill" iconColor:UIColor.systemOrangeColor];
	}];
}

@end

@implementation SCIDownloadDelegate

- (instancetype)initWithAction:(DownloadAction)action showProgress:(BOOL)showProgress {
	self = [super init];

	if (self) {
		_action = action;
		_showProgress = showProgress;
		self.downloadManager = [[SCIDownloadManager alloc] initWithDelegate:self];
	}

	return self;
}

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel {
	SCIDownloadPillView *pill = SCIDownloadPillView.shared;
	self.pill = pill;

	__weak typeof(self) weakSelf = self;
	self.ticketId = [pill beginTicketWithTitle:hudLabel ?: SCILocalized(@"Downloading...") onCancel:^{
		[weakSelf.downloadManager cancelDownload];
	}];

	NSLog(@"[SCInsta] Download: Will start download for url \"%@\" with file extension: \".%@\"", url, fileExtension);
	[self.downloadManager downloadFileWithURL:url fileExtension:fileExtension];
}

- (void)downloadDidStart {
	NSLog(@"[SCInsta] Download: Download started");
}

- (void)downloadDidCancel {
	[self.pill finishTicket:self.ticketId cancelled:SCILocalized(@"Cancelled")];
	NSLog(@"[SCInsta] Download: Download cancelled");
}

- (void)downloadDidProgress:(float)progress {
	if (!self.showProgress) return;

	float safeProgress = SCIClampProgress(progress);
	[self.pill updateTicket:self.ticketId progress:safeProgress];
	[self.pill updateTicket:self.ticketId text:[NSString stringWithFormat:@"Downloading %d%%", (int)(safeProgress * 100.0f)]];
}

- (void)downloadDidFinishWithError:(NSError *)error {
	if (!error || error.code == NSURLErrorCancelled) return;

	NSLog(@"[SCInsta] Download: Download failed with error: \"%@\"", error);
	[self.pill finishTicket:self.ticketId errorMessage:SCILocalized(@"Download failed")];
}

- (void)downloadDidFinishWithFileURL:(NSURL *)fileURL {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSLog(@"[SCInsta] Download: Finished with url: \"%@\"", fileURL.absoluteString);

		if (self.action != saveToPhotos) {
			[self.pill finishTicket:self.ticketId successMessage:SCILocalized(@"Done")];
		}

		switch (self.action) {
			case share:
				[SCIUtils showShareVC:fileURL];
				break;

			case quickLook:
				[SCIUtils showQuickLookVC:@[fileURL]];
				break;

			case saveToPhotos:
				[self saveFileToPhotos:fileURL];
				break;
		}
	});
}

- (void)saveFileToPhotos:(NSURL *)fileURL {
	[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
		if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
				[self.pill finishTicket:self.ticketId errorMessage:SCILocalized(@"Photo library access denied")];
			});
			return;
		}

		BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];

		void (^onDone)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (success) {
					[self.pill finishTicket:self.ticketId successMessage:useAlbum ? SCILocalized(@"Saved to RyukGram") : SCILocalized(@"Saved to Photos")];
				} else {
					NSLog(@"[SCInsta] Download: Save to Photos failed: %@", error);
					[self.pill finishTicket:self.ticketId errorMessage:SCILocalized(@"Failed to save")];
				}
			});
		};

		if (useAlbum) {
			[SCIPhotoAlbum saveFileToAlbum:fileURL completion:onDone];
			return;
		}

		[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
			NSString *extension = fileURL.pathExtension.lowercaseString;
			BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:extension];

			PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
			PHAssetResourceCreationOptions *options = [PHAssetResourceCreationOptions new];
			options.shouldMoveFile = YES;

			[request addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto) fileURL:fileURL options:options];
			request.creationDate = NSDate.date;
		} completionHandler:onDone];
	}];
}

@end