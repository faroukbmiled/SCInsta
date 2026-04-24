# RyukGram
A feature-rich iOS tweak for Instagram, forked from [SCInsta](https://github.com/SoCuul/SCInsta) with additional features and fixes.\
`Version v1.2.2` | `Tested on Instagram 426.0.0`

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
- Carousel and multi-story reel support with bulk download **\***
- Repost via IG's native creation flow **\***
- Full-screen media viewer with zoom and swipe **\***
- Story playback pauses when menus are open **\***

### Profile **\***
- Zoom profile photo — long press to view full-screen **\***
- Save profile picture
- View highlight cover from profile long-press menu **\***
- Profile copy button **\***
- Follow indicator — shows whether the user follows you **\***
- Copy note on long press **\***
- Fake profile stats — verified badge and follower/following/post counts **\***

### Profile Analyzer (beta) **\***
- Follower and following scans with progress and cancel **\***
- Mutuals and non-followbacks lists **\***
- New and lost followers/following trackers across scans **\***
- Profile change history — username, name, bio, pfp **\***
- Searchable lists with batch follow/unfollow **\***

### Saving
- Enhanced HD downloads up to 1080p **\***
  - Quality picker with preview playback **\***
  - Audio-only and raw photo download options **\***
  - Fallback to 720p without FFmpegKit **\***
- Download pill with progress bar and bulk counter **\***
- Save to RyukGram album **\***
- Download confirmation dialog **\***
- Output filenames formatted as `@username_context_timestamp` **\***
- Legacy long-press gesture (deprecated, customizable finger count + hold time) **\***

### Stories and messages
- Keep deleted messages **\***
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
- Send audio as file from DM plus menu **\***
- Download voice messages **\***
- Disable typing status
- Disable vanish mode swipe **\***
- Hide voice/video call buttons (independent toggles) **\***
- Unlimited replay of direct stories **\***
- Full last active date **\***
- Send files in DMs (experimental) **\***
- Notes actions — copy text, download GIF/audio **\***
- Copy note text on long press **\***
- Disable view-once limitations
- Disable screenshot detection
- Disable story seen receipt **\***
- Keep stories visually seen locally **\***
- Manual mark story as seen (button or toggle mode) **\***
- Long-press the story seen button for quick actions **\***
- Per-user story seen-receipt exclusion list with Block all / Block selected mode **\***
- Story audio mute/unmute toggle **\***
- View story mentions **\***
- Stop story auto-advance **\***
- Reveal poll/slider vote counts and quiz answers on stories and reels before interacting **\***
- Force legacy Quiz sticker back into the story composer tray **\***
- Disappearing DM media overlay — action button, mark-as-viewed eye, and audio toggle **\***
- Download disappearing DM media **\***
- Upload audio as voice message with built-in trim editor **\***
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
- Messages-only mode — inbox + profile only, launch straight into inbox **\***
  - Hide tab bar sub-toggle — floating settings gear replaces it **\***
- Launch tab — pick which tab the app opens to **\***

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
- Confirm changing direct message theme
- Confirm sticker interaction (stories / highlights, separate toggles) **\***

### Fake location **\***
- Override location app-wide for any IG feature reading coordinates
- MapKit picker with search + reverse-geocoded names
- Saved presets
- Quick toggle button on the Friends Map

### Theme **\***
- Force dark mode
- Full OLED — pure black app-wide
- OLED chat theme — pure black DM thread and incoming bubbles
- Keyboard theme — dark or OLED
- Apply & restart button

### Tweak settings **\***
- Search bar with breadcrumbs across nested pages
- Pause playback when opening settings **\***
- Quick-access via long-press on feed tab **\***

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
- Currently shipping: **English**, **Spanish**, **Russian**, **Korean**, **Arabic**, **Chinese (Traditional)**

### Optimization
- Clear Instagram cache on demand with optional auto-clear interval **\***

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
$ ./build.sh <sideload/rootless/rootful>
```

# Credits
- [SCInsta](https://github.com/SoCuul/SCInsta) by [@SoCuul](https://github.com/SoCuul) — original tweak this fork is based on
- [@BandarHL](https://github.com/BandarHL) — creator of the original BHInstagram project
- [@faroukbmiled](https://github.com/faroukbmiled) — RyukGram modifications and additional features
- [@euoradan](https://t.me/euoradan) (Radan) — experimental Instagram feature flag research
- [@erupts0](https://github.com/erupts0) (John) — testing and feature suggestions
- [BillyCurtis/OpenInstagramSafariExtension](https://github.com/BillyCurtis/OpenInstagramSafariExtension) — base for the bundled Safari extension
- [@asdfzxcvbn](https://github.com/asdfzxcvbn) — [ipapatch](https://github.com/asdfzxcvbn/ipapatch) and [zxPluginsInject](https://github.com/asdfzxcvbn/zxPluginsInject)
- Furamako — Spanish translation
- [@ch1tmdgus](https://github.com/ch1tmdgus) (N4C) — Korean translation
- [ZomkaDEV](https://github.com/ZomkaDEV) — Russian translation
- [@bruuhim](https://github.com/bruuhim) — Arabic translation
- [@jaydenjcpy](https://github.com/jaydenjcpy) — Chinese (Traditional) translation
