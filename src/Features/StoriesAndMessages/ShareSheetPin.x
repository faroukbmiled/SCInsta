// Pin recipients in the IG share sheet — long-press to pin/unpin, pinned
// recipients render at the top.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

#define SSPIN_KEY @"share_sheet_pinned_thread_ids"

#pragma mark - storage

static NSArray<NSString *> *sciSSPinList(void) {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:SSPIN_KEY];
    return [a isKindOfClass:[NSArray class]] ? a : @[];
}

static BOOL sciSSPinContains(NSString *tid) {
    if (!tid.length) return NO;
    return [sciSSPinList() containsObject:tid];
}

static NSUInteger sciSSPinRank(NSString *tid) {
    if (!tid.length) return NSNotFound;
    return [sciSSPinList() indexOfObject:tid];
}

static void sciSSPinSave(NSArray<NSString *> *list) {
    [[NSUserDefaults standardUserDefaults] setObject:(list ?: @[]) forKey:SSPIN_KEY];
}

static void sciSSPinToggle(NSString *tid) {
    if (!tid.length) return;
    NSMutableArray *m = [sciSSPinList() mutableCopy];
    BOOL wasPinned = [m containsObject:tid];
    if (wasPinned) {
        [m removeObject:tid];
    } else {
        [m insertObject:tid atIndex:0];
    }
    sciSSPinSave(m);
    SCINotifySuccess(SCI_NOTIF_PIN_THREAD, wasPinned ? SCILocalized(@"Recipient unpinned") : SCILocalized(@"Recipient pinned"), nil);
}

static NSString *sciSSPinThreadIDFromVM(id vm) {
    if (!vm || ![vm respondsToSelector:@selector(recipient)]) return nil;
    id rec = nil;
    @try { rec = [vm recipient]; } @catch (__unused id e) {}
    if (!rec || ![rec respondsToSelector:@selector(threadID)]) return nil;
    @try { return [rec threadID]; } @catch (__unused id e) { return nil; }
}

#pragma mark - reorder

static NSArray *sciSSPinReorder(NSArray *out) {
    if (![SCIUtils getBoolPref:@"share_sheet_pin_threads"]) return out;
    if (![out isKindOfClass:[NSArray class]] || out.count < 2) return out;
    NSArray<NSString *> *pins = sciSSPinList();
    if (pins.count == 0) return out;

    NSMutableArray *pinned = [NSMutableArray new];
    NSMutableArray *rest = [NSMutableArray new];
    for (id obj in out) {
        NSString *tid = sciSSPinThreadIDFromVM(obj);
        if (tid.length && [pins containsObject:tid]) {
            [pinned addObject:obj];
        } else {
            [rest addObject:obj];
        }
    }
    if (pinned.count == 0) return out;

    [pinned sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSUInteger ia = sciSSPinRank(sciSSPinThreadIDFromVM(a));
        NSUInteger ib = sciSSPinRank(sciSSPinThreadIDFromVM(b));
        if (ia == ib) return NSOrderedSame;
        return ia < ib ? NSOrderedAscending : NSOrderedDescending;
    }];
    [pinned addObjectsFromArray:rest];
    return pinned;
}

#pragma mark - long-press handler

static const void *kSSPinGestureKey = &kSSPinGestureKey;
static char kSSPinHandlerKey;

@interface SCISSPinHandler : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController *vc;
@end

@implementation SCISSPinHandler

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    return [SCIUtils getBoolPref:@"share_sheet_pin_threads"];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIViewController *vc = self.vc;
    if (!vc.view) return;

    CGPoint loc = [g locationInView:vc.view];
    UIView *hit = [vc.view hitTest:loc withEvent:nil];
    UICollectionViewCell *cell = nil;
    UIView *cur = hit;
    while (cur) {
        if ([cur isKindOfClass:[UICollectionViewCell class]]) { cell = (UICollectionViewCell *)cur; break; }
        cur = cur.superview;
    }
    if (!cell) return;

    UICollectionView *cv = nil;
    Ivar cvIvar = class_getInstanceVariable([vc class], "_collectionView");
    if (cvIvar) cv = object_getIvar(vc, cvIvar);
    if (!cv) {
        UIView *p = cell.superview;
        while (p && ![p isKindOfClass:[UICollectionView class]]) p = p.superview;
        cv = (UICollectionView *)p;
    }
    NSIndexPath *ip = [cv indexPathForCell:cell];
    if (!ip) return;

    Ivar adapterIvar = class_getInstanceVariable([vc class], "_listAdapter");
    IGListAdapter *adapter = adapterIvar ? object_getIvar(vc, adapterIvar) : nil;
    if (!adapter) return;

    id model = nil;
    @try { model = [adapter objectAtSection:ip.section]; } @catch (__unused id e) {}
    NSString *tid = sciSSPinThreadIDFromVM(model);
    if (!tid.length) {
        SCINotifyError(SCI_NOTIF_VALIDATION_ERROR, SCILocalized(@"Couldn't resolve recipient id"), nil);
        return;
    }

    [[UIImpactFeedbackGenerator new] impactOccurred];
    sciSSPinToggle(tid);

    if ([adapter respondsToSelector:@selector(performUpdatesAnimated:completion:)]) {
        [adapter performUpdatesAnimated:YES completion:nil];
    }
}

@end

static void sciSSPinAttachLongPress(UIViewController *vc) {
    if (!vc.view) return;
    if (objc_getAssociatedObject(vc.view, kSSPinGestureKey)) return;

    SCISSPinHandler *h = [SCISSPinHandler new];
    h.vc = vc;
    objc_setAssociatedObject(vc, &kSSPinHandlerKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc]
        initWithTarget:h action:@selector(longPressed:)];
    g.minimumPressDuration = 0.3;
    g.cancelsTouchesInView = NO;
    g.delegate = h;
    [vc.view addGestureRecognizer:g];
    objc_setAssociatedObject(vc.view, kSSPinGestureKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - cell pin badge

static const void *kSSPinBadgeKey = &kSSPinBadgeKey;

static UIView *sciSSPinFindAvatar(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass([v class]) isEqualToString:@"IGDirectAvatarView"]) return v;
        for (UIView *s in v.subviews) [queue addObject:s];
    }
    return nil;
}

static void sciSSPinUpdateBadge(UICollectionViewCell *cell, BOOL pinned) {
    UIView *badge = objc_getAssociatedObject(cell, kSSPinBadgeKey);
    if (!pinned) {
        [badge removeFromSuperview];
        objc_setAssociatedObject(cell, kSSPinBadgeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    UIView *avatar = sciSSPinFindAvatar(cell.contentView);
    if (!avatar) return;
    UIView *parent = avatar.superview ?: cell.contentView;

    if (!badge || badge.superview != parent) {
        [badge removeFromSuperview];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold];
        UIImage *img = [UIImage systemImageNamed:@"pin.fill" withConfiguration:cfg];
        UIImageView *icon = [[UIImageView alloc] initWithImage:img];
        icon.tintColor = [UIColor systemBlueColor];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.userInteractionEnabled = NO;
        icon.layer.shadowColor = [UIColor blackColor].CGColor;
        icon.layer.shadowOpacity = 0.25;
        icon.layer.shadowRadius = 2;
        icon.layer.shadowOffset = CGSizeMake(0, 1);
        badge = icon;
        [parent addSubview:badge];
        [NSLayoutConstraint activateConstraints:@[
            [badge.centerXAnchor constraintEqualToAnchor:avatar.leadingAnchor constant:6],
            [badge.centerYAnchor constraintEqualToAnchor:avatar.topAnchor constant:6],
        ]];
        objc_setAssociatedObject(cell, kSSPinBadgeKey, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [parent bringSubviewToFront:badge];
    badge.hidden = NO;
}

static UICollectionViewCell *sciSSPinEnclosingCell(UIView *v) {
    UIView *p = v;
    while (p) {
        if ([p isKindOfClass:[UICollectionViewCell class]]) return (UICollectionViewCell *)p;
        p = p.superview;
    }
    return nil;
}

static void sciSSPinRefreshFromAvatar(UIView *avatar) {
    UICollectionViewCell *cell = sciSSPinEnclosingCell(avatar);
    if (!cell) return;
    if (![SCIUtils getBoolPref:@"share_sheet_pin_threads"]) {
        sciSSPinUpdateBadge(cell, NO);
        return;
    }
    UIView *p = cell.superview;
    while (p && ![p isKindOfClass:[UICollectionView class]]) p = p.superview;
    UICollectionView *cv = (UICollectionView *)p;
    if (!cv) return;
    NSIndexPath *ip = [cv indexPathForCell:cell];
    if (!ip) return;

    id ds = cv.dataSource;
    if (![ds respondsToSelector:@selector(objectAtSection:)]) return;
    id vm = nil;
    @try { vm = [(IGListAdapter *)ds objectAtSection:ip.section]; } @catch (__unused id e) { return; }
    NSString *tid = sciSSPinThreadIDFromVM(vm);
    sciSSPinUpdateBadge(cell, sciSSPinContains(tid));
}

#pragma mark - hooks

// IGListAdapterDataSource lives on the VC itself; hook -objectsForListAdapter:
// at runtime once we have the actual class.
static NSMutableSet *sciSSPinHookedDSClasses(void) {
    static NSMutableSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet new]; });
    return s;
}

static void sciSSPinHookDataSourceClass(Class cls) {
    if (!cls) return;
    @synchronized (sciSSPinHookedDSClasses()) {
        NSString *name = NSStringFromClass(cls);
        if ([sciSSPinHookedDSClasses() containsObject:name]) return;
        [sciSSPinHookedDSClasses() addObject:name];
    }
    SEL sel = @selector(objectsForListAdapter:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    IMP newImp = imp_implementationWithBlock(^NSArray *(id self_, id la) {
        NSArray *out = ((NSArray *(*)(id, SEL, id))orig)(self_, sel, la);
        return sciSSPinReorder(out);
    });
    method_setImplementation(m, newImp);
}

%hook IGDirectRecipientListViewController

- (void)viewDidLoad {
    %orig;
    sciSSPinAttachLongPress(self);

    Ivar adapterIvar = class_getInstanceVariable([self class], "_listAdapter");
    IGListAdapter *adapter = adapterIvar ? object_getIvar(self, adapterIvar) : nil;
    id ds = [adapter respondsToSelector:@selector(dataSource)] ? [adapter dataSource] : nil;
    if (ds) sciSSPinHookDataSourceClass([ds class]);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sciSSPinAttachLongPress(self);
}

%end

%ctor {
    @autoreleasepool {
        // Avatar layoutSubviews — refresh the badge each pass so it follows
        // cell recycle / reorder / scroll.
        Class avCls = NSClassFromString(@"IGDirectAvatarView");
        if (avCls) {
            SEL sel = @selector(layoutSubviews);
            Method m = class_getInstanceMethod(avCls, sel);
            if (m) {
                IMP orig = method_getImplementation(m);
                IMP newImp = imp_implementationWithBlock(^(UIView *self_) {
                    ((void (*)(id, SEL))orig)(self_, sel);
                    sciSSPinRefreshFromAvatar(self_);
                });
                method_setImplementation(m, newImp);
            }
        }

        // Strip stale badge before cell rebinds to a different recipient.
        Class cellCls = NSClassFromString(@"IGDirectSupershareSwiftV3.IGDirectSupershareV3Cell");
        if (cellCls) {
            SEL sel = @selector(prepareForReuse);
            Method m = class_getInstanceMethod(cellCls, sel);
            if (m) {
                IMP orig = method_getImplementation(m);
                IMP newImp = imp_implementationWithBlock(^(UICollectionViewCell *self_) {
                    sciSSPinUpdateBadge(self_, NO);
                    ((void (*)(id, SEL))orig)(self_, sel);
                });
                method_setImplementation(m, newImp);
            }
        }
    }
}
