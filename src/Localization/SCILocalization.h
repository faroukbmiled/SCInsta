#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// Localization pref key — value is BCP-47 code ("en", "ar", "es") or "system".
extern NSString *const SCILanguagePrefKey;

// Resource bundle (RyukGram.bundle) shipped next to the dylib.
// Returns nil only on broken installs; callers fall back to the key itself.
NSBundle * _Nullable SCILocalizationBundle(void);

// Fresh lookup each call — cheap enough (NSBundle caches strings files internally).
// `fallback` is returned when the key is missing. Pass the English source text.
NSString *SCILocalizedString(NSString *key, NSString * _Nullable fallback);

// Languages we actually ship. `system` means "follow iOS locale".
// Ordered for the picker UI; first entry is always "system".
NSArray<NSDictionary<NSString *, NSString *> *> *SCIAvailableLanguages(void);

// Currently-active language code ("en", "ar", …) after resolving "system".
NSString *SCIResolvedLanguageCode(void);

// Invalidate cached bundles/strings after a language switch.
void SCILocalizationReset(void);

// Writable path for user-imported lproj overrides (Library/RyukGram.bundle/).
NSString *SCILocalizationOverridePath(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

// Convenience macro — key doubles as English fallback so missing translations
// degrade gracefully to the source text.
#define SCILocalized(key) SCILocalizedString((key), (key))
