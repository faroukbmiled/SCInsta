#import "Download.h"
#import "../PhotoAlbum.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

// Compat shim — forwards the legacy ticket / non-ticket API to SCINotificationCenter.
// Each ticket gets its own SCINotificationHandle; the non-ticket API drives one
// shared ad-hoc handle. New code should call SCINotifyProgress directly.

static inline float SCIClamp(float v) {
	return MAX(0.0f, MIN(v, 1.0f));
}

@interface SCIDownloadPillView ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCINotificationHandle *> *ticketHandles;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *ticketTitles;
@property (nonatomic, strong) SCINotificationHandle *adHocHandle;
@property (nonatomic, copy)   NSString *adHocTitle;
@property (nonatomic, copy)   NSString *adHocSubtitle;
@end

@implementation SCIDownloadPillView

+ (instancetype)shared {
	static SCIDownloadPillView *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [SCIDownloadPillView new]; });
	return shared;
}

- (instancetype)init {
	self = [super initWithFrame:CGRectZero];
	if (!self) return nil;
	_ticketHandles = [NSMutableDictionary new];
	_ticketTitles = [NSMutableDictionary new];
	return self;
}

- (void)sciOnMain:(dispatch_block_t)block {
	if (!block) return;
	NSThread.isMainThread ? block() : dispatch_async(dispatch_get_main_queue(), block);
}

- (void)sciEnsureAdHocStarted {
	if (self.adHocHandle && !self.adHocHandle.isFinished) return;
	__weak typeof(self) weakSelf = self;
	self.adHocHandle = SCINotifyProgress(SCI_NOTIF_DOWNLOAD,
	                                     self.adHocTitle ?: SCILocalized(@"Downloading..."),
	                                     ^{
		void (^cb)(void) = weakSelf.onCancel;
		weakSelf.onCancel = nil;
		if (cb) cb();
	});
}

#pragma mark - Legacy non-ticket API (forwards to a single ad-hoc handle)

- (void)resetState {
	[self sciOnMain:^{
		[self.adHocHandle dismiss];
		self.adHocHandle = nil;
		self.adHocTitle = SCILocalized(@"Downloading...");
		self.adHocSubtitle = nil;
	}];
}

- (void)showInView:(UIView *)view {
	(void)view; // Center handles host view internally.
	[self sciOnMain:^{ [self sciEnsureAdHocStarted]; }];
}

- (void)dismiss {
	[self sciOnMain:^{
		[self.adHocHandle dismiss];
		self.adHocHandle = nil;
		self.onCancel = nil;
	}];
}

- (void)dismissAfterDelay:(NSTimeInterval)delay {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self dismiss];
	});
}

- (void)setProgress:(float)progress {
	[self sciOnMain:^{
		[self sciEnsureAdHocStarted];
		[self.adHocHandle setProgress:SCIClamp(progress)];
	}];
}

- (void)setText:(NSString *)text {
	[self sciOnMain:^{
		self.adHocTitle = text;
		if (self.adHocHandle && !self.adHocHandle.isFinished) {
			[self.adHocHandle setTitle:text ?: @""];
		}
	}];
}

- (void)setSubtitle:(NSString *)text {
	[self sciOnMain:^{
		self.adHocSubtitle = text;
		if (self.adHocHandle && !self.adHocHandle.isFinished) {
			[self.adHocHandle setSubtitle:text];
		}
	}];
}

- (void)showSuccess:(NSString *)text {
	[self sciOnMain:^{
		[self sciEnsureAdHocStarted];
		[self.adHocHandle success:text ?: SCILocalized(@"Done")];
		self.adHocHandle = nil;
		self.onCancel = nil;
	}];
}

- (void)showError:(NSString *)text {
	[self sciOnMain:^{
		[self sciEnsureAdHocStarted];
		[self.adHocHandle error:text ?: SCILocalized(@"Failed")];
		self.adHocHandle = nil;
		self.onCancel = nil;
	}];
}

- (void)showBulkProgress:(NSUInteger)completed total:(NSUInteger)total {
	NSUInteger safeTotal = MAX(total, 1);
	NSString *title = [NSString stringWithFormat:SCILocalized(@"Downloading %lu of %lu"),
	                   (unsigned long)MIN(completed + 1, safeTotal), (unsigned long)safeTotal];
	[self sciOnMain:^{
		[self sciEnsureAdHocStarted];
		[self.adHocHandle setTitle:title];
		[self.adHocHandle setProgress:SCIClamp((float)completed / (float)safeTotal)];
	}];
}

#pragma mark - Ticket API (one handle per ticket)

- (NSString *)beginTicketWithTitle:(NSString *)title onCancel:(void (^)(void))cancel {
	NSString *ticketId = NSUUID.UUID.UUIDString;
	NSString *resolvedTitle = title ?: SCILocalized(@"Downloading...");
	void (^cancelCopy)(void) = [cancel copy];
	[self sciOnMain:^{
		SCINotificationHandle *h = SCINotifyProgress(SCI_NOTIF_DOWNLOAD, resolvedTitle, cancelCopy);
		if (h) self.ticketHandles[ticketId] = h;
		self.ticketTitles[ticketId] = resolvedTitle;
	}];
	return ticketId;
}

- (void)updateTicket:(NSString *)ticketId progress:(float)progress {
	if (!ticketId.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] setProgress:SCIClamp(progress)];
	}];
}

- (void)updateTicket:(NSString *)ticketId text:(NSString *)text {
	if (!ticketId.length || !text.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] setTitle:text];
		self.ticketTitles[ticketId] = text;
	}];
}

- (void)finishTicket:(NSString *)ticketId successMessage:(NSString *)message {
	if (!ticketId.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] success:message ?: SCILocalized(@"Done")];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

- (void)finishTicket:(NSString *)ticketId errorMessage:(NSString *)message {
	if (!ticketId.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] error:message ?: SCILocalized(@"Failed")];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

- (void)finishTicket:(NSString *)ticketId cancelled:(NSString *)message {
	if (!ticketId.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] cancelled:message ?: SCILocalized(@"Cancelled")];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
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

	[self.downloadManager downloadFileWithURL:url fileExtension:fileExtension];
}

- (void)downloadDidStart {
}

- (void)downloadDidCancel {
	[self.pill finishTicket:self.ticketId cancelled:SCILocalized(@"Cancelled")];
}

- (void)downloadDidProgress:(float)progress {
	if (!self.showProgress) return;

	float safeProgress = SCIClamp(progress);

	[self.pill updateTicket:self.ticketId progress:safeProgress];
	[self.pill updateTicket:self.ticketId text:[NSString stringWithFormat:SCILocalized(@"Downloading %d%%"), (int)(safeProgress * 100.0f)]];
}

- (void)downloadDidFinishWithError:(NSError *)error {
	if (!error || error.code == NSURLErrorCancelled) return;

	NSLog(@"[RyukGram] Download: Download failed with error: \"%@\"", error);

	[self.pill finishTicket:self.ticketId errorMessage:SCILocalized(@"Download failed")];
}

- (void)downloadDidFinishWithFileURL:(NSURL *)fileURL {
	dispatch_async(dispatch_get_main_queue(), ^{
		// saveToPhotos / saveToGallery report their own pill state.
		if (self.action != saveToPhotos && self.action != saveToGallery) {
			[self.pill finishTicket:self.ticketId successMessage:SCILocalized(@"Done")];
		}

		NSString *galleryMode = [SCIUtils getStringPref:@"gallery_save_mode"];
		BOOL isAudio = SCIGalleryExtensionIsAudio(fileURL.pathExtension);

		switch (self.action) {
			case share:
				[SCIUtils showShareVC:fileURL];
				if ([galleryMode isEqualToString:@"mirror"] && self.pendingGallerySaveMetadata) {
					[self logFileToGalleryQuiet:fileURL];
				}
				break;

			case quickLook:
				[SCIUtils showQuickLookVC:@[fileURL]];
				break;

			case saveToPhotos:
				// Photos library rejects audio — fall back to gallery / share.
				if (isAudio) {
					if ([galleryMode isEqualToString:@"off"] || galleryMode.length == 0) {
						[self.pill finishTicket:self.ticketId successMessage:SCILocalized(@"Done")];
						[SCIUtils showShareVC:fileURL];
					} else {
						[self saveFileToGallery:fileURL];
					}
					break;
				}
				if ([galleryMode isEqualToString:@"gallery_only"]) {
					[self saveFileToGallery:fileURL];
				} else {
					[self saveFileToPhotos:fileURL];
					if ([galleryMode isEqualToString:@"mirror"] && self.pendingGallerySaveMetadata) {
						[self logFileToGalleryQuiet:fileURL];
					}
				}
				break;

			case saveToGallery:
				[self saveFileToGallery:fileURL];
				break;
		}
	});
}

- (void)saveFileToGallery:(NSURL *)fileURL {
	NSError *err = nil;
	SCIGalleryFile *file = [self saveFileURL:fileURL toGalleryWithError:&err];
	if (file && !err) {
		[self.pill finishTicket:self.ticketId successMessage:SCILocalized(@"Saved to Gallery")];
	} else {
		NSLog(@"[RyukGram] Gallery save failed: %@", err);
		[self.pill finishTicket:self.ticketId errorMessage:SCILocalized(@"Failed to save")];
	}
}

// Mirror mode: Photos save reports pill, gallery log is fire-and-forget.
- (void)logFileToGalleryQuiet:(NSURL *)fileURL {
	NSError *err = nil;
	[self saveFileURL:fileURL toGalleryWithError:&err];
	if (err) NSLog(@"[RyukGram] Gallery mirror log failed: %@", err);
}

// Copies (not moves) so share/Photos flow can still use the source file.
- (SCIGalleryFile *)saveFileURL:(NSURL *)fileURL toGalleryWithError:(NSError **)error {
	SCIGalleryMediaType mediaType = SCIGalleryMediaTypeForExtension(fileURL.pathExtension);
	SCIGallerySaveMetadata *metadata = [self.pendingGallerySaveMetadata isKindOfClass:[SCIGallerySaveMetadata class]]
		? self.pendingGallerySaveMetadata
		: nil;
	SCIGallerySource source = metadata ? (SCIGallerySource)metadata.source : SCIGallerySourceOther;
	return [SCIGalleryFile saveFileToGallery:fileURL
	                                  source:source
	                               mediaType:mediaType
	                              folderPath:nil
	                                metadata:metadata
	                                   error:error];
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
		void (^done)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (success) {
					[self.pill finishTicket:self.ticketId successMessage:useAlbum ? SCILocalized(@"Saved to RyukGram") : SCILocalized(@"Saved to Photos")];
				} else {
					NSLog(@"[RyukGram] Download: Save to Photos failed: %@", error);
					[self.pill finishTicket:self.ticketId errorMessage:SCILocalized(@"Failed to save")];
				}
			});
		};
		if (useAlbum) {
			[SCIPhotoAlbum saveFileToAlbum:fileURL completion:done];
			return;
		}
		[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
			NSString *ext = fileURL.pathExtension.lowercaseString;
			BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];
			PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
			PHAssetResourceCreationOptions *options = PHAssetResourceCreationOptions.new;
			options.shouldMoveFile = YES;
			[request addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto) fileURL:fileURL options:options];
			request.creationDate = NSDate.date;
		} completionHandler:done];
	}];
}
@end
