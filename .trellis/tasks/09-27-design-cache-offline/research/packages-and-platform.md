# Research: 快取與離線設計 — 套件與平台客觀事實

- **Query**: 為「快取與離線」設計蒐集套件版本、維護狀態、平台限制與 API 事實（圖片快取、HTTP 層快取、音訊快取、平台快取目錄、網路狀態偵測）
- **Scope**: external（pub.dev / GitHub / Android 官方文件 / mpv 手冊）+ 內部（FMP `pubspec.yaml` / `pubspec.lock` 現況比對）
- **Date**: 2026-09-27
- **查證方式**：版本號與最後發佈日期一律讀 pub.dev（用 `https://pub.dev/api/packages/<name>` 這個 pub.dev 官方 JSON 端點，內容與 pub.dev 套件頁一致；未特別註明則來源即此端點）；維護狀態讀對應 GitHub repo 的 `pushed_at` 與 open issues（GitHub REST API）；套件行為讀對應版本的原始碼（GitHub raw）與官方 README；Android 系統行為讀 `developer.android.com` 與 `support.google.com`；mpv 快取行為讀 `mpv.io` 官方手冊（master）。沒有用 context7（環境未提供 context7 / tavily 工具，全部改用可直接存取的 pub.dev API、GitHub API 與官方文件頁）。本文件不含任何未查證的版本號或 API 細節；查不到的欄位明確標註「查不到」。

FMP 現況對照（讀自 repo 內 `pubspec.yaml` / `pubspec.lock`，非外部查證）：
- `dio: ^5.11.1`（lock 內實際解析為 `5.11.1`，即目前最新版）
- `cached_network_image: ^4.0.0`（lock 內實際解析為 `4.0.0`，非目前最新的 `4.0.2`）
- `flutter_cache_manager: ^3.4.2`（lock 內實際解析為 `3.4.2`，非目前最新的 `3.4.5`）
- 安裝的 Flutter 版本：`3.47.1`（Dart `3.13.1`），高於 cached_network_image 4.0.2 要求的 `Flutter >=3.44.0` / `Dart ^3.12.0`，故理論上可升到 4.0.2

---

## Findings

### 1. 圖片快取套件

#### cached_network_image

| 項目 | 內容 |
|---|---|
| 最新穩定版 | `4.0.2` |
| 最後發佈日期 | 2026-09-23 |
| 來源 | https://pub.dev/packages/cached_network_image （資料取自 `pub.dev/api/packages/cached_network_image`） |
| GitHub repo | https://github.com/Baseflow/flutter_cached_network_image |
| repo 最後 push | 2026-09-24（`pushed_at`，GitHub API），open issues 327 個 — 近期仍有活躍 commit |

- 4.0.2 的 `environment` 要求 `sdk: ^3.12.0`、`flutter: >=3.44.0`；依賴 `flutter_cache_manager: ^3.4.1`、`octo_image: ^2.1.0`，以及新拆出的 `cached_network_image_platform_interface`、`cached_network_image_web`。
- **自訂 HTTP client / dio 整合**：`CachedNetworkImage` widget 建構子有 `cacheManager`（型別 `BaseCacheManager?`）參數，可傳入自訂 `CacheManager`（原始碼：`cached_network_image/lib/src/cached_image_widget.dart` 第 47-61、222-242 行，GitHub `Baseflow/flutter_cached_network_image@main`）。實際抓取行為由底層 `flutter_cache_manager` 的 `FileService` 決定（見下一節），本套件本身不直接曝露 dio 整合點，是透過傳入客製化的 `CacheManager` 間接達成。
- **Windows / Linux 支援狀況（已知限制）**：cached_network_image 本身是純 Dart 套件，不宣告平台限制；但底層 `flutter_cache_manager` 在 Windows / Linux 上使用不同的中繼資料儲存後端（見下一節），行為與 Android/iOS/macOS 不同。GitHub 上仍有數個與 Windows 相關、狀態為 open 的 issue：
  - #1023「CachedNetworkImage logs errors / crashes on Windows when image URL returns 404」（open，最後更新 2026-03-30）
  - #981「Deadlock Freezes on windows if image data is invalid」（open，最後更新 2024-10-22）
  - #887「CacheManager attempts to create file named guid.* on Windows」（open，最後更新 2023-11-13，檔名相關）
  - #707「please add windows support」（open，最後更新 2023-09-01，仍掛著但套件目前技術上可在 Windows 執行，此 issue 較像是要求官方正式承諾支援）
  （來源：`https://api.github.com/search/issues?q=repo:Baseflow/flutter_cached_network_image+windows+...`）
- **快取上限與手動清除 API**：`CachedNetworkImage` 本身不直接提供清快取方法；清除要透過底層 `CacheManager`（見下一節的 `emptyCache()` / `removeFile()`）。`CachedNetworkImage.evictFromCache(url)` 靜態方法存在，用於清除單一 URL 的快取（原始碼第 47-53 行，內部呼叫 `cacheManager.removeFile`／預設 `CachedNetworkImageProvider.defaultCacheManager`）。

#### flutter_cache_manager（cached_network_image 的依賴）

| 項目 | 內容 |
|---|---|
| 最新穩定版 | `3.4.5` |
| 最後發佈日期 | 2026-09-19 |
| 來源 | https://pub.dev/packages/flutter_cache_manager |
| GitHub repo | https://github.com/Baseflow/flutter_cache_manager |
| repo 最後 push | 2026-09-23（GitHub API `pushed_at`），open issues 133 個 |

- **儲存後端**：檔案本體一律落地檔案系統（`FileSystem` / `IOFileSystem`，實際路徑見第 4 節 `path_provider`）；中繼資料（cache key、過期時間等）依平台不同：
  - Android／iOS／macOS：預設用 **sqflite**（`CacheObjectProvider`）
  - 其他平台（**包含 Windows、Linux**）：預設用 **`JsonCacheInfoRepository`**（不是 sqlite，是 JSON 檔）
  - Web：`NonStoringObjectProvider`（不落地）
  原文（`flutter_cache_manager/lib/src/config/config.dart` dartdoc，GitHub `Baseflow/flutter_cache_manager@master`）：
  > "On Android, iOS and macOS this defaults to `CacheObjectProvider`, a sqflite implementation due to legacy... On the other platforms this defaults to `JsonCacheInfoRepository`."
  對應實作（`_config_io.dart`）：
  ```dart
  static CacheInfoRepository _createRepo(String key) {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return CacheObjectProvider(databaseName: key);
    }
    return JsonCacheInfoRepository(databaseName: key);
  }
  ```
- **上限設定方式**：`Config` 建構子的 `stalePeriod`（預設 **30 天**）與 `maxNrOfCacheObjects`（預設 **200**），原始碼同上（`_config_io.dart`）。
- **自訂 HTTP client / dio 整合**：`FileService` 是抽象介面（`abstract class FileService { Future<FileServiceResponse> get(...); }`），預設實作 `HttpFileService` 用 `package:http`；原始碼 dartdoc 明確寫：
  > "One can easily adapt it to use dio or any other http client."
  （`flutter_cache_manager/lib/src/web/file_service.dart`）。也就是說 dio 整合需自行實作一個 `FileService`，透過 `Config(fileService: ...)` 注入，套件本身不附帶現成的 dio 版 `FileService`。
- **手動清除 API**：`CacheManager.emptyCache()`（清整個快取）、`CacheManager.removeFile(key)`（清單一檔案）、`CacheStore.getCacheSize()`（讀目前快取大小）。（`cache_manager.dart` / `cache_store.dart`，同 repo）

#### extended_image（替代方案）

| 項目 | 內容 |
|---|---|
| 最新穩定版 | `10.1.0` |
| 最後發佈日期 | 2026-07-12 |
| 來源 | https://pub.dev/packages/extended_image |
| GitHub repo | https://github.com/fluttercandies/extended_image |
| repo 最後 push | 2026-07-12（GitHub API），open issues 44 個 |
| 依賴 | `extended_image_library: ^5.0.0`（實際圖片快取邏輯在此子套件） |

- `extended_image_library` 最新版 `5.0.1`（發佈 2025-05-30，來源 `pub.dev/api/packages/extended_image_library`）。
- **是否支援自訂 cache 策略**：查到的原始碼（`extended_image_library/lib/src/_extended_network_image_utils_io.dart`，GitHub `fluttercandies/extended_image_library@main`）顯示快取是**扁平檔案快取**，固定寫入 `getTemporaryDirectory()/<cacheImageFolderName>`，只提供：
  - `clearDiskCachedImages({Duration? duration})` — 清全部或清超過某個存活時間的檔案
  - `clearDiskCachedImage(url, {cacheKey})` — 清單一檔案
  - `getCachedSizeBytes()` — 讀快取大小
  沒有找到等同 `flutter_cache_manager` `Config`（`stalePeriod`／`maxNrOfCacheObjects`）或 `FileService` 那種可插拔的策略介面；`httpClient` 是靜態 getter，指向 `dart:io` 的 `HttpClient`，不是可替換的抽象介面，沒有找到官方文件說明如何整合 dio。extended_image 主 repo 的 README 全文未提及 "cache" 相關章節。

#### Flutter 內建 `ImageCache`

- 來源：`https://api.flutter.dev/flutter/painting/ImageCache-class.html`（Flutter 官方 API 文件）
- 原文：
  > "Class for caching images. Implements a least-recently-used cache of up to 1000 images, and up to 100 MB. The maximum size can be adjusted using `maximumSize` and `maximumSizeBytes`."
- **確認為純記憶體快取**：文件與命名皆未提及落地磁碟；`ImageCache` 是 `PaintingBinding` 持有的全域單例（`imageCache` 頂層屬性），生命週期跟著 App process，**App 重啟（process 結束）即清空**，且與磁碟快取（如 `flutter_cache_manager`）是兩層互相獨立的快取。
- 限制：預設上限 1000 張圖或 100 MB（先到者為準），可透過 `maximumSize` / `maximumSizeBytes` 調整；不提供依 URL 手動落地磁碟的機制。

---

### 2. HTTP 層快取

#### dio_cache_interceptor

| 項目 | 內容 |
|---|---|
| 最新穩定版 | `4.0.7` |
| 最後發佈日期 | 2026-06-26 |
| 來源 | https://pub.dev/packages/dio_cache_interceptor |
| GitHub repo（monorepo） | https://github.com/llfbandit/dart_http_cache |
| repo 最後 push | 2026-07-10（GitHub API），open issues 僅 1 個（相對非常少） |
| dio 相容性 | `pubspec.yaml` 宣告 `dio: ^5.2.0+1`，涵蓋 FMP 目前用的 `dio 5.11.1`，**相容** |

- **儲存後端**：`dio_cache_interceptor` 本體只含 `MemCacheStore`（純記憶體，`http_cache_core/lib/src/store/mem_cache_store.dart`）。其餘後端是同 monorepo 下的**獨立 pub 套件**：
  | 套件 | 最新版 | 最後發佈 | 底層儲存 |
  |---|---|---|---|
  | `http_cache_file_store` | 2.0.2 | 2026-07-09 | 純檔案系統 |
  | `http_cache_hive_store` | 5.1.1 | 2026-07-09 | `hive_ce` |
  | `http_cache_isar_store` | 3.1.0 | 2026-05-20 | `isar_community 3.3.2`（**與 FMP 現用的 `isar_community: ^3.3.2` 同一大版本**） |
  | `http_cache_drift_store` | 7.0.1 | 2026-07-09 | `drift` |
  | `http_cache_sembast_store` / `http_cache_mmkv_store` / `http_cache_objectbox_store` | 各自獨立版本 | 查頁面可得，未逐一列出 | sembast／MMKV／ObjectBox |
  （來源：`pub.dev/api/packages/<name>`，逐一查詢）
- **是否適合快取 JSON API 回應**：套件描述本身即「respecting HTTP directives (or not)」。`CachePolicy` enum（`http_cache_core/lib/src/model/cache/cache_policy.dart`）提供：
  - `request`：有 cache 指令才快取，沿用標準 HTTP 語意
  - `forceCache` / `refreshForceCache`：**即使來源沒有回 cache 指令也強制快取**（dartdoc：「In short, you'll save every successful GET requests.」）
  - `noCache` / `refresh`：不快取或略過快取直接打來源
  也就是說即使排行榜／搜尋結果等 API 沒有回 `Cache-Control`，也能用 `forceCache` 之類的策略強制快取，這點是查到的客觀事實。

（此段沒有查到「dio_cache_interceptor 是否明確測試過 dio 5.11.1」這種逐版相容性資訊，只查到 pubspec 宣告的版本區間；`^5.2.0+1` 語法保證可解析到 `5.11.1`。）

---

### 3. 音訊快取

#### just_audio 的 `LockCachingAudioSource`

| 項目 | 內容 |
|---|---|
| 最新穩定版 | `0.10.6` |
| 最後發佈日期 | 2026-06-29 |
| 來源 | https://pub.dev/packages/just_audio |
| GitHub repo | https://github.com/ryanheise/just_audio |
| repo 最後 push | 2026-06-29（GitHub API），open issues 345 個 |

- **是否仍是 experimental**：查了目前（`minor` 分支，即目前開發／最新發佈分支）原始碼 `just_audio/lib/just_audio.dart` 第 3368-3373 行，`LockCachingAudioSource` 類別上方仍標註 `@experimental`，dartdoc 原文：
  > "This is an experimental audio source that caches the audio while it is being downloaded and played. It is not supported on platforms that do not provide access to the file system (e.g. web)."
  **結論：截至 0.10.6，`LockCachingAudioSource` 仍是 experimental API，未被扶正。**
- **支援平台（含 Windows 確認）**：`just_audio` 套件本身在 `pubspec.yaml` 的 `flutter.plugin.platforms` 只宣告了 **android、ios、macos、web** 四個平台（來源：`pub.dev/api/packages/just_audio` 的 pubspec 內容），**沒有 windows、沒有 linux**。官方 README（`ryanheise/just_audio@minor` 分支 `README.md`）明確說明：
  > Windows / Linux 支援需要額外加裝第三方聯邦式套件（`just_audio_media_kit`、`just_audio_windows`、`just_audio_libwinmedia` 三選一），並提醒「For issues with the Windows implementation, please open an issue on the respective implementation's GitHub issues page.」——換句話說 Windows/Linux 上跑的其實是另一個社群套件的實作，不是 just_audio 官方原生實作，`LockCachingAudioSource` 依賴的本機 HTTP proxy 機制（README 原文：「just_audio's proxy (used to implement features such as headers, caching and stream audio sources) runs on a `localhost` HTTP server」）在 Windows/Linux 上是否等效運作**沒有查到官方文件明確保證**。
  這與 FMP 自己 `pubspec.yaml` 註解一致：FMP 目前的架構是 **Android 用 just_audio、Windows 用 media_kit**（並未使用 `just_audio_media_kit` 這個橋接套件），因此 `LockCachingAudioSource` 在 FMP 目前架構下只會在 Android 路徑上出現。
- **已知問題（GitHub issues，依 `updated_at` 排序，皆與 `LockCachingAudioSource` 直接相關）**：
  - #1213「An Unhandled Exception is thrown when loading LockCachingAudioSource fails.」— open，最後更新 2026-09-17（非常新）
  - #594「`LockCachingAudioSource` does not recover from network errors」— open，最後更新 2026-02-11
  - #1425「Player returning 0 position and duration when using LockCachingAudioSource and accept-ranges missing from response headers」— open，最後更新 2025-03-18
  - #1469「LockCachingAudioSource throws unhandled exception with cache and part files on `_fetch`」— **closed**，最後更新 2025-05-28
  （來源：`https://api.github.com/search/issues?q=repo:ryanheise/just_audio+LockCachingAudioSource+...`）

#### media_kit（libmpv 封裝）

| 項目 | 內容 |
|---|---|
| 最新穩定版 | `1.2.6` |
| 最後發佈日期 | 2025-12-13（距查證日 2026-09-27 已約 9.5 個月未出新版） |
| 來源 | https://pub.dev/packages/media_kit |
| GitHub repo | https://github.com/media-kit/media-kit |
| repo 最後 push | 2026-08-30（GitHub API，**repo 本身仍有近期 commit**，但尚未對應新的 pub.dev 發版），open issues 353 個 |

- **是否有 demuxer cache／邊放邊落地到磁碟的機制**：media_kit 的 `NativePlayer`（libmpv 後端）原始碼（`media_kit/lib/src/player/native/player/real.dart` 第 2470-2471 行，GitHub `media-kit/media-kit@main`）對所有平台（註解標示 `// ALL:`，非僅 Android）硬編碼設定：
  ```dart
  'cache': 'yes',
  'cache-on-disk': 'yes',
  ```
  也就是 libmpv 的網路串流確實會落地到磁碟的暫存快取檔。**但**查了 mpv 官方手冊（`https://mpv.io/manual/master/`，`--cache-on-disk` 條目）原文：
  > "Write packet data to a temporary file, instead of keeping them in memory... **The cache file is deleted when playback is closed.** ... A cache file is generally worthless after the media is closed, and it's hard to retrieve any media data from it (**it's not supported by design**)."
  **結論（客觀事實，非建議）：media_kit／libmpv 目前啟用的磁碟快取是播放期間的暫存緩衝，關閉播放即刪除，且設計上不支援事後取出重用，不等同「下載存檔」。**
  mpv 手冊另外記載 `--stream-record=<file>`（把 demuxer 收到的原始資料寫到指定檔案，可用於網路串流，但「Switching streams or seeking during recording might result in recording being stopped and/or broken files」）與 `dump-cache <start> <end> <filename>` 指令（含 `<end>=no` 的連續傾印模式）。media_kit 的 `NativePlayer` 有公開的 `setProperty()` / `command()` 方法（`real.dart` 第 1232、1432 行），理論上可讓應用層呼叫這些 mpv 原生指令；但**這是 mpv 底層能力，media_kit 官方文件（README、pub.dev 頁）本身沒有針對「邊聽邊存」寫任何說明或封裝 API**。
- **GitHub issue 現況（截至查證日）**：
  - #269「[Enhancement] Cache Media」— **open**，2023-07-17 開出，2025-01-17 仍有人追問進度。maintainer（`alexmercerind`）在 2023-08-09 明確回覆：
    > "Network caching is not present as a feature & will be likely implemented sometime in future... It will be implemented from scratch, there's no existing dedicated API."
    後續討論中（2024-04）多位使用者提到唯一可行的變通方法是**自建本機 HTTP proxy server，邊轉發邊把 bytes 寫檔**（同 just_audio `LockCachingAudioSource` 的做法），因為要在 mpv/libmpv C 原始碼層面加真正的快取功能超出專案能力範圍（maintainer 原話：「we don't really have the required skillset & time to implement it directly in C source-code of mpv」）。
  - #633「Please add completed cache file save to local storage with encrypt」— open，2024-04-02 開出，同樣尚無官方實作。
  **結論：截至查證日，media_kit 沒有官方、文件化的「播放同時落地成可重用檔案」功能，此為社群長期待實作的 enhancement request。**

#### 兩者在「邊聽邊存」的支援程度比較（僅陳述查到的事實）

- `just_audio`：`LockCachingAudioSource` 是官方套件內建、有公開 Dart API（`cacheFile`、`downloadProgressStream`、`clearCache()`）的功能，但標記 experimental，且只在 Android/iOS/macOS 的原生實作路徑上有文件保證；Windows/Linux 需經第三方橋接套件，官方文件未保证該功能在該路徑上等效。
- `media_kit`：不論哪個平台，都**沒有**官方封裝的「邊聽邊存為可重用檔案」API；libmpv 有的磁碟快取機制（`cache-on-disk`）依 mpv 官方手冊明確設計為播放期暫存、關閉即刪，不支援事後取出；若要邊聽邊存，需自行在應用層實作類似 just_audio 的本機 proxy 方案，或改用 mpv 的 `--stream-record` / `dump-cache` 原生指令（media_kit 有暴露 `command()`/`setProperty()` 可呼叫，但無官方文件與封裝）。

---

### 4. 平台快取目錄

#### path_provider — `getApplicationCacheDirectory()`

| 項目 | 內容 |
|---|---|
| `path_provider` 最新版 | `2.1.6`（發佈 2026-06-15），來源 https://pub.dev/packages/path_provider |
| 平台實作套件版本 | `path_provider_android 2.3.1`（2026-04-08）／`path_provider_windows 2.3.0`（2024-07-09，**已一年多沒更新**）／`path_provider_linux 2.2.2`（2026-06-24）／`path_provider_foundation 2.6.0`（2026-01-15，iOS+macOS 共用） |

各平台實際對應的系統路徑／概念（原始碼來源：`flutter/packages` monorepo，`main` 分支，逐一列出）：

- **Android**：`path_provider_android/lib/src/path_provider_android_real.dart` 第 44-49 行，直接回傳 `context.cacheDir`（Android `Context.getCacheDir()`，即內部儲存的 App 專屬快取目錄，實體路徑概念上是 `/data/data/<package>/cache`）。註：該套件目前用 `dart:jni`（jnigen）直接呼叫 Android API，已無獨立的 Kotlin/Java 外掛程式碼目錄。
- **iOS / macOS**（`path_provider_foundation/lib/src/path_provider_foundation_real.dart` 第 62-71 行）：對應 `NSSearchPathDirectory.NSCachesDirectory`。macOS 上會額外把 App 的 bundle identifier 接在路徑後面；**iOS 則不會**（原始碼註解：「This is not done for iOS, for compatibility with older versions of the plugin.」），因為 iOS App 本身已是逐 App 沙盒。
- **Windows**（`path_provider_windows/lib/src/path_provider_windows_real.dart` 第 124-126、243-259 行）：對應 `WindowsKnownFolder.LocalAppData`（即 `%LOCALAPPDATA%`）底下再接一層由執行檔 VERSIONINFO 資源讀出的 `<CompanyName>\<ProductName>` 子目錄。**沒有額外的「Cache」字面子資料夾**——即 ApplicationCache 與 ApplicationSupport 用的是同一套 `<CompanyName>\<ProductName>` 命名規則，差別只在於前者掛在 `LocalAppData`（不隨帳號漫遊）、後者掛在 `RoamingAppData`（`%APPDATA%`）。
- **Linux**（`path_provider_linux/lib/src/path_provider_linux.dart` 第 70-88 行）：對應 `xdg.cacheHome`（即 XDG Base Directory 規範的 `$XDG_CACHE_HOME`，未設定時預設 `~/.cache`）底下的 `<applicationId>` 子目錄；若該目錄不存在，會 fallback 嘗試以執行檔名稱為子目錄名（原始碼註解引用了一個相容性問題 `flutter/flutter#186834`）。

#### Android 系統對快取目錄的自動清除行為（官方文件）

- 來源：`https://developer.android.com/training/data-storage/app-specific`（Android 官方開發者文件，「Create cache files」「Remove cache files」章節）
- 原文（節錄）：
  > "Caution: When the device is low on internal storage space, Android may delete these cache files to recover space. So check for the existence of your cache files before reading them."
  > "Even though Android sometimes deletes cache files on its own, you shouldn't rely on the system to clean up these files for you. You should always maintain your app's cache files within internal storage."
  **結論：Android 系統在裝置儲存空間不足時「可能」（而非保證、也無固定時機）自動清除 App 的快取目錄內容，官方明確建議 App 自己做存在性檢查與清理，不要依賴系統。**
- **使用者手動清除 App 快取**：來源 `https://support.google.com/android/answer/7431795`（Google 官方支援頁，Android 設定 App 管理頁面說明），原文：
  > "Clear cache: Deletes temporary data. Some apps may be slow the next time you open them."
  即使用者可在系統設定的「應用程式資訊」頁面對單一 App 執行「清除快取」，此動作會清掉 `getCacheDir()`／`getExternalCacheDir()` 底下的內容（該頁面未逐一列出實作細節，此為官方對使用者的行為描述，非開發者 API 文件）。

#### Windows／Linux 的系統層級自動清快取機制

- **查不到** Windows 官方文件（`learn.microsoft.com`）中有任何作業系統層級「自動清除 `%LOCALAPPDATA%` 底下任意程式子目錄」的機制說明；本次查證只確認了 `path_provider_windows` 如何決定路徑（見上），沒有查到 Windows 系統本身會主動清除該路徑內容的官方陳述。
- **查不到** Linux 發行版或 XDG 規範中有「系統自動清除 `$XDG_CACHE_HOME` 內容」的通用機制說明；XDG Base Directory 規範本身只定義路徑慣例，未查到規範文字承諾自動清除行為。
- 因此本題目前的查證結果是：**沒有找到 Windows／Linux 官方文件證實存在系統層級自動清快取機制**（這不等於「確定不存在」，只是查證範圍內沒有找到相關官方陳述），與 Android 有明確官方文件記載的行為形成對比。

---

### 5. 網路狀態偵測

#### connectivity_plus

| 項目 | 內容 |
|---|---|
| 最新穩定版 | `7.3.1` |
| 最後發佈日期 | 2026-07-23 |
| 來源 | https://pub.dev/packages/connectivity_plus |
| GitHub repo | https://github.com/fluttercommunity/plus_plugins（monorepo，`connectivity_plus` 只是其中一個子套件） |
| repo 最後 push | 2026-09-26（GitHub API，非常新），open issues 109 個（monorepo 全部子套件合計） |
| 支援平台 | README 平台表格列出 **Android、iOS、macOS、Web、Linux、Windows 全部打勾**（來源：`plus_plugins/packages/connectivity_plus/connectivity_plus/README.md`，`main` 分支） |

- **官方明確警語**（README 開頭 Note 區塊，原文）：
  > "You should not rely on the current connectivity status to decide whether you can reliably make a network request. Always guard your app code against timeouts and errors that might come from the network layer. Connection type availability does not guarantee that there is an Internet access. For example, the plugin might return Wi-Fi connection type, but it might be a connection with no Internet access due to network requirements (like on hotel Wi-Fi networks where user often needs to go through a captive portal to authorize first)."
  **結論：官方文件本身就明講「偵測到網路介面連上不代表真的能上網」，並直接建議用「請求本身要處理逾時與錯誤」而不是依賴連線狀態來判斷是否離線** —— 也就是查到了任務描述裡預期的那種警語與建議搭配用法，來源是套件自己的 README，不是第三方推論。
- 其餘平台特定備註（同 README）：Android 上「同時開行動網路和 Wi-Fi 時，系統只會回報 Wi-Fi」；iOS/macOS 上沒有獨立的 VPN 介面類型，VPN 連線會回報成 `other`。
- 版本需求（README「Requirements」章節）：Flutter >=3.19.0、Dart >=3.3.0 <4.0.0、iOS >=13.0、macOS >=10.15、Java 17、AGP >=8.12.1、Gradle wrapper >=8.13、Xcode >=26.1.1。

---

## Caveats / 查不到

- 沒有用到 context7 或 tavily：本次執行環境沒有掛載這兩個工具，改用 pub.dev 官方 JSON API、GitHub REST API 與各官方文件頁直接查證，資料來源與官方頁面內容一致（pub.dev API 就是 pub.dev 頁面的資料來源）。
- **dio_cache_interceptor 與 dio 5.11.1 的逐版相容性**：只查到 pubspec 宣告的版本區間（`^5.2.0+1`，涵蓋 5.11.1），沒有查到官方是否針對 5.11.x 做過專門測試或已知問題列表。
- **cached_network_image / extended_image 是否有「已知平台限制」的官方聲明文件**（例如 pub.dev 頁面的 Platform 支援表格細節）：本次用 GitHub issue 搜尋佐證 Windows 上仍有已知 bug（見上），但沒有找到官方 README 或文件明確列出「不支援某平台」的正式聲明；cached_network_image／flutter_cache_manager 的 pub.dev pubspec 都沒有宣告 `flutter.plugin.platforms` 限制（純 Dart 套件，理論上全平台可跑），實際限制來自底層儲存後端行為（已於上文列出）。
- **Windows／Linux 系統層級自動清快取機制**：查不到官方文件證實存在（見第 4 節說明），非「確認不存在」，只是本次查證範圍內沒有找到來源。
- **media_kit `command()`/`setProperty()` 呼叫 `stream-record`／`dump-cache` 在 Flutter/Dart 層的官方封裝或範例**：查不到；只確認了這兩個方法存在且為 public API，以及 mpv 手冊對這兩個原生指令的行為說明，沒有查到 media_kit 官方或社群提供的 Dart 範例程式碼。
- **`http_cache_sembast_store` / `http_cache_mmkv_store` / `http_cache_objectbox_store` 的確切版本號與發佈日期**：已確認存在於同一 monorepo，但本次沒有逐一查詢它們的 pub.dev 頁面（時間關係只深入查了 `file_store`／`hive_store`／`isar_store`／`drift_store` 四個較常見的後端）。
