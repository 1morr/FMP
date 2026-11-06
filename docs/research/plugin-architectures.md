> 2026-11-06 訪談（`/grill-with-docs`）時的研究輸出，查證日期見內文。brief〈查證過的事實〉R6–R7 引用本檔。

# 音源插件機制研究（MusicFree / LX Music / Spotube / Listen1 / Nuclear / Harmony）

查證日期 2026-11-06。來源以 GitHub 原始碼為主（用 `gh api` 讀 master），官方文件站多半連不上或 404，已註明。
標記：「事實」附來源；「推測」是我的推論；「查不到」就是沒找到。
GitHub blob 前綴簡寫：MF = https://github.com/maotoumao/MusicFree/blob/master/、
LX = https://github.com/lyswhut/lx-music-desktop/blob/master/、
SP = https://github.com/team-spotube/spotube/blob/master/。

## 0. 結論速覽

| 產品 | 插件語言 / 引擎 | 能力寬度 | 遠端歌單寫入 | VIP 標識欄位 | 登入 |
| --- | --- | --- | --- | --- | --- |
| Spotube v6 beta | Kotlin 編成 JS，Zipline（QuickJS） | 最寬（有型別化介面） | 介面有（create/update/delete/add/remove） | 沒有（只有 `explicit`） | 插件自管 + WebView |
| MusicFree | JS（CommonJS），宿主 `Function()` 執行 | 中等（約 14 個可選方法） | 沒有 | 沒有 | 只有 `userVariables`（使用者貼字串） |
| Nuclear | TypeScript，provider 註冊 | 中等（6 種 provider） | 只有本地歌單，遠端寫入查不到 | 查不到 | 查不到 |
| Listen1 | 內建 provider（非下載插件） | 中（含登入、使用者歌單、推薦） | 該檔案沒有寫入函式 | 用 `fee` 判斷可否播放，但不暴露 VIP 標識 | provider 內自己實作 |
| LX Music | 單檔 JS 腳本，Electron sandbox 外的隔離 window | 最窄（只有 musicUrl/lyric/pic） | 不可能 | 不可能 | 不適用 |
| Harmony Music | 無插件系統 | 無 | 無 | 無 | 無 |

寬窄排序（寬到窄）：Spotube v6 > MusicFree ≈ Nuclear ≈ Listen1（內建，非插件）> LX Music。

## 1. MusicFree（maotoumao/MusicFree，最後 push 2026-10-15）

### 1.1 插件協議
事實：插件是 CommonJS 模組，匯出 `IPluginDefine`。來源：MF`src/types/plugin.d.ts`（WebFetch 讀回的內容）。

欄位：`platform`（必填）、`version`、`appVersion`、`srcUrl`（更新用）、`primaryKey`、`defaultSearchType`、`supportedSearchType`、
`cacheControl`（`cache | no-cache | no-store`）、`author`、`description`（markdown）、`userVariables`、`hints`。

方法全部可選：
- `search(query, page, type)`
- `getMediaSource(musicItem, quality)` -> `{url, headers, userAgent, quality}` 或 null
- `getMusicInfo`、`getLyric`
- `getAlbumInfo`、`getMusicSheetInfo`、`getArtistWorks`
- `importMusicSheet(urlLike)`、`importMusicItem(urlLike)`
- `getTopLists`、`getTopListDetail`
- `getRecommendSheetTags`、`getRecommendSheetsByTag`
- `getMusicComments`

事實：沒有 login / logout、沒有建立歌單、加歌、移除歌曲、收藏同步這類寫入方法。依據是上面這份型別定義的完整方法清單。

### 1.2 能力宣告與 UI
- 宿主靠「方法存不存在」判斷能力（推測，依「全部可選」的型別；未讀 UI 程式碼逐一確認）。
- `supportedSearchType` 宣告插件能搜哪些類型（music/album/artist/sheet/lyric）。
- 音質只有 4 級：`"low" | "standard" | "high" | "super"`。來源：MF`src/types/music.d.ts` 第 8 行。

### 1.3 媒體物件與 VIP
事實：`IMusicItem` 欄位是 `id, platform, artist, title, alias?, duration, album, artwork, url?, source?, lyric?, qualities?`，
外加 `[k: string]: any`（任意可序列化欄位）。來源：MF`src/types/music.d.ts` 第 30-63 行。
事實：全文沒有 vip / paid / fee 之類欄位（對 music.d.ts、common.d.ts、plugin.ts 搜 `vip|paid|payment` 無結果）。
推測：插件若要標 VIP，只能塞進 `[k: string]: any` 的自訂欄位，宿主不認得，UI 不會顯示。
事實：官方 bilibili 插件（`MusicFreePlugins/dist/bilibili/index.js`）內 `vip` 出現 0 次。

### 1.4 登入與憑證
事實：`userVariables: [{key, name?, hint?}]` 讓使用者在設定頁填字串，插件經 `env.userVariables` 讀取。
來源：MF`src/core/pluginManager/plugin.ts` 第 915-927 行（`env.getUserVariables()` 從 `_internalPluginMeta` 取）。
事實：宿主沒有登入流程 API。bilibili 插件自己用 axios 去抓匿名 cookie（`buvid3` 等）。
憑證保管：使用者填的字串存在宿主的 plugin meta；是否加密或進 Keychain 查不到（推測：明文本機儲存）。

### 1.5 宿主 API 與執行環境
事實：宿主只提供一份固定 `require` 白名單：`cheerio, crypto-js, axios, dayjs, big-integer, qs, he, webdav`，
外加一個 deprecated 的 `@react-native-cookies/cookies` 假物件。來源：MF`src/core/pluginManager/plugin.ts` 第 57-67 行。
事實：`axios.defaults.timeout = 2000`（第 36 行），所有插件共用。
事實：執行方式是 `Function('use strict'; return function(require, __musicfree_require, module, exports, console, env, URL, process){ <插件原始碼> })`
（第 935-947 行）。沒有 sandbox：插件跑在宿主的 JS 主執行環境（React Native Hermes），能碰到全域物件。
`env` 內容：`getUserVariables, userVariables, appVersion, os: "android", lang: "zh-CN"`（第 915-927 行）。
注意：`os` 與 `process.platform` 是寫死的 `"android"`。

### 1.6 安裝與更新
事實：兩種安裝方式，本地 `.js` 檔，或 `installPluginFromUrl(url)`（axios GET 後直接 `new Plugin(code)`）。
來源：MF`src/core/pluginManager/index.ts` 第 183、272-300 行。更新：讀插件的 `srcUrl` 再裝一次（第 429-435 行）。
以 `hash`（`sha256(path@appVersion)` 一類，第 1009 行）判斷已安裝。`appVersion` 欄位用 semver 檢查相容（第 1022 行）。
事實：安裝流程沒有權限對話框、沒有簽章（原始碼無相關檢查）。
事實：官方「訂閱」格式是一份 `plugins.json`：`{desc, plugins:[{name,url,version}]}`。
來源：https://github.com/maotoumao/MusicFreePlugins/blob/master/dist/_plugins/plugins.json 。
官方文件站：搜尋結果只指向 musicfree.upup.fun（plugins.json 的 desc 內有寫），本次未能開啟，內容查不到。

## 2. LX Music（lyswhut/lx-music-desktop）

事實：自訂源是單一 JS 腳本，在隱藏的 Electron `BrowserWindow` 內執行，`contextIsolation: true, nodeIntegration: false, sandbox: false`，
由 preload 注入全域 `globalThis.lx`。來源：LX`src/main/modules/userApi/main.ts` 第 74-88 行、
LX`src/main/modules/userApi/renderer/preload.js`。

### 2.1 腳本 API（preload.js）
- `lx.EVENT_NAMES = {request, inited, updateAlert}`（第 19-22 行）。
- `lx.on(EVENT_NAMES.request, handler)`：handler 收 `{source, action, info}`，回 Promise。
- `lx.send(EVENT_NAMES.inited, {openDevTools, sources, status})`：宣告能力，要在腳本最後呼叫。
- `lx.request(url, options, callback)`：封裝 `needle`，timeout 上限 60 秒（約第 205 行）。
- `lx.utils`：`crypto.aesEncrypt/rsaEncrypt`、`buffer`、`zlib`（第 273-318 行）。`lx.version`、`lx.env = 'desktop'`（第 320-326 行）。

### 2.2 能力宣告
事實：`sources` 的 key 被寫死為 `kw, kg, tx, wy, mg, local`（第 28 行）；每個 source 宣告 `{type:'music', actions, qualitys}`。
`actions` 只能是 `'musicUrl' | 'lyric' | 'pic'`（型別：LX`src/common/types/user_api.d.ts` 第 3-4 行）。
除 `local` 外每個 source 只允許 `musicUrl`（第 37-44 行）。音質只能是 `128k, 320k, flac, flac24bit`（第 29-36 行）。
宿主會把腳本宣告與自己的白名單取交集（第 143-157 行），宣告多的會被丟掉。

### 2.3 回傳值驗證
- `musicUrl` 回傳必須是 `^https?:` 字串且長度 <= 2048（第 77-80 行）。
- `lyric` 要有 `lyric` 字串且 <= 51200 字元（第 58-64 行）。
- `pic` 同樣是 URL 字串。

### 2.4 能力範圍
很窄：腳本只是「把 LX 自己的歌曲 id 換成可播網址」。搜尋、榜單、歌單、專輯都由 LX 內建的 6 個平台實作，
腳本沒有入口。沒有 VIP 標識、沒有登入流程、沒有遠端寫入（事實，由 actions 白名單得出）。
安裝：使用者在設定匯入本地檔或線上網址（LX`src/renderer/views/Setting/components/UserApiOnlineImportModal.vue`，僅確認檔案存在，未逐行讀）；
腳本有 `updateAlert` 事件做更新通知。官方文件站（lxmusic.toside.cn）本次未開啟，查不到。

## 3. Spotube

### 3.1 現況（重點：已換掉 hetu_script）
事實：
- v5.x（最新 v5.1.2，2026-06-05）插件用 hetu_script，manifest 為 `plugins.json`，`abilities: ["authentication","scrobbling"]`，
  endpoint 為 `auth, album, artist, playlist, search, track, user`。來源：https://spotube.krtirtho.dev/docs/developing-plugins/introduction （搜尋摘要，該網址已 301 到 docs.spotube.cc，後者 WebFetch 404，未能讀原文）。
- v6.0.0-beta.0（2026-10-30）已從 Flutter 遷到 Compose Multiplatform，插件改為 Kotlin 編譯成 JS、由 Zipline（Cash App，QuickJS）執行；
  release notes 明寫「Migration from hetu_script to Kotlin for plugin development. Powered by Zipline」並新增 Lyrics 與 Scrobbling 插件。
  來源：`gh api repos/team-spotube/spotube/releases`（v6.0.0-beta.0 body）。
- 結論：hetu_script 是舊況，現況是 Zipline/QuickJS。Spotube 不再是 Flutter，所以它的宿主實作不能直接搬，但介面設計可參考。

### 3.2 Manifest 與權限模型（v6）
事實：`plugin.json` 範例：`{name, version, apiVersion, author, capabilities:[...], abilities:[...]}`。
來源：SP`js_plugin_example/plugin.json`。
- `capabilities`（權限）：`PERSISTENT_STORAGE`、`NETWORK_REQUESTS`、`WEBVIEW`。來源：SP`composeApp/.../modules/plugin/PluginModels.kt` 第 29-36 行。
- `abilities`（功能）：`METADATA`、`AUDIO`、`LYRICS`、`SCROBBLE`（同檔第 39-48 行）。
- 未知值會被丟掉而不是整份拒絕（`LenientEnumListSerializer`，同檔第 51-80 行），讓新舊 API 版本相容。
- 權限是「沒宣告就不綁定 host API」：宿主只在 capability 存在時才 `zipline.bind<HttpClientAPI/WebViewAPI/PersistedStorageAPI>`；
  `CryptoAPI` 與 `SystemInformationAPI` 永遠綁定。來源：SP`composeApp/.../core/zipline/ZiplinePluginService.kt` 第 153-185 行。
- 安裝時有權限對話框：`PluginPermissionsDialog.kt` 列出請求的 capability 與版本更新前後差異（`plugin_permissions_compare_title`）。
- 簽章：`ManifestVerifier.NO_SIGNATURE_CHECKS`（`ZiplinePluginService.kt` 第 138 行），即沒有簽章驗證。
- 分發：從 GitHub 搜尋 repo、下載 release 中的 `.smplug`（`GitHubPluginRepo.kt` 第 70-92 行）。
- 每個 ability 在 `PluginManagerStates.Data.selectedPlugins: Map<PluginAbility, PluginEntry>` 選一個預設插件（`PluginModels.kt`）。

### 3.3 插件介面（plugin_interfaces 模組）
Core：`CoreAPI`（`requiresAuthentication`、`loggedInFlow: StateFlow<Boolean>`、`login()`、`logout()`、`checkPluginUpdates`、`supportMarkdownText`）。
來源：SP`plugin_interfaces/src/commonMain/kotlin/org/spotube/plugin_interfaces/plugin_apis/core/CoreAPI.kt`。
Metadata 分六組：album、artist、browse、playlist、search、track、user。
Audio：`AudioAPI.supportedQualities: List<AudioFormat>`（codec/container/qualities，含 `AudioQuality.Lossy(bitrate)`）、
`getStreamsByTrack(track): List<AudioSource>`（`AudioSource.Basic` 含 `confidence` 分數）。來源：`js_plugin_example/.../RealAudioAPI.kt`。
Lyrics、Scrobble 各自一個 API。

**遠端歌單寫入**（事實）：`MetadataPlaylistAPI` 有 `savedPlaylists / isSavedPlaylists / savePlaylists / removeSavedPlaylists /
createPlaylist / updatePlaylist / deletePlaylist / addTracksToPlaylist(playlistId, trackIds) / removeTracksFromPlaylist`。
來源：`plugin_apis/metadata/playlist/MetadataPlaylistAPI.kt` 第 27-65 行。
**VIP 標識**（事實）：`MetadataTrack` 只有 `explicit: Boolean?` 與 `isrcCode: String?`（對 Track models 搜 `premium|paid|vip|restrict|playable` 無結果；
Audio models 搜 `premium|drm|login|auth|vip` 無結果）。沒有 VIP 欄位。

### 3.4 登入與憑證
- 插件自己實作 `login()`；可用 `WEBVIEW` capability 開網頁取 cookie（v5 文件提到 `getCookies`，v6 有 `WebViewAPI`）。
- 憑證存放：`PersistedStorageAPI` 以 `"${pluginInfo.id}:$key"` 為鍵寫進宿主的 DataStore（`RealPersistedStorageAPI.kt`），
  有插件命名空間隔離，但看不出用了 Keychain / Keystore（推測：DataStore 明文，查不到加密）。
- 寫入確認：沒找到宿主在寫入前彈確認的程式（查不到；只看了插件目錄與 `PluginModels`）。
- UI 是否依 ability 顯示入口：有 `MetadataPluginGuard` 與 `DefaultAbilityPluginGrid`，未讀內容，細節查不到。

### 3.5 Spotube 對本專案的參考價值
- `capabilities`（權限）與 `abilities`（功能）分兩個詞，且未知值寬容忽略。
- host API 依權限才綁定，是「沒宣告就根本呼叫不到」，比事後檢查可靠。
- 缺點：介面是靜態 Kotlin 型別，要求插件與宿主同一 API 版本（`apiVersion`）。

## 4. 其他產品（各一兩句）

- **Listen1**（listen1_chrome_extension，最後 push 2025-06-17）：沒有下載式插件，provider 是內建的 JS 檔（`js/provider/netease.js` 等）。
  netease provider 暴露函式：`search, lyric, get_playlist, get_playlist_filters, get_recommend_playlist, login, logout, get_user,
  get_user_playlist, get_user_created_playlist, get_user_favorite_playlist, get_login_url, parse_url`；
  可播判斷用 `is_playable(song) = song.fee !== 4 && song.fee !== 1`（第 397 行），不可播就把 `url` 設 `''`，沒有獨立 VIP 標識欄位。
  該檔案沒有建立歌單 / 加歌函式（查該檔 `static` 函式清單）。來源：https://github.com/listen1/listen1_chrome_extension/blob/master/js/provider/netease.js 。
- **Nuclear**（nukeop/nuclear，2026-11-06 仍在更新）：插件是 TypeScript，`package.json` 帶 `nuclear.permissions`（未知權限只警告），
  生命週期 `onEnable/onDisable/onUnload`，用 `api.Providers.register()` 註冊 6 種 provider：`metadata, streaming, dashboard, playlists, discovery, lyrics`；
  provider 以 `searchCapabilities: ['artists','albums']` 宣告能力，UI 在 Sources 頁自動出現新種類。`api.Playlists.*`、`api.Favorites.*` 操作的是本地資料，
  `PlaylistProvider` 是「從 URL 匯入歌單」。遠端寫入、VIP、登入：查不到。
  來源：https://github.com/nukeop/nuclear/blob/master/packages/docs/plugins/providers.md 、`getting-started.md`（權限欄位）、`playlists.md`、`favorites.md`。
- **Harmony Music**（anandnet/Harmony-Music）：沒有插件系統，直接用 `youtube_explode_dart`（pubspec.yaml 依賴）。

## 5. Flutter 嵌入 JS 引擎

pub.dev 資料取自 `https://pub.dev/api/packages/<name>`（2026-11-06 查）。

| 套件 | 版本 / 最後發布 | 引擎 | 平台（pubspec / pub 標籤） | 備註 |
| --- | --- | --- | --- | --- |
| flutter_js | 0.8.7，2026-01-27 | Android、Windows、Linux 用 QuickJS；iOS、macOS 用 JavaScriptCore | android/ios/macos/windows/linux 皆標示 | 提供 xhr、fetch、Promise、setTimeout；README 說明刻意不在 iOS 用 QuickJS |
| flutter_qjs | 0.3.7，2022-05-19 | QuickJS（含 iOS） | 5 平台 | 3 年多沒發布，repo 2026-10-19 仍有 push |
| quickjs_engine | 0.1.7，2026-11-05 | QuickJS-NG 0.14.0，全平台同一引擎 | 5 平台 | flutter_js 的 fork，likes 只有 4，很新 |
| fjs | 3.3.2，2026-09-30 | Rust 包 QuickJS | 5 平台 ffiPlugin | ES modules、async/await、可設記憶體上限、內建 fetch 選項；fluttercandies 維護，115 stars |
| flutter_jscore | 1.0.0，2021-06-06 | JavaScriptCore | 標示 5 平台 | 久未更新 |

來源：flutter_js README（https://github.com/abner/flutter_js/blob/master/README.md ，約第 3-29 行）、fjs README（https://github.com/fluttercandies/fjs ）。

重點：
- iOS：可用 JavaScriptCore（系統內建，flutter_js 的做法）或自帶 QuickJS（fjs、flutter_qjs、quickjs_engine）。
- macOS：flutter_js 走 JavaScriptCore；README 的 macOS 區塊列出需要 `com.apple.security.cs.allow-jit` 等 entitlement（第 273-277 行）。
- Windows、Android：全部是 QuickJS 系。
- 行為一致性：flutter_js 在 Apple 與其他平台用不同引擎，行為差異要自己測；quickjs_engine、fjs 全平台同一引擎（單一引擎的好處，推測對本專案較重要）。
- flutter_js README 引用的 4.7 文字（「must use WebKit and JavaScript Core」）和現行 Guidelines 原文不同，見 §6，不能拿來當依據。
- 未驗證：各套件在實機的 Promise / async 行為、記憶體、Windows 建置難度（只讀了 README 與 pub 資料，沒有實跑）。

## 6. App Store 政策（原文）

來源：https://developer.apple.com/app-store/review/guidelines/ （WebFetch，2026-11-06 讀回，前 100000 字元）。

**2.5.2**：
> Apps should be self-contained in their bundles, and may not read or write data outside the designated container area, nor may they download, install, or execute code which introduces or changes features or functionality of the app, including other apps. Educational apps designed to teach, develop, or allow students to test executable code may, in limited circumstances, download code provided that such code is not used for other purposes. Such apps must make the source code provided by the app completely viewable and editable by the user.

**4.7**：
> Apps may offer certain software that is not embedded in the binary, specifically HTML5 and JavaScript mini apps and mini games, streaming games, chatbots, and plug-ins. Additionally, retro game console and PC emulator apps can offer to download games. You are responsible for all such software offered in your app, including ensuring that such software complies with these Guidelines and all applicable laws. Software that does not comply with one or more guidelines will lead to the rejection of your app. You must also ensure that the software adheres to the additional rules that follow in 4.7.1 through 4.7.5. ...

- **4.7.1**：遵守 5.1 隱私；有過濾不當內容的方法、檢舉機制與回應、封鎖濫用使用者的能力；數位商品遵守 3.1。
- **4.7.2**：「Your app may not extend or expose native platform APIs or technologies to the software without prior permission from Apple.」
- **4.7.3**：「Your app may not share data or privacy permissions to any individual software offered in your app without explicit user consent in each instance.」
- **4.7.4**：「You must provide an index of software and metadata available in your app. It must include universal links that lead to all of the software offered in your app.」
- **4.7.5**：要讓使用者辨識超過 app 年齡分級的軟體，並用經驗證或自報年齡的機制限制未成年人存取。

解讀（推測，不是法律意見）：
- 現行 4.7 明文允許「JavaScript mini apps ... and plug-ins」這類不在 binary 內的軟體，所以下載 JS 插件有條文可依，但必須同時滿足 4.7.1-4.7.5。
- 4.7.2 的限制直接影響設計：宿主對插件暴露的只能是自訂的小型 API（HTTP、storage、crypto），不能把 `dart:io`、檔案系統、Keychain 之類原生 API 轉手給插件。Spotube 的 capability 白名單就是這個形狀。
- 4.7.4 要求有「軟體索引 + universal link」：插件目錄 / 訂閱清單要能列出每個插件。
- 4.7.1 的檢舉、過濾與封鎖機制，對「使用者自行加入任意插件網址」的模式是不容易滿足的缺口（推測：這是審核風險點）。
- 2.5.2 仍禁止下載會「introduces or changes features or functionality」的程式碼；4.7 是特例，不是 2.5.2 的豁免全部。審核員如何裁量查不到。
- JavaScriptCore 不在 Guidelines 原文中出現（WebFetch 結果明說）；最後 14428 字元沒讀到，未排除其中有相關條文（2.5.6 只被 WebFetch 概述，未取得原文）。
- 另一個推測：Apple 對第三方 App 的 JIT 限制，使 JIT 型引擎在 iOS 上沒有優勢，QuickJS 是純直譯器；此點沒有在本次查證，勿當事實。

## 7. 綜合：各產品如何處理四個問題

### 7.1 能力宣告
- MusicFree：沒有明確宣告，靠「匯出了哪些方法」+ `supportedSearchType`（推測，未讀 UI 程式碼）。
- LX：`lx.send(inited, {sources:{src:{type, actions, qualitys}}})`，宿主與白名單取交集。
- Spotube v6：manifest 的 `abilities`（做什麼）與 `capabilities`（要什麼權限）分開；未知值忽略；`apiVersion` 相容檢查。
- Nuclear：provider 註冊時帶 `kind`，加上 `searchCapabilities` 之類子能力；manifest 有 `nuclear.permissions`。
- Listen1：內建，無宣告。

### 7.2 UI 依能力出現入口
- Nuclear（文件明說）：新 provider kind 自動出現在 Sources 頁，active provider 可切換，第一個註冊者自動為預設。
- Spotube：`selectedPlugins` 以 ability 為單位選預設插件；入口是否隨能力顯示查不到。
- MusicFree：搜尋類型由 `supportedSearchType` 決定（推測）。
- LX：由 `sources` 決定哪些音源可用。

### 7.3 寫入確認（遠端歌單寫入）
- 沒有任何產品的文件或原始碼顯示「寫入前確認」的流程。MusicFree、LX、Nuclear 根本沒有遠端寫入介面。
- 只有 Spotube v6 的介面定義了遠端歌單寫入（見 §3.3），但宿主端是否確認，查不到。
- 推測：沒有現成慣例可抄，寫入確認要自己設計。

### 7.4 登入憑證由誰保管
- MusicFree：使用者貼進 `userVariables` 的字串，宿主存；宿主不管登入流程。
- LX：不涉及。
- Spotube v6：插件實作 `login()/logout()`，宿主給 WebView 與命名空間化的 key-value storage，憑證由插件自己決定存什麼；宿主端為 DataStore（未見加密）。
- Listen1：provider 自己登入並維持 cookie（`login`、`get_user`、`logout`）。
- Nuclear：查不到。

### 7.5 對 FMP 的三點事實性提醒
1. 兩個要的功能（VIP 標識、遠端歌單寫入）沒有現成插件協議可以照抄：VIP 欄位在所有查過的產品都沒有；遠端歌單寫入只有 Spotube v6 有介面。
2. Spotube v6 的 `MetadataPlaylistAPI` 介面（create/update/delete/add/remove/save）是目前唯一可對照的遠端歌單寫入介面形狀。
3. FMP 只有 3 個已知音源，且要上 iOS：4.7.2 要求不能把原生 API 暴露給插件，這使「插件=內建 Dart 實作」與「插件=下載 JS」的審核風險差別很大。推測：若不需要使用者自己裝第三方插件，內建音源模組比下載 JS 保守。（這是設計判斷，不是查證事實。）
