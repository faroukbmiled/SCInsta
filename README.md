# RyukGram
A feature-rich iOS tweak for Instagram, forked from [SCInsta](https://github.com/SoCuul/SCInsta) with additional features and fixes.\
`Version v1.2.3` | `Tested on Instagram 426.0.0`

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
- Download / copy GIF comments **\***
- Custom GIF in comments — long-press the GIF button to paste any Giphy link **\***
- Download audio from the reels audio page **\***
- Profile copy button **\***
- Replace domain in shared links for embeds (Discord, Telegram, etc.) **\***
- Strip tracking params from shared links **\***
- Open links in external browser **\***
- Strip tracking from browser links **\***
- Do not save recent searches
- Open link from clipboard — long-press the search tab **\***
- Use detailed (native) color picker
- Enable liquid glass buttons
- Enable liquid glass surfaces **\***
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
  - Skip sensitive content covers **\***
- Live
  - Anonymous live viewing **\***
  - Toggle live comments **\***
- Privacy
  - Hide RyukGram UI on screenshots, screen recordings, and mirroring **\***

### Feed
- Hide stories tray
- Hide suggested stories **\***
- View profile picture from story tray long-press menu **\***
- Hide entire feed
- No suggested posts
- No suggested for you (accounts)
- No suggested reels
- No suggested threads posts
- Disable video autoplay
- Media zoom — long press media to expand in full-screen viewer **\***
- Start media muted — expanded videos open with sound off **\***
- Custom date format — feed, notes/comments/stories, and DMs **\***
- Disable background refresh, home button refresh, and home button scroll **\***
- Disable reels tab button refresh **\***
- Hide repost button in feed **\***

### Reels
- Modify tap controls
- Auto-scroll reels mode **\***
- Always show progress scrubber
- Disable auto-unmuting reels **\***
- Confirm reel refresh
- Unlock password-locked reels **\***
- Hide reels header
- Hide repost button in reels **\***
- Hide friends avatars on the reels Friends tab **\***
- Hide social context overlay on reels (reposted/commented bubbles) **\***
- Hide "Made with Edits" / "Open in Edits" promo pills on reels **\***
- Hide reels blend button
- Disable scrolling reels
- Prevent doom scrolling (limit maximum viewable reels)
- Enhanced Pause/Play mode (when Pause/Play tap control is set): **\***
  - Mute toggle auto-hidden
  - Audio forced on in reels tab
  - Play indicator hidden during playback
  - Playback toggle synced with overlay during hold/zoom
  - Optional tap-to-mute on photo reels

### Action buttons **\***
- Context-aware action menu on feed, reels, and stories **\***
- Configurable default tap action per context **\***
- Global icon picker — change the icon used across feed, stories, reels and DMs **\***
- Optional date header at the top of the action menu **\***
- Carousel and multi-story reel support with bulk download **\***
- Repost via IG's native creation flow **\***
- Full-screen media viewer with zoom and swipe **\***
- Story playback pauses when menus are open **\***

### Profile **\***
- Zoom profile photo — long press to view full-screen **\***
- Save profile picture
- View highlight cover from profile long-press menu **\***
- Profile copy button **\***
- Follow indicator — shows whether the user follows you (off / on / colored) **\***
- Copy note on long press **\***
- Fake profile stats — verified badge and follower/following/post counts **\***

### Profile Analyzer (beta) **\***
- Follower and following scans with progress and cancel **\***
- Mutuals and non-followbacks lists **\***
- New and lost followers/following trackers across scans **\***
- Profile change history — username, name, bio, pfp **\***
- Searchable lists with inline and batch follow/unfollow **\***
- Visited profiles tracker — log every profile you open with date / verified / private filters **\***
- Pull-to-refresh on the visited list re-syncs identity and pictures from IG **\***

### Saving
- Enhanced HD downloads up to 1080p **\***
  - Quality picker with preview playback **\***
  - Audio-only and raw photo download options **\***
  - Fallback to 720p without FFmpegKit **\***
- Download pill with progress bar and bulk counter **\***
- Save to RyukGram album — every download + share-sheet "Save to Photos" routes into a dedicated album **\***
- Enhanced media resolution — IG's CDN ships higher-quality images **\***
- Download confirmation dialog **\***
- Output filenames formatted as `@username_context_timestamp` across every save surface (feed / reels / DMs / notes / comments / disappearing media) **\***
- Legacy long-press gesture (deprecated, customizable finger count + hold time) **\***

### Gallery **\***
- On-device gallery — every download can mirror into an in-app library **\***
- Stores images, videos, audio (m4a/aac/mp3/ogg/opus/...) and animated GIFs **\***
- Filter chips by type, source (feed / reels / stories / DMs / profile / notes / comments) and uploader; favorites; folders **\***
- In-app preview carousel — image / video / audio scrubber / GIF playback **\***
- Audio + GIF picker — DM Upload Audio and (in future surfaces) Comment GIF can pull straight from the gallery **\***
- "Download to Gallery" submenu on every download surface when the gallery is enabled, with Photos / Gallery / Share options for audio **\***

### Stories and messages
- Keep deleted messages **\***
- Deleted messages log — dedicated UI for unsent texts, photos, videos, voice (inline play + scrub), GIFs, stickers and shared posts; per-sender groups, search, multi-kind filter, bulk select with Save / Share / Delete **\***
- Hide trailing action buttons on preserved messages
- Warn before pull-to-refresh clears preserved messages **\***
- Manually mark messages as seen (button or toggle mode) **\***
- Long-press the seen button for quick actions **\***
- Auto mark seen on send **\***
- Auto mark seen on typing **\***
- Mark seen on story like **\***
- Mark seen on story reply **\***
- Advance to next story when marking as seen **\***
- Advance on story like **\***
- Advance on story reply **\***
- Per-chat read-receipt exclusion list with Block all / Block selected mode **\***
- Send audio as file — DM plus menu, or long-press the camera button while replying **\***
- Download voice messages **\***
- Disable typing status
- Disable vanish mode swipe **\***
- Hide voice/video call buttons (independent toggles) **\***
- Hide send to group chat in the share sheet **\***
- Bypass DM character limit **\***
- Pin recipients on long-press in the share sheet — pinned chats render at the top **\***
- Unlimited replay of direct stories **\***
- Full last active date **\***
- Send files in DMs (experimental) **\***
- Hold the DM tab button to open the on-device gallery **\***
- Notes actions — copy text, download GIF / audio (Photos or Gallery) **\***
- Copy note text on long press **\***
- Disable view-once limitations
- Disable screenshot detection
- Disable story seen receipt **\***
- Keep stories visually seen locally **\***
- Manual mark story as seen (button or toggle mode) **\***
- Long-press the story seen button for quick actions **\***
- Per-user story seen-receipt exclusion list with Block all / Block selected mode **\***
- Story audio mute/unmute toggle **\***
- View story mentions, with optional quick-access overlay button **\***
- Stop story auto-advance **\***
- Reveal poll/slider vote counts and quiz answers on stories and reels before interacting **\***
- Force legacy Quiz and Reveal stickers back into the story composer tray **\***
- Bypass Reveal sticker — view stories blurred behind a Reveal sticker without DMing the author **\***
- Allow video in photo sticker — story photo sticker picker accepts videos too **\***
- Custom solid or gradient color for music and lyric stickers **\***
- Disappearing DM media overlay — action button, mark-as-viewed eye, and audio toggle **\***
- Download disappearing DM media **\***
- Upload audio as voice message with built-in trim editor **\***
- Disable instants creation
- Send Instants from your photo album — gallery button on the Instants camera with a built-in square cropper, posts through IG's native capture flow; pick from the in-app gallery or Photos library when the gallery is enabled
- Allow screenshots on Instants — bypasses the screenshot/screen-record block, scoped to the Instants viewer only
- Instants action button — Expand / Save (Photos / Gallery) / Share / Save all, fully configurable through the standard action-menu config
- Confirm Instants emoji reaction — optional confirmation before a quick-reaction sends
- Save to Gallery from the expanded media viewer — share button surfaces a Save / Share menu when the gallery is enabled, with username / source attribution carried through

### Interface **\***
- Tab bar shortcuts — Home shortcut button + Action button icon picker, grouped at the top of the page
- Notifications — universal in-app pill (Minimal / Colorful / Glow / Island), per-action routing (custom pill / IG-native / off), top or bottom position, master kill switch, swipe-to-dismiss, multi-pill stacking
- Modify tab bar icon order
- Modify swiping between tabs
- Hiding tabs
  - Hide feed tab
  - Hide explore tab
  - Hide reels tab
  - Hide create tab
  - Hide messages tab
- Messages-only mode — inbox + profile only, launch straight into inbox **\***
  - Hide tab bar sub-toggle — floating settings gear replaces it **\***
- Launch tab — pick which tab the app opens to **\***
- Home shortcut button — extra button on the home top bar with a configurable multi-action menu **\***
- Experimental flags

### Confirm actions
- Confirm like: Posts/Stories
- Confirm story emoji reaction **\***
- Confirm like: Reels
- Confirm follow
- Confirm unfollow **\***
- Confirm repost
- Confirm voice call **\***
- Confirm video call **\***
- Confirm voice messages
- Confirm follow requests
- Confirm vanish mode
- Confirm posting comment
- Confirm send to group chat **\***
- Confirm changing direct message theme
- Confirm sticker interaction (stories / highlights, per-surface: disabled / all / reaction stickers only) **\***

### Fake location **\***
- Override location app-wide for any IG feature reading coordinates
- MapKit picker with search + reverse-geocoded names
- Saved presets
- Quick toggle button on the Friends Map

### Theme **\***
- Theme picker — Off / Light / Dark / OLED, with optional Force theme to override the iOS appearance
- OLED chat theme — pure black DM thread and incoming bubbles
- Keyboard theme — dark or OLED, sticks through search keyboard activations
- Apply & restart, plus Reset theme to revert every theme option

### Tweak settings **\***
- Search bar with breadcrumbs across nested pages
- Pause playback when opening settings **\***
- Quick-access via long-press on feed tab **\***
- Native Instagram icons throughout settings and in-app menus **\***

### Advanced experimental features **\***
- Toggle hidden Instagram experiments: QuickSnap (Instants), Direct Notes reply types, Friend Map, Homecoming, Prism
- Batched changes with an Apply & restart button
- Auto-reset after 3 consecutive launch crashes

### Backup & Restore **\***
- Export RyukGram settings as JSON
- Import settings from JSON
- Preview before saving or applying

### Localization **\***
- Multi-language UI with fallback to English **\***
- Built-in language picker in Settings **\***
- Currently shipping: **English**, **Spanish**, **Russian**, **Korean**, **Arabic**, **Chinese (Traditional)**, **Chinese (Simplified)**, **Portuguese (Brazil)**, **Turkish**

### Optimization
- Clear Instagram cache on demand with optional auto-clear interval, with a toggle to preserve DMs, drafts, and Notes **\***

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
- Preserved unsent messages cannot be removed using "Delete for you". Pull to refresh in the DMs tab clears the active account's preserved messages (with optional confirmation if "Warn before clearing on refresh" is enabled).
- "Delete for you" detection uses a ~2 second window after the local action. If a real other-party unsend happens to land in the same window, it may not be preserved. Rare in practice and limited to that specific overlap.
- With Liquid Glass buttons + Hide UI on capture both on, the DM eye leaves an empty glass bubble in captures — IG draws that backdrop, not the tweak, so it's outside our redaction.

# Opening Tweak Settings

|                                             |                                             |
|:-------------------------------------------:|:-------------------------------------------:|
| <img src="https://i.imgur.com/uPMcugZ.png"> | <img src="https://i.imgur.com/RUlsg4k.jpeg"> |

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
$ ./build.sh <sideload/sidestore/rootless/rootful>
```

# Credits
- [SCInsta](https://github.com/SoCuul/SCInsta) by [@SoCuul](https://github.com/SoCuul) — original tweak this fork is based on
- [@BandarHL](https://github.com/BandarHL) — creator of the original BHInstagram project
- [Instaoled](https://t.me/ciesIPAs) by @VAXMG — OLED theme inspiration
- [@euoradan](https://t.me/euoradan) (Radan) — experimental Instagram feature flag research
- [@Mikasa-san](https://github.com/Mikasa-san) — code contributions
- [@n3d1117](https://github.com/n3d1117) (Edoardo) — Following feed mode (ported from [InstaSane](https://github.com/n3d1117/InstaSane))
- [@erupts0](https://github.com/erupts0) (John) — testing and feature suggestions
- [BillyCurtis/OpenInstagramSafariExtension](https://github.com/BillyCurtis/OpenInstagramSafariExtension) — base for the bundled Safari extension
- [@asdfzxcvbn](https://github.com/asdfzxcvbn) — [ipapatch](https://github.com/asdfzxcvbn/ipapatch) and [zxPluginsInject](https://github.com/asdfzxcvbn/zxPluginsInject)
- Furamako — Spanish translation
- [@ch1tmdgus](https://github.com/ch1tmdgus) (N4C) — Korean translation
- [ZomkaDEV](https://github.com/ZomkaDEV) — Russian translation
- [@bruuhim](https://github.com/bruuhim) — Arabic translation
- [@jaydenjcpy](https://github.com/jaydenjcpy) — Chinese (Traditional and Simplified) translation
- Bruno ([@brunorainha](https://github.com/brunorainha)) — Portuguese (Brazil) translation
- [@yesnt10](https://github.com/yesnt10) — Turkish translation

# Support

RyukGram is free and open source. If you'd like to support development:

- [☕ Donate to Ryuk (RyukGram)](https://ko-fi.com/ryuk744335)
- [☕ Donate to SoCuul (original SCInsta)](https://ko-fi.com/SoCuul) — RyukGram wouldn't exist without SoCuul's original SCInsta, so showing them some love is always welcome
