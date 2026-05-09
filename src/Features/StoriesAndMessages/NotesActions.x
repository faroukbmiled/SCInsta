// Notes actions — copy text, download GIF/audio from notes long-press menu.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../UI/SCIDownloadMenu.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "SCIDirectUserResolver.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static SCIGallerySaveMetadata *sciNotesMetadataForNote(id note) {
    SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
    md.source = (int16_t)SCIGallerySourceNotes;
    if (!note) return md;
    @try {
        id uf = [note valueForKey:@"userFields"];
        md.sourceUsername = sciDirectUserResolverUsernameFromUser(uf);
        md.sourceUserPK = sciDirectUserResolverPKFromUser(uf);
        md.sourceProfileURLString = sciDirectUserResolverProfilePicURLStringFromUser(uf);
    } @catch (__unused id e) {}
    md.sourceMediaPK = sciDirectUserResolverPKFromUser(note);
    return md;
}

// Find the note model matching a username from visible tray cells
static id sciFindNoteForUser(UIView *root, NSString *username) {
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    int scanned = 0;
    while (q.count && scanned < 500) {
        UIView *cur = q.firstObject; [q removeObjectAtIndex:0]; scanned++;
        NSString *cls = NSStringFromClass([cur class]);
        if (![cls containsString:@"NotesTray"] && ![cls containsString:@"NotesUser"]) {
            for (UIView *s in cur.subviews) [q addObject:s];
            continue;
        }
        unsigned int cnt = 0;
        Ivar *ivars = class_copyIvarList([cur class], &cnt);
        for (unsigned int i = 0; i < cnt; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            @try {
                id val = object_getIvar(cur, ivars[i]);
                if (!val || ![val respondsToSelector:NSSelectorFromString(@"note")]) continue;
                id note = [val valueForKey:@"note"];
                if (!note || ![note respondsToSelector:@selector(text)]) continue;
                NSString *noteUser = nil;
                @try {
                    id uf = [note valueForKey:@"userFields"];
                    if ([uf respondsToSelector:NSSelectorFromString(@"username")])
                        noteUser = [uf valueForKey:@"username"];
                } @catch (__unused id e) {}
                if (!username || [noteUser isEqualToString:username])
                    { free(ivars); return note; }
            } @catch (__unused id e) {}
        }
        if (ivars) free(ivars);
        for (UIView *s in cur.subviews) [q addObject:s];
    }
    return nil;
}

// Find the cell view model for a specific note, return the cell view
static UIView *sciFindCellForNote(UIView *root, id targetNote) {
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    int scanned = 0;
    while (q.count && scanned < 300) {
        UIView *cur = q.firstObject; [q removeObjectAtIndex:0]; scanned++;
        if (![NSStringFromClass([cur class]) containsString:@"Notes"]) {
            for (UIView *s in cur.subviews) [q addObject:s];
            continue;
        }
        Ivar vmIvar = class_getInstanceVariable([cur class], "viewModel");
        if (!vmIvar) vmIvar = class_getInstanceVariable([cur class], "_viewModel");
        if (!vmIvar) { for (UIView *s in cur.subviews) [q addObject:s]; continue; }
        id vm = object_getIvar(cur, vmIvar);
        if (!vm || ![vm respondsToSelector:NSSelectorFromString(@"note")]) {
            for (UIView *s in cur.subviews) [q addObject:s]; continue;
        }
        if ([vm valueForKey:@"note"] == targetNote) return cur;
        for (UIView *s in cur.subviews) [q addObject:s];
    }
    return nil;
}

// Get GIF image from a cell's IGGIFView only
static UIImage *sciGIFImageFromCell(UIView *cell) {
    if (!cell) return nil;
    NSMutableArray *q = [NSMutableArray arrayWithObject:cell];
    int s = 0;
    while (q.count && s < 100) {
        UIView *cur = q.firstObject; [q removeObjectAtIndex:0]; s++;
        // Only match IGGIFView — not profile pics or other image views
        if ([NSStringFromClass([cur class]) containsString:@"GIFView"]) {
            if ([cur isKindOfClass:[UIImageView class]]) {
                UIImage *img = [(UIImageView *)cur image];
                if (img && img.size.width > 20) return img;
            }
            // Check subviews of GIFView for the actual image view
            for (UIView *sub in cur.subviews) {
                if ([sub isKindOfClass:[UIImageView class]]) {
                    UIImage *img = [(UIImageView *)sub image];
                    if (img && img.size.width > 20) return img;
                }
            }
        }
        for (UIView *sub in cur.subviews) [q addObject:sub];
    }
    return nil;
}

// Audio track from the note cell's view model. 426 added launcherSet.
static id sciAudioTrackFromCell(UIView *cell) {
    if (!cell) return nil;
    Ivar vmIvar = class_getInstanceVariable([cell class], "viewModel");
    if (!vmIvar) vmIvar = class_getInstanceVariable([cell class], "_viewModel");
    if (!vmIvar) return nil;
    id vm = object_getIvar(cell, vmIvar);
    if (!vm) return nil;

    SEL audioSel2 = NSSelectorFromString(@"audioTrackWithUserMap:launcherSet:");
    SEL audioSel1 = NSSelectorFromString(@"audioTrackWithUserMap:");
    @try {
        if ([vm respondsToSelector:audioSel2]) {
            id session = [SCIUtils activeUserSession];
            id launcher = nil;
            @try { launcher = session ? [session valueForKey:@"launcherSet"] : nil; } @catch (__unused id e) {}
            return ((id(*)(id,SEL,id,id))objc_msgSend)(vm, audioSel2, nil, launcher);
        }
        if ([vm respondsToSelector:audioSel1]) {
            return ((id(*)(id,SEL,id))objc_msgSend)(vm, audioSel1, nil);
        }
    } @catch (__unused id e) {}
    return nil;
}

// Pull URL from the track's IGAsyncTask — sync if cached, else async.
static void sciResolveAudioURL(id track, void (^completion)(NSURL *)) {
    if (!track || !completion) { if (completion) completion(nil); return; }
    id task = nil;
    @try {
        if ([track respondsToSelector:@selector(audioFileURLTask)])
            task = ((id(*)(id,SEL))objc_msgSend)(track, @selector(audioFileURLTask));
    } @catch (__unused id e) {}
    if (!task) { completion(nil); return; }

    @try {
        id res = [task valueForKey:@"result"];
        if ([res isKindOfClass:[NSURL class]]) { completion(res); return; }
    } @catch (__unused id e) {}

    SEL onSuccess = NSSelectorFromString(@"onSuccess:");
    if (![task respondsToSelector:onSuccess]) { completion(nil); return; }
    void (^cb)(id) = ^(id resolved) {
        NSURL *u = [resolved isKindOfClass:[NSURL class]] ? resolved : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(u); });
    };
    @try {
        ((void(*)(id,SEL,id))objc_msgSend)(task, onSuccess, cb);
    } @catch (__unused id e) { completion(nil); }
}

static void (*orig_present)(UIViewController *, SEL, UIViewController *, BOOL, id);
static void hook_present(UIViewController *self, SEL _cmd, UIViewController *vc, BOOL animated, id completion) {
    if (![NSStringFromClass([vc class]) isEqualToString:@"IGActionSheetController"]) {
        orig_present(self, _cmd, vc, animated, completion);
        return;
    }

    Ivar actIvar = class_getInstanceVariable([vc class], "_actions");
    if (!actIvar) { orig_present(self, _cmd, vc, animated, completion); return; }

    NSArray *actions = object_getIvar(vc, actIvar);
    BOOL isNotes = NO;
    for (id a in actions) {
        if (![a respondsToSelector:@selector(title)]) continue;
        NSString *t = [a valueForKey:@"title"];
        if ([t isKindOfClass:[NSString class]] && [t containsString:@"Mute notes"])
            { isNotes = YES; break; }
    }

    if (!isNotes) { orig_present(self, _cmd, vc, animated, completion); return; }

    BOOL copyOnHold = [SCIUtils getBoolPref:@"note_copy_on_hold"];
    BOOL noteActions = [SCIUtils getBoolPref:@"note_actions"];

    if (!copyOnHold && !noteActions) {
        orig_present(self, _cmd, vc, animated, completion);
        return;
    }

    // Copy text immediately on long press, then let the menu open normally
    if (copyOnHold) {
        id note = sciFindNoteForUser(self.view, nil);
        NSString *text = nil;
        @try { text = [note valueForKey:@"text"]; } @catch (__unused id e) {}
        if (text.length) {
            [[UIPasteboard generalPasteboard] setString:text];
            SCINotifySuccess(SCI_NOTIF_COPY_NOTE, SCILocalized(@"Note text copied"), nil);
        }
    }

    Class actionCls = NSClassFromString(@"IGActionSheetControllerAction");
    SEL initSel = @selector(initWithTitle:subtitle:style:handler:accessibilityIdentifier:accessibilityLabel:);
    if (!actionCls || ![actionCls instancesRespondToSelector:initSel]) {
        orig_present(self, _cmd, vc, animated, completion);
        return;
    }

    __weak UIViewController *weakSelf = self;
    __weak UIViewController *weakVC = vc;
    void (^handler)(void) = ^{
        UIViewController *sheet = weakVC;
        UIViewController *presenter = weakSelf;
        if (!presenter) return;

        // Read username from the visible sheet
        NSString *user = nil;
        if (sheet && sheet.isViewLoaded) {
            NSMutableArray *lq = [NSMutableArray arrayWithObject:sheet.view];
            int ls = 0;
            while (lq.count && ls < 100) {
                UIView *cur = lq.firstObject; [lq removeObjectAtIndex:0]; ls++;
                if ([cur isKindOfClass:[UILabel class]]) {
                    NSString *t = [(UILabel *)cur text];
                    if (t.length > 0 && t.length < 30
                        && ![t isEqualToString:@"Cancel"]
                        && ![t isEqualToString:@"Report"]
                        && ![t isEqualToString:@"Mute notes"]
                        && ![t isEqualToString:@"View profile"]
                        && ![t isEqualToString:@"Note actions"]) {
                        user = t; break;
                    }
                }
                for (UIView *s in cur.subviews) [lq addObject:s];
            }
        }

        id note = sciFindNoteForUser(presenter.view, user);
        if (!note) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Note not found")]; return; }

        NSString *text = nil;
        @try { text = [note valueForKey:@"text"]; } @catch (__unused id e) {}
        UIView *cell = sciFindCellForNote(presenter.view, note);

        // Build submenu
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:nil message:nil
            preferredStyle:UIAlertControllerStyleActionSheet];

        if (text.length) {
            [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy text")
                style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                [[UIPasteboard generalPasteboard] setString:text];
                SCINotifySuccess(SCI_NOTIF_COPY_NOTE, SCILocalized(@"Note text copied"), nil);
            }]];
        }

        SCIGallerySaveMetadata *noteMD = sciNotesMetadataForNote(note);

        UIImage *gifImage = sciGIFImageFromCell(cell);
        if (gifImage) {
            [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save GIF")
                style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                NSData *data = UIImagePNGRepresentation(gifImage);
                if (!data) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Failed to encode GIF")]; return; }
                NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"note_gif_%@.png", [[NSUUID UUID] UUIDString]]];
                [data writeToFile:path atomically:YES];
                NSURL *fileURL = [NSURL fileURLWithPath:path];
                [SCIMediaActions setCurrentFilenameStem:
                    [SCIMediaActions filenameStemForUsername:noteMD.sourceUsername contextLabel:@"note-gif"]];
                [SCIDownloadMenu presentForURL:fileURL
                                          mode:SCIDownloadMenuModeLocalFile
                                 fileExtension:@"png"
                                      hudLabel:SCILocalized(@"Save GIF")
                                      metadata:noteMD
                                       isAudio:NO
                                        fromVC:nil];
            }]];
        }

        id audioTrack = sciAudioTrackFromCell(cell);
        if (audioTrack) {
            [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Download audio")
                style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                sciResolveAudioURL(audioTrack, ^(NSURL *audioURL) {
                    if (!audioURL) {
                        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Audio URL not available")];
                        return;
                    }
                    NSString *ext = [[audioURL.path pathExtension] lowercaseString];
                    if (!SCIGalleryExtensionIsAudio(ext)) ext = @"m4a";
                    [SCIMediaActions setCurrentFilenameStem:
                        [SCIMediaActions filenameStemForUsername:noteMD.sourceUsername contextLabel:@"note-audio"]];
                    [SCIDownloadMenu presentForURL:audioURL
                                              mode:SCIDownloadMenuModeRemoteURL
                                     fileExtension:ext
                                          hudLabel:SCILocalized(@"Download audio")
                                          metadata:noteMD
                                           isAudio:YES
                                            fromVC:nil];
                });
            }]];
        }

        [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
            style:UIAlertActionStyleCancel handler:nil]];

        [sheet dismissViewControllerAnimated:YES completion:^{
            [presenter presentViewController:alert animated:YES completion:nil];
        }];
    };

    typedef id (*InitFn)(id, SEL, id, id, NSInteger, id, id, id);
    id noteAction = ((InitFn)objc_msgSend)([actionCls alloc], initSel,
        SCILocalized(@"Note actions"), nil, (NSInteger)0, handler, nil, nil);

    if (noteActions && noteAction) {
        NSMutableArray *newActions = [actions mutableCopy];
        [newActions insertObject:noteAction atIndex:0];
        object_setIvar(vc, actIvar, [newActions copy]);
    }

    orig_present(self, _cmd, vc, animated, completion);
}

%ctor {
    MSHookMessageEx([UIViewController class],
        @selector(presentViewController:animated:completion:),
        (IMP)hook_present, (IMP *)&orig_present);
}
