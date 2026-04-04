// Shared helpers for story/DM visual message features
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Downloader/Download.h"
#import <objc/runtime.h>
#import <objc/message.h>

typedef id (*SCIMsgSend)(id, SEL);
typedef id (*SCIMsgSend1)(id, SEL, id);

static inline id sciCall(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((SCIMsgSend)objc_msgSend)(obj, sel);
}
static inline id sciCall1(id obj, SEL sel, id arg1) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((SCIMsgSend1)objc_msgSend)(obj, sel, arg1);
}

static inline UIViewController * _Nullable sciFindVC(UIResponder *start, NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return nil;
    UIResponder *r = start;
    while (r) {
        if ([r isKindOfClass:cls]) return (UIViewController *)r;
        r = [r nextResponder];
    }
    return nil;
}

static inline IGMedia * _Nullable sciExtractMediaFromItem(id item) {
    if (!item) return nil;
    Class mediaClass = NSClassFromString(@"IGMedia");
    if (!mediaClass) return nil;
    NSArray *trySelectors = @[@"media", @"mediaItem", @"storyItem", @"item",
                              @"feedItem", @"igMedia", @"model", @"backingModel",
                              @"storyMedia", @"mediaModel"];
    for (NSString *selName in trySelectors) {
        id val = sciCall(item, NSSelectorFromString(selName));
        if (val && [val isKindOfClass:mediaClass]) return (IGMedia *)val;
    }
    unsigned int iCount = 0;
    Ivar *ivars = class_copyIvarList([item class], &iCount);
    for (unsigned int i = 0; i < iCount; i++) {
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (type && type[0] == '@') {
            id val = object_getIvar(item, ivars[i]);
            if (val && [val isKindOfClass:mediaClass]) { free(ivars); return (IGMedia *)val; }
        }
    }
    if (ivars) free(ivars);
    return nil;
}

static inline id _Nullable sciGetCurrentStoryItem(UIResponder *start) {
    UIViewController *storyVC = sciFindVC(start, @"IGStoryViewerViewController");
    if (!storyVC) return nil;
    id vm = sciCall(storyVC, @selector(currentViewModel));
    if (!vm) return nil;
    return sciCall1(storyVC, @selector(currentStoryItemForViewModel:), vm);
}

static inline id _Nullable sciFindSectionController(UIViewController *storyVC) {
    Class sectionClass = NSClassFromString(@"IGStoryFullscreenSectionController");
    if (!sectionClass || !storyVC) return nil;
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList([storyVC class], &count);
    UICollectionView *cv = nil;
    for (unsigned int i = 0; i < count; i++) {
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') continue;
        id val = object_getIvar(storyVC, ivars[i]);
        if (val && [val isKindOfClass:[UICollectionView class]]) { cv = val; break; }
    }
    if (ivars) free(ivars);
    if (!cv) return nil;
    for (UICollectionViewCell *cell in cv.visibleCells) {
        unsigned int cCount = 0;
        Ivar *cIvars = class_copyIvarList([cell class], &cCount);
        for (unsigned int i = 0; i < cCount; i++) {
            const char *type = ivar_getTypeEncoding(cIvars[i]);
            if (!type || type[0] != '@') continue;
            id val = object_getIvar(cell, cIvars[i]);
            if (!val) continue;
            unsigned int vCount = 0;
            Ivar *vIvars = class_copyIvarList([val class], &vCount);
            for (unsigned int j = 0; j < vCount; j++) {
                const char *type2 = ivar_getTypeEncoding(vIvars[j]);
                if (!type2 || type2[0] != '@') continue;
                id val2 = object_getIvar(val, vIvars[j]);
                if (val2 && [val2 isKindOfClass:sectionClass]) { free(vIvars); free(cIvars); return val2; }
            }
            if (vIvars) free(vIvars);
        }
        if (cIvars) free(cIvars);
    }
    return nil;
}
