// Copy note text on long press — long-press the note bubble to copy text.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>

// IGDirectNotesThoughtBubbleView declared in InstagramHeaders.h

%hook IGDirectNotesThoughtBubbleView

- (void)layoutSubviews {
    %orig;
    if (![SCIUtils getBoolPref:@"profile_note_copy"]) return;

    // Only add once
    static const NSInteger kCopyGestureTag = 99791;
    for (UIGestureRecognizer *gr in self.gestureRecognizers) {
        if (gr.view.tag == kCopyGestureTag) return;
    }
    self.tag = kCopyGestureTag;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(sciCopyNoteLongPress:)];
    lp.minimumPressDuration = 0.5;
    [self addGestureRecognizer:lp];
}

%new - (void)sciCopyNoteLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    Ivar textIvar = class_getInstanceVariable([self class], "_noteText");
    if (!textIvar) return;
    NSString *text = object_getIvar(self, textIvar);
    if (!text.length) return;

    [[UIPasteboard generalPasteboard] setString:text];
    SCINotifySuccess(SCI_NOTIF_COPY_NOTE, SCILocalized(@"Note copied"), nil);
}

%end
