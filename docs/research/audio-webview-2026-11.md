> 2026-11-06 訪談（`/grill-with-docs`）時的研究輸出，查證日期見內文。brief〈查證過的事實〉R1–R5、R8 引用本檔。

# FMP 音訊後端 / 登入 WebView / secure storage 外部研究

查詢日期：2026-11-06。版本與發布日期取自 pub.dev API（`https://pub.dev/api/packages/<name>`）與套件 tarball 原始碼。
「舊版」= repo 根目錄 pubspec.lock。標「推測」= 沒有直接來源。未改動 repo。

## 0. 版本總表（pub.dev，2026-11-06）

| 套件 | 最新穩定 | 發布日 | pub 平台標籤 | 舊版 lock |
| --- | --- | --- | --- | --- |
| just_audio | 0.10.6 | 2026-06-29 | android ios macos web (+linux/windows 靠外掛) | 0.10.6 |
| just_audio_windows | 0.2.3 | 2026-04-04 | windows | - |
| just_audio_media_kit | 2.1.0 | 2025-04-13（repo 2026-04-27 仍有 merge） | 全平台 | - |
| media_kit | 1.2.6 | 2025-12-13 | 全平台 | 1.2.6 |
| media_kit_libs_windows_audio | 1.0.9 | 2023-09-27 | windows | 1.0.9 |
| media_kit_libs_{ios,macos}_audio | 1.1.4 | 2023-09-27 | - | - |
| media_kit_libs_android_audio | 1.3.8 | 2025-10-05 | - | - |
| audio_service | 0.18.19（CHANGELOG 已有 0.18.20） | 2026-06-29 | android ios macos web | 0.18.18 |
| audio_session | 0.2.4 | 2026-06-29 | android ios macos web | 0.2.4 |
| smtc_windows | 1.1.0 | 2025-08-18 | windows | 1.1.0 |
| audio_service_win | 0.0.3 | 2026-03-29 | windows | - |
| audioplayers | 6.8.1 | 2026-06-27 | 全平台 | - |
| flutter_soloud | 5.2.3 | 2026-11-05 | 全平台 | - |
| flutter_inappwebview | 6.1.5 | 2024-10-08 | android ios macos windows web | 6.1.5 |
| flutter_inappwebview 預覽版 | 6.2.0-beta.3 | 2026-02-04 | 同上 | - |
| webview_flutter | 4.14.1 | 2026-07-07 | android ios macos（無 windows） | - |
| webview_windows | 0.4.0 | 2024-02-17 | windows | - |
| desktop_webview_window | 0.4.2 | 2026-11-06 | windows linux macos | - |
| flutter_secure_storage | 11.2.0 | 2026-09-16 | 全平台 | 10.3.1 |
| flutter_secure_storage_darwin | 0.4.3 | 2026-09-16 | - | - |

來源：pub.dev API；平台標籤 `https://pub.dev/api/packages/<name>/score`。

## 1. 音訊後端

### 1.1 各套件現況

**just_audio**（ryanheise）
- README 首行：「Android, iOS, macOS, web, Linux and Windows」，但 Windows、Linux 要另加實作套件。來源：https://github.com/ryanheise/just_audio/blob/minor/just_audio/README.md（2026-11-06）
- Android = ExoPlayer，iOS/macOS = AVPlayer（README 與 CHANGELOG 提到 AVURLAsset、ExoPlayer 行為）。
- Windows 沒有 federated 預設實作。README〈Windows〉列出替代選項：`just_audio_windows`、`just_audio_media_kit`。
- 活躍度：repo pushed_at 2026-06-29，open issues 358（GitHub API）。0.10.6 只是 AGP 9 / Kotlin DSL 相容。
- 自訂 header：`AudioSource.uri(uri, headers: {...})`。預設經本機 HTTP proxy 實作，Android/iOS/macOS 需開 cleartext（`NSAllowsLocalNetworking` 或 Android network security config）。`useProxyForRequestHeaders: false` 時 iOS 走未公開的 `AVURLAssetHTTPHeaderFieldsKey`。來源同上〈Working with headers〉。
- 網易雲部分 http:// URL：另需 ATS / cleartext 設定（README〈Platform specific configuration〉）。
- iOS 對副檔名與 Content-Type 嚴格，Android 較寬容（README 同節）。Bilibili `.m4s` 在 AVPlayer 上能否播：查不到直接證據，需實機 spike。

**just_audio_windows 0.2.3**
- 用 WinRT `MediaPlayer`。README 功能表「request headers」欄**空白**＝不支援。支援 gapless、speed、pitch。
- 結論：Bilibili Referer、YouTube header 都不行，不適合本專案（來源：套件 tarball README，pub.dev/packages/just_audio_windows）。

**just_audio_media_kit 2.1.0**（Pato05）
- 描述：「media_kit bindings for just_audio to support Linux and Windows」。可用 `ensureInitialized(android:, iOS:, macOS:)` 啟用其他平台，但 README 說不必要，因 just_audio 原生已支援。
- Windows 依賴：`media_kit_libs_windows_audio`。
- 功能表：request headers「✅ (untested)」（原始碼 `Media(uri, httpHeaders: audioSource.headers)`）；gapless 「✅ 需手動開啟」且標 highly experimental（`prefetchPlaylist`）；speed、pitch 可；`shuffleOrder` 被忽略；不處理電話中斷。
- 維護：pub 版本停在 2025-04（2.1.0），repo 2026-04-27 仍有 merge（TLS 屬性）。維護者單人，open issues 5。

**media_kit 1.2.6**
- README 平台表：Android 5+、iOS 9+、macOS 10.9+、Windows 7+ 皆支援 audio。來源：https://github.com/media-kit/media-kit
- 有 `setAudioDevice` / `audioDevices`（輸出裝置選擇，README〈Select audio device〉）。
- repo 活躍：main 最新 commit 2026-08-30（fix: memory leaks），open issues 365。但**最後一次 pub 發布是 2025-12-13**，main 上的修正沒發。
- **Windows libmpv 仍是舊快照**：已發布的 `media_kit_libs_windows_audio 1.0.9` 的 CMakeLists 下載 `mpv-dev-x86_64-20230924-git-652a1dd.7z`（mpv v0.36.0-403，FFmpeg n6.0；issue #1460 2026-10-06 也說明）。我解開 tarball 親自確認。
- main 分支的 CMake 已改成 `mpv-dev-x86_64-20251213-git-140ec21`（raw.githubusercontent main），但**未發布成 pub 版本**。這是 workspace 遷移後的狀態，要用得 git 依賴（推測：含 monorepo 遷移風險）。
- 相關 open issues：#1436（Windows ARM64 + libmpv 0.41 更新 PR，2026-08-02）、#1442 與一則「bundled libmpv 2023-09-24 在 HLS master 鎖定字幕 rendition 導致黑畫面」（video 場景，音訊影響小）、#1472（Windows 同時 dispose 多個 player 原生 crash，2026-11-04）。來源：https://github.com/media-kit/media-kit/issues
- iOS/macOS audio libs 也停在 2023-09 發布版（main 有 2026-06-27 "bump libmpv"，未發布）。

**audio_service 0.18.19 / audio_session 0.2.4**
- audio_service README 表格：Android / iOS / macOS / Web；**Windows 不在其中**，pub 標籤也無 windows。macOS 無 lock screen controls。
- audio_session pub 標籤無 windows（Windows 無中斷概念，合理）。
- Windows SMTC：`smtc_windows 1.1.0`（獨立套件，需 rustup 建置，13 likes、30 天下載 ~11.9k）。也有 `audio_service_win 0.0.3`（`implements: audio_service_platform_interface`，3 likes，新套件，推測成熟度低）。
- 附註：舊版 lock 裡 audio_service 是 0.18.18；0.18.19/0.18.20 為 AGP 9 與 iOS 修正。

**flutter_soloud 5.2.3 / audioplayers 6.8.1**
- flutter_soloud README：串流不支援 MP4/M4A（Bilibili/YouTube AAC 不能走串流），lib 內無 HTTP header 參數。不適合。來源：套件 tarball README。
- audioplayers：lib 無 header 參數；issue #806「Play audio from url with Http headers」已關閉（未驗證結論）。在 6.8.1 原始碼 grep 不到 header 設定。不適合串流加自訂 header（除非自架本機 proxy）。
- 兩者都不含系統媒體控制，需另接。

### 1.2 AVPlayer 能否播 WebM/Opus
- 官方文件：查不到明確聲明。Apple 文件頁（AVPlayer）只說播 AVAsset。
- 間接證據：Stack Overflow 的 `AVURLAsset.audiovisualTypes()` 列表有 caf、m4a、mp4、flac、mp3、aac、xhe，**沒有 webm / ogg / opus**（https://stackoverflow.com/questions/21879981，舊文章，iOS 版本不明）。
- 另一則（https://stackoverflow.com/questions/42383310）有人稱 iOS 17.4.1 上 VP8+Opus 的 webm 可播，但是「partial answer」，無法確認是 AVPlayer 或 WebView。
- Safari 的 WebM/Opus 支援（iOS 15 起音訊）≠ AVPlayer；不要混用。
- 結論：**視為 AVPlayer 不能播 WebM/Opus**（推測），Apple 平台 YouTube 一律選 m4a/AAC 串流（Opus 僅 Android/Windows 可選）。要驗證須實機 spike。

### 1.3 「四平台單一後端」組合

| 組合 | 一致性 | 代價 |
| --- | --- | --- |
| **A. just_audio（Android/iOS/macOS 原生）+ just_audio_media_kit（僅 Windows）** | 單一 just_audio API；Windows 走 libmpv | Windows libmpv 為 2023-09 快照（發布版）；header「untested」要自測；gapless 在 Windows 為實驗性；just_audio_media_kit 單人維護 |
| **B. media_kit 單獨四平台** | 真正單一後端（libmpv），行為一致，有輸出裝置選擇，可播 WebM/Opus | iOS/macOS/Windows 的 libmpv 皆為 2023-09 發布版；沒有 audio_service 整合（要自己把 Player 狀態餵給 Now Playing/MediaSession，社群有手寫範例，推測）；背景播放、中斷處理（audio_session）自己接；App Store 體積加大（libmpv+FFmpeg） |
| C. just_audio + just_audio_windows | 原生 | Windows 不支援 request headers，Bilibili/YouTube 不可行 |
| D. audioplayers / flutter_soloud | - | header 或 M4A 串流不支援，淘汰 |

建議：**A**。理由：Android/iOS/macOS 用平台原生解碼，省電、背景與中斷行為最成熟，且與 audio_service/audio_session 已整合；Windows 用 libmpv 補 header、WebM/Opus。若之後要「輸出裝置選擇」，Windows/macOS 端可再評估 media_kit（其他平台 just_audio 無對應 API，推測）。

媒體控制組合：
- Android / iOS / macOS：`audio_service` + `audio_session`。
- Windows：`smtc_windows`（較成熟）自己橋接 player 狀態；`audio_service_win` 太新，只當備選。
- 注意 audio_service 在 macOS 沒有 lock screen controls（表格），Now Playing 是否完整需實測。

必做 spike（無法由文件確認）：
1. Bilibili `.m4s`（AAC，需 Referer）在 iOS/macOS 經 just_audio proxy 能否播、能否 seek、duration 是否正確。
2. just_audio_media_kit Windows 帶 Referer/UA header 實測（含 YouTube googlevideo 長連線、Range seek）。
3. Windows 同時多 Player dispose 的 crash（media-kit #1472）是否影響單 Player 設計。
4. gapless：Android ExoPlayer / AVPlayer 對 AAC 無縫的實際表現；Windows `prefetchPlaylist` 實驗性。
5. 若 libmpv 2023 快照出問題：改用 git 依賴指向 media-kit main（已含 2025-12 libmpv），評估風險。

## 2. 登入 WebView

### 2.1 套件現況
- **flutter_inappwebview 6.1.5（2024-10-08，穩定版）已含 Windows 與 macOS**：pubspec 的 `flutter.plugin.platforms` 有 windows→`flutter_inappwebview_windows ^0.6.0`、macos→`flutter_inappwebview_macos`。6.1.0 release notes 寫「Added initial Windows support」「InAppWebView widget MacOS support」（https://github.com/pichillilorenzo/flutter_inappwebview/releases）。
  - 但 Windows 實作版本仍是 0.6.0（0.x），beta 為 6.2.0-beta.3（2026-02-04，Dart ≥3.8），**穩定版 6.2.0 尚未出**（Discussion #2646 詢問發布日，無答案）。穩定版 2024-10 後無更新，已 25 個月。
  - 需求：Windows 需 `nuget` CLI 在 PATH、WebView2 Runtime；macOS 要開 App Sandbox「Outgoing Connections (Client)」。來源：https://inappwebview.dev/docs/intro
- **webview_flutter 4.14.1**：官方，**僅 Android / iOS / macOS**（pubspec platforms），**無 Windows**。
- **webview_windows 0.4.0**（2024-02-17）：WebView2，僅 Windows，已 20 個月沒更新；controller 有 `executeScript`、`setUserAgent`、`clearCookies`，**沒有讀 cookie API**（原始碼 grep）。
- **desktop_webview_window 0.4.2**（2026-11-06 剛發）：Windows(WebView2) / macOS(WKWebView) / Linux，另開原生視窗；有 `getAllCookies()`（`webview_impl.dart`）；沒有 Android/iOS。

### 2.2 讀取 HttpOnly cookie

| 套件/平台 | 能讀嗎 | 依據 |
| --- | --- | --- |
| flutter_inappwebview Windows | 是，含 `isHttpOnly` | `cookie_manager.cpp` 用 CDP `Network.getCookies`，回傳 `httpOnly` 欄位（0.6.0 tarball 原始碼） |
| flutter_inappwebview iOS/macOS | 是 | 平台介面文件註明走 `WKHTTPCookieStore.getAllCookies`（含 HttpOnly） |
| flutter_inappwebview Android | 是（推測：Android `CookieManager.getCookie` 含 HttpOnly 值） | 平台介面列為支援；HttpOnly 旗標本身可能拿不到 |
| webview_flutter iOS/macOS | 是，`getCookies(domain)` 用 `getAllCookies` | `webkit_webview_cookie_manager.dart` |
| webview_flutter Android | 值有，但有 bug：用 `cookie.split('=')` 取 `.last`，**cookie 值含 `=` 會被截斷**，且 domain 欄位是整個 URL | `android_webview_cookie_manager.dart` |
| webview_windows | 否（要靠 JS，讀不到 HttpOnly） | 無 API |
| desktop_webview_window | 是（`getAllCookies`），不確定是否含 HttpOnly | 未讀 native 碼：推測 |

### 2.3 YouTube（Google）登入與 UA
- Google 對嵌入式 WebView 的 OAuth 回 `disallowed_useragent`（Google Developers Blog：https://developers.googleblog.com/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews ）。注意：該政策針對 OAuth endpoint；本專案是直接登入 `accounts.google.com` 網頁取 cookie，是否被擋、改 UA 是否有效，**查不到可靠來源，需實測**（推測：改成桌面 Chrome UA 可能過，但會隨 Google 風控變動）。
- inappwebview 與 webview_windows 都可設 UA（`setUserAgent` / `InAppWebViewSettings.userAgent`）。

### 2.4 推薦
- **主選：flutter_inappwebview 6.1.5 單一套件覆蓋四平台**（Windows 用 WebView2、macOS/iOS 用 WKWebView、Android 用 WebView），cookie API 統一且 Windows 能拿到 HttpOnly。代價：Windows/macOS 實作標 0.x、穩定版兩年沒更新；若遇 bug 只能升 6.2.0-beta.3（Dart ≥3.8 ，Flutter 3.47 滿足）。
- 備選（若 inappwebview 在 Windows 出問題）：Windows 單獨用 desktop_webview_window，其餘用 inappwebview 或 webview_flutter。webview_flutter 不能單獨成案（無 Windows）。
- B 站、網易雲用 QR，不需 WebView；只有 YouTube 需要。登入後只取需要的 cookie（SAPISID 系列等）。

## 3. flutter_secure_storage（最新 11.2.0，2026-09-16）

- 11.0.0（2026-08-06）為**破壞性升級**：移除 v10 deprecated 項目，從 v9 直升會讓舊資料失效，需先升 v10；Android minSdk 24、compileSdk 37。11.1.0 新增 `checkUpgradeStatus()`。全新專案無遷移問題。來源：https://github.com/juliansteenbakker/flutter_secure_storage/blob/develop/flutter_secure_storage/CHANGELOG.md
- 舊版 lock 為 10.3.1。
- **macOS 簽章/entitlement**：
  - README：預設（Data Protection Keychain）要在 `DebugProfile.entitlements` 與 `Release.entitlements` 加 `keychain-access-groups`（空陣列）。這需要 provisioning profile；免費開發者帳號 Xcode 會嵌入綁定本機的 profile，**app 只能在建置的那台 Mac 啟動，無法散布**（README〈macOS: Keychain Sharing requires provisioning〉，issue #1176 已關）。
  - 繞法：`MacOsOptions(usesDataProtectionKeychain: false)` 走 legacy keychain，不需 entitlement 與 provisioning（README 同節）。
  - 但 issue #1104（Developer ID 簽章、關 sandbox、已設 `usesDataProtectionKeychain: false` 仍出現 `-34018 errSecMissingEntitlement`）：2026-08-29 留言指根因是 `baseQuery` 仍加 `kSecAttrAccessible`/`kSecAttrSynchronizable`；darwin 0.4.2（2026-09-11）修了 synchronizable 查詢，**accessible 是否已修無法確認**（issue 已 completed 但留言所述程式碼我沒逐行比對，標推測）。
  - **未簽章 / ad-hoc 簽章**：沒有找到針對 ad-hoc 的專門 issue 或文件，查不到。-34018 是缺 entitlement 的典型錯誤（issues #293、#804、#686「signed and notarized app read 回 null」）。推測：ad-hoc 簽章 + 預設 Data Protection Keychain 會失敗，ad-hoc + legacy keychain 較可能可用，且 keychain ACL 綁 app 身分，重簽/更新 .app 後可能要重新授權（#1104 留言提到 auto-updater 重寫 bundle 的變體）。**需在實機 spike**。
  - 與 `usesDataProtectionKeychain: false` 時 iCloud 同步不可用（synchronizable 相關）：本專案不需要。
- **iOS**：同樣要 `keychain-access-groups`（README 同節）；若有 App Group，需列在群組名稱，否則「寫入看似成功但實際未寫入」。darwin 0.4.0 起 iOS 最低 13.0。iOS 資料在解除安裝後可能留存（Keychain 行為，一般知識，未查來源）。
- Windows：`flutter_secure_storage_windows 4.2.2`，用 Windows 憑證保護；11.x changelog 提到 deleteAll/containsKey 加 mutex（Dart ≥3.10 自動套用）。
- Android：minSdk 24；移除 EncryptedSharedPreferences；open issues #1282（Samsung 生物辨識註冊後 resetOnError 遞迴），影響有開生物辨識選項者，本專案不必開。

## 4. 結論摘要
見回覆；本檔未列的皆為「查不到」。
