# Third-Party Licenses

FMP is distributed under the MIT license (see `LICENSE`). This file records the
third-party components FMP ships or derives from, and where to obtain their
sources and license texts. Full texts referenced below live in `licenses/`.

## 1. Native libraries in the Windows desktop build

`flutter build windows` copies these next to `fmp.exe`, so they are present in
both the portable ZIP and the installer. The Android build contains none of
them — it plays audio through ExoPlayer/Media3 via `just_audio` (Apache-2.0).

### libmpv and FFmpeg — LGPL-2.1-or-later

`libmpv-2.dll` is the audio backend `media_kit` uses on Windows. The Dart
package `media_kit_libs_windows_audio` (MIT) does not contain it; it downloads
a prebuilt archive during the build:

```
media_kit_libs_windows_audio-1.0.9/windows/CMakeLists.txt:66,69
  mpv-dev-x86_64-20230924-git-652a1dd.7z
  https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/
```

That archive is produced by
<https://github.com/media-kit/libmpv-win32-audio-build> (archived, and carrying
no license file of its own). Its build scripts exclude every GPL-only
component:

| Script | Flags |
|---|---|
| `packages/mpv.cmake:29` | `-Dgpl=false` |
| `packages/ffmpeg.cmake:34-36` | `--disable-gpl --disable-nonfree --enable-version3` |

mpv is therefore built as **LGPL-2.1-or-later**, and FFmpeg as
**LGPL-2.1-or-later** with the LGPL-3 components that `--enable-version3`
turns on. Neither is GPL.

**How this distribution complies.** `libmpv-2.dll` is dynamically linked and
shipped as a separate file, so a recipient can replace it with a modified
build without rebuilding FMP. FMP applies no technical measure that would
prevent reverse engineering for that purpose, and the copyright notices inside
the binary are unmodified. Sources are available from
<https://github.com/mpv-player/mpv> and <https://github.com/FFmpeg/FFmpeg>,
and the exact recipe used for this binary from the archived repository above.

License texts: `licenses/LGPL-2.1.txt` and `licenses/LGPL-3.0.txt`. LGPL-3.0 is
written as a set of additional permissions on top of GPL-3.0, so
`licenses/GPL-3.0.txt` is included as well.

### Other native libraries

| File | Origin | License |
|---|---|---|
| `flutter_windows.dll` | Flutter engine | BSD-3-Clause |
| `libisar.dll` | prebuilt inside `isar_community_flutter_libs` | Apache-2.0 |
| `WebView2Loader.dll` | `Microsoft.Web.WebView2` 1.0.2792.45, fetched from NuGet at build time by `flutter_inappwebview_windows` | Microsoft Edge WebView2 SDK terms |
| `smtc_windows.dll` | `smtc_windows` | MIT |
| `*_plugin.dll` | the corresponding pub packages | see section 2 |

## 2. Dart and Flutter packages

`pubspec.lock` pins 207 packages: 202 from pub.dev and 5 from the Flutter SDK.
Reading the `LICENSE` file of every hosted package gives:

| License | Packages |
|---|---:|
| BSD-3-Clause | 116 |
| MIT | 60 |
| Apache-2.0 | 19 |
| BSD-2-Clause | 6 |
| CC0-1.0 | 1 |
| **GPL / LGPL / MPL / AGPL** | **0** |

The full text of every one of those licenses is available inside the app under
**Settings → About → Open-source licenses**, which also lists the entries in
section 1.

## 3. Protocol research

FMP reaches Bilibili, YouTube, NetEase Cloud Music and QQ Music through private
APIs. Endpoint shapes, signing steps and protocol constants come from public
reverse-engineering write-ups rather than from any project's source:

| Source | License | Used for |
|---|---|---|
| [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect) | CC BY-NC 4.0 | Bilibili endpoints and the cookie-refresh public key |
| [netease-cloud-music](https://github.com/chaunsin/netease-cloud-music) | MIT | NetEase request-format reference |

`bilibili-API-collect` is licensed **CC BY-NC 4.0**. Attribution is given here
and in the README; its NonCommercial term applies to that documentation. The
upstream repository was emptied in January 2026 and its history rewritten, so
the GitHub API now reports no license for it; contributor mirrors still carry
the CC BY-NC 4.0 `LICENSE`, with commits dating to 2020.

**FMP implements no WBI signing at all.** What it took from each write-up is
the protocol fact, not an implementation. The two crypto units were compared
against the community projects implementing the same protocols and share no
structure with them:

- **NetEase** (`lib/core/utils/netease_crypto.dart`) -- the keys, IV and RSA
  modulus are shipped verbatim in music.163.com's own `core.js`. FMP writes
  fixed-mode three-argument private helpers and its own `BigInt.modPow`; the
  reference implementations dispatch through a general
  `aesEncrypt(text, mode, key, iv, format)` and parse PEM with a library.
- **Bilibili** (`lib/services/account/bilibili_crypto.dart`) -- the public key,
  the `refresh_{ts}` plaintext and the choice of RSA-OAEP/SHA-256 are protocol
  facts. Every demo in the write-up parses the PEM with a library; FMP hand
  writes a DER/ASN.1 parser instead.

## 4. License texts

- `licenses/LGPL-2.1.txt` — GNU Lesser General Public License, version 2.1
- `licenses/LGPL-3.0.txt` — GNU Lesser General Public License, version 3
- `licenses/GPL-3.0.txt` — GNU General Public License, version 3
