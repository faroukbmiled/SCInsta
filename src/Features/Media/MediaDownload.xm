// Legacy download gestures — off by default, kept for users who prefer the
// old multi-finger long-press workflow over the action button menu.
//
// The modern flow lives in:
//   src/ActionButton/                    — menu + handlers
//   src/Features/ActionButton/           — per-context button injection
//   src/Features/StoriesAndMessages/OverlayButtons.xm — stories action button
//
// This file only contains:
//   1. Long-press gesture recognizers on feed/story/reel media views, gated
//      by `dw_legacy_gesture`. When on, they reuse the old sciDownload* path
//      and save via the user's `dw_save_action` preference.
//   2. The profile-picture long-press gesture (always on when `save_profile`).

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import <objc/runtime.h>

static SCIDownloadDelegate *imageDownloadDelegate;
static SCIDownloadDelegate *videoDownloadDelegate;

static DownloadAction sciGetDownloadAction() {
    NSString *method = [SCIUtils getStringPref:@"dw_save_action"];
    if ([method isEqualToString:@"photos"]) return saveToPhotos;
    return share;
}

static void initDownloaders() {
    DownloadAction action = sciGetDownloadAction();
    DownloadAction imgAction = (action == saveToPhotos) ? saveToPhotos : quickLook;
    imageDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:imgAction showProgress:NO];
    videoDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:YES];
}

static BOOL sciLegacyGestureEnabled() {
    return [SCIUtils getBoolPref:@"dw_legacy_gesture"];
}


/* * Feed (legacy gesture) * */

%hook IGFeedPhotoView
- (void)didMoveToSuperview {
    %orig;
    if (!sciLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender && sender.state != UIGestureRecognizerStateBegan) return;

    IGPhoto *photo;
    if ([self.delegate isKindOfClass:%c(IGFeedItemPhotoCell)]) {
        IGFeedItemPhotoCellConfiguration *_configuration = MSHookIvar<IGFeedItemPhotoCellConfiguration *>(self.delegate, "_configuration");
        if (!_configuration) return;
        photo = MSHookIvar<IGPhoto *>(_configuration, "_photo");
    } else if ([self.delegate isKindOfClass:%c(IGFeedItemPagePhotoCell)]) {
        IGFeedItemPagePhotoCell *pagePhotoCell = self.delegate;
        photo = pagePhotoCell.pagePhotoPost.photo;
    }

    NSURL *photoUrl = [SCIUtils getPhotoUrl:photo];
    if (!photoUrl) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract photo url from post")]; return; }

    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:photoUrl
                                 fileExtension:[[photoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end

%hook IGModernFeedVideoCell.IGModernFeedVideoCell
- (void)didMoveToSuperview {
    %orig;
    if (!sciLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender && sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:[self mediaCellFeedItem]];
    if (!videoUrl) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract video url from post")]; return; }

    initDownloaders();
    [videoDownloadDelegate downloadFileWithURL:videoUrl
                                 fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end


/* * Stories (legacy gesture) * */

%hook IGStoryPhotoView
- (void)didMoveToSuperview {
    %orig;
    if (!sciLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *photoUrl = [SCIUtils getPhotoUrlForMedia:[self item]];
    if (!photoUrl) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract photo url from story")]; return; }

    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:photoUrl
                                 fileExtension:[[photoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end

%hook IGStoryModernVideoView
- (void)didMoveToSuperview {
    %orig;
    if (!sciLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:self.item];
    if (!videoUrl) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract video url from story")]; return; }

    initDownloaders();
    [videoDownloadDelegate downloadFileWithURL:videoUrl
                                 fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                      hudLabel:nil];
}
%end

%hook IGStoryVideoView

- (void)didMoveToSuperview {
	%orig;
	if (!sciLegacyGestureEnabled()) return;
	[self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
	if (sender.state != UIGestureRecognizerStateBegan) return;
	NSURL *videoUrl = nil;
	id item = nil;
	if ([self respondsToSelector:@selector(item)]) {
		item = [self item];
	}
	if (item) {
		videoUrl = [SCIUtils getVideoUrlForMedia:item];
	}
	if (!videoUrl) {
		id provider = nil;
		if ([self respondsToSelector:@selector(videoURLProvider)]) {
			provider = [self videoURLProvider];
		}
		if (provider) {
			videoUrl = [SCIUtils getVideoUrlForMedia:provider];
		}
	}
	if (!videoUrl) {
		id parentVC = [SCIUtils nearestViewControllerForView:self];
		if (!parentVC || ![parentVC isKindOfClass:%c(IGDirectVisualMessageViewerController)]) return;
		IGDirectVisualMessageViewerViewModeAwareDataSource *_dataSource = MSHookIvar<IGDirectVisualMessageViewerViewModeAwareDataSource *>(parentVC, "_dataSource");
		if (!_dataSource) return;
		IGDirectVisualMessage *_currentMessage = MSHookIvar<IGDirectVisualMessage *>(_dataSource, "_currentMessage");
		if (!_currentMessage) return;
		IGVideo *rawVideo = _currentMessage.rawVideo;
		if (!rawVideo) return;
		videoUrl = [SCIUtils getVideoUrl:rawVideo];
	}
	if (!videoUrl) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract video url from story")];
		return;
	}
	initDownloaders();
	[videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:[[videoUrl lastPathComponent] pathExtension] hudLabel:nil];
}
%end


/* * Reels (legacy gesture) * */

%hook IGSundialViewerPhotoView
- (void)didMoveToSuperview {
    %orig;
    if (!sciLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        IGPhoto *_photo = MSHookIvar<IGPhoto *>(self, "_photo");
        if (!_photo) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not access reel photo")]; return; }

        NSURL *photoUrl = [SCIUtils getPhotoUrl:_photo];
        if (!photoUrl) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract photo url from reel")]; return; }

        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:photoUrl
                                     fileExtension:[[photoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Reel photo download error: %@", exception);
    }
}
%end

%hook IGSundialViewerVideoCell
- (void)didMoveToSuperview {
    %orig;
    if (!sciLegacyGestureEnabled()) return;
    [self addLongPressGestureRecognizer];
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        // Runtime ivar scan: the exact name varies across IG releases.
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList([self class], &ivarCount);
        Class mediaClass = NSClassFromString(@"IGMedia");
        IGMedia *media = nil;
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char *name = ivar_getName(ivars[i]);
            if (!name) continue;
            NSString *lower = [[NSString stringWithUTF8String:name] lowercaseString];
            if ([lower containsString:@"video"] || [lower containsString:@"media"] || [lower containsString:@"item"]) {
                id val = object_getIvar(self, ivars[i]);
                if (val && mediaClass && [val isKindOfClass:mediaClass]) { media = val; break; }
            }
        }
        if (ivars) free(ivars);

        if (!media) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not access reel media")]; return; }

        NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:media];
        if (!videoUrl) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract video url from reel")]; return; }

        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Reel download error: %@", exception);
    }
}
%end


/* * Profile pictures * */

// Get profile info by walking up to IGProfileViewController
static NSString *sciProfileCaption(UIView *view) {
    Class profileCls = NSClassFromString(@"IGProfileViewController");
    Class userCls = NSClassFromString(@"IGUser");
    UIResponder *r = view;
    while (r) {
        if (profileCls && [r isKindOfClass:profileCls]) {
            id user = nil;
            for (NSString *key in @[@"user", @"userGQL", @"profileUser"]) {
                @try { user = [(UIViewController *)r valueForKey:key]; } @catch (__unused id e) {}
                if (user) break;
            }
            if (!user && userCls) {
                unsigned int cnt = 0;
                Ivar *ivars = class_copyIvarList([r class], &cnt);
                for (unsigned int i = 0; i < cnt; i++) {
                    id v = object_getIvar(r, ivars[i]);
                    if (v && [v isKindOfClass:userCls]) { user = v; break; }
                }
                if (ivars) free(ivars);
            }
            if (user) {
                NSString *name = nil, *username = nil, *bio = nil;
                @try { username = [user valueForKey:@"username"]; } @catch (__unused id e) {}
                @try { name = [user valueForKey:@"fullName"]; } @catch (__unused id e) {}
                if (!name) @try { name = [user valueForKey:@"name"]; } @catch (__unused id e) {}
                @try { bio = [user valueForKey:@"biography"]; } @catch (__unused id e) {}

                NSMutableString *caption = [NSMutableString string];
                if (name.length) [caption appendString:name];
                if (username.length) {
                    if (caption.length) [caption appendString:@"\n"];
                    [caption appendFormat:@"@%@", username];
                }
                if (bio.length) {
                    if (caption.length) [caption appendString:@"\n\n"];
                    [caption appendString:bio];
                }
                return caption.length ? caption : nil;
            }
        }
        r = [r nextResponder];
    }
    return nil;
}

// Profile photo zoom — intercepts IG's profile pic long press
%hook IGProfilePhotoCoinFlipUI.IGProfilePhotoCoinFlipView

- (void)viewLongPressedWithGesture:(UILongPressGestureRecognizer *)gesture {
    if (![SCIUtils getBoolPref:@"zoom_profile_photo"]) { %orig; return; }
    if (gesture.state != UIGestureRecognizerStateBegan) { %orig; return; }

    // Find the IGProfilePictureImageView inside us
    UIView *source = gesture.view;
    NSMutableArray *q = [NSMutableArray arrayWithObject:source];
    int scanned = 0;
    while (q.count && scanned < 30) {
        UIView *cur = q.firstObject; [q removeObjectAtIndex:0]; scanned++;
        if ([cur isKindOfClass:NSClassFromString(@"IGProfilePictureImageView")]) {
            IGImageView *imgView = MSHookIvar<IGImageView *>(cur, "_imageView");
            if (imgView) {
                IGImageSpecifier *spec = imgView.imageSpecifier;
                NSURL *url = spec ? spec.url : nil;
                if (url) {
                    NSString *caption = sciProfileCaption(cur);
                    [SCIMediaViewer showWithVideoURL:nil photoURL:url caption:caption];
                    return;
                }
            }
        }
        for (UIView *s in cur.subviews) [q addObject:s];
    }

    %orig;
}

%end


%hook IGProfilePictureImageView
- (void)didMoveToSuperview {
    %orig;
    if ([SCIUtils getBoolPref:@"save_profile"] || [SCIUtils getBoolPref:@"zoom_profile_photo"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    IGImageView *_imageView = MSHookIvar<IGImageView *>(self, "_imageView");
    if (!_imageView) return;

    IGImageSpecifier *imageSpecifier = _imageView.imageSpecifier;
    if (!imageSpecifier) return;

    NSURL *imageUrl = imageSpecifier.url;
    if (!imageUrl) return;

    // Zoom: open in full-screen viewer with profile info
    if ([SCIUtils getBoolPref:@"zoom_profile_photo"]) {
        NSString *caption = sciProfileCaption(self);
        [SCIMediaViewer showWithVideoURL:nil photoURL:imageUrl caption:caption];
        return;
    }

    // Legacy: direct download
    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:imageUrl
                                 fileExtension:[[imageUrl lastPathComponent] pathExtension]
                                      hudLabel:@"Loading"];
}
%end
