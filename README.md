# RyukGram
A feature-rich iOS tweak for Instagram, forked from [SCInsta](https://github.com/SoCuul/SCInsta) with additional features and fixes.\
`Version v1.2.0` | `Tested on Instagram 425.0.0`

---

> [!NOTE]
> To modify RyukGram's settings, check out [this section below](#opening-tweak-settings) for help

---

# Installation
>[!IMPORTANT]
> Which type of device are you planning on installing this tweak on?
> - Jailbroken/TrollStore device -> [Download pre-built tweak](https://github.com/faroukbmiled/RyukGram/releases/latest)
> - Standard iOS device -> Sideload the .deb using Feather or similar

# Features
> Features marked with **\*** are new or improved in RyukGram

### General
- Hide ads
- Hide Meta AI
- Hide metrics (likes, comments, shares counts)
- Disable app haptics
- Copy description
- Copy comment text from long-press menu **\***
- Download GIF comments **\***
- Profile copy button **\***
- Replace domain in shared links — rewrite copied/shared links for embeds in Discord, Telegram, etc. with preset or custom domains **\***
- Strip tracking params from shared links (igsh, utm) **\***
- Open links in external browser **\***
- Strip tracking from browser links **\***
- Do not save recent searches
- Use detailed (native) color picker
- Enable liquid glass buttons
- Enable liquid glass surfaces — floating tab bar, dynamic sizing, and other UI elements **\***
- Enable teen app icons
- IG Notes:
  - Hide notes tray
  - Hide friends map
  - Enable note theming
  - Custom note themes
- Focus/Distractions
  - No suggested users
  - No suggested chats
  - Hide trending searches
  - Hide explore posts grid

### Feed
- Hide stories tray
- Hide suggested stories — removes suggested accounts from the stories tray **\***
- View profile picture from story tray long-press menu (HD via API) **\***
- Hide entire feed
- No suggested posts
- No suggested for you (accounts)
- No suggested reels
- No suggested threads posts
- Disable video autoplay
- Media zoom — long press on media to expand in full-screen viewer **\***
- Custom date format (moved to General > Date format, now supports feed, notes/comments/stories, and DMs) **\***
- Disable background refresh, home button refresh, and home button scroll **\***
- Disable reels tab button refresh **\***
- Hide repost button in feed **\***

### Reels
- Modify tap controls
- Auto-scroll reels — IG default or RyukGram mode (keeps advancing after swiping back) **\***
- Always show progress scrubber
- Disable auto-unmuting reels (properly blocks mute switch, volume buttons, and announcer broadcasts) **\***
- Confirm reel refresh
- Unlock password-locked reels **\***
- Hide reels header
- Hide repost button in reels **\***
- Hide reels blend button
- Disable scrolling reels
- Prevent doom scrolling (limit maximum viewable reels)
- Enhanced Pause/Play mode (when Pause/Play tap control is set): **\***
  - Mute toggle auto-hidden, only play/pause icon visible
  - Audio forced on in reels tab
  - Play indicator properly hidden when video plays (fixes IG bug after hold/zoom)
  - Playback toggle synced with overlay during hold/zoom
  - Works across IG A/B test variants

### Action buttons **\***
- Context-aware action menu on feed, reels, and stories (expand, repost, download, copy caption, etc.) **\***
- Configurable default tap action per context **\***
- Carousel and multi-story reel support with bulk download **\***
- Repost via IG's native creation flow **\***
- Full-screen media viewer with zoom and swipe **\***
- Story playback pauses when menus are open **\***

### Profile **\***
- Zoom profile photo — long press to view full-screen with user info **\***
- Save profile picture
- View highlight cover from profile long-press menu **\***
- Profile copy button **\***
- Follow indicator — shows whether the user follows you **\***
- Copy note on long press — long-press the note bubble to copy text **\***

### Saving
- Enhanced HD downloads — up to 1080p via DASH + FFmpegKit **\***
  - Quality picker with preview playback **\***
  - Fallback to 720p without FFmpegKit **\***
- Download pill with frosted glass, progress bar, bulk counter, success/error states **\***
- Save to RyukGram album — routes downloads into a dedicated album in Photos **\***
- Download confirmation — optional dialog before downloading **\***
- Legacy long-press gesture — deprecated, off by default. Finger count + hold time customizable **\***

### Stories and messages
- Keep deleted messages (preserves unsent messages with visual indicator and notification pill) **\***
- Hide trailing action buttons on preserved messages
- Warn before clearing on refresh — optional confirmation when pulling to refresh the DMs tab if preserved messages would be cleared **\***
- Manually mark messages as seen (button or toggle mode) **\***
- Long-press the seen button for quick actions **\***
- Auto mark seen on send (marks messages as read when you send any message) **\***
- Auto mark seen on typing (marks messages as read the moment you start typing, even when typing status is hidden) **\***
- Mark seen on story like **\***
- Mark seen on story reply — also covers text replies and emoji reactions **\***
- Advance to next story when marking as seen — tapping the eye button auto-skips to the next story **\***
- Advance on story like — liking a story auto-skips to the next one **\***
- Advance on story reply — sending a reply or emoji reaction auto-skips to the next story **\***
- Per-chat read-receipt list with blocking mode — "Block all" (exclude list) or "Block selected only" (include list). Long-press any DM chat to add/remove. Settings page with search, sort, multi-select, and per-entry keep-deleted override **\***
- Send audio as file — send audio files as voice messages from the DM plus menu **\***
- Download voice messages — adds a Download option to the long-press menu on voice messages, saves as M4A via share sheet **\***
- Disable typing status
- Disable disappearing messages mode — blocks the swipe-to-enable gesture in DMs **\***
- Hide voice/video call buttons — independent toggles for each, remaining nav items reflow dynamically **\***
- Unlimited replay of direct stories (toggle in eye button menu) **\***
- Full last active date — show full date instead of relative time **\***
- Send files in DMs (experimental) — send select file types via the plus menu **\***
- Notes actions — copy text, download GIF/audio from notes long-press menu **\***
- Copy note text on long press **\***
- Disable view-once limitations
- Disable screenshot detection
- Disable story seen receipt (blocks network upload, toggleable at runtime without restart) **\***
- Keep stories visually seen locally — mark stories as seen locally (grey ring) while the seen receipt is still blocked on the server **\***
- Manual mark story as seen — button on story overlay to selectively mark stories as seen (button or toggle mode) **\***
- Long-press the story seen button for quick actions **\***
- Per-user story seen-receipt list with blocking mode — "Block all" (exclude list) or "Block selected only" (include list). Manage via 3-dot menu, eye button long-press, or settings list **\***
- Story audio mute/unmute toggle — button on overlay and in action menu to toggle audio **\***
- View story mentions — bottom sheet with profile pic, follow/unfollow, tap-to-open profile **\***
- Stop story auto-advance — stories won't auto-skip when the timer ends **\***
- Download disappearing DM media (photos + videos) — expand, share, or save from action menu **\***
- Mark disappearing messages as viewed button **\***
- Upload audio as voice message — send audio files, extract audio from videos, with built-in trim editor **\***
- Disable instants creation

### Navigation
- Modify tab bar icon order
- Modify swiping between tabs
- Hiding tabs
  - Hide feed tab
  - Hide explore tab
  - Hide reels tab
  - Hide create tab
  - Hide messages tab
- Messages-only mode — keep DM inbox + profile, hide everything else, force launch into inbox **\***
- Launch tab — pick which tab the app opens to (ignored in Messages-only mode) **\***

### Confirm actions
- Confirm like: Posts/Stories
- Confirm like: Reels
- Confirm follow
- Confirm unfollow **\***
- Confirm repost
- Confirm call
- Confirm voice messages
- Confirm follow requests
- Confirm shh mode (disappearing messages)
- Confirm posting comment
- Confirm changing direct message theme
- Confirm sticker interaction

### Fake location **\***
- Overrides CoreLocation app-wide so any IG feature reading a coord (Friends Map, posts, etc.) gets your chosen location
- MapKit picker with search + reverse-geocoded names
- Saved presets — tap to apply
- Quick toggle button injected into the Friends Map: enable/disable, swap presets, change location, open settings

### Tweak settings **\***
- Search bar in the main settings page — recursively finds any setting across nested pages with a breadcrumb to its location
- Pause playback when opening settings (toggleable) **\***
- Quick-access via long-press on feed tab **\***

### Backup & Restore **\***
- Export RyukGram settings as a JSON file
- Import settings from a JSON file
- Searchable, collapsible, editable preview before saving or applying

### Localization **\***
- Multi-language UI — every user-facing string in RyukGram flows through a central translation layer **\***
- Built-in language picker — globe icon in the top-right of Settings; pick System default or any shipped language **\***
- Falls back to English when a translation is missing, so nothing ever breaks **\***
- Currently shipping: **English**, **Spanish** — other languages land as translators submit them (see below).

### Optimization
- Automatically clears unneeded cache folders, reducing the size of your Instagram installation

# Translating RyukGram
Want to see RyukGram in your language? Two ways:

### Option A: In-app (fastest)
1. Open **Settings → Debug → Localization → Export English strings** — share the base `.strings` file to yourself.
2. Translate the **right-hand side** of every `"key" = "value";` line. Never touch the left-hand side.
3. Go to **Debug → Localization → Update → + Add new language** — enter your language code (e.g. `fr`), pick the translated file, restart.
4. Your language now appears in the globe menu. Test it, tweak it, re-import as needed.
5. When ready, open a pull request with the file at `src/Localization/Resources/<code>.lproj/Localizable.strings`.

### Option B: PR directly
1. Copy `src/Localization/Resources/en.lproj/Localizable.strings` into a new folder: `<code>.lproj/Localizable.strings`
2. Translate the right-hand side of every line.
3. Keep format specifiers (`%@`, `%lu`, `%d`, `%1$@`…) exactly as-is. Use positional specifiers if your language needs different word order.
4. Keep section banners and structure — makes the diff easy to review.
5. Open a PR at <https://github.com/faroukbmiled/RyukGram/pulls>. Title it e.g. `l10n: Add French translation`.

Partial translations are welcome — untranslated keys fall back to English at runtime.

If you find a string that still renders in English on a translated build, open an issue with a screenshot.

## Known Issues
- Preserved unsent messages cannot be removed using "Delete for you". Pull to refresh in the DMs tab clears all preserved messages (with optional confirmation if "Warn before clearing on refresh" is enabled).
- "Delete for you" detection uses a ~2 second window after the local action. If a real other-party unsend happens to land in the same window, it may not be preserved. Rare in practice and limited to that specific overlap.

# Opening Tweak Settings

|                                             |                                             |
|:-------------------------------------------:|:-------------------------------------------:|
| <img src="https://i.imgur.com/uPMcugZ.png"> | <img src="https://i.imgur.com/ctIiL7i.png"> |

# Building from source
### Prerequisites
- XCode + Command-Line Developer Tools
- [Homebrew](https://brew.sh/#install)
- [CMake](https://formulae.brew.sh/formula/cmake#default) (`brew install cmake`)
- [Theos](https://theos.dev/docs/installation)
- [cyan](https://github.com/asdfzxcvbn/pyzule-rw?tab=readme-ov-file#install-instructions) **\*only required for sideloading**
- [ipapatch](https://github.com/asdfzxcvbn/ipapatch/releases/latest) **\*only required for sideloading**

### Setup
1. Install iOS 16.2 frameworks for theos
   1. [Click to download iOS SDKs](https://github.com/xybp888/iOS-SDKs/archive/refs/heads/master.zip)
   2. Unzip, then copy the `iPhoneOS16.2.sdk` folder into `~/theos/sdks`
2. Clone repo: `git clone --recurse-submodules https://github.com/faroukbmiled/RyukGram`
3. **For sideloading**: Download a decrypted Instagram IPA from a trusted source, making sure to rename it to `com.burbn.instagram.ipa`.
   Then create a folder called `packages` inside of the project folder, and move the Instagram IPA file into it.

### Run build script
```sh
$ chmod +x build.sh
$ ./build.sh <sideload/rootless/rootful>
```

# Credits
- [SCInsta](https://github.com/SoCuul/SCInsta) by [@SoCuul](https://github.com/SoCuul) — original tweak this fork is based on
- [@BandarHL](https://github.com/BandarHL) — creator of the original BHInstagram project
- [@faroukbmiled](https://github.com/faroukbmiled) — RyukGram modifications and additional features
- [@euoradan](https://t.me/euoradan) (Radan) — experimental Instagram feature flag research
- [@erupts0](https://github.com/erupts0) (John) — testing and feature suggestions
- [BillyCurtis/OpenInstagramSafariExtension](https://github.com/BillyCurtis/OpenInstagramSafariExtension) — base for the bundled Safari extension
- Furamako — Spanish translation
