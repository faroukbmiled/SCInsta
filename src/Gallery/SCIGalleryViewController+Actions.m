// SCIGalleryViewController (Actions) — file actions, selection-mode bulk
// handlers, folder CRUD, and a few related helpers extracted from
// SCIGalleryViewController.m to keep the main file focused on layout.

#import "SCIGalleryViewController_Internal.h"
#import "SCIGalleryFile.h"
#import "SCIGalleryCoreDataStack.h"
#import "SCIGalleryListCollectionCell.h"
#import "SCIGalleryGridCell.h"
#import "SCIGalleryDeleteViewController.h"
#import "SCIGalleryOriginController.h"
#import "SCIAssetUtils.h"
#import "SCIGalleryShim.h"
#import "../Utils.h"
#import "../PhotoAlbum.h"
#import "../Downloader/Download.h"
#import <CoreData/CoreData.h>
#import <Photos/Photos.h>

static UIImage *SCIGalleryActionIcon(NSString *resourceName) {
    return [SCIAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
                                   pointSize:17.0];
}

@implementation SCIGalleryViewController (Actions)

- (void)showGalleryOpenFailureMessage:(NSString *)title actionIdentifier:(NSString *)actionIdentifier {
    [SCIUtils showToastForActionIdentifier:actionIdentifier duration:2.0
                             title:title
                          subtitle:SCILocalized(@"The original content may no longer exist.")
                      iconResource:@"error_filled"
                              tone:SCIFeedbackPillToneError];
}

- (void)dismissGalleryForOriginOpenWithCompletion:(void (^)(void))completion {
    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        if (completion) completion();
    }];
}

// Open natively in IG via NSUserActivity continueUserActivity (the same path
// PasteLinkFromSearch uses). Dismisses the gallery first so IG can replace
// the active view stack.
- (void)openOriginalPostForFile:(SCIGalleryFile *)file {
    if ([SCIGalleryOriginController openOriginalPostForGalleryFile:file]) {
        [self dismissGalleryForOriginOpenWithCompletion:nil];
    } else {
        [self showGalleryOpenFailureMessage:SCILocalized(@"Unable to open original post") actionIdentifier:kSCIFeedbackActionGalleryOpenOriginal];
    }
}

- (void)openProfileForFile:(SCIGalleryFile *)file {
    if ([SCIGalleryOriginController openProfileForGalleryFile:file]) {
        [self dismissGalleryForOriginOpenWithCompletion:nil];
    } else {
        [self showGalleryOpenFailureMessage:SCILocalized(@"Unable to open profile") actionIdentifier:kSCIFeedbackActionGalleryOpenProfile];
    }
}
- (void)animateSelectionModeTransition {
    for (NSIndexPath *indexPath in self.collectionView.indexPathsForVisibleItems) {
        SCIGalleryFile *file = [self galleryFileForCollectionIndexPath:indexPath];
        if (!file) {
            continue;
        }

        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
        BOOL selected = [self.selectedFileIDs containsObject:file.identifier];
        if ([cell isKindOfClass:[SCIGalleryListCollectionCell class]]) {
            [(SCIGalleryListCollectionCell *)cell setSelectionMode:self.selectionMode selected:selected animated:YES];
            [(SCIGalleryListCollectionCell *)cell setMoreActionsMenu:self.selectionMode ? nil : [self fileActionsMenuForFile:file]];
        } else if ([cell isKindOfClass:[SCIGalleryGridCell class]]) {
            [(SCIGalleryGridCell *)cell setSelectionMode:self.selectionMode selected:selected animated:YES];
        }
    }
}

- (NSArray<SCIGalleryFile *> *)selectedGalleryFiles {
    if (self.selectedFileIDs.count == 0) {
        return @[];
    }

    NSMutableArray<SCIGalleryFile *> *files = [NSMutableArray array];
    for (SCIGalleryFile *file in [self visibleGalleryFiles]) {
        if ([self.selectedFileIDs containsObject:file.identifier]) {
            [files addObject:file];
        }
    }
    return files;
}

- (void)enterSelectionMode {
    self.selectionMode = YES;
    [self.selectedFileIDs removeAllObjects];
    [self refreshNavigationItems];
    [self refreshBottomToolbarItems];
    [self animateSelectionModeTransition];
}

- (void)exitSelectionMode {
    self.selectionMode = NO;
    [self.selectedFileIDs removeAllObjects];
    [self refreshNavigationItems];
    [self refreshBottomToolbarItems];
    [self animateSelectionModeTransition];
}

- (void)toggleSelectionForFile:(SCIGalleryFile *)file {
    if (file.identifier.length == 0) {
        return;
    }
    if ([self.selectedFileIDs containsObject:file.identifier]) {
        [self.selectedFileIDs removeObject:file.identifier];
    } else {
        [self.selectedFileIDs addObject:file.identifier];
    }
    [self refreshNavigationItems];
    [self.collectionView reloadData];
}

- (void)selectAllVisibleFiles {
    NSArray<SCIGalleryFile *> *files = [self visibleGalleryFiles];
    if (files.count > 0 && self.selectedFileIDs.count == files.count) {
        [self.selectedFileIDs removeAllObjects];
    } else {
        [self.selectedFileIDs removeAllObjects];
        for (SCIGalleryFile *file in files) {
            if (file.identifier.length > 0) {
                [self.selectedFileIDs addObject:file.identifier];
            }
        }
    }
    self.navigationItem.rightBarButtonItem.title = (self.selectedFileIDs.count == files.count && files.count > 0) ? SCILocalized(@"Deselect All") : SCILocalized(@"Select All");
    [self.collectionView reloadData];
}

- (void)shareSelectedFiles {
    NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) {
        return;
    }

    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:files.count];
    for (SCIGalleryFile *file in files) {
        [urls addObject:file.fileURL];
    }

    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    [SCIPhotoAlbum armWatcherIfEnabled];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)saveSelectedFilesToPhotos {
    NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) return;
    [self sciSaveGalleryFilesToPhotos:files];
    [self exitSelectionMode];
}

// Sequential Photos write that honours save_to_ryukgram_album.
- (void)sciSaveGalleryFilesToPhotos:(NSArray<SCIGalleryFile *> *)files {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
            });
            return;
        }
        BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];
        SCIDownloadPillView *pill = [SCIDownloadPillView shared];
        NSString *ticket = [pill beginTicketWithTitle:SCILocalized(@"Saving...") onCancel:nil];

        __block NSUInteger saved = 0;
        __block NSUInteger idx = 0;
        __block void (^next)(void) = nil;
        next = ^{
            if (idx >= files.count) {
                NSString *destination = useAlbum ? SCILocalized(@"Saved to RyukGram") : SCILocalized(@"Saved to Photos");
                NSString *msg = files.count == 1 ? destination : [NSString stringWithFormat:SCILocalized(@"Saved %lu items"), (unsigned long)saved];
                [pill finishTicket:ticket successMessage:msg];
                next = nil;
                return;
            }
            SCIGalleryFile *file = files[idx++];
            [pill updateTicket:ticket progress:(float)idx / (float)files.count];
            void (^done)(BOOL, NSError *) = ^(BOOL ok, NSError *err) {
                if (ok) saved++;
                else NSLog(@"[RyukGram] Gallery → Photos save failed: %@", err);
                if (next) next();
            };
            NSURL *fileURL = file.fileURL;
            if (useAlbum) {
                // saveFileToAlbum uses shouldMoveFile=YES — copy first so
                // the gallery's source isn't emptied.
                NSURL *temp = [self sciCopyToTemp:fileURL];
                if (!temp) { done(NO, nil); return; }
                [SCIPhotoAlbum saveFileToAlbum:temp completion:done];
            } else {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    NSString *ext = fileURL.pathExtension.lowercaseString;
                    BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];
                    PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
                    PHAssetResourceCreationOptions *opts = [PHAssetResourceCreationOptions new];
                    opts.shouldMoveFile = NO;
                    [req addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto)
                                     fileURL:fileURL options:opts];
                    req.creationDate = [NSDate date];
                } completionHandler:done];
            }
        };
        next();
    }];
}

- (NSURL *)sciCopyToTemp:(NSURL *)src {
    if (!src) return nil;
    NSString *name = [NSString stringWithFormat:@"sci_gal_%@.%@", [[NSUUID UUID] UUIDString], src.pathExtension ?: @"bin"];
    NSURL *dst = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSError *err = nil;
    if (![[NSFileManager defaultManager] copyItemAtURL:src toURL:dst error:&err]) {
        NSLog(@"[RyukGram] Temp copy failed: %@", err);
        return nil;
    }
    return dst;
}

- (void)moveSelectedFiles {
    NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) {
        return;
    }
    [self presentMoveSheetForFiles:files];
}

- (void)toggleFavoriteForSelectedFiles {
    NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) {
        return;
    }

    BOOL shouldFavorite = NO;
    for (SCIGalleryFile *file in files) {
        if (!file.isFavorite) {
            shouldFavorite = YES;
            break;
        }
    }

    for (SCIGalleryFile *file in files) {
        file.isFavorite = shouldFavorite;
    }
    [[SCIGalleryCoreDataStack shared] saveContext];
    [self refetch];
}

- (void)deleteSelectedFiles {
    NSArray<SCIGalleryFile *> *files = [self selectedGalleryFiles];
    if (files.count == 0) {
        return;
    }

    NSString *message = [NSString stringWithFormat:SCILocalized(@"This will permanently remove %ld file%@ from the gallery."), (long)files.count, files.count == 1 ? @"" : @"s"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Delete Selected Files?")
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        NSError *firstError = nil;
        for (SCIGalleryFile *file in files) {
            NSError *removeError = nil;
            [file removeWithError:&removeError];
            if (!firstError && removeError) {
                firstError = removeError;
            }
        }
        if (firstError) {
            [SCIUtils showToastForActionIdentifier:kSCIFeedbackActionGalleryDeleteSelected duration:2.0
                                     title:SCILocalized(@"Failed to delete")
                                  subtitle:firstError.localizedDescription
                              iconResource:@"error_filled"
                                      tone:SCIFeedbackPillToneError];
            return;
        }
        [SCIUtils showToastForActionIdentifier:kSCIFeedbackActionGalleryDeleteSelected duration:1.5
                                         title:SCILocalized(@"Deleted selected files")
                                      subtitle:nil
                                  iconResource:@"circle_check_filled"
                                          tone:SCIFeedbackPillToneSuccess];
        [self exitSelectionMode];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (UIMenu *)fileActionsMenuForFile:(SCIGalleryFile *)file {
    __weak typeof(self) weakSelf = self;

    NSString *favTitle = file.isFavorite ? SCILocalized(@"Unfavorite") : SCILocalized(@"Favorite");
    UIImage *favImg = file.isFavorite
        ? SCIGalleryActionIcon(@"heart_filled")
        : SCIGalleryActionIcon(@"heart");

    UIAction *favoriteAction = [UIAction actionWithTitle:favTitle
                                                   image:favImg
                                              identifier:nil
                                                 handler:^(UIAction *a) {
        file.isFavorite = !file.isFavorite;
        [[SCIGalleryCoreDataStack shared] saveContext];
    }];

     UIImage *renameImg = SCIGalleryActionIcon(@"edit");
    UIAction *renameAction = [UIAction actionWithTitle:SCILocalized(@"Rename")
                                                 image:renameImg
                                            identifier:nil
                                               handler:^(UIAction *a) { [weakSelf renameFile:file]; }];

     UIImage *moveImg = SCIGalleryActionIcon(@"folder_move");
    UIAction *moveAction = [UIAction actionWithTitle:SCILocalized(@"Move to Folder")
                                               image:moveImg
                                          identifier:nil
                                             handler:^(UIAction *a) { [weakSelf moveFile:file]; }];

     UIImage *shareImg = SCIGalleryActionIcon(@"share");
    UIAction *shareAction = [UIAction actionWithTitle:SCILocalized(@"Share")
                                                image:shareImg
                                           identifier:nil
                                              handler:^(UIAction *a) {
        NSURL *url = [file fileURL];
        UIActivityViewController *acVC = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        [SCIPhotoAlbum armWatcherIfEnabled];
        [weakSelf presentViewController:acVC animated:YES completion:nil];
    }];

    UIAction *saveAction = [UIAction actionWithTitle:SCILocalized(@"Save to Photos")
                                               image:SCIGalleryActionIcon(@"download")
                                          identifier:nil
                                             handler:^(__unused UIAction *a) {
        [weakSelf sciSaveGalleryFilesToPhotos:@[file]];
    }];

    UIAction *openOriginalAction = nil;
    if (file.hasOpenableOriginalMedia) {
        openOriginalAction = [UIAction actionWithTitle:SCILocalized(@"Open Original Post")
                                                 image:SCIGalleryActionIcon(@"external_link")
                                            identifier:nil
                                               handler:^(__unused UIAction *a) {
            [weakSelf openOriginalPostForFile:file];
        }];
    }

    UIAction *openProfileAction = nil;
    if (file.hasOpenableProfile) {
        openProfileAction = [UIAction actionWithTitle:SCILocalized(@"Open Profile")
                                                image:SCIGalleryActionIcon(@"profile")
                                           identifier:nil
                                              handler:^(__unused UIAction *a) {
            [weakSelf openProfileForFile:file];
        }];
    }

    UIImage *deleteImg = SCIGalleryActionIcon(@"trash");
    UIAction *deleteAction = [UIAction actionWithTitle:SCILocalized(@"Delete")
                                                 image:deleteImg
                                            identifier:nil
                                               handler:^(UIAction *a) {
        [weakSelf confirmDeleteFile:file];
    }];
    deleteAction.attributes = UIMenuElementAttributesDestructive;

    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
    if (openOriginalAction) [children addObject:openOriginalAction];
    if (openProfileAction) [children addObject:openProfileAction];
    if (children.count > 0) {
        [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[]]];
    }
    [children addObjectsFromArray:@[favoriteAction, renameAction, moveAction, saveAction, shareAction, deleteAction]];
    return [UIMenu menuWithTitle:@"" children:children];
}

// Shared delete confirm flow — used by both the per-row context menu action
// and the list-row left-swipe gesture.
- (void)confirmDeleteFile:(SCIGalleryFile *)file {
    if (!file) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"Delete from Gallery?")
                         message:SCILocalized(@"This will permanently remove this file from the gallery.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
        NSError *err = nil;
        [file removeWithError:&err];
        if (err) {
            [SCIUtils showToastForActionIdentifier:kSCIFeedbackActionGalleryDeleteFile duration:2.0
                                             title:SCILocalized(@"Failed to delete")
                                          subtitle:err.localizedDescription
                                      iconResource:@"error_filled"
                                              tone:SCIFeedbackPillToneError];
        } else {
            [SCIUtils showToastForActionIdentifier:kSCIFeedbackActionGalleryDeleteFile duration:1.5
                                             title:SCILocalized(@"Deleted from Gallery")
                                          subtitle:nil
                                      iconResource:@"circle_check_filled"
                                              tone:SCIFeedbackPillToneSuccess];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIContextMenuConfiguration *)contextMenuForFile:(SCIGalleryFile *)file {
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        return strongSelf ? [strongSelf fileActionsMenuForFile:file] : nil;
    }];
}

- (UIContextMenuConfiguration *)contextMenuForFolder:(NSString *)folderPath {
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
    UIImage *folderRenameImg = SCIGalleryActionIcon(@"edit");
        UIAction *renameAction = [UIAction actionWithTitle:SCILocalized(@"Rename Folder")
                                                     image:folderRenameImg
                                                identifier:nil
                                                   handler:^(UIAction *a) { [weakSelf renameFolder:folderPath]; }];

    UIImage *folderDeleteImg = SCIGalleryActionIcon(@"trash");
        UIAction *deleteAction = [UIAction actionWithTitle:SCILocalized(@"Delete Folder")
                                                     image:folderDeleteImg
                                                identifier:nil
                                                   handler:^(UIAction *a) { [weakSelf deleteFolder:folderPath]; }];
        deleteAction.attributes = UIMenuElementAttributesDestructive;

        return [UIMenu menuWithTitle:@"" children:@[renameAction, deleteAction]];
    }];
}
- (void)presentCreateFolder {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"New Folder")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = SCILocalized(@"Folder name");
        tf.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Create")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0) return;
        [self createFolderNamed:name];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createFolderNamed:(NSString *)name {
    NSString *newPath = [self folderPathByAppendingComponent:name toBase:self.currentFolderPath];

    // Folders materialize when any file references them. To make empty folders
    // discoverable, we store a placeholder record in NSUserDefaults.
    NSString *key = @"gallery_folders";
    NSMutableArray<NSString *> *placeholders = [[[NSUserDefaults standardUserDefaults] arrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    if (![placeholders containsObject:newPath]) {
        [placeholders addObject:newPath];
        [[NSUserDefaults standardUserDefaults] setObject:placeholders forKey:key];
    }
    [self reloadSubfolders];
    [self.collectionView reloadData];
    [self updateEmptyState];
}

- (NSString *)folderPathByAppendingComponent:(NSString *)component toBase:(NSString *)base {
    NSString *sanitized = [component stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    if (base.length == 0) return [@"/" stringByAppendingString:sanitized];
    return [base stringByAppendingFormat:@"/%@", sanitized];
}

- (void)mergePlaceholderSubfolders {
    NSArray<NSString *> *placeholders = [[NSUserDefaults standardUserDefaults] arrayForKey:@"gallery_folders"] ?: @[];
    NSString *base = self.currentFolderPath ?: @"";
    NSString *prefix = base.length == 0 ? @"/" : [base stringByAppendingString:@"/"];

    NSMutableSet<NSString *> *merged = [NSMutableSet setWithArray:self.subfolders];
    for (NSString *p in placeholders) {
        if (![p hasPrefix:prefix]) continue;
        NSString *rest = [p substringFromIndex:prefix.length];
        if (rest.length == 0) continue;
        NSRange slash = [rest rangeOfString:@"/"];
        NSString *folderName = slash.location == NSNotFound ? rest : [rest substringToIndex:slash.location];
        [merged addObject:[prefix stringByAppendingString:folderName]];
    }
    self.subfolders = [[merged allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (void)renameFolder:(NSString *)folderPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Rename Folder")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [folderPath lastPathComponent];
        tf.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Rename")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newName.length == 0) return;
        [self performRenameOfFolder:folderPath toName:newName];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performRenameOfFolder:(NSString *)oldPath toName:(NSString *)newName {
    NSString *parent = [oldPath stringByDeletingLastPathComponent];
    if (![parent hasPrefix:@"/"]) parent = [@"/" stringByAppendingString:parent];
    NSString *newPath = [parent isEqualToString:@"/"]
        ? [@"/" stringByAppendingString:newName]
        : [parent stringByAppendingFormat:@"/%@", newName];

    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.predicate = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@",
                     oldPath, [oldPath stringByAppendingString:@"/"]];
    NSArray<SCIGalleryFile *> *files = [ctx executeFetchRequest:req error:nil];
    for (SCIGalleryFile *f in files) {
        NSString *current = f.folderPath ?: @"";
        if ([current isEqualToString:oldPath]) {
            f.folderPath = newPath;
        } else if ([current hasPrefix:[oldPath stringByAppendingString:@"/"]]) {
            NSString *suffix = [current substringFromIndex:oldPath.length];
            f.folderPath = [newPath stringByAppendingString:suffix];
        }
    }
    [ctx save:nil];

    // Update placeholders.
    NSString *key = @"gallery_folders";
    NSMutableArray<NSString *> *placeholders = [[[NSUserDefaults standardUserDefaults] arrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    NSMutableArray<NSString *> *updated = [NSMutableArray array];
    for (NSString *p in placeholders) {
        if ([p isEqualToString:oldPath]) {
            [updated addObject:newPath];
        } else if ([p hasPrefix:[oldPath stringByAppendingString:@"/"]]) {
            [updated addObject:[newPath stringByAppendingString:[p substringFromIndex:oldPath.length]]];
        } else {
            [updated addObject:p];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:updated forKey:key];

    [self reloadSubfolders];
    [self.collectionView reloadData];
}

- (void)deleteFolder:(NSString *)folderPath {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.predicate = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@",
                     folderPath, [folderPath stringByAppendingString:@"/"]];
    NSInteger count = [ctx countForFetchRequest:req error:nil];

    NSString *msg = count == 0
        ? SCILocalized(@"This folder is empty.")
        : [NSString stringWithFormat:SCILocalized(@"This folder contains %ld file(s). They will be moved to the parent folder."), (long)count];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Delete Folder")]
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Delete")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        [self performDeleteFolder:folderPath];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performDeleteFolder:(NSString *)folderPath {
    NSString *parent = [folderPath stringByDeletingLastPathComponent];
    if (parent.length == 0 || [parent isEqualToString:@"/"]) parent = nil; // move to root

    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.predicate = [NSPredicate predicateWithFormat:@"folderPath == %@ OR folderPath BEGINSWITH %@",
                     folderPath, [folderPath stringByAppendingString:@"/"]];
    NSArray<SCIGalleryFile *> *files = [ctx executeFetchRequest:req error:nil];
    for (SCIGalleryFile *f in files) {
        f.folderPath = parent;
    }
    [ctx save:nil];

    // Remove placeholders beneath the folder path.
    NSString *key = @"gallery_folders";
    NSMutableArray<NSString *> *placeholders = [[[NSUserDefaults standardUserDefaults] arrayForKey:key] mutableCopy] ?: [NSMutableArray array];
    NSString *prefix = [folderPath stringByAppendingString:@"/"];
    [placeholders filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *p, NSDictionary *b) {
        return ![p isEqualToString:folderPath] && ![p hasPrefix:prefix];
    }]];
    [[NSUserDefaults standardUserDefaults] setObject:placeholders forKey:key];

    [self reloadSubfolders];
    [self.collectionView reloadData];
    [self updateEmptyState];
}
- (void)renameFile:(SCIGalleryFile *)file {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Rename")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [file displayName];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Save")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        file.customName = newName.length > 0 ? newName : nil;
        [[SCIGalleryCoreDataStack shared] saveContext];
        [self.collectionView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)assignFolderPath:(nullable NSString *)folderPath toFiles:(NSArray<SCIGalleryFile *> *)files {
    for (SCIGalleryFile *file in files) {
        file.folderPath = folderPath;
    }
    [[SCIGalleryCoreDataStack shared] saveContext];
    [self refetch];
}

- (void)presentMoveSheetForFiles:(NSArray<SCIGalleryFile *> *)files {
    NSArray<NSString *> *allFolders = [self allFolderPaths];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Move to Folder")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Root")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        [self assignFolderPath:nil toFiles:files];
    }]];

    for (NSString *folder in allFolders) {
        [sheet addAction:[UIAlertAction actionWithTitle:folder
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [self assignFolderPath:folder toFiles:files];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"New folder…")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        UIAlertController *createAlert = [UIAlertController alertControllerWithTitle:SCILocalized(@"New Folder")
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleAlert];
        [createAlert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = SCILocalized(@"Folder name"); }];
        [createAlert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [createAlert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Create & Move")
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *x) {
            NSString *name = [createAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (name.length == 0) return;
            NSString *newPath = [self folderPathByAppendingComponent:name toBase:self.currentFolderPath];
            [self assignFolderPath:newPath toFiles:files];
        }]];
        [self presentViewController:createAlert animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)moveFile:(SCIGalleryFile *)file {
    [self presentMoveSheetForFiles:@[file]];
}

- (NSArray<NSString *> *)allFolderPaths {
    NSManagedObjectContext *ctx = [SCIGalleryCoreDataStack shared].viewContext;
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
    req.resultType = NSDictionaryResultType;
    req.propertiesToFetch = @[@"folderPath"];
    req.returnsDistinctResults = YES;
    req.predicate = [NSPredicate predicateWithFormat:@"folderPath != nil AND folderPath != ''"];
    NSArray<NSDictionary *> *results = [ctx executeFetchRequest:req error:nil];

    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (NSDictionary *d in results) {
        NSString *p = d[@"folderPath"];
        if (p.length > 0) [set addObject:p];
    }
    NSArray<NSString *> *placeholders = [[NSUserDefaults standardUserDefaults] arrayForKey:@"gallery_folders"] ?: @[];
    [set addObjectsFromArray:placeholders];

    return [[set allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

@end
