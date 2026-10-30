# LoFi HUD for macOS

A native macOS rewrite of [LoFi HUD](https://github.com/rutamt/lofi-player): a zero-ad, menu-bar
background player for your local LoFi library, with global hotkeys and a floating glass HUD.

It behaves the same as the original Python app, but it's built with Swift, SwiftUI and AppKit
instead of Python, Tk and VLC.

| | Python build | Native build |
|---|---|---|
| App size | ~100 MB+ (Python + Tk + VLC) | **~1.6 MB** |
| Idle CPU | Polling timers (1.5 s / 2 s) | **0%**: fully event-driven |
| Audio engine | libVLC (requires VLC installed) | AVAudioEngine (built in), gapless + crossfade |
| Global hotkeys | pynput event tap (**needs Accessibility**) | Carbon hot keys (**no permission prompt**) |
| Media keys / AirPods | Keyboard media keys only | Media keys, AirPods/Bluetooth buttons, Control Center |
| Start at login | Hand-written LaunchAgent | `SMAppService` (shows in Login Items) |

## Features

- **Shuffled, looping local playback** of `~/Music/LoFi` (configurable, scanned recursively in the
  background). The order is reshuffled every time it wraps around, and the same song never plays
  twice in a row.
- **Gapless playback** (sample-accurate between files of the same format) or an optional
  **crossfade** of 1–12 s.
- **Picks up where you left off**: the play order, current song and position are restored after a
  restart.
- **Live library**: new files dropped into the music folder are picked up automatically (FSEvents).
  Rescanning never interrupts the current song.
- **Global hotkeys**: each action has its own combo, with any mix of ⌃ ⌥ ⇧ ⌘. Defaults:

  | Action | Default |
  |---|---|
  | Play / Pause | `⌥ Q` |
  | Next / Previous track | `⌥ 2` / `⌥ 1` |
  | Show current song | `⌥ 3` |
  | Remove song (moves it to a sibling `Ignored_Lofi` folder and skips) | `⌥ 4` |
  | Favorite / unfavorite song | `⌥ 5` |
  | Volume up / down (±5%, repeats while held) | `⌥ ↑` / `⌥ ↓` |

  Everything except Play/Pause only acts while music is playing. Settings flags duplicate combos,
  combos held by other apps, and combos that override common shortcuts like ⌘Q.
- **Removing is undoable**: click **Undo** on the HUD or in the menu bar. A file never overwrites
  an existing one in `Ignored_Lofi`.
- **Favorites** and a **Favorites Only** shuffle mode.
- **Sleep timer** (15–90 min, or the end of the current song) with a 10 s fade-out.
- **Ambient noise layer** (brown, pink or white noise) mixed under the music, with its own volume.
- **Hardware media keys**: keyboard ⏯ ⏭ ⏮, AirPods and Bluetooth headset buttons, and Control
  Center, all handled through the system Now Playing integration.
- **Glass HUD overlay** with Now Playing and a live progress bar, play/pause, volume and library
  status. It never steals focus and shows on every Space and over full-screen apps. Choose one of
  7 positions or drag it anywhere, and pick the display (the one with the pointer, the main
  display, or a specific one).
- **14 themes**: Harbor Night, Tokyo Night, Rosé Pine, Polar Dusk, Gruvbox Warm, Catppuccin Mocha,
  Dracula, One Dark, Kanagawa, Everforest, Solarized Dark/Light, Catppuccin Latte and System
  Light. **System (Auto)** follows macOS appearance with a light/dark pair you choose. The accent
  color can follow the theme, the macOS accent, or a custom color.
- **Auto-pause** when the playing device disconnects (any headphones), or when a specific device
  does. Devices are matched by their stable CoreAudio UID.
- **Menu bar menu**: the current song with its time and favorite status, a volume slider,
  play/pause/next/previous, favorite, remove/undo, Favorites Only, sleep timer, ambient noise,
  rescan, open folder, update check, Settings… (`⌘,`) and Quit. The icon turns into a waveform
  while playing.
- **Settings apply instantly**; there's no Save button. An option hides the Dock icon while
  Settings is open.
- **Update check** against GitHub Releases (daily, optional). It notifies you and links to the DMG
  without installing anything itself.
- **Smart titles**, **single instance**, **clean uninstall**, as before.

Supported formats: MP3, AAC/M4A, ALAC, FLAC, WAV, AIFF and CAF. Files that can't be decoded are
skipped, left out of the track count, and retried if the file changes (e.g. after a download
finishes).

## Settings migration

Settings live in `~/Library/Application Support/LoFiHUD/config.json`, the **same file** as the
Python build (the schema is a superset), so your existing theme, hotkeys, HUD position, volume and
music folder carry over. Old single-modifier bindings like `"key_play": "q"` keep working and are
rewritten as full combos (`"option+q"`) when you next change a hotkey. The play queue, resume
position and favorites are stored separately in `state.json`. On first launch, the old `~/Library/LaunchAgents/com.rutamt.lofihud.plist` is removed and
replaced by a native login item, so the app never starts twice.

## Build

Requires macOS 14+ and the Swift toolchain (the Xcode Command Line Tools are enough).

```bash
scripts/build.sh            # → build/LoFi HUD.app (release, ad-hoc signed)
scripts/make_dmg.sh         # → build/LoFiHUD_v2.1.0.dmg (drag-to-Applications installer)
scripts/test.sh             # logic self-tests (queue, config, themes, key combos, scanning, updates)
scripts/test.sh --audio     # + real-audio engine tests (gapless gap measurement, crossfade, undo…)
scripts/release.sh 2.1.0    # test + build + DMG; add --publish to tag and upload a GitHub release
```

Options: `VERSION=2.1.0 scripts/build.sh`, `UNIVERSAL=1` for arm64 + x86_64 (needs full Xcode).

The app is ad-hoc signed. On first launch of a downloaded copy, macOS asks you to allow it under
**System Settings → Privacy & Security → Open Anyway**.

`swift scripts/make_icon.swift` regenerates `Resources/AppIcon.icns`.

### Development runs

To run without touching your real settings or login items, point the app at a scratch directory:

```bash
LOFIHUD_HOME=/tmp/lofi-dev "build/LoFi HUD.app/Contents/MacOS/LoFiHUD"
```

## Uninstall

- Click **Uninstall** in the Settings footer. This removes the login item and settings, moves the
  app to the Trash, and keeps your music.
- From the command line:
  ```bash
  "/Applications/LoFi HUD.app/Contents/MacOS/LoFiHUD" --uninstall [--keep-music | --delete-music]
  ```
  With no flag you're asked whether to delete the music folder, and the default is **Keep**.

## Project layout

```
Sources/LoFiHUD/
  main.swift, AppDelegate.swift   entry point, single-instance guard, CLI uninstall
  AppController.swift             composition root: routes every input to the same actions
  Core/        AppConfig + PlaybackState, Paths, Themes, TitleCleaner, Log (os.Logger)
  Audio/       Player (AVAudioEngine, two-deck gapless/crossfade), PlayQueue (pure shuffle logic),
               Library (scan + FSEvents watcher), Noise, AudioDevices (CoreAudio listeners)
  Input/       Hotkeys (Carbon), KeyCodes + KeyCombo (layout-aware), MediaKeys (MPRemoteCommandCenter)
  UI/          HUD (glass panel), StatusMenu, SettingsView/SettingsModel (SwiftUI, live apply)
  System/      LoginItem (SMAppService), SingleInstance (flock), Uninstaller, Updater (GitHub)
```

## Credits

- Created by Rutam and Gemini; native macOS port with Claude.
- Free music: [OpenLofi](https://github.com/btahir/open-lofi) by Bashar Tahir.
