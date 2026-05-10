#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Disable Story Tray Section
%hook IGStoryTraySectionController
+ (id)alloc {if ([SCIUtils getBoolPref:@"hide_stories_tray"]) {return nil;}return %orig;}
%end