#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <substrate.h>

// ============ KEEP DELETED MESSAGES ============
// Blocks remote unsends while allowing local deletes.
// IGDirectMessageUpdate._removeMessages_reason: 0 = unsend, 2 = delete-for-you.
// Delete-for-you fires reason=2 then reason=0 follow-up — tracked with a counter.
// Remote unsend fires only reason=0 — blocked when counter is 0 and not local.

static BOOL sciKeepDeletedEnabled() {
    return [SCIUtils getBoolPref:@"keep_deleted_message"];
}

static BOOL sciIndicateUnsentEnabled() {
    return [SCIUtils getBoolPref:@"indicate_unsent_messages"];
}

static void sciUpdateCellIndicator(id cell);
static BOOL sciLocalDeleteInProgress = NO;
static NSMutableArray *sciPendingUpdates = nil;
static NSInteger sciDeleteForYouCount = 0;
static NSMutableSet *sciPreservedIds = nil;

#define SCI_PRESERVED_IDS_KEY @"SCIPreservedMsgIds"
#define SCI_PRESERVED_MAX 200
#define SCI_PRESERVED_TAG 1399

static NSMutableSet *sciGetPreservedIds() {
    if (!sciPreservedIds) {
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:SCI_PRESERVED_IDS_KEY];
        sciPreservedIds = saved ? [NSMutableSet setWithArray:saved] : [NSMutableSet set];
    }
    return sciPreservedIds;
}

static void sciSavePreservedIds() {
    NSMutableSet *ids = sciGetPreservedIds();
    while (ids.count > SCI_PRESERVED_MAX)
        [ids removeObject:[ids anyObject]];
    [[NSUserDefaults standardUserDefaults] setObject:[ids allObjects] forKey:SCI_PRESERVED_IDS_KEY];
}

static void sciClearPreservedIds() {
    [sciGetPreservedIds() removeAllObjects];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SCI_PRESERVED_IDS_KEY];
}

// ============ ALLOC TRACKING ============

static id (*orig_msgUpdate_alloc)(id self, SEL _cmd);
static id new_msgUpdate_alloc(id self, SEL _cmd) {
    id instance = orig_msgUpdate_alloc(self, _cmd);
    if (sciKeepDeletedEnabled() && instance) {
        if (!sciPendingUpdates) sciPendingUpdates = [NSMutableArray array];
        @synchronized(sciPendingUpdates) {
            [sciPendingUpdates addObject:instance];
            while (sciPendingUpdates.count > 10)
                [sciPendingUpdates removeObjectAtIndex:0];
        }
    }
    return instance;
}

// ============ REMOTE UNSEND DETECTION ============

static BOOL sciConsumeRemoteUnsend() {
    if (!sciPendingUpdates) return NO;

    BOOL shouldBlock = NO;
    @synchronized(sciPendingUpdates) {
        for (id update in [sciPendingUpdates copy]) {
            @try {
                Ivar removeIvar = class_getInstanceVariable([update class], "_removeMessages_messageKeys");
                if (!removeIvar) continue;
                NSArray *keys = object_getIvar(update, removeIvar);
                if (!keys || keys.count == 0) continue;

                long long reason = -1;
                Ivar reasonIvar = class_getInstanceVariable([update class], "_removeMessages_reason");
                if (reasonIvar) {
                    ptrdiff_t off = ivar_getOffset(reasonIvar);
                    reason = *(long long *)((char *)(__bridge void *)update + off);
                }

                if (reason == 2) {
                    sciDeleteForYouCount++;
                    continue;
                }

                if (reason == 0 && !sciLocalDeleteInProgress) {
                    if (sciDeleteForYouCount > 0) {
                        sciDeleteForYouCount--;
                        continue;
                    }
                    for (id key in keys) {
                        Ivar sidIvar = class_getInstanceVariable([key class], "_messageServerId");
                        if (sidIvar) {
                            NSString *sid = object_getIvar(key, sidIvar);
                            if ([sid isKindOfClass:[NSString class]] && sid.length > 0)
                                [sciGetPreservedIds() addObject:sid];
                        }
                    }
                    sciSavePreservedIds();
                    shouldBlock = YES;
                    break;
                }
            } @catch(id e) {}
        }
        [sciPendingUpdates removeAllObjects];
    }
    return shouldBlock;
}

// ============ CACHE UPDATE HOOK ============

static void (*orig_applyUpdates)(id self, SEL _cmd, id updates, id completion, id userAccess);
static void new_applyUpdates(id self, SEL _cmd, id updates, id completion, id userAccess) {
    if (sciKeepDeletedEnabled() && sciConsumeRemoteUnsend()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Update visible cell indicators
            Class cellClass = NSClassFromString(@"IGDirectMessageCell");
            if (cellClass) {
                UIWindow *window = [UIApplication sharedApplication].keyWindow;
                NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
                while (stack.count > 0) {
                    UIView *v = stack.lastObject;
                    [stack removeLastObject];
                    if ([v isKindOfClass:cellClass]) {
                        sciUpdateCellIndicator(v);
                        continue;
                    }
                    for (UIView *sub in v.subviews)
                        [stack addObject:sub];
                }
            }

            // Show pill notification
            if ([SCIUtils getBoolPref:@"unsent_message_toast"]) {
                UIView *hostView = [UIApplication sharedApplication].keyWindow;
                if (hostView) {
                    UIView *pill = [[UIView alloc] init];
                    pill.backgroundColor = [UIColor colorWithRed:0.85 green:0.15 blue:0.15 alpha:0.95];
                    pill.layer.cornerRadius = 18;
                    pill.layer.shadowColor = [UIColor blackColor].CGColor;
                    pill.layer.shadowOpacity = 0.4;
                    pill.layer.shadowOffset = CGSizeMake(0, 2);
                    pill.layer.shadowRadius = 8;
                    pill.translatesAutoresizingMaskIntoConstraints = NO;
                    pill.alpha = 0;

                    UILabel *label = [[UILabel alloc] init];
                    label.text = @"A message was unsent";
                    label.textColor = [UIColor whiteColor];
                    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
                    label.textAlignment = NSTextAlignmentCenter;
                    label.translatesAutoresizingMaskIntoConstraints = NO;
                    [pill addSubview:label];

                    [hostView addSubview:pill];

                    [NSLayoutConstraint activateConstraints:@[
                        [pill.topAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.topAnchor constant:8],
                        [pill.centerXAnchor constraintEqualToAnchor:hostView.centerXAnchor],
                        [pill.heightAnchor constraintEqualToConstant:36],
                        [label.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],
                        [label.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
                        [label.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:20],
                        [label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-20],
                    ]];

                    [UIView animateWithDuration:0.3 animations:^{ pill.alpha = 1; }];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [UIView animateWithDuration:0.3 animations:^{ pill.alpha = 0; } completion:^(BOOL f) {
                            [pill removeFromSuperview];
                        }];
                    });
                }
            }
        });
        return;
    }
    orig_applyUpdates(self, _cmd, updates, completion, userAccess);
}

// ============ LOCAL DELETE TRACKING ============

static void (*orig_removeMutation_execute)(id self, SEL _cmd, id handler, id pkg);
static void new_removeMutation_execute(id self, SEL _cmd, id handler, id pkg) {
    sciLocalDeleteInProgress = YES;
    orig_removeMutation_execute(self, _cmd, handler, pkg);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciLocalDeleteInProgress = NO;
    });
}

// ============ VISUAL INDICATOR ============

static NSString * _Nullable sciGetCellServerId(id cell) {
    @try {
        Ivar vmIvar = class_getInstanceVariable([cell class], "_viewModel");
        if (!vmIvar) return nil;
        id vm = object_getIvar(cell, vmIvar);
        if (!vm) return nil;

        SEL metaSel = NSSelectorFromString(@"messageMetadata");
        if (![vm respondsToSelector:metaSel]) return nil;
        id meta = ((id(*)(id,SEL))objc_msgSend)(vm, metaSel);
        if (!meta) return nil;

        Ivar keyIvar = class_getInstanceVariable([meta class], "_key");
        if (!keyIvar) return nil;
        id keyObj = object_getIvar(meta, keyIvar);
        if (!keyObj) return nil;

        Ivar sidIvar = class_getInstanceVariable([keyObj class], "_serverId");
        if (!sidIvar) return nil;
        NSString *serverId = object_getIvar(keyObj, sidIvar);
        return [serverId isKindOfClass:[NSString class]] ? serverId : nil;
    } @catch(id e) {}
    return nil;
}

static void sciUpdateCellIndicator(id cell) {
    UIView *view = (UIView *)cell;
    UIView *oldIndicator = [view viewWithTag:SCI_PRESERVED_TAG];

    if (!sciIndicateUnsentEnabled()) {
        if (oldIndicator) [oldIndicator removeFromSuperview];
        return;
    }

    NSString *serverId = sciGetCellServerId(cell);
    BOOL isPreserved = serverId && [sciGetPreservedIds() containsObject:serverId];

    if (isPreserved) {
        if (!oldIndicator) {
            Ivar bubbleIvar = class_getInstanceVariable([cell class], "_messageContentContainerView");
            UIView *bubble = bubbleIvar ? object_getIvar(cell, bubbleIvar) : nil;
            UIView *parent = bubble ?: view;

            UILabel *label = [[UILabel alloc] init];
            label.tag = SCI_PRESERVED_TAG;
            label.text = @"Unsent";
            label.font = [UIFont italicSystemFontOfSize:10];
            label.textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.9];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            // Add as subview of the bubble so it moves with the bubble during
            // long-press context menu animation (otherwise it stays on the cell
            // and gets exposed behind the bubble).
            [parent addSubview:label];

            [NSLayoutConstraint activateConstraints:@[
                [label.leadingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:4],
                [label.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],
            ]];
        }
    } else if (oldIndicator) {
        [oldIndicator removeFromSuperview];
    }
}

static void (*orig_configureCell)(id self, SEL _cmd, id vm, id ringSpec, id launcherSet);
static void new_configureCell(id self, SEL _cmd, id vm, id ringSpec, id launcherSet) {
    orig_configureCell(self, _cmd, vm, ringSpec, launcherSet);
    sciUpdateCellIndicator(self);
}

// ============ RUNTIME HOOKS ============

%ctor {
    Class msgUpdateClass = NSClassFromString(@"IGDirectMessageUpdate");
    if (msgUpdateClass) {
        MSHookMessageEx(object_getClass(msgUpdateClass), @selector(alloc),
                        (IMP)new_msgUpdate_alloc, (IMP *)&orig_msgUpdate_alloc);
    }

    Class cacheClass = NSClassFromString(@"IGDirectCacheUpdatesApplicator");
    if (cacheClass) {
        SEL sel = NSSelectorFromString(@"_applyThreadUpdates:completion:userAccess:");
        if (class_getInstanceMethod(cacheClass, sel))
            MSHookMessageEx(cacheClass, sel, (IMP)new_applyUpdates, (IMP *)&orig_applyUpdates);
    }

    Class cellClass = NSClassFromString(@"IGDirectMessageCell");
    if (cellClass) {
        SEL configSel = NSSelectorFromString(@"configureWithViewModel:ringViewSpecFactory:launcherSet:");
        if (class_getInstanceMethod(cellClass, configSel))
            MSHookMessageEx(cellClass, configSel,
                            (IMP)new_configureCell, (IMP *)&orig_configureCell);
    }

    Class removeMutationClass = NSClassFromString(@"IGDirectMessageOutgoingUpdateRemoveMessagesMutationProcessor");
    if (removeMutationClass) {
        SEL execSel = NSSelectorFromString(@"executeWithResultHandler:accessoryPackage:");
        if (class_getInstanceMethod(removeMutationClass, execSel))
            MSHookMessageEx(removeMutationClass, execSel,
                            (IMP)new_removeMutation_execute, (IMP *)&orig_removeMutation_execute);
    }

    if (![SCIUtils getBoolPref:@"indicate_unsent_messages"]) {
        sciClearPreservedIds();
    }
}
