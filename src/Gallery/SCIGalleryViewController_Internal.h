// Private continuation header — exposes SCIGalleryViewController's ivars +
// helper methods to the main implementation file and its category files.
//
// Treat this as internal: do NOT import from outside src/Gallery/.

#import "SCIGalleryViewController.h"
#import "SCIGalleryFilterViewController.h"
#import "SCIGallerySortViewController.h"
#import <CoreData/CoreData.h>

@class SCIGalleryFile;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIGalleryViewMode) {
    SCIGalleryViewModeGrid = 0,
    SCIGalleryViewModeList = 1,
};

@interface SCIGalleryViewController () <UICollectionViewDataSource,
                                        UICollectionViewDelegate,
                                        UICollectionViewDelegateFlowLayout,
                                        NSFetchedResultsControllerDelegate,
                                        SCIGallerySortViewControllerDelegate,
                                        SCIGalleryFilterViewControllerDelegate,
                                        UIAdaptivePresentationControllerDelegate,
                                        UISearchResultsUpdating>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UILabel *emptyStateLabel;
@property (nonatomic, strong, nullable) UIView *bottomBar;
@property (nonatomic, strong, nullable) UIStackView *bottomBarStack;
@property (nonatomic, strong, nullable) id scrollToTopButton;

@property (nonatomic, copy, nullable) NSString *currentFolderPath;
@property (nonatomic, strong) NSArray<NSString *> *subfolders;

@property (nonatomic, assign) SCIGalleryViewMode viewMode;
@property (nonatomic, assign) SCIGallerySortMode sortMode;

@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterTypes;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterSources;
@property (nonatomic, strong) NSMutableSet<NSString *> *filterUsernames;
@property (nonatomic, assign) BOOL filterFavoritesOnly;

@property (nonatomic, assign) BOOL selectionMode;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedFileIDs;

@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchQuery;

// Picker mode — selecting a file fires `pickerCompletion` and dismisses.
// Folder navigation still works; multi-select / settings chrome is hidden.
@property (nonatomic, assign) BOOL pickerMode;
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *pickerAllowedMediaTypes;
@property (nonatomic, copy, nullable) void (^pickerCompletion)(NSURL * _Nullable url, SCIGalleryFile * _Nullable file);
@property (nonatomic, copy, nullable) NSString *pickerTitleOverride;

// Methods that live in the main implementation. The (Actions) category
// declares its own additions below.
- (void)refetch;
- (void)reloadSubfolders;
- (void)refreshNavigationItems;
- (void)refreshBottomToolbarItems;
- (void)updateEmptyState;
- (NSArray<SCIGalleryFile *> *)visibleGalleryFiles;
- (SCIGalleryFile *)galleryFileForCollectionIndexPath:(NSIndexPath *)indexPath;
- (BOOL)isFolderIndexPath:(NSIndexPath *)indexPath;

@end

@interface SCIGalleryViewController (Actions)
- (UIMenu *)fileActionsMenuForFile:(SCIGalleryFile *)file;
- (UIContextMenuConfiguration *)contextMenuForFile:(SCIGalleryFile *)file;
- (UIContextMenuConfiguration *)contextMenuForFolder:(NSString *)folderPath;
- (void)confirmDeleteFile:(SCIGalleryFile *)file;
- (void)openOriginalPostForFile:(SCIGalleryFile *)file;
- (void)openProfileForFile:(SCIGalleryFile *)file;
- (void)renameFile:(SCIGalleryFile *)file;
- (void)moveFile:(SCIGalleryFile *)file;
- (void)assignFolderPath:(nullable NSString *)folderPath toFiles:(NSArray<SCIGalleryFile *> *)files;
- (void)presentMoveSheetForFiles:(NSArray<SCIGalleryFile *> *)files;

- (void)enterSelectionMode;
- (void)exitSelectionMode;
- (void)toggleSelectionForFile:(SCIGalleryFile *)file;
- (void)selectAllVisibleFiles;
- (void)shareSelectedFiles;
- (void)saveSelectedFilesToPhotos;
- (void)sciSaveGalleryFilesToPhotos:(NSArray<SCIGalleryFile *> *)files;
- (void)moveSelectedFiles;
- (void)toggleFavoriteForSelectedFiles;
- (void)deleteSelectedFiles;
- (NSArray<SCIGalleryFile *> *)selectedGalleryFiles;
- (void)animateSelectionModeTransition;

- (void)presentCreateFolder;
- (void)createFolderNamed:(NSString *)name;
- (void)renameFolder:(NSString *)folderPath;
- (void)performRenameOfFolder:(NSString *)oldPath toName:(NSString *)newName;
- (void)deleteFolder:(NSString *)folderPath;
- (void)performDeleteFolder:(NSString *)folderPath;
- (NSString *)folderPathByAppendingComponent:(NSString *)component toBase:(nullable NSString *)base;
- (NSArray<NSString *> *)allFolderPaths;
- (void)mergePlaceholderSubfolders;

- (void)showGalleryOpenFailureMessage:(NSString *)title actionIdentifier:(NSString *)actionIdentifier;
- (void)dismissGalleryForOriginOpenWithCompletion:(void (^_Nullable)(void))completion;
@end

NS_ASSUME_NONNULL_END
