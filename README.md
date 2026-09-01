<p align="center">
  <img src="assets/icon/app_icon_bg.png" alt="FMP" width="112" height="112">
</p>
<h1 align="center">FMP</h1>
<p align="center">One music player for Bilibili, YouTube and NetEase Cloud Music.<br>Android and Windows.</p>
<p align="center">
  <a href="https://github.com/1morr/FMP/releases/latest"><img src="https://img.shields.io/github/v/release/1morr/FMP?color=blue" alt="Latest release"></a>
  <a href="https://github.com/1morr/FMP/actions/workflows/ci.yml"><img src="https://github.com/1morr/FMP/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20Windows-green" alt="Platform">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License: GPL-3.0"></a>
</p>
<p align="center"><b>English</b> · <a href="README.zh-Hant.md">繁體中文</a></p>

Your playlists live on three different platforms and none of their apps will play
the other two. FMP searches across all of them, plays from any of them, and keeps one
queue, one library and one set of listening history.

## Download

<!-- DOWNLOAD_START -->
| Platform | | |
|---|---|---|
| **Android** | [APK](https://github.com/1morr/FMP/releases/latest/download/fmp-latest-android-universal.apk) | Install directly on the device |
| **Windows** | [Installer (recommended)](https://github.com/1morr/FMP/releases/latest/download/fmp-latest-windows-installer.exe) | Full SMTC, Start menu, shortcuts, system integration |
| Windows | [Portable ZIP](https://github.com/1morr/FMP/releases/latest/download/fmp-latest-windows.zip) | Unzip and run; media keys and shortcut identity may be incomplete |
<!-- DOWNLOAD_END -->

All versions and release notes: [GitHub Releases](https://github.com/1morr/FMP/releases).

<p align="center">
  <img src="screenshots/home_desktop.png" alt="FMP on Windows" width="860">
</p>

<p align="center">
  <img src="screenshots/search-page.png" alt="Search across sources" width="420">
  <img src="screenshots/lyrics-features.png" alt="Lyrics" width="420">
</p>

<details>
<summary>More screenshots</summary>

| Home | Library |
|---|---|
| <img src="screenshots/home-page.png" width="420"> | <img src="screenshots/library-page.png" width="420"> |

| Queue | Radio |
|---|---|
| <img src="screenshots/queue-page.png" width="420"> | <img src="screenshots/radio-page.png" width="420"> |

| Settings |
|---|
| <img src="screenshots/settings-page.png" width="420"> |

</details>

## What it does

- **Three sources, one search.** Bilibili (video audio, multi-part collections,
  live-room audio, favourites import), YouTube (videos, playlists, Mix/Radio
  dynamic queues, Opus/AAC preference), and NetEase (songs, playlists, VIP and
  availability flags). Paste a URL to play it directly.
- **Your library, imported.** Build playlists with custom covers, or import them
  from any of the three — plus fuzzy-matched import from QQ Music and Spotify
  exports.
- **Playback you expect.** Queue reordering, repeat and shuffle modes, speed
  control, and a "try this one" mode that returns you to where you were. The
  queue survives a restart.
- **Lyrics** from NetEase, QQ Music and lrclib with a source priority you set,
  synced scrolling, translation and romanization, and a separate desktop lyrics
  window on Windows.
- **Offline.** Download single tracks or whole playlists; downloads become part
  of the local library.
- **Live rooms as radio,** with their own playback page.
- History with a timeline and statistics, local backup and restore, and an
  in-app update check against GitHub Releases.

| | Android | Windows |
|---|:-:|:-:|
| Background playback | ✅ | — |
| Notification controls | ✅ | — |
| System media keys | ✅ | ✅ |
| Windows SMTC | — | ✅ |
| System tray | — | ✅ |
| Global hotkeys | — | ✅ |
| Desktop lyrics window | — | ✅ |

## Built with

| Layer | |
|---|---|
| App | Flutter · Dart · Material 3 |
| State | Riverpod |
| Local data | Isar |
| Routing | go_router |
| Audio | just_audio (Android) · media_kit (Windows) |
| Network | Dio · youtube_explode_dart · per-platform adapters |
| i18n | slang |

The UI switches between bottom navigation, a side rail and a desktop detail pane
by width.

## Building

Needs the Flutter SDK. A Windows desktop build additionally needs the **NuGet
CLI** (pulled in by `flutter_inappwebview_windows`) and a **Rust toolchain**
(`smtc_windows` builds a Rust crate through cargokit).

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run slang
flutter analyze
flutter test
```

Generated code is not committed — run the two codegen steps before analyzing.

The in-depth docs are written in Traditional Chinese.

| | |
|---|---|
| [docs/README.md](docs/README.md) | What each document covers |
| [docs/building.md](docs/building.md) | Local Android and Windows builds |
| [docs/development.md](docs/development.md) | Architecture, sources, data model |
| [docs/build-and-release.md](docs/build-and-release.md) | CI, releases, signing, in-app update assets |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common build and runtime problems |

## Privacy and disclaimer

FMP hosts no music. It reads the public interfaces of platforms you already have
accounts on, and your history, playlists, settings, credentials and downloads
stay on your device. There are no ad or analytics SDKs.

> [!WARNING]
> For study and personal use. Membership-only, restricted and unavailable content
> still follows the source platform's rules. Frequent or abnormal requests may
> get your account limited or banned — that risk is yours. The authors accept no
> liability for any loss arising from use of this software.

## Credits

API research from [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
and [netease-cloud-music](https://github.com/chaunsin/netease-cloud-music).
Built on [media_kit](https://github.com/media-kit/media-kit),
[just_audio](https://github.com/ryanheise/just_audio),
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart),
[Isar](https://github.com/isar/isar) and [Riverpod](https://github.com/rrousselGit/riverpod).

## License

[GPL-3.0](LICENSE)
