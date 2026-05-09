#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import "../InstagramHeaders.h"
#import "../Utils.h"

#import "Manager.h"

@interface SCIDownloadPillView : UIView
@property (nonatomic, copy) void (^onCancel)(void);

- (void)resetState;
- (void)showInView:(UIView *)view;
- (void)dismiss;
- (void)dismissAfterDelay:(NSTimeInterval)delay;
- (void)setProgress:(float)progress;
- (void)setText:(NSString *)text;
- (void)setSubtitle:(NSString *)text;
- (void)showSuccess:(NSString *)text;
- (void)showError:(NSString *)text;
- (void)showBulkProgress:(NSUInteger)completed total:(NSUInteger)total;

// Multi-download ticket API. All methods are safe from any thread.
// Tap-to-cancel pops the most recently pushed ticket.
- (NSString *)beginTicketWithTitle:(NSString *)title onCancel:(void (^)(void))cancel;
- (void)updateTicket:(NSString *)ticketId progress:(float)progress;
- (void)updateTicket:(NSString *)ticketId text:(NSString *)text;
- (void)finishTicket:(NSString *)ticketId successMessage:(NSString *)message;
- (void)finishTicket:(NSString *)ticketId errorMessage:(NSString *)message;
- (void)finishTicket:(NSString *)ticketId cancelled:(NSString *)message;

/// Shared singleton pill — reused across all downloads so only one shows at a time.
+ (instancetype)shared;
@end

@interface SCIDownloadDelegate : NSObject <SCIDownloadDelegateProtocol>

typedef NS_ENUM(NSUInteger, DownloadAction) {
    share,
    quickLook,
    saveToPhotos,
    saveToGallery
};
@property (nonatomic, readonly) DownloadAction action;
@property (nonatomic, readonly) BOOL showProgress;
/// Optional gallery metadata. When set + the global save mode includes the
/// gallery, the download is also (or instead) logged into the RyukGram gallery.
@property (nonatomic, strong, nullable) id pendingGallerySaveMetadata;

@property (nonatomic, strong) SCIDownloadManager *downloadManager;
@property (nonatomic, strong) SCIDownloadPillView *pill;
@property (nonatomic, copy) NSString *ticketId;

- (instancetype)initWithAction:(DownloadAction)action showProgress:(BOOL)showProgress;

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel;

@end
