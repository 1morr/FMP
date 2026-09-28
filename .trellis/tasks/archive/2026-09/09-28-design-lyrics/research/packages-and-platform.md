# 套件與平台事實

- 查證日期：2026-09-28
- 查證方式：context7 / tavily-search / tavily-extract / pub.dev（各節註明）

本文件只列事實，不含設計建議。版本、最後發佈日期、平台支援一律以 pub.dev 為準；日期未標時區者為 UTC。
查不到的項目一律寫「查不到」；不確定的推論標「推測」。

---

## A. 桌面多視窗

### A1. `desktop_multi_window`

查證方式：pub.dev 套件頁與 `/versions` 頁、pub.dev API、GitHub API（context7 查不到此套件，`resolve-library-id` 無法解析，故改用 pub.dev / GitHub）。

- 最新版本 **0.3.1**，發佈日 **2026-08-26**（pub.dev API `published` 欄位 = `2026-08-26T06:49:31.717877Z`）。
  來源：https://pub.dev/api/packages/desktop_multi_window
- 套件頁宣告平台：**Windows / Linux / macOS**（三平台皆有實作）。
  來源：https://pub.dev/packages/desktop_multi_window
- 授權 Apache-2.0；Likes **289**；pub points **160**；發佈者為 mixin.dev（verified publisher）。
  來源：https://pub.dev/packages/desktop_multi_window/score
- 版本歷史：0.0.1（2022-01-28）… 0.3.0（2025-10-28），0.3.1（2026-08-26）。
  來源：https://pub.dev/packages/desktop_multi_window/versions
- 原始碼位於 **monorepo** `MixinNetwork/flutter-plugins` 的 `packages/desktop_multi_window` 子目錄。
  來源：https://github.com/MixinNetwork/flutter-plugins
- 倉庫層級數字（**整個 monorepo，不是此套件單獨的數字**）：stars 512、open issues 146、`pushed_at` 2026-09-01。
  來源：https://api.github.com/repos/MixinNetwork/flutter-plugins
- 與此套件相關的近期 commit：2026-08-26 發佈準備；2026-06-22 加入 Swift Package Manager 支援（#482）；2026-06-22 Windows 全螢幕修復（#483）。
- 架構事實：README 說明**每個視窗使用各自獨立的 Flutter engine**（非共用 isolate）。
- 維護狀態：有在持續發佈（0.3.0 → 0.3.1 間隔約 10 個月），倉庫活躍；但 open issue 數偏高（146，含 monorepo 全部外掛）。
- 查不到：官方沒有逐平台功能對照表；也查不到 CI 對三平台的測試覆蓋說明。

### A2. Flutter 官方多視窗（Desktop Windowing API）

查證方式：tavily-search + 官方部落格（WebFetch 對 flutter.dev 可用）。

- **截至 2026-09-28，Flutter 官方有多視窗 API，但仍是實驗性、只在 `main` channel**，尚未進入 stable。
- 啟用方式（官方部落格逐字）：
  ```
  flutter channel main
  flutter upgrade
  flutter config --enable-windowing
  ```
  來源：https://flutter.dev/blog/desktop-windowing-apis
- 官方部落格標題 **"Introducing the Desktop Windowing API for Flutter"**，作者 Matthew Kosarek，發佈日 **2026-08-24**。
  來源：https://flutter.dev/blog/desktop-windowing-apis
- 同名頁面 banner 顯示 **Flutter 3.47** 為當時版本。
  來源：https://flutter.dev/blog/desktop-windowing-apis
- 官方 API 元素（部落格內文）：`WindowController`、`DialogWindowController`、`Window`、`DialogWindow`、`WindowScope`、`WindowControllerDelegate`（回呼 `onWindowDestroyed`、`onWindowCloseRequested`）；建立視窗用 `WindowController(title: ..., size: ...)`。
- 入口改為 **`runWidget`** 而非 `runApp`。
- 視窗型別：regular / dialog / tooltip / popup / satellite。
- Material 整合（規劃中）：`showDialog`、`showMenu`、`Tooltip` 在桌面會產生真正的 OS 視窗，行動平台則沿用現有 in-app 實作 —— 同一份程式碼兩邊都能跑。
- 桌面三平台（macOS / Linux / Windows）「out of the box」可用。
- 社群分析（**非官方來源**）：此 API 目前「available on the main channel as an experimental feature … the API surface may change based on feedback. Production use is recommended only for applications that can tolerate breaking changes between Flutter versions」。
  來源：https://blog.redlinesoft.net/posts/flutter-desktop-windowing-api （2026-09-17）
- 治理背景（**非官方新聞來源**）：Google 在 I/O 2026 宣布 Canonical 成為 Flutter desktop 的 lead maintainer 與「strategic steward」（Windows/macOS/Linux）；此多視窗 API 由 Canonical 主導。
  來源：https://www.omgubuntu.co.uk/2026/05/flutter-desktop-canonical-maintained
- 查不到：正式納入 stable 的時程、以及穩定性承諾（官方文件只說實驗性、可能變更）。

### A3. `window_manager` 與各平台視窗能力

查證方式：pub.dev、GitHub 原始碼（raw）、GitHub API、tavily-search。

套件基本事實：

- 最新版本 **0.5.2**，發佈日 **2026-07-04**。
  來源：https://pub.dev/packages/window_manager/versions
- 平台：**Windows / Linux / macOS**；授權 MIT；Likes **1.13k**；pub points **160**；下載數 **728k**。
  來源：https://pub.dev/packages/window_manager
- 倉庫 `leanflutter/window_manager`：stars 845；`pushed_at` 2026-09-19（活躍）。
  來源：https://api.github.com/repos/leanflutter/window_manager
- README 有**遷移通知**，指向新專案 `libnativeapi/nativeapi-flutter`（作者轉向新套件）。
  來源：https://github.com/leanflutter/window_manager
- **注意**：GitHub API 回報 `open_issues_count: 0`，但 issue #576 明顯存在 → 此欄位不可信，issue 狀態一律以網頁為準。
  來源：https://github.com/leanflutter/window_manager/issues/576

逐 API 平台能力（來源：Dart 原始碼 `packages/window_manager/lib/src/window_manager.dart` 的 `@platforms` 標註，
https://github.com/leanflutter/window_manager/blob/main/packages/window_manager/lib/src/window_manager.dart ）：

| API | `@platforms` 標註 |
|---|---|
| `getId` / `blur` / `isFocused` / `setClosable` / `setProgressBar` / `setHasShadow` | `macos, windows` |
| `isDockable` / `dock` / `undock` / `setIcon` | `windows` |
| `setMovable` / `setVisibleOnAllWorkspaces` / `setBadgeLabel` | `macos` |
| `setAlwaysOnBottom` / `startResizing` | `linux, windows` |
| `grabKeyboard` / `ungrabKeyboard` | `linux` |
| `setAlwaysOnTop` / `setIgnoreMouseEvents` / `setOpacity` / `setBackgroundColor` / `setPosition` | **無 `@platforms` 標註**（宣告上三平台皆可，但各平台實作程度不同） |

各平台實作事實：

- **透明（Linux）**：Linux 後端把 `backgroundColor` 的 ARGB 拆成 `rgba(...)` 字串，透過 `GtkCssProvider` 套用 `window { background-color: <color>; }`。即 Linux 的「透明」是靠 CSS 背景色，不是視窗層的 alpha。
  來源：https://raw.githubusercontent.com/leanflutter/window_manager/main/packages/window_manager/linux/window_manager_plugin.cc
- **置頂（Linux）**：`setAlwaysOnTop` 的 Linux 實作直接呼叫 `gtk_window_set_keep_above(get_window(self), isAlwaysOnTop);`。
  來源：同上檔案。
- **滑鼠穿透（`setIgnoreMouseEvents`）**：變更紀錄顯示 **0.2.0 只實作 macOS + Windows**（PR #89），**Linux 沒有**；該 Linux 後端 `.cc` 檔中完全找不到 ignore / click-through 相關實作。→ 在 Linux 上呼叫此 API 沒有對應行為。
  來源：https://github.com/leanflutter/window_manager/blob/main/packages/window_manager/CHANGELOG.md （`## 0.2.0` 條目：「[macos & windows] Implement `setIgnoreMouseEvents` metnod #89」）
- **`setOpacity`**：0.1.4 實作於 macOS/Windows（#37 #45）；**0.2.5 才實作於 Linux**（#157）。
  來源：同上 CHANGELOG（`## 0.1.4`、`## 0.2.5`）。
- **已知未修 issue**：#179「BackgroundColor transparent doen't work on (Arch) Linux」**建立於 2022-07-12**，累積 16 則留言後，於 **2026-09-21** 由維護者 lijy91 關為 **not planned**；回報內容為 Windows 正常、Linux 顯示黑色。**注意：報告初稿把「建立日」誤記成「關閉日」——實際關閉是 2026-09-21，不是 2022-07-12。**
  來源：https://github.com/leanflutter/window_manager/issues/179 （`gh api` 讀 `created_at` / `closed_at` / `state_reason`）
- 查不到：官方文件**沒有**逐 API 的 Wayland 支援對照表；tavily-search 只找到「Linux/macOS/Windows ✔️ Fully supported」這種籠統的功能表。
  來源：https://leanflutter.dev/window_manager （介紹頁）

Wayland 平台層級事實（與套件無關，屬 compositor 協定層）：

- **XDG shell 故意不提供**客戶端視窗定位（全域座標）與堆疊（置頂/置底）控制。
  來源：https://wayland.app/protocols/xdg-shell ；https://discourse.ubuntu.com/t/gtk-backend-selection-or-why-gtk-cannot-open-display-0/17657
- **GNOME Discourse 逐字**：「Wayland does have support for input regions, but those are limited to your own window surfaces; you cannot set input regions on windows you did not create within your process, unlike on X11」「positioning windows directly using global coordinates, or changing the input mask—are not possible with Wayland. Additionally, all the hints API may not work」。
  來源：https://discourse.gnome.org/t/overlay-with-gtk3-on-wayland/2216
- **GTK4 遷移指南**把 `gtk_window_set_keep_above()`、`gtk_window_set_keep_below()`、`gtk_window_move()` 列為**已移除的 X11 專有 API**。
  來源：https://docs.gtk.org/gtk4/migrating-3to4.html
- `wlr-layer-shell` 協定可提供錨定 + 置頂/置底層，但**一個 surface 只能有一個角色**（不能同時是 xdg-shell 與 layer-shell 視窗）。
  來源：https://wayland.app/protocols/wlr-layer-shell-unstable-v1
- **推測**：GTK3 + Wayland 下 `gtk_window_set_keep_above()` 是否生效取決於 compositor（GNOME Mutter / KDE KWin 各有實作差異）。查不到權威說明，需實機驗證。
- 生態系直接佐證：套件 `desktop_lyrics` README 明寫 **「Wayland：由於技術限制，目前不支援點擊穿透」**，且 Linux 上 overlay 尺寸/位置**不會自動跟隨系統縮放與解析度變化**（X11 與 Wayland 皆然）。
  來源：https://pub.dev/packages/desktop_lyrics

其他多視窗外掛（同類選項，只列事實）：

- `window_manager_plus` — 以 window_manager 為基礎再加多視窗；**不支援 Linux**。
- `multi_window_native` — 原生多視窗；僅 macOS / Windows。

---

## B. 行動平台浮動歌詞（只列事實）

### B1. Android 懸浮窗（overlay）

查證方式：tavily-search 取 developer.android.com 與 Google Play 政策頁正文。

權限與版本限制：

- 需在 `AndroidManifest.xml` 宣告 `<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>`。
  來源：https://developer.android.com/reference/android/Manifest.permission#SYSTEM_ALERT_WINDOW
- **API 23（Android 6）起 SAW 是 special permission**：manifest 宣告不夠，必須用 `ACTION_MANAGE_OVERLAY_PERMISSION` intent 把使用者帶到系統設定頁手動授予。
  來源：https://developer.android.com/reference/android/content/Intent#ACTION_MANAGE_OVERLAY_PERMISSION
- **API 26（Android 8）起**，`TYPE_SYSTEM_ALERT`、`TYPE_PHONE`、`TYPE_PRIORITY_PHONE` 等視窗型別被 deprecated，**必須改用 `TYPE_APPLICATION_OVERLAY`**。
  來源：https://developer.android.com/reference/android/view/WindowManager.LayoutParams#TYPE_APPLICATION_OVERLAY
- **Android 10（Go edition）無法取得 SYSTEM_ALERT_WINDOW**。
  來源：https://developer.android.com/about/versions/10/behavior-changes-all
- **Android 11**：`ACTION_MANAGE_OVERLAY_PERMISSION` 一律把使用者帶到**最上層**的設定頁（不能再導到單一 App 的頁面）。
  來源：https://developer.android.com/about/versions/11/behavior-changes-11
- **Android 12（API 31）行為變更**（以下皆出自同一頁）：
  - 遮蔽（obscuring）視窗的**不透明度上限預設 0.8**，超過會擋掉穿透觸控（obscured touch）。
  - 系統封鎖**不可信觸控（untrusted touch）** 事件。
  - 新增 `HIDE_OVERLAY_WINDOWS` 權限與 `Window.setHideOverlayWindows()`，讓其他 App 可要求系統對其隱藏 overlay。
  - Android 12 起「make it more difficult to obtain the SYSTEM_ALERT_WINDOW permission」。
  來源：https://developer.android.com/about/versions/12/behavior-changes-12
- **Android 15 行為變更**：以 SAW 作為啟動前景服務（FGS）的豁免條件收緊 —— 必須已有**可見的** `TYPE_APPLICATION_OVERLAY` 視窗，否則拋 `ForegroundServiceStartNotAllowedException`。
  來源：https://developer.android.com/about/versions/15/behavior-changes-15

Google Play 政策：

- 敏感權限頁面允許的用法是「引導使用者前往系統設定頁批准特殊權限（例如 `SYSTEM_ALERT_WINDOW`）」。
  來源：https://support.google.com/googleplay/android-developer/answer/9888170
- 裝置與網路濫用政策禁止「阻擋或干擾其他 App 顯示廣告」（overlay 擋廣告是明確違規樣態）。
  來源：https://support.google.com/googleplay/android-developer/answer/9888379
- **查不到**：Google Play 有一條專門針對 overlay / SAW 的**申報表單或單獨禁令**（本次搜尋結果中沒有）。

### B2. iOS

查證方式：tavily-search 取 Apple Developer 文件正文（Apple 文件頁為 JS 渲染，WebFetch 只回標題，故改用搜尋回傳的正文）。

- **沒有 API 可以讓 App 在其他 App 之上繪製系統級懸浮視窗**。系統唯一的浮動窗是 Picture in Picture。
- `AVPictureInPictureController.ContentSource` **只接受**：`AVPlayerLayer`、`AVSampleBufferDisplayLayer`、或 `AVPictureInPictureVideoCallViewController` 來源 → **PiP 僅限影片內容**，無法用來顯示歌詞文字。誤用會被 App Review 以 "Misusing PiP" 拒絕。
  來源：https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource
- `MPNowPlayingInfoCenter.nowPlayingInfo` 接受的是 **`MPMediaItem` 的屬性子集**：`AlbumTitle`、`AlbumTrackCount`、`AlbumTrackNumber`、`Artist`、`Artwork`、`Composer`、`DiscCount`、`DiscNumber`、`Genre`、`MediaType`、`PersistentID`、`PlaybackDuration`、`Title`，外加 `MPNowPlayingInfoProperty*` 鍵（如 elapsed time、playback rate、media type、external content id）。**歌詞不在這個子集裡。**
  來源：https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
- Apple 文件逐字：**「You don't have direct control over what information the system displays, or its formatting.」** → 即使把歌詞塞進非標準欄位，系統也不會照 App 的意思顯示。
  來源：https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
- **Live Activities（ActivityKit）時間限制**：活動最長活躍 **8 小時**，之後可在鎖屏再保留最多 **4 小時**，總計最多 **12 小時**。
  來源：https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- **更新預算**：ActivityKit 的推送更新有 budget，超出即被系統節流。`Info.plist` 的 `NSSupportsLiveActivitiesFrequentUpdates` 設為 `YES` 可提高預算（使用者可在系統設定關閉；以 `ActivityAuthorizationInfo.frequentPushesEnabled` 查詢目前狀態）；APNs **priority 5** 的更新不計入預算，**priority 10** 計入。
  來源：https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
- Live Activity 的版面是**固定版型**（鎖屏卡片 + Dynamic Island 區域），可自訂的只有各區域內容，無法自由排版成長歌詞列表。
  來源：https://developer.apple.com/design/human-interface-guidelines/live-activities
- 生態系現況：Apple Developer Forums 有一則與 FMP 需求幾乎相同的提問（音樂 App 想讓 Live Activity **隨每行歌詞**更新），回報更新被延遲或遺失，且該串在本次查證時**無人回答**。
  來源：https://developer.apple.com/forums/ （音樂 App + Live Activity 逐行更新討論串）

---

## C. LRC / 逐字歌詞解析的 Dart 套件

查證方式：pub.dev 套件頁、`/versions`、搜尋頁；context7 無法解析這些套件。

- **`lrc`**
  - 版本 **1.0.2**，發佈日 **2023-09-28**；純 Dart（不依賴 Flutter）；授權 BSD-3-Clause；Likes 18；pub points 160。
  - 能力：支援 simple / extended / enhanced LRC 及混合模式 `extended_enhanced`；支援**逐詞（word-level）時間戳**；提供 `stream` 屬性。
  - 倉庫：`Yivan000/lrc`。
  - 來源：https://pub.dev/packages/lrc ；https://pub.dev/packages/lrc/versions
- **`lyrics_parser`**
  - 版本 **1.0.0-nullsafety.0**，發佈日 **2021-02-03**。
  - 限制：要求 **Dart < 3.0.0** → 與 Dart 3 / 現行 Flutter **不相容，無法安裝**。
  - 來源：https://pub.dev/packages/lyrics_parser
- **`lrc_parser`**
  - 版本 **0.0.1**，發佈日 **2026-02-03**。
  - 能力：基於 **ANTLR4**；支援 normal / word-by-word / mixed 三種解析層級；支援時間平移（time shift）。
  - 來源：https://pub.dev/packages/lrc_parser
- **`flutter_lyric`**
  - 版本 **3.0.8**，發佈日 **2026-09-16**；授權 MIT；Likes 109；pub points 160。
  - 能力：內建 **`.lrc` 解析器** + **`.qrc` 解析器**（QQ 音樂逐字格式）+ `LrcToQrcUtil.convert` 轉換工具 + **YRC**（網易雲逐字純文字格式）解析；逐字高亮渲染元件。
  - **不支援 KRC（酷狗格式）**。
  - 注意：**3.0.5 已被撤回（retracted）**，同日被 3.0.6 取代 → 鎖版本時避開 3.0.5。
  - 倉庫：`ozyl/flutter_lyric`。
  - 來源：https://pub.dev/packages/flutter_lyric ；https://pub.dev/packages/flutter_lyric/versions
- **`desktop_lyrics`**
  - 版本 **0.0.8**，發佈日 **2026-07-09**；桌面置頂浮動歌詞 overlay 外掛；平台 Windows / Linux / macOS。
  - **不解析 LRC**：App 必須自己把時間軸傳進去（`DesktopLyricsFrame.fromTimedTokens` / `fromKaraokeTimeline`）。
  - 預設 `enabled: false`；README 明寫 **Wayland 不支援點擊穿透**；Linux 上 overlay 尺寸/位置不跟隨系統縮放/解析度變化。
  - 來源：https://pub.dev/packages/desktop_lyrics
- 專門的 **YRC / QRC / KRC Dart 解析套件**：**查不到**。pub.dev 搜 `qrc`、`krc`、`yrc` 只得到 QR code 與酷狗 API 相關套件；唯一覆蓋 QRC + YRC 的是上面 `flutter_lyric` 的內建解析器。
- pub.dev 搜 `lyric` 的其他結果（第 1 頁，另有第 2 頁）：`genius_lyrics`、`lyrics_parser`、`chordify_lyrics`、`lyric_xx`、`mmoo_lyric`、`flutter_lyric_custom_ui`、`my_lyric`。
  來源：https://pub.dev/packages?q=lyric

---

## D. LLM API 呼叫

查證方式：tavily-search + tavily-extract（OpenAI 官方文件與說明中心）、pub.dev、Sentry 官方文件。

OpenAI 相容端點與金鑰處理的官方立場：

- OpenAI 說明中心文章 5112595「Best Practices for API Key Safety」（頁面標示更新日 **2026-09-28**）逐字：
  - **「Never deploy your key in client-side environments like browsers or mobile apps」**
  - 「requests should always be routed through your own backend server」
  - 「Never commit your key to a repository」
  - 建議每位團隊成員使用獨立金鑰；優先用 workload identity federation 取代長期金鑰。
  來源：https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety
  → 事實：對純客戶端 App（如 FMP）而言，把 OpenAI key 內嵌在 App 內正是官方明文反對的做法。
- OpenAI 生產最佳實踐逐字：「Avoid exposing your API keys in your code or public repositories; store them in a secure location」「expose keys to your application via environment variables or key management services」；建議為金鑰設定到期時間 + 定期輪替，且**撤銷舊金鑰前先確認新金鑰可用**。
  來源：https://platform.openai.com/docs/guides/production-best-practices
- **OpenAI 相容端點是生態系事實標準**：`POST /v1/chat/completions` 搭配可覆寫的 `base_url`，由 Ollama、vLLM、LM Studio、DeepSeek、OpenRouter、xAI、GPUStack 等自架與第三方服務提供。
  來源：https://platform.openai.com/docs/api-reference/chat

客戶端儲存 API key（Flutter / Dart 生態）：

- **`flutter_secure_storage`**
  - 版本 **11.2.0**，發佈日 **2026-09-16**；發佈者 steenbakker.dev；平台 Android / iOS / Linux / macOS / Web / Windows。
  - **Linux**：底層用 **libsecret**，需要系統 keyring（`gnome-keyring` / `kwalletmanager` / secret-service）以及 `libsecret-1-dev`、`libsecret-1-0` 套件。
  - **Windows**：需要 C++ **ATL** 標頭。
  - **iOS / macOS**：需要 **Keychain Sharing** entitlement（`keychain-access-groups`），除非改用 `MacOsOptions(usesDataProtectionKeychain: false)`。
  - **Android**：minSdk 23。
  來源：https://pub.dev/packages/flutter_secure_storage
- 其他常見做法（只列事實）：環境變數 / 設定檔 / 系統 keyring。keyring 與 secure storage 的關係即上一條的 libsecret / Keychain / Credential Manager 後端。

「不要把 API key 寫進 log」的常見實作手法：

- **Sentry Flutter 官方文件「Scrubbing Sensitive Data」**列出的四種手法：
  1. 在 log 語句內**去識別化**（例如 email → 內部 id）；
  2. 用 **`beforeBreadcrumb`** 在 breadcrumb 被附到事件前過濾掉；
  3. **關閉 logging breadcrumb integration**；
  4. 另外設定 **server-side scrubbing**（在 Sentry UI 設定，立即對新事件生效）。
  來源：https://docs.sentry.io/platforms/dart/guides/flutter/data-management/sensitive-data
- 同一份文件的事實警告：部分 SDK（JS 與 Java 的 logging integration）會**自動抓取已執行的 log 語句**當 breadcrumb；多數 SDK 會把 **HTTP query string 與 fragment** 加進 breadcrumb → 「Do not log PII if using this feature」。
  來源：同上
- `sentry_logging` 套件變更紀錄中有一條 **「Sanitize sensitive data from URLs (span desc, span data, crumbs, client errors)」**，顯示 URL 內 token 的清理是 SDK 既有能力。
  來源：https://pub.dev/packages/sentry_logging/changelog
- 通用 logger level 的事實（非 Sentry 專屬）：verbose 等級（`Level.all` / `silly` / `fine` / `verbose`）可能記錄 API key、使用者識別與**完整請求 URL** → 不應在 production 開啟。
  來源：https://pub.dev/packages/logging
- 查不到：Flutter 生態沒有一個「官方指定」的 redaction 套件；本節列出的都是各 SDK 自己的機制。

---

## 小結：FMP 重寫時要先確認的平台事實

1. **官方多視窗有，但不穩定**：Flutter 的 Desktop Windowing API 存在（`WindowController`、`runWidget`、`flutter config --enable-windowing`），但只在 `main` channel、標示實驗性、API 可能變更（官方部落格 2026-08-24，Canonical 主導）。要穩定就得走 `desktop_multi_window`（0.3.1 / 2026-08-26，每視窗一個 engine）。
2. **Wayland 是桌面浮動歌詞的最大風險**：XDG shell 刻意不給全域定位與堆疊控制；`window_manager` 的 Linux 後端根本沒有 `setIgnoreMouseEvents` 實作，`desktop_lyrics` 也明寫 Wayland 不支援點擊穿透。
3. **置頂的可行性取決於 GTK 版本與 compositor**：`gtk_window_set_keep_above()` 是 GTK4 已移除的 X11 專有 API，而 GTK3 + Wayland 下是否生效查不到權威說明 —— 必須實機驗證，不能只看文件。
4. **Android 懸浮窗是「使用者手動授予的特殊權限」**：SAW 需 `ACTION_MANAGE_OVERLAY_PERMISSION` 引導設定；API 26 起強制 `TYPE_APPLICATION_OVERLAY`；Android 12+ 有遮蔽觸控、不可信觸控、`HIDE_OVERLAY_WINDOWS` 三重限制；Android 15 又收緊以 SAW 啟動 FGS 的豁免；Go edition 拿不到 SAW。
5. **iOS 上「其他 App 之上的懸浮歌詞」做不到**：PiP 只接受影片來源且誤用會被拒；`MPNowPlayingInfoCenter` 的屬性子集不含歌詞，且「你無法控制系統顯示什麼」；Live Activity 有 12 小時總上限與更新預算節流 —— Apple 論壇已有同類未解問題。
6. **LRC 解析有現成選擇，逐字格式只有部分覆蓋**：`lrc`（1.0.2 / 2023-09-28，純解析、逐詞）與 `flutter_lyric`（3.0.8 / 2026-09-16，含渲染 + QRC/YRC）；`lyrics_parser` 已與 Dart 3 不相容；**沒有專門的 KRC Dart 套件**。
7. **`desktop_lyrics` 可直接當桌面 overlay 的候選**（0.0.8 / 2026-07-09），但**它不解析 LRC**，且 Wayland 下無點擊穿透、Linux 不跟隨縮放。
8. **LLM key 不能內嵌在客戶端**：OpenAI 官方明文要求不要在瀏覽器或行動 App 部署 key、要走自家後端；若仍採 BYOK，儲存只能靠 `flutter_secure_storage`（Linux 需系統 keyring、Windows 需 ATL、macOS/iOS 需 Keychain entitlement），且必須自行在 SDK 層遮蔽日誌（`beforeBreadcrumb` / 關閉 logging integration / server-side scrubbing）。
