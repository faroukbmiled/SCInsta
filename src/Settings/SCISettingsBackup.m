#import "SCISettingsBackup.h"
#import "TweakSettings.h"
#import "SCISetting.h"
#import "../Utils.h"
#import "../Tweak.h"
#import "../Features/ProfileAnalyzer/SCIProfileAnalyzerStorage.h"
#import "SCIBackupScopePickerVC.h"
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import "SCISearchBarStyler.h"

typedef NS_OPTIONS(NSInteger, SCIBackupScope) {
    SCIBackupScopeSettings = 1 << 0,   // preferences only (no lists, no analyzer)
    SCIBackupScopeLists    = 1 << 1,   // excluded chats / story users / embed domains
    SCIBackupScopeAnalyzer = 1 << 2,   // Profile Analyzer snapshots + header cache
};
static const SCIBackupScope SCIBackupScopeAll =
    SCIBackupScopeSettings | SCIBackupScopeLists | SCIBackupScopeAnalyzer;

// Export / import / reset for Settings, excluded lists, and analyzer data —
// scoped via SCIBackupScopePickerVC, written as v2 JSON with a v1 flat-file
// import path for back-compat.


@interface SCISettingsBackup ()
+ (void)showError:(NSString *)message;
+ (void)showSuccessHUD:(NSString *)message;
+ (void)presentApplyConfirmationForData:(NSData *)data;
+ (void)pickFromFiles;
@end

#pragma mark - Helper singleton (document picker delegate)

@interface SCIBackupHelper : NSObject <UIDocumentPickerDelegate>
@property (nonatomic) BOOL expectingExportPick;
@end

@implementation SCIBackupHelper

+ (instancetype)shared {
    static SCIBackupHelper *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SCIBackupHelper alloc] init]; });
    return s;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.expectingExportPick) {
        self.expectingExportPick = NO;
        [SCISettingsBackup showSuccessHUD:SCILocalized(@"Settings exported")];
        return;
    }
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL access = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (access) [url stopAccessingSecurityScopedResource];
    if (!data) {
        [SCISettingsBackup showError:SCILocalized(@"Could not read file.")];
        return;
    }
    [SCISettingsBackup presentApplyConfirmationForData:data];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.expectingExportPick = NO;
}

@end

#pragma mark - SCISettingsBackup

@implementation SCISettingsBackup

#pragma mark Key discovery

// Extra NSUserDefaults keys that aren't surfaced through a settings cell but
// still need to round-trip via export/import (lists, structured data, etc.).
+ (NSArray<NSString *> *)extraDataKeys {
    return @[
        @"excluded_threads",
        @"included_threads",
        @"excluded_story_users",
        @"included_story_users",
        @"embed_custom_domains",
    ];
}

+ (NSSet<NSString *> *)allPrefKeys {
    NSMutableSet *keys = [NSMutableSet set];
    // Settings UI (recursive — picks up every cell + menu)
    [self collectKeysFromSections:[SCITweakSettings sections] into:keys];
    // Every default registered by Tweak.x — covers prefs without a UI cell
    [keys addObjectsFromArray:[[SCIUtils sciRegisteredDefaults] allKeys]];
    // Manually-tracked storage (lists/dicts not exposed via registerDefaults)
    [keys addObjectsFromArray:[self extraDataKeys]];
    return keys;
}

// Settings-scope keys = allPrefKeys minus the list keys. Used when the user
// picks "Settings only" in the scope sheet — lists stay put on import/reset.
+ (NSSet<NSString *> *)settingsOnlyKeys {
    NSMutableSet *keys = [[self allPrefKeys] mutableCopy];
    [keys minusSet:[NSSet setWithArray:[self extraDataKeys]]];
    return keys;
}

+ (void)collectKeysFromSections:(NSArray *)sections into:(NSMutableSet *)keys {
    for (id section in sections) {
        if (![section isKindOfClass:[NSDictionary class]]) continue;
        NSArray *rows = ((NSDictionary *)section)[@"rows"];
        for (id row in rows) {
            if (![row isKindOfClass:[SCISetting class]]) continue;
            SCISetting *s = row;
            if (s.defaultsKey.length) [keys addObject:s.defaultsKey];
            if (s.baseMenu) [self collectKeysFromMenu:s.baseMenu into:keys];
            if (s.navSections) [self collectKeysFromSections:s.navSections into:keys];
        }
    }
}

+ (void)collectKeysFromMenu:(UIMenu *)menu into:(NSMutableSet *)keys {
    for (id child in menu.children) {
        if ([child isKindOfClass:[UIMenu class]]) {
            [self collectKeysFromMenu:child into:keys];
        } else if ([child isKindOfClass:[UICommand class]]) {
            id pl = [(UICommand *)child propertyList];
            if ([pl isKindOfClass:[NSDictionary class]]) {
                NSString *k = ((NSDictionary *)pl)[@"defaultsKey"];
                if ([k isKindOfClass:[NSString class]] && k.length) [keys addObject:k];
            }
        }
    }
}

#pragma mark Snapshot / serialize / apply

+ (NSDictionary *)snapshotCurrentSettings {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in [self allPrefKeys]) {
        id v = [d objectForKey:key];
        if (v && [NSJSONSerialization isValidJSONObject:@{@"v": v}]) {
            out[key] = v;
        }
    }
    return out;
}

+ (NSData *)serializeSettings:(NSDictionary *)settings {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:(settings ?: @{})
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&err];
    if (err) NSLog(@"[RyukGram] backup: serialize failed: %@", err);
    return data;
}

+ (NSDictionary *)parseSettingsFromData:(NSData *)data {
    if (!data) return nil;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *root = obj;
    NSDictionary *settings = root[@"settings"];
    if ([settings isKindOfClass:[NSDictionary class]]) return settings;
    return root;
}

+ (void)applySettings:(NSDictionary *)settings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSSet *known = [self allPrefKeys];
    for (NSString *key in known) [d removeObjectForKey:key];
    for (NSString *key in settings) {
        if ([known containsObject:key]) {
            [d setObject:settings[key] forKey:key];
        }
    }
    [d synchronize];
}

#pragma mark Helpers

+ (NSString *)timestampString {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    return [fmt stringFromDate:[NSDate date]];
}

+ (NSString *)prettyJSONForSettings:(NSDictionary *)settings {
    NSData *d = [self serializeSettings:settings];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
}

+ (void)showSuccessHUD:(NSString *)message {
    SCINotifySuccess(SCI_NOTIF_SETTINGS_ACTION, message, nil);
}

+ (void)showError:(NSString *)message {
    SCINotifyError(SCI_NOTIF_SETTINGS_ACTION, SCILocalized(@"Import failed"), message);
}

#pragma mark Scope picker

// Scope enum bits match SCIBackupScopePickerMask one-to-one, so the mask can
// be cast back and forth.
+ (void)presentScopePickerWithContinueTitle:(NSString *)continueTitle
                                     message:(NSString *)message
                                availableMask:(SCIBackupScope)available
                             initialSelection:(SCIBackupScope)initial
                                      payload:(NSDictionary *)payload
                                      handler:(void(^)(SCIBackupScope scope))handler {
    SCIBackupScopePickerVC *vc = [SCIBackupScopePickerVC new];
    vc.title = continueTitle;
    vc.continueTitle = continueTitle;
    vc.headerMessage = message;
    vc.availableScopes = (SCIBackupScopePickerMask)available;
    vc.initialSelection = (SCIBackupScopePickerMask)initial;
    vc.payload = payload;
    vc.onContinue = ^(SCIBackupScopePickerMask chosen) { handler((SCIBackupScope)chosen); };

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [topMostController() presentViewController:nav animated:YES completion:nil];
}

#pragma mark Scoped payload build / apply

+ (NSDictionary *)snapshotForScope:(SCIBackupScope)scope {
    NSMutableDictionary *root = [NSMutableDictionary dictionary];
    root[@"ryukgram_export"] = @(YES);
    root[@"version"] = @(2);
    root[@"exported_at"] = @([[NSDate date] timeIntervalSince1970]);

    NSDictionary *full = [self snapshotCurrentSettings];
    if (scope & SCIBackupScopeSettings) {
        NSMutableDictionary *s = [NSMutableDictionary dictionary];
        NSSet *listKeys = [NSSet setWithArray:[self extraDataKeys]];
        for (NSString *k in full) if (![listKeys containsObject:k]) s[k] = full[k];
        root[@"settings"] = s;
    }
    if (scope & SCIBackupScopeLists) {
        NSMutableDictionary *l = [NSMutableDictionary dictionary];
        for (NSString *k in [self extraDataKeys]) if (full[k]) l[k] = full[k];
        root[@"lists"] = l;
    }
    if (scope & SCIBackupScopeAnalyzer) {
        root[@"analyzer"] = [SCIProfileAnalyzerStorage exportedDict] ?: @{};
    }
    return root;
}

// Applies the intersection of payload sections and the chosen scope.
+ (BOOL)applyImport:(NSDictionary *)root scope:(SCIBackupScope)scope {
    if (![root isKindOfClass:[NSDictionary class]]) return NO;
    BOOL anyApplied = NO;

    NSDictionary *settings = [root[@"settings"] isKindOfClass:[NSDictionary class]] ? root[@"settings"] : nil;
    // v1 back-compat: file is a flat map of pref keys → value.
    if (!settings && !root[@"ryukgram_export"]) settings = root;

    if ((scope & SCIBackupScopeSettings) && settings) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSSet *keys = [self settingsOnlyKeys];
        for (NSString *k in keys) [d removeObjectForKey:k];
        for (NSString *k in settings) if ([keys containsObject:k]) [d setObject:settings[k] forKey:k];
        [d synchronize];
        anyApplied = YES;
    }
    if ((scope & SCIBackupScopeLists) && [root[@"lists"] isKindOfClass:[NSDictionary class]]) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        for (NSString *k in [self extraDataKeys]) [d removeObjectForKey:k];
        NSDictionary *lists = root[@"lists"];
        for (NSString *k in lists) if ([[self extraDataKeys] containsObject:k]) [d setObject:lists[k] forKey:k];
        [d synchronize];
        anyApplied = YES;
    }
    if ((scope & SCIBackupScopeAnalyzer) && [root[@"analyzer"] isKindOfClass:[NSDictionary class]]) {
        [SCIProfileAnalyzerStorage importFromDict:root[@"analyzer"]];
        anyApplied = YES;
    }
    return anyApplied;
}

+ (void)resetForScope:(SCIBackupScope)scope {
    if (scope & SCIBackupScopeSettings) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        for (NSString *k in [self settingsOnlyKeys]) [d removeObjectForKey:k];
        [d synchronize];
    }
    if (scope & SCIBackupScopeLists) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        for (NSString *k in [self extraDataKeys]) [d removeObjectForKey:k];
        [d synchronize];
    }
    if (scope & SCIBackupScopeAnalyzer) {
        [SCIProfileAnalyzerStorage resetAll];
    }
}

#pragma mark Export

+ (void)presentExport {
    NSDictionary *preview = [self snapshotForScope:SCIBackupScopeAll];
    [self presentScopePickerWithContinueTitle:SCILocalized(@"Export")
                                       message:SCILocalized(@"Tick what to include. Tap any row to inspect its contents.")
                                 availableMask:SCIBackupScopeAll
                              initialSelection:SCIBackupScopeAll
                                       payload:preview
                                       handler:^(SCIBackupScope scope) {
        // Rebuild payload against the final selection.
        NSDictionary *payload = [self snapshotForScope:scope];
        [self writeExportToFilePicker:payload host:topMostController()];
    }];
}

+ (void)writeExportToFilePicker:(NSDictionary *)payload host:(UIViewController *)host {
    NSData *data = [self serializeSettings:payload];
    NSString *fname = [NSString stringWithFormat:@"ryukgram-export-%@.json", [self timestampString]];
    NSURL *tmp = [[NSFileManager defaultManager].temporaryDirectory URLByAppendingPathComponent:fname];
    NSError *err = nil;
    [data writeToURL:tmp options:NSDataWritingAtomic error:&err];
    if (err) { [self showError:SCILocalized(@"Could not write temporary file.")]; return; }
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initForExportingURLs:@[tmp]];
    SCIBackupHelper *helper = [SCIBackupHelper shared];
    helper.expectingExportPick = YES;
    p.delegate = helper;
    [host presentViewController:p animated:YES completion:nil];
}

#pragma mark Import

+ (void)presentImport {
    // File first, then scope picker against its contents.
    [self pickFromFiles];
}

+ (void)presentReset {
    NSDictionary *preview = [self snapshotForScope:SCIBackupScopeAll];
    [self presentScopePickerWithContinueTitle:SCILocalized(@"Reset")
                                       message:SCILocalized(@"Selected data will be cleared. Tap any row to see what's stored.")
                                 availableMask:SCIBackupScopeAll
                              initialSelection:0
                                       payload:preview
                                       handler:^(SCIBackupScope scope) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:SCILocalized(@"Reset selected data?")
                             message:SCILocalized(@"This can't be undone.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Reset")
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *a) {
            [self resetForScope:scope];
            if (scope & SCIBackupScopeSettings) [SCIUtils showRestartConfirmation];
            else [self showSuccessHUD:SCILocalized(@"Reset complete")];
        }]];
        [topMostController() presentViewController:alert animated:YES completion:nil];
    }];
}

+ (void)pickFromFiles {
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.json", @"public.text", @"public.data"]
                                                                inMode:UIDocumentPickerModeImport];
    p.delegate = [SCIBackupHelper shared];
    p.allowsMultipleSelection = NO;
    [topMostController() presentViewController:p animated:YES completion:nil];
}

+ (void)presentApplyConfirmationForData:(NSData *)data {
    NSError *parseErr = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseErr];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        [self showError:SCILocalized(@"File is not a valid RyukGram export.")];
        return;
    }
    NSDictionary *root = parsed;

    // Offer only the sections actually present in the file.
    SCIBackupScope available = 0;
    if ([root[@"settings"] isKindOfClass:[NSDictionary class]]) available |= SCIBackupScopeSettings;
    if ([root[@"lists"] isKindOfClass:[NSDictionary class]]) available |= SCIBackupScopeLists;
    if ([root[@"analyzer"] isKindOfClass:[NSDictionary class]]) available |= SCIBackupScopeAnalyzer;
    // v1 back-compat: flat pref map → treat as settings-only.
    if (!available && !root[@"ryukgram_export"]) available = SCIBackupScopeSettings;
    if (!available) { [self showError:SCILocalized(@"File has no importable sections.")]; return; }

    // Wrap v1 flat files into the v2 envelope for the picker.
    NSDictionary *normalized = root[@"ryukgram_export"] ? root : @{ @"settings": root };

    [self presentScopePickerWithContinueTitle:SCILocalized(@"Apply")
                                       message:SCILocalized(@"Tick what to apply. Tap any row to inspect. Sections not in the file are disabled.")
                                 availableMask:available
                              initialSelection:available
                                       payload:normalized
                                       handler:^(SCIBackupScope scope) {
        UIAlertController *confirm = [UIAlertController
            alertControllerWithTitle:SCILocalized(@"Apply imported data?")
                             message:SCILocalized(@"Existing values for the selected scope will be replaced. The app may need to restart for some changes to take effect.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Apply") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
            BOOL applied = [self applyImport:root scope:scope];
            if (!applied) { [self showError:SCILocalized(@"Nothing was applied.")]; return; }
            [self showSuccessHUD:SCILocalized(@"Import complete")];
            if (scope & SCIBackupScopeSettings) [SCIUtils showRestartConfirmation];
        }]];
        [topMostController() presentViewController:confirm animated:YES completion:nil];
    }];
}

@end
