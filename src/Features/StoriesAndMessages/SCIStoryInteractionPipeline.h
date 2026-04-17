// Story interaction pipeline — confirm gate + seen/advance per policy table.

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SCIStoryInteraction) {
    SCIStoryInteractionLike,
    SCIStoryInteractionEmojiReaction,
    SCIStoryInteractionTextReply,
};

void sciStoryInteraction(SCIStoryInteraction type,
                         void (^action)(void),
                         void (^_Nullable uiRevert)(void),
                         void (^_Nullable uiReapply)(void));

// Side-effects only (seen/advance). No confirm, no action.
void sciStoryInteractionSideEffects(SCIStoryInteraction type);
