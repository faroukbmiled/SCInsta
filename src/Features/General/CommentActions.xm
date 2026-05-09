// Comment long-press menu extras: copy text + GIF download/link submenu.
#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../UI/SCIIcon.h"
#import "../../UI/SCIDownloadMenu.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../StoriesAndMessages/SCIDirectUserResolver.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static DownloadAction sciGifDownloadAction(void) {
    NSString *method = [SCIUtils getStringPref:@"dw_save_action"];
    return [method isEqualToString:@"photos"] ? saveToPhotos : share;
}

static void sciFillGifMetadataFromComment(SCIGallerySaveMetadata *md, id comment) {
    if (!md || !comment) return;
    @try {
        id user = nil;
        for (NSString *key in @[@"user", @"author", @"commenter"]) {
            @try { user = [comment valueForKey:key]; } @catch (__unused id e) {}
            if (user) break;
        }
        md.sourceUsername = sciDirectUserResolverUsernameFromUser(user);
        md.sourceUserPK = sciDirectUserResolverPKFromUser(user);
        md.sourceProfileURLString = sciDirectUserResolverProfilePicURLStringFromUser(user);
    } @catch (__unused id e) {}
}

static id (*orig_commentCtxMenu)(id, SEL, id, id, CGPoint);
static id new_commentCtxMenu(id self, SEL _cmd, id cv, id indexPath, CGPoint point) {
    UIContextMenuConfiguration *config = orig_commentCtxMenu(self, _cmd, cv, indexPath, point);
    if (!config) return config;

    Ivar commentIvar = class_getInstanceVariable([self class], "_longPressedComment");
    id comment = commentIvar ? object_getIvar(self, commentIvar) : nil;
    if (!comment) return config;

    NSString *text = nil;
    @try { text = ((id(*)(id,SEL))objc_msgSend)(comment, @selector(text)); } @catch (__unused id e) {}

    NSString *gifId = nil;
    @try {
        SEL sel = NSSelectorFromString(@"gifMediaId");
        if ([comment respondsToSelector:sel])
            gifId = ((id(*)(id,SEL))objc_msgSend)(comment, sel);
    } @catch (__unused id e) {}

    NSString *gifURL = nil;
    if (gifId.length) {
        Ivar attIvar = class_getInstanceVariable([comment class], "_commentAttachment");
        id att = attIvar ? object_getIvar(comment, attIvar) : nil;
        if (att) {
            Ivar urlIvar = class_getInstanceVariable([att class], "_image_imageURL");
            if (urlIvar) {
                id url = object_getIvar(att, urlIvar);
                if ([url isKindOfClass:[NSString class]]) gifURL = url;
                else if ([url isKindOfClass:[NSURL class]]) gifURL = [(NSURL *)url absoluteString];
            }
        }
    }

    BOOL hasText = text.length > 0;
    BOOL hasGif = gifURL.length > 0;
    if (!hasText && !hasGif) return config;

    id origProvider = [config valueForKey:@"actionProvider"];
    id<NSCopying> origIdent = [config valueForKey:@"identifier"];
    UIContextMenuContentPreviewProvider origPreview = [config valueForKey:@"previewProvider"];

    UIContextMenuActionProvider wrapped = ^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIMenu *base = origProvider ? ((UIMenu *(^)(NSArray *))origProvider)(suggested)
                                    : [UIMenu menuWithChildren:suggested];
        NSMutableArray *extra = [NSMutableArray array];

        if (hasText && [SCIUtils getBoolPref:@"copy_comment"]) {
            [extra addObject:[UIAction actionWithTitle:SCILocalized(@"Copy")
                                                 image:[SCIIcon imageNamed:@"doc.on.doc"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *_) {
                [UIPasteboard generalPasteboard].string = text;
                SCINotifySuccess(SCI_NOTIF_COPY_COMMENT, SCILocalized(@"Comment copied"), nil);
            }]];
        }

        if (hasGif && [SCIUtils getBoolPref:@"download_gif_comment"]) {
            UIAction *download = [UIAction actionWithTitle:SCILocalized(@"Download GIF")
                                                     image:[SCIIcon imageNamed:@"arrow.down.circle"]
                                                identifier:nil
                                                   handler:^(__kindof UIAction *_) {
                NSURL *url = [NSURL URLWithString:gifURL];
                if (!url) return;
                SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
                md.source = (int16_t)SCIGallerySourceComments;
                if (gifId.length) md.sourceMediaPK = gifId;
                md.sourceMediaURLString = gifURL;
                sciFillGifMetadataFromComment(md, comment);
                [SCIMediaActions setCurrentFilenameStem:
                    [SCIMediaActions filenameStemForUsername:md.sourceUsername contextLabel:@"comment-gif"]];

                if ([SCIUtils getBoolPref:@"sci_gallery_enabled"]) {
                    [SCIDownloadMenu presentForURL:url
                                              mode:SCIDownloadMenuModeRemoteURL
                                     fileExtension:@"gif"
                                          hudLabel:SCILocalized(@"Download GIF")
                                          metadata:md
                                           isAudio:NO
                                            fromVC:nil];
                } else {
                    [SCIDownloadMenu downloadURL:url
                                   fileExtension:@"gif"
                                        hudLabel:nil
                                        metadata:md
                                     forceTarget:(sciGifDownloadAction() == saveToPhotos ? 0 : 2)];
                }
            }];
            NSString *pageURL = gifId.length ? [NSString stringWithFormat:@"https://giphy.com/gifs/%@", gifId] : nil;
            UIAction *copy = [UIAction actionWithTitle:SCILocalized(@"Copy GIF link")
                                                 image:[SCIIcon imageNamed:@"link"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *_) {
                if (!pageURL.length) return;
                [UIPasteboard generalPasteboard].string = pageURL;
                SCINotifySuccess(SCI_NOTIF_COPY_GIF, SCILocalized(@"GIF link copied"), nil);
            }];
            [extra addObject:[UIMenu menuWithTitle:@"GIF"
                                             image:[SCIIcon imageNamed:@"photo"]
                                        identifier:nil
                                           options:0
                                          children:@[download, copy]]];
        }

        if (!extra.count) return base;
        NSMutableArray *kids = [base.children mutableCopy] ?: [NSMutableArray array];
        NSUInteger insertIdx = kids.count > 0 ? kids.count - 1 : 0;
        UIMenu *ourMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil
                                        options:UIMenuOptionsDisplayInline children:extra];
        [kids insertObject:ourMenu atIndex:insertIdx];
        return [base menuByReplacingChildren:kids];
    };

    return [UIContextMenuConfiguration configurationWithIdentifier:origIdent
                                                    previewProvider:origPreview
                                                     actionProvider:wrapped];
}

__attribute__((constructor)) static void _commentActionsInit(void) {
    Class cls = NSClassFromString(@"IGCommentThreadViewController");
    if (!cls) return;
    SEL s = @selector(collectionView:contextMenuConfigurationForItemAtIndexPath:point:);
    if (class_getInstanceMethod(cls, s))
        MSHookMessageEx(cls, s, (IMP)new_commentCtxMenu, (IMP *)&orig_commentCtxMenu);
}
