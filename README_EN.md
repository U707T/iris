<img height="100px" width="100px" alt="logo" src="./assets/images/logo.png"/>

# IRIS - A lightweight video player

[![CI](https://github.com/U707T/iris/actions/workflows/ci.yml/badge.svg)](https://github.com/U707T/iris/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/U707T/iris)](https://github.com/U707T/iris/releases/latest)
[![License](https://img.shields.io/github/license/U707T/iris)](./LICENSE)

English | [中文](./README.md)

IRIS is a lightweight video player built with Flutter. This repository is an enhanced fork of [nini22P/iris](https://github.com/nini22P/iris): it keeps the complete upstream feature set and adds a **short video mode** along with a series of playback-experience and stability improvements. Windows / Android installers are built and published automatically by this repository's CI.

## Features

- [X] Based on [Media Kit](https://github.com/media-kit/media-kit) (libmpv / FFmpeg), supports multiple video formats
- [X] Local storage and WebDAV support
- [X] **Short video mode**: seamless vertical swipe, single-item loop, draggable progress bar, double-tap seek feedback, long-press speed effect, volume button
- [X] Switchable audio track
- [X] Playback queue support for random and repeat
- [X] Comprehensive gesture support
- [X] Long press to speed up playback (configurable)
- [X] Smooth video zoom
- [X] Screenshot, rotate / flip the video
- [X] Playback stats (frame rate, dropped frames, decoder)
- [X] File search
- [X] Remember window size and position
- [X] Configurable skip duration
- [X] Pure black (OLED) theme

### Highlights added by this fork

- **Short video mode**: enter it from the control bar button; a preloaded player pool makes vertical swiping seamless; the progress bar can be tapped / dragged; double-tapping the left / right side seeks with a brief "±Ns" pill; long-press speed-up shows a breathing light effect; hold the volume button and slide to adjust the device volume (hover + wheel to fine-tune on desktop)
- **More reliable playback start**: videos open paused and wait for the first frame before playing, so sound and picture appear together instead of starting with a black screen; preloaded neighbours decode their first frame too
- **Shuffle rework**: switching shuffle on reshuffles the queue (the current video stays first), and the queue is reshuffled on launch while shuffle is on; switching it off restores the original file order
- **Windows fixes**: the workaround for the Flutter engine accessibility crash ([flutter/flutter#175041](https://github.com/flutter/flutter/issues/175041)) is built in and enabled by default (see "Troubleshooting")
- **A batch of stability fixes** across the player and short video mode (playback-history cap, fullscreen toggle, volume popover, search dialog, edge cases; see [CHANGELOG.md](./CHANGELOG.md))

## Download

| Platform | Arch/Channel | Download Link                                                                                                      | Notes                  |
| :------- | :----------- | :----------------------------------------------------------------------------------------------------------------- | :--------------------- |
| Windows  | Installer    | [IRIS-windows-installer.exe](https://github.com/U707T/iris/releases/latest/download/IRIS-windows-installer.exe)     | For 64-bit systems     |
|          | Portable     | [IRIS-windows.zip](https://github.com/U707T/iris/releases/latest/download/IRIS-windows.zip)                         | Unzip and run          |
| Android  | arm64-v8a    | [IRIS-android-arm64-v8a.apk](https://github.com/U707T/iris/releases/latest/download/IRIS-android-arm64-v8a.apk)     | For 64-bit devices     |
|          | armeabi-v7a  | [IRIS-android-armeabi-v7a.apk](https://github.com/U707T/iris/releases/latest/download/IRIS-android-armeabi-v7a.apk) | For 32-bit devices     |
|          | x86_64       | [IRIS-android-x86_64.apk](https://github.com/U707T/iris/releases/latest/download/IRIS-android-x86_64.apk)           | For emulators / x86 devices |

> Installers are built by GitHub Actions; versions with an `-rc` suffix are release candidates. See [Releases](https://github.com/U707T/iris/releases) for all versions.

## Keyboard and Gesture Controls

### Keyboard Controls

| Key                    | Description                                        |
| ---------------------- | -------------------------------------------------- |
| `Space`              | Play / Pause / Select file                         |
| `Arrow Left`         | Fast backward                    |
| `Arrow Right`        | Fast forward                    |
| `Arrow Up`           | Volume up                                          |
| `Arrow Down`         | Volume down                                        |
| `Ctrl + Arrow Left`  | Previous                                           |
| `Ctrl + Arrow Right` | Next                                               |
| `Ctrl + X`           | Shuffle                                            |
| `Ctrl + R`           | Repeat                                             |
| `Ctrl + V`           | Video zoom                                         |
| `Ctrl + M`           | Volume mute                                        |
| `S`                  | Audio tracks                                      |
| `P`                  | Play queue                                         |
| `F`                  | Storages                                           |
| `Ctrl + O`           | Open file                                          |
| `Ctrl + L`           | Open link                                          |
| `Ctrl + C`           | Close currently media file                         |
| `Ctrl + H`           | Play history                                       |
| `Ctrl + P`           | Settings                                           |
| `Ctrl + S`           | Screenshot                                         |
| `Ctrl + T`           | Rotate / flip the video                            |
| `Ctrl + I`           | Playback stats                                     |
| `Shift + ?`          | Keyboard shortcuts                                 |
| `+`                  | Step forward                                       |
| `-`                  | Step backward                                      |
| `Enter`              | Enter full screen / Exit full screen / Select file |
| `F11`                | Enter full screen / Exit full screen               |
| `Esc`                | Exit current Menu / Go back / Exit full screen     |
| `F10`                | Toggle always on top                               |
| `Alt + X`            | Exit application                                   |

### Gesture Controls

| Gesture                           | Description                   |
| --------------------------------- | ----------------------------- |
| Tap                               | Select an item or open a menu |
| Double tap center                 | Play / Pause                  |
| Double tap left side              | Fast backward                |
| Double tap right side             | Fast forward                |
| Swipe left / right                | Adjust playback progress      |
| Swipe up / down on left side      | Adjust screen brightness      |
| Swipe up / down on right side     | Adjust device volume          |
| Long press                        | Speed up playback (speed is configurable in settings) |
| Pinch with two fingers            | Smoothly zoom the video       |
| `Ctrl` + scroll wheel             | Smoothly zoom the video (desktop) |

### Short Video Mode

Enter from the control bar button or the "⋮" menu; press `Esc` / back to exit.

| Action                                | Description                                          |
| ------------------------------------- | ---------------------------------------------------- |
| Swipe up / down                       | Previous / next video                                |
| Tap / double tap centre               | Play / pause                                         |
| Double tap left side                  | Seek backward by the configured step ("±Ns" pill)    |
| Double tap right side                 | Seek forward (same as above)                         |
| Horizontal drag                       | Adjust playback progress (anywhere on the picture)   |
| Bottom progress bar                   | Tap / drag to seek                                   |
| Long press                            | Speed up playback (release to restore)               |
| Tap the volume button                 | Mute / unmute IRIS only                              |
| Hold the volume button and slide      | Adjust device volume (same as the hardware keys)     |
| Desktop: wheel / `↑` `↓`             | Previous / next video                                |
| Desktop: wheel over the volume button | Fine-tune the device volume                          |

## Troubleshooting

- **Windows: the app crashes right after launch or during the first interactions** (`0xC0000005` in `flutter_windows.dll`). This is a known Flutter engine bug on Windows ([flutter/flutter#175041](https://github.com/flutter/flutter/issues/175041)): it is triggered when a UI Automation client — remote-desktop tools such as Chrome Remote Desktop / RDP, screen readers, automation utilities — enumerates the window while the app is still starting. **The compatibility workaround is built into IRIS and enabled by default**, so the app starts normally out of the box. To do that, IRIS turns its own Windows accessibility integration off, which means screen readers cannot read the app. If you need accessibility tools to work and accept the crash risk, opt out with either:
  - set the environment variable `IRIS_ENABLE_WINDOWS_A11Y=1` (e.g. run `setx IRIS_ENABLE_WINDOWS_A11Y 1` once, then start IRIS), or
  - start IRIS with the command-line argument `--enable-windows-a11y`.

  (The older `IRIS_DISABLE_WINDOWS_A11Y=1` / `--disable-windows-a11y` are still accepted.)

## Build from Source

A Flutter stable release is required (CI uses 3.47.5):

```bash
flutter pub get
dart run build_runner build          # generate code (freezed, localizations, ...)
flutter build windows                # Windows
flutter build apk --split-per-abi    # Android (release builds need your own signing config)
```

## Upstream & Credits

- This project is based on [nini22P/iris](https://github.com/nini22P/iris) by [nini22P](https://github.com/nini22P); the upstream original is available on the [Microsoft Store](https://apps.microsoft.com/detail/9NML7WNHNRTJ).
- If you like this project, consider supporting the upstream author: [Afdian](https://afdian.com/a/nini22P) / [Ko-fi](https://ko-fi.com/nini22p).

## Feedback

- This repository is a personally maintained enhanced fork. For problems with features that come from upstream, please use the [upstream issue tracker](https://github.com/nini22P/iris/issues); the changes and fixes of this fork are documented in [CHANGELOG.md](./CHANGELOG.md).

## License

This project is licensed under the MPL-2.0 license, see the [LICENSE](./LICENSE) file for details.
