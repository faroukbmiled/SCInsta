#import "OverlayHelpers.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../Downloader/Download.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "SCIDirectUserResolver.h"

// MARK: - DM sender metadata

static NSString *sciStringFromAny(id v) {
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return nil;
}

static id sciActiveUserSession(void) {
    @try {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                @try {
                    id session = [window valueForKey:@"userSession"];
                    if (session) return session;
                } @catch (__unused id e) {}
            }
        }
    } @catch (__unused id e) {}
    return nil;
}

// Resolves to IGUser via the shared cache, with session.user as the
// self-authored fallback.
static id sciResolveUserForPK(NSString *pk) {
    if (!pk.length) return nil;
    id user = sciDirectUserResolverUserForPK(pk);
    if (user) return user;

    id session = sciActiveUserSession();
    if (!session) return nil;
    @try {
        id selfUser = [session valueForKey:@"user"];
        NSString *selfPK = sciDirectUserResolverPKFromUser(selfUser);
        if (selfPK && [selfPK isEqualToString:pk]) return selfUser;
    } @catch (__unused id e) {}
    return nil;
}

// IGDevirtualizedValueObject resolves its accessors via forwardInvocation —
// respondsToSelector: lies but methodSignatureForSelector: tells the truth.
static id sciCall0(id obj, SEL sel) {
    if (!obj || !sel) return nil;
    @try {
        if (![obj respondsToSelector:sel] && ![obj methodSignatureForSelector:sel]) return nil;
        typedef id (*Fn)(id, SEL);
        return ((Fn)objc_msgSend)(obj, sel);
    } @catch (__unused id e) { return nil; }
}

// IGDirectVisualMessage._message → IGDirectUIMessage.metadata.senderPk.
// IGDirectAudioMessageViewModel.messageMetadata.senderPk. Both funnel here.
static NSString *sciSenderPKFromMessageObject(id msg) {
    if (!msg) return nil;
    Ivar inner = class_getInstanceVariable([msg class], "_message");
    if (inner) {
        id wrapped = object_getIvar(msg, inner);
        if (wrapped) msg = wrapped;
    }
    for (NSString *sel in @[@"metadata", @"messageMetadata"]) {
        id mdObj = sciCall0(msg, NSSelectorFromString(sel));
        if (!mdObj) continue;
        NSString *pk = sciStringFromAny(sciCall0(mdObj, @selector(senderPk)));
        if (pk.length) return pk;
    }
    return sciStringFromAny(sciCall0(msg, @selector(senderPk)));
}

SCIGallerySaveMetadata *sciDMMetadataFromMessage(id msg) {
    SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
    md.source = (int16_t)SCIGallerySourceDMs;
    if (!msg) return md;

    NSString *senderPK = sciSenderPKFromMessageObject(msg);
    if (!senderPK.length) return md;

    md.sourceUserPK = senderPK;
    id user = sciResolveUserForPK(senderPK);
    if (user) {
        md.sourceUsername = sciDirectUserResolverUsernameFromUser(user);
        md.sourceProfileURLString = sciDirectUserResolverProfilePicURLStringFromUser(user);
    }
    return md;
}

SCIGallerySaveMetadata *sciDMMetadataForVC(UIViewController *dmVC) {
    SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
    md.source = (int16_t)SCIGallerySourceDMs;
    if (!dmVC) return md;

    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    return sciDMMetadataFromMessage(msg);
}

// MARK: - Context detection

BOOL sciOverlayIsInDMContext(UIView *overlay) {
    Class dmCls = NSClassFromString(@"IGDirectVisualMessageViewerController");
    if (!dmCls) return NO;

    UIResponder *r = overlay.nextResponder;
    while (r) {
        if ([r isKindOfClass:dmCls]) return YES;
        r = r.nextResponder;
    }

    // Fallback: _gestureDelegate ivar is the DM VC in DM contexts.
    static Ivar gdIvar = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"IGStoryFullscreenOverlayView");
        if (c) gdIvar = class_getInstanceVariable(c, "_gestureDelegate");
    });
    if (gdIvar) {
        id d = object_getIvar(overlay, gdIvar);
        if (d && [d isKindOfClass:dmCls]) return YES;
    }
    return NO;
}

UIView *sciFindOverlayInView(UIView *root) {
    Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayCls || !root) return nil;
    if ([root isKindOfClass:overlayCls]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = sciFindOverlayInView(sub);
        if (found) return found;
    }
    return nil;
}

// MARK: - DM media URL

NSURL *sciDMMediaURL(UIViewController *dmVC, BOOL *outIsVideo) {
    if (!dmVC) return nil;

    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    if (!msg) return nil;

    Ivar vmiIvar = class_getInstanceVariable([msg class], "_visualMediaInfo");
    id vmi = vmiIvar ? object_getIvar(msg, vmiIvar) : nil;
    Ivar mIvar = vmi ? class_getInstanceVariable([vmi class], "_media") : nil;
    id visMedia = mIvar ? object_getIvar(vmi, mIvar) : nil;
    if (!visMedia) return nil;

    @try {
        id rawVideo = [msg valueForKey:@"rawVideo"];
        if (rawVideo) {
            NSURL *url = [SCIUtils getVideoUrl:rawVideo];
            if (url) { if (outIsVideo) *outIsVideo = YES; return url; }
        }
    } @catch (__unused NSException *e) {}

    Ivar pi = class_getInstanceVariable([visMedia class], "_photo_photo");
    id photo = pi ? object_getIvar(visMedia, pi) : nil;
    if (photo) {
        if (outIsVideo) *outIsVideo = NO;
        return [SCIUtils getPhotoUrl:photo];
    }
    return nil;
}

// MARK: - DM actions

// Strong refs so the delegate outlives the URLSession callbacks.
static SCIDownloadDelegate *sciDMShareDelegate = nil;
static SCIDownloadDelegate *sciDMDownloadDelegate = nil;

void sciDMExpandMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDMMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
    if (isVideo) [SCIMediaViewer showWithVideoURL:url photoURL:nil caption:nil];
    else         [SCIMediaViewer showWithVideoURL:nil photoURL:url caption:nil];
}

// Stamps `@sender_dm_<ts>` for Photos/share/gallery saves and returns the
// metadata so the gallery branch sees the same sender attribution.
static SCIGallerySaveMetadata *sciDMMetadataAndStem(UIViewController *dmVC) {
    SCIGallerySaveMetadata *md = sciDMMetadataForVC(dmVC);
    [SCIMediaActions setCurrentFilenameStem:
        [SCIMediaActions filenameStemForUsername:md.sourceUsername contextLabel:@"dm"]];
    return md;
}

void sciDMShareMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDMMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
    sciDMShareDelegate = [[SCIDownloadDelegate alloc] initWithAction:share showProgress:YES];
    sciDMShareDelegate.pendingGallerySaveMetadata = sciDMMetadataAndStem(dmVC);
    [sciDMShareDelegate downloadFileWithURL:url fileExtension:(isVideo ? @"mp4" : @"jpg") hudLabel:nil];
}

void sciDMDownloadMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDMMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
    sciDMDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:saveToPhotos showProgress:YES];
    sciDMDownloadDelegate.pendingGallerySaveMetadata = sciDMMetadataAndStem(dmVC);
    [sciDMDownloadDelegate downloadFileWithURL:url fileExtension:(isVideo ? @"mp4" : @"jpg") hudLabel:nil];
}

void sciDMDownloadMediaToGallery(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = sciDMMediaURL(dmVC, &isVideo);
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
    sciDMDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:saveToGallery showProgress:YES];
    sciDMDownloadDelegate.pendingGallerySaveMetadata = sciDMMetadataAndStem(dmVC);
    [sciDMDownloadDelegate downloadFileWithURL:url fileExtension:(isVideo ? @"mp4" : @"jpg") hudLabel:nil];
}

// Toggles dmVisualMsgsViewedButtonEnabled for ~1s so VisualMsgModifier lets
// the begin/end playback callbacks through.
void sciDMMarkCurrentAsViewed(UIViewController *dmVC) {
    if (!dmVC) return;

    BOOL wasEnabled = dmVisualMsgsViewedButtonEnabled;
    dmVisualMsgsViewedButtonEnabled = YES;

    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    Ivar erIvar = class_getInstanceVariable([dmVC class], "_eventResponders");
    NSArray *responders = erIvar ? object_getIvar(dmVC, erIvar) : nil;

    if (responders && msg) {
        for (id resp in responders) {
            SEL beginSel = @selector(visualMessageViewerController:didBeginPlaybackForVisualMessage:atIndex:);
            if ([resp respondsToSelector:beginSel]) {
                typedef void (*Fn)(id, SEL, id, id, NSInteger);
                ((Fn)objc_msgSend)(resp, beginSel, dmVC, msg, 0);
            }
            SEL endSel = @selector(visualMessageViewerController:didEndPlaybackForVisualMessage:atIndex:mediaCurrentTime:forNavType:);
            if ([resp respondsToSelector:endSel]) {
                typedef void (*Fn)(id, SEL, id, id, NSInteger, CGFloat, NSInteger);
                ((Fn)objc_msgSend)(resp, endSel, dmVC, msg, 0, 0.0, 0);
            }
        }
    }

    SEL dismissSel = NSSelectorFromString(@"_didTapHeaderViewDismissButton:");
    if ([dmVC respondsToSelector:dismissSel]) {
        ((void(*)(id,SEL,id))objc_msgSend)(dmVC, dismissSel, nil);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dmVisualMsgsViewedButtonEnabled = wasEnabled;
    });

    SCINotifySuccess(SCI_NOTIF_SEEN_DM, SCILocalized(@"Marked as viewed"), nil);
}

// MARK: - Settings shortcut

void sciOpenMessagesSettings(UIView *source) {
    UIWindow *win = source.window;
    if (!win) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
            if (win) break;
        }
    }
    if (!win) return;
    [SCIUtils showSettingsVC:win atTopLevelEntry:SCILocalized(@"Messages")];
}
