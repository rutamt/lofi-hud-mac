# LoFi HUD for macOS

A native macOS rewrite of [LoFi HUD](https://github.com/rutamt/lofi-player): a zero-ad, menu-bar
background player for your local LoFi library, with global hotkeys and a floating glass HUD.

It behaves the same as the original Python app, but it's built with Swift, SwiftUI and AppKit
instead of Python, Tk and VLC.

| | Python build | Native build |
|---|---|---|
| App size | ~100 MB+ (Python + Tk + VLC) | **~1.6 MB** |
| Idle CPU | Polling timers (1.5 s / 2 s) | **0%**: fully event-driven |
| Audio engine | libVLC (requires VLC installed) | AVFoundation (built in) |
| Global hotkeys | pynput event tap (**needs Accessibility**) | Carbon hot keys (**no permission prompt**) |
| Media keys / AirPods | Keyboard media keys only | Media keys, AirPods/Bluetooth buttons, Control Center |
| Start at login | Hand-written LaunchAgent | `SMAppService` (shows in Login Items) |

## Features

- **Shuffled, looping local playback** of `~/Music/LoFi` (configurable, scanned recursively).
- **Global hotkeys**: hold the modifier (default `⌥ Option`) and press:

  | Action | Default |
  |---|---|
  | Play / Pause | `⌥ Q` |
  | Next / Previous track | `⌥ 2` / `⌥ 1` |
  | Show current song | `⌥ 3` |
  | Ignore song (moves it to a sibling `Ignored_Lofi` folder and skips) | `⌥ 4` |
  | Volume up / down (±5%, repeats while held) | `⌥ ↑` / `⌥ ↓` |

  Next, previous, show, ignore and volume only act while music is playing, as in the original.
- **Hardware media keys**: keyboard ⏯ ⏭ ⏮, AirPods and Bluetooth headset buttons, and Control
  Center, all handled through the system Now Playing integration (debounced at 300 ms).
- **Glass HUD overlay** with Now Playing, play/pause, volume bar, and library status. It's
  click-through, never steals focus, and shows on every Space and over full-screen apps. Choose
  from 7 positions and set the timeouts.
- **Themes**: System (Auto), Harbor Night, Tokyo Night, Rosé Pine, Polar Dusk, Gruvbox Warm,
  Catppuccin Latte, System Light. System (Auto) follows macOS appearance changes live.
- **Auto-pause** when a chosen output device (e.g. Bluetooth headphones) disconnects.
- **Smart titles**: strips downloader prefixes, track numbers, `(Official Audio)` / `[320 kbps]`
  noise, and underscores, then title-cases the result.
- **Menu bar menu** showing the current track, Play/Pause, Next, Rescan Library, Open Music Folder,
  Settings… (`⌘,`) and Quit.
- **Single instance**: launching it again opens Settings and shows "Already Running".
- **Clean uninstall** from the Settings footer, or from the command line (see below).

Supported formats are whatever AVFoundation decodes: MP3, AAC/M4A, ALAC, FLAC, WAV, AIFF and CAF.
Files it can't decode (e.g. WMA) are skipped automatically.

## Settings migration

Settings live in `~/Library/Application Support/LoFiHUD/config.json`, the **same file and schema**
as the Python build, so your existing theme, hotkeys, HUD position, volume and music folder carry
over. On first launch, the old `~/Library/LaunchAgents/com.rutamt.lofihud.plist` is removed and
replaced by a native login item, so the app never starts twice.

## Build

Requires macOS 14+ and the Swift toolchain (the Xcode Command Line Tools are enough).

```bash
scripts/build.sh        # → build/LoFi HUD.app (release, ad-hoc signed)
scripts/make_dmg.sh     # → build/LoFiHUD_v2.0.0.dmg (drag-to-Applications installer)
scripts/test.sh         # logic self-tests (title cleaning, config compat, key mapping, scanning)
```

Options: `VERSION=2.1.0 scripts/build.sh`, `UNIVERSAL=1` for arm64 + x86_64 (needs full Xcode),
`SIGN_IDENTITY="Developer ID Application: …"` for a real signature.

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
  Core/        AppConfig, Paths, Themes, TitleCleaner
  Audio/       Player (AVAudioPlayer), AudioDevices (CoreAudio listener)
  Input/       Hotkeys (Carbon), KeyCodes (layout-aware), MediaKeys (MPRemoteCommandCenter)
  UI/          HUD (glass panel), StatusMenu, SettingsView/SettingsModel (SwiftUI)
  System/      LoginItem (SMAppService), SingleInstance (flock), Uninstaller
```

## Credits

- Created by Rutam and Gemini; native macOS port with Claude.
- Free music: [OpenLofi](https://github.com/btahir/open-lofi) by Bashar Tahir.
