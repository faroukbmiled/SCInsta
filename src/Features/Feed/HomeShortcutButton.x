// Home feed top-bar shortcut button. Hooks IGBadgeButton, slots a button in
// next to the leftmost trailing badge (+) and shifts the others right to make
// room. Catalog (action IDs, titles, presenters) in SCIHomeShortcutCatalog.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import "SCIHomeShortcutCatalog.h"
#import <objc/runtime.h>

static const void *kSCIHomeShortcutBtnKey           = &kSCIHomeShortcutBtnKey;
static const void *kSCIHomeShortcutSigKey           = &kSCIHomeShortcutSigKey;
static const void *kSCIHomeShortcutSingleActionKey  = &kSCIHomeShortcutSingleActionKey;
static const void *kSCIHomeShortcutLeftBadgeKey     = &kSCIHomeShortcutLeftBadgeKey;

// Tracks every parent view that currently hosts an injected shortcut button so
// the live-config observer can rebuild them in place.
static NSHashTable<UIView *> *sciHomeShortcutHosts(void) {
    static NSHashTable *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [NSHashTable weakObjectsHashTable]; });
    return t;
}

static CGFloat const kSCIHomeShortcutGap = 4.0;
static CGFloat const kSCIHomeShortcutMinSide = 28.0;
static CGFloat const kSCIHomeShortcutPointSize = 17.0;

#pragma mark - Helpers

static BOOL sciIsHomeTopbarBadge(IGBadgeButton *b) {
    UIView *gp = b.superview.superview;
    if (!gp) return NO;
    return [NSStringFromClass([gp class]) containsString:@"HomeFeed"];
}

static void sciClearInjectedButton(UIView *parent) {
    SCIChromeButton *btn = objc_getAssociatedObject(parent, kSCIHomeShortcutBtnKey);
    [sciHomeShortcutHosts() removeObject:parent];
    if (!btn) return;
    [btn removeFromSuperview];
    objc_setAssociatedObject(parent, kSCIHomeShortcutBtnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(parent, kSCIHomeShortcutSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Force IG to re-run the badge layout so the gap left by our button
    // closes. Without this, badges stay at their shifted positions after a
    // live disable until the next IG layout pass.
    [parent setNeedsLayout];
    [parent.superview setNeedsLayout];
}

// Sorted by window-X (parent-X fallback) so the leftmost is always the visual `+`.
static NSArray<UIView *> *sciSortedBadgesIn(UIView *parent) {
    UIWindow *win = parent.window;
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    for (UIView *sib in parent.subviews) {
        if (![sib isKindOfClass:[%c(IGBadgeButton) class]]) continue;
        if (sib.frame.size.width <= 1.0) continue;
        [out addObject:sib];
    }
    [out sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = win ? [a convertRect:a.bounds toView:win].origin.x : a.frame.origin.x;
        CGFloat bx = win ? [b convertRect:b.bounds toView:win].origin.x : b.frame.origin.x;
        if (ax < bx) return NSOrderedAscending;
        if (ax > bx) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return out;
}

// Explicit user pick wins; "auto"/blank derives from the active action set.
static NSString *sciResolvedSymbol(NSArray<NSString *> *actionIDs) {
    NSString *userIcon = [SCIUtils getStringPref:kSCIHomeShortcutIconPrefKey];
    if (userIcon.length && ![userIcon isEqualToString:@"auto"]) return userIcon;
    if (actionIDs.count == 1) {
        return [SCIHomeShortcutCatalog actionForID:actionIDs.firstObject].symbol ?: @"ellipsis.circle.fill";
    }
    return @"ellipsis.circle.fill";
}

static NSString *sciSignature(NSArray<NSString *> *actionIDs, NSString *symbol) {
    return [NSString stringWithFormat:@"%@|%@", symbol ?: @"", [actionIDs componentsJoinedByString:@","]];
}

// Idempotent — skips badges already past us.
static void sciShiftRightSiblings(UIView *parent, UIView *plus, UIView *btn, CGRect plusFrame, CGRect btnFrame) {
    CGFloat clearX = CGRectGetMaxX(btnFrame) + kSCIHomeShortcutGap;
    for (UIView *sib in parent.subviews) {
        if (sib == plus || sib == btn) continue;
        if (![sib isKindOfClass:[%c(IGBadgeButton) class]]) continue;
        if (sib.frame.origin.x <= plusFrame.origin.x) continue;
        if (sib.frame.origin.x >= clearX) continue;
        CGRect r = sib.frame;
        r.origin.x = clearX;
        sib.frame = r;
    }
}

// No-op when cached signature matches.
static void sciSyncTargetForButton(SCIChromeButton *btn,
                                    UIView *sigOwner,
                                    NSArray<NSString *> *actionIDs,
                                    NSString *symbol,
                                    id targetForSingleAction,
                                    SEL singleActionSelector) {
    NSString *sig = sciSignature(actionIDs, symbol);
    NSString *prevSig = objc_getAssociatedObject(sigOwner, kSCIHomeShortcutSigKey);
    if ([prevSig isEqualToString:sig]) return;

    [btn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    btn.menu = nil;
    btn.showsMenuAsPrimaryAction = NO;
    btn.symbolName = symbol;
    btn.symbolPointSize = kSCIHomeShortcutPointSize;

    if (actionIDs.count == 1) {
        objc_setAssociatedObject(btn, kSCIHomeShortcutSingleActionKey, actionIDs.firstObject, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [btn addTarget:targetForSingleAction action:singleActionSelector forControlEvents:UIControlEventTouchUpInside];
    } else {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
        NSMutableArray<UIAction *> *items = [NSMutableArray arrayWithCapacity:actionIDs.count];
        for (NSString *aid in actionIDs) {
            SCIHomeShortcutAction *a = [SCIHomeShortcutCatalog actionForID:aid];
            UIImage *icon = a.symbol.length ? [UIImage systemImageNamed:a.symbol withConfiguration:cfg] : nil;
            __weak typeof(btn) weakBtn = btn;
            [items addObject:[UIAction actionWithTitle:(a.title ?: aid)
                                                 image:icon
                                            identifier:nil
                                               handler:^(__unused UIAction *_) {
                [SCIHomeShortcutCatalog fireActionID:aid contextView:weakBtn];
            }]];
        }
        btn.menu = [UIMenu menuWithTitle:@"" children:items];
        btn.showsMenuAsPrimaryAction = YES;
    }
    objc_setAssociatedObject(sigOwner, kSCIHomeShortcutSigKey, [sig copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
}

// Shared by layoutSubviews and setFrame:. Returns the button (created on
// demand) or nil when actions are empty.
static SCIChromeButton *sciPlaceButtonForCluster(UIView *parent,
                                                  NSArray<UIView *> *sortedBadges,
                                                  id<NSObject> hookTarget,
                                                  SEL singleActionSel) {
    NSArray<NSString *> *actionIDs = [SCIHomeShortcutCatalog enabledActionIDs];
    SCIChromeButton *btn = objc_getAssociatedObject(parent, kSCIHomeShortcutBtnKey);
    if (actionIDs.count == 0 || sortedBadges.count == 0) {
        sciClearInjectedButton(parent);
        return nil;
    }

    UIView *plus = sortedBadges.firstObject;
    NSString *symbol = sciResolvedSymbol(actionIDs);
    CGFloat side = MAX(kSCIHomeShortcutMinSide, plus.frame.size.height);

    if (!btn) {
        btn = [[SCIChromeButton alloc] initWithSymbol:symbol pointSize:kSCIHomeShortcutPointSize diameter:side];
        btn.translatesAutoresizingMaskIntoConstraints = YES;
        btn.iconTint = [UIColor labelColor];
        btn.bubbleColor = [UIColor clearColor];
        [parent addSubview:btn];
        objc_setAssociatedObject(parent, kSCIHomeShortcutBtnKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sciHomeShortcutHosts() addObject:parent];
    }

    sciSyncTargetForButton(btn, parent, actionIDs, symbol, hookTarget, singleActionSel);

    CGRect plusFrame = plus.frame;
    CGRect target = CGRectMake(CGRectGetMaxX(plusFrame) + kSCIHomeShortcutGap,
                                plusFrame.origin.y, side, side);
    if (!CGRectEqualToRect(btn.frame, target)) btn.frame = target;
    btn.alpha = plus.alpha;
    btn.hidden = plus.hidden;
    [parent bringSubviewToFront:btn];

    sciShiftRightSiblings(parent, plus, btn, plusFrame, target);
    return btn;
}

#pragma mark - Hook

%hook IGBadgeButton

- (void)layoutSubviews {
    %orig;
    if (!sciIsHomeTopbarBadge(self)) return;

    UIView *parent = self.superview;
    NSArray<UIView *> *badges = sciSortedBadgesIn(parent);
    if (badges.firstObject != self) return; // only the leftmost handles injection
    sciPlaceButtonForCluster(parent, badges, self, @selector(sciHomeShortcutFireSingle:));
}

// IG re-positions badges via direct setFrame: which doesn't fire layoutSubviews.
- (void)setFrame:(CGRect)frame {
    CGRect old = self.frame;
    %orig;
    if (CGRectEqualToRect(old, frame)) return;
    if (!sciIsHomeTopbarBadge(self)) return;
    UIView *parent = self.superview;
    if (!objc_getAssociatedObject(parent, kSCIHomeShortcutBtnKey)) return;
    NSArray<UIView *> *badges = sciSortedBadgesIn(parent);
    sciPlaceButtonForCluster(parent, badges, self, @selector(sciHomeShortcutFireSingle:));
}

// Mirror chrome fade-on-scroll — badges animate alpha/hidden directly.
- (void)setAlpha:(CGFloat)a {
    %orig;
    SCIChromeButton *btn = objc_getAssociatedObject(self.superview, kSCIHomeShortcutBtnKey);
    if (btn && btn.superview == self.superview) btn.alpha = a;
}

- (void)setHidden:(BOOL)h {
    %orig;
    SCIChromeButton *btn = objc_getAssociatedObject(self.superview, kSCIHomeShortcutBtnKey);
    if (btn && btn.superview == self.superview) btn.hidden = h;
}

%new - (void)sciHomeShortcutFireSingle:(UIButton *)sender {
    NSString *aid = objc_getAssociatedObject(sender, kSCIHomeShortcutSingleActionKey);
    if (aid.length) [SCIHomeShortcutCatalog fireActionID:aid contextView:sender];
}

%end

#pragma mark - Live config refresh

// Collects every parent view that currently holds at least one home top-bar
// IGBadgeButton. Used as the live-refresh fallback when the master toggle
// flips on after launch — those parents aren't tracked yet because no button
// has been injected against them.
static NSArray<UIView *> *sciCollectHomeBadgeParents(void) {
    NSMutableSet<UIView *> *set = [NSMutableSet set];
    Class badgeCls = %c(IGBadgeButton);
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) [stack addObject:w];
    }
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *sub in v.subviews) [stack addObject:sub];
        if (![v isKindOfClass:badgeCls]) continue;
        UIView *parent = v.superview;
        if (parent && sciIsHomeTopbarBadge((IGBadgeButton *)v)) [set addObject:parent];
    }
    return set.allObjects;
}

static void sciHomeShortcutHandleConfigChange(void) {
    NSMutableSet<UIView *> *seen = [NSMutableSet set];
    @synchronized (sciHomeShortcutHosts()) {
        for (UIView *p in sciHomeShortcutHosts().allObjects) if (p) [seen addObject:p];
    }
    [seen addObjectsFromArray:sciCollectHomeBadgeParents()];
    for (UIView *parent in seen) {
        if (!parent.superview) { sciClearInjectedButton(parent); continue; }
        NSArray<UIView *> *badges = sciSortedBadgesIn(parent);
        UIView *leftBadge = badges.firstObject;
        sciPlaceButtonForCluster(parent, badges, leftBadge,
                                 NSSelectorFromString(@"sciHomeShortcutFireSingle:"));
    }
}

%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:SCIHomeShortcutConfigDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        sciHomeShortcutHandleConfigChange();
    }];
}
