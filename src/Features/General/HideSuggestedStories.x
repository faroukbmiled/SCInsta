// Hide suggested stories from the tray. Only filters when suggested items
// are present — skips clean inputs to avoid IGListKit diff cascade.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static BOOL sciIsSuggestedTrayItem(id obj) {
    if (![NSStringFromClass([obj class]) isEqualToString:@"IGStoryTrayViewModel"]) return NO;

    @try {
        if ([[obj valueForKey:@"isCurrentUserReel"] boolValue]) return NO;

        id owner = [obj valueForKey:@"reelOwner"];
        if (!owner) return NO;

        Ivar userIvar = class_getInstanceVariable([owner class], "_userReelOwner_user");
        if (!userIvar) return NO;
        id igUser = object_getIvar(owner, userIvar);
        if (!igUser) return NO;

        Ivar fcIvar = NULL;
        for (Class c = [igUser class]; c && !fcIvar; c = class_getSuperclass(c))
            fcIvar = class_getInstanceVariable(c, "_fieldCache");
        if (!fcIvar) return NO;

        id fc = object_getIvar(igUser, fcIvar);
        if (![fc isKindOfClass:[NSDictionary class]]) return NO;
        if ([(NSDictionary *)fc count] == 0) return YES;

        id fs = [(NSDictionary *)fc objectForKey:@"friendship_status"];
        if (!fs) return NO;

        return ![[fs valueForKey:@"following"] boolValue];
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static NSArray *(*orig_objectsForListAdapter)(id, SEL, id);
static NSArray *hook_objectsForListAdapter(id self, SEL _cmd, id adapter) {
    NSArray *objects = orig_objectsForListAdapter(self, _cmd, adapter);

    if (![SCIUtils getBoolPref:@"hide_suggested_stories"]) return objects;

    // Pass through unchanged when input has no suggestions (avoids cascade).
    BOOL hasSuggested = NO;
    for (id obj in objects) {
        if (sciIsSuggestedTrayItem(obj)) { hasSuggested = YES; break; }
    }
    if (!hasSuggested) return objects;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:objects.count];
    for (id obj in objects) {
        if (!sciIsSuggestedTrayItem(obj)) [filtered addObject:obj];
    }
    return [filtered copy];
}

%ctor {
    Class dsCls = NSClassFromString(@"IGStoryTrayListAdapterDataSource");
    if (!dsCls) return;

    SEL sel = NSSelectorFromString(@"objectsForListAdapter:");
    if (class_getInstanceMethod(dsCls, sel))
        MSHookMessageEx(dsCls, sel, (IMP)hook_objectsForListAdapter, (IMP *)&orig_objectsForListAdapter);
}
