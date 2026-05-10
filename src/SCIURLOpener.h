// Routes URLs into IG: https IG hosts via `continueUserActivity:`, `instagram://`
// via the delegate's `openURL:options:`, redirectors (l.instagram.com/?u=…)
// unwrapped first. Anything else falls back to system openURL.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIURLOpener : NSObject

+ (BOOL)openURL:(NSURL * _Nullable)url;
+ (BOOL)openURLString:(NSString * _Nullable)urlString;

// Dismisses the topmost presented chain rooted at `presenter` before opening.
+ (BOOL)dismiss:(UIViewController * _Nullable)presenter thenOpenURL:(NSURL * _Nullable)url;

// Profile deep link with web fallback when the instagram scheme is unavailable.
+ (BOOL)openInstagramProfileForUsername:(NSString * _Nullable)username;
+ (BOOL)dismiss:(UIViewController * _Nullable)presenter thenOpenInstagramProfileForUsername:(NSString * _Nullable)username;

@end

NS_ASSUME_NONNULL_END
