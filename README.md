# RyukGram
A feature-rich iOS tweak for Instagram, forked from [SCInsta](https://github.com/SoCuul/SCInsta) with additional features and fixes.\
`Version v1.1.4` | `Tested on Instagram 423.1.0`

---

> [!NOTE]
> To modify RyukGram's settings, check out [this section below](#opening-tweak-settings) for help

---

# Installation
>[!IMPORTANT]
> Which type of device are you planning on installing this tweak on?
> - Jailbroken/TrollStore device -> [Download pre-built tweak](https://github.com/faroukbmiled/RyukGram/releases/latest)
> - Standard iOS device -> Sideload the dylib using Feather or similar

# Features
> Features marked with **\*** are new or improved in RyukGram

### General
- Hide ads
- Hide Meta AI
- Copy description
- Do not save recent searches
- Use detailed (native) color picker
- Enable liquid glass buttons
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
- Hide entire feed
- No suggested posts
- No suggested for you (accounts)
- No suggested reels
- No suggested threads posts
- Disable video autoplay

### Reels
- Modify tap controls
- Always show progress scrubber
- Disable auto-unmuting reels (properly blocks mute switch, volume buttons, and announcer broadcasts) **\***
- Confirm reel refresh
- Unlock password-locked reels **\***
- Hide reels header
- Hide reels blend button
- Disable scrolling reels
- Prevent doom scrolling (limit maximum viewable reels)
- Enhanced Pause/Play mode (when Pause/Play tap control is set): **\***
  - Mute toggle auto-hidden, only play/pause icon visible
  - Audio forced on in reels tab
  - Play indicator properly hidden when video plays (fixes IG bug after hold/zoom)
  - Playback toggle synced with overlay during hold/zoom
  - Works across IG A/B test variants

### Saving
- Download feed posts (photo + video)
- Download reels
- Download stories
- Save profile picture
- Download buttons on media — tap a button directly on feed posts, reels sidebar, and story overlay **\***
- Download method — choose between download button or long-press gesture **\***
- Save action — choose between share sheet or save directly to Photos **\***
- Download confirmation — optional confirmation dialog before downloading **\***
- Non-blocking download HUD — pill-style progress at the top, tap to cancel **\***
- Debug fallback — if IG updates break downloads, shows diagnostic info instead of crashing **\***
- *Customize finger count for long-press*
- *Customize hold time for long-press*

### Stories and messages
- Keep deleted messages (preserves unsent messages with visual indicator and notification pill) **\***
- Manually mark messages as seen (button or toggle mode) **\***
- Auto mark seen on send (marks messages as read when you send any message) **\***
- Send audio as file — send audio files as voice messages from the DM plus menu **\***
- Download voice messages — adds a Download option to the long-press menu on voice messages, saves as M4A via share sheet **\***
- Disable typing status
- Unlimited replay of direct stories
- Disable view-once limitations
- Disable screenshot detection
- Disable story seen receipt (blocks network upload, toggleable at runtime without restart) **\***
- Keep stories visually unseen — keeps the colorful ring in the tray after viewing **\***
- Manual mark story as seen — button on story overlay to selectively mark stories as seen **\***
- Stop story auto-advance — stories won't auto-skip when the timer ends **\***
- Story download button — download directly from the story overlay **\***
- Download disappearing DM media (photos + videos) **\***
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

### Confirm actions
- Confirm like: Posts/Stories
- Confirm like: Reels
- Confirm follow
- Confirm repost
- Confirm call
- Confirm voice messages
- Confirm follow requests
- Confirm shh mode (disappearing messages)
- Confirm posting comment
- Confirm changing direct message theme
- Confirm sticker interaction

### Optimization
- Automatically clears unneeded cache folders, reducing the size of your Instagram installation

## Known Issues
- Preserved unsent messages cannot be removed using "Delete for you". Pull to refresh in the DMs tab clears all preserved messages as a workaround.

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
