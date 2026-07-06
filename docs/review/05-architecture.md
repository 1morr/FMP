# 05 — 架構與「新增音源」可擴充性（面向 D，本審查重點）

> 唯讀審查；證據均含 `file:line`。本面向經「子系統並行掃描 → 彙整 → 對抗驗證」三階段。成熟度評分：**3 / 5**。

## 1. 現狀摘要

- **好：** 核心抽象層（`SourceManager` + narrow capability + 共用 quality fallback + `MediaHandoff`/`SourceHttpPolicy` 嚴守「憑證不送進 CDN byte 請求」的 auth 邊界）對新音源相當友善——runtime 播放/下載/搜尋主路徑幾乎不消費具體 source，新增音源「至少能播放、能透過 All 被搜尋」。
- **壞：** 往外每一層都殘留三源硬編碼——`SourceType` 三值 enum 雖有 exhaustive switch 編譯保護（相對安全），但 per-source Settings 欄位、`homeRankingSourceIds` 字串常數、UI ChoiceChip/帳號卡/串流優先級區、`SourceHttpPolicy` 三個 switch、`SourceManager.dispose()` 具體型別檢查等多為「編譯器抓不到的字串/具名欄位」hardcode，新增第 4 個音源需同步改 8–12 個分散檔案，且部分漏改會**靜默失效**。

## 2. 新增一個音源需碰哪些地方（步驟清單）

| # | 步驟 | 檔案 | 難度 | 會卡住？ | 分散？ |
|---|------|------|------|----------|--------|
| 1 | `SourceType` enum 補值 + `displayName` case | `lib/data/models/track.dart:8-20` | 中 | 會（根 key，exhaustive 編譯保護） | 否 |
| 2 | `SourceManager` 預設建構清單註冊 adapter | `lib/data/sources/source_provider.dart:13-21` | 易 | 會（不加則完全不註冊） | 否 |
| 3 | `SourceManager.dispose()` 補新源 dispose 分支（建議改 Disposable 介面） | `lib/data/sources/source_provider.dart:184-191` | 中 | 視情況（持有資源則會洩漏，無編譯警告） | 否 |
| 4 | 補 per-source Settings 欄位 + `AudioStreamConfig.fromSettings` + `useAuthForPlay` switch | `lib/data/models/settings.dart:185-191,269-275,586-608`、`lib/data/sources/base_source.dart:44-56`、`lib/providers/audio/audio_settings_provider.dart:14-15` | 難 | 會（含 Isar schema migration） | 是 |
| 5 | `SourceHttpPolicy` 三 switch + `imageHeadersForUrl` host 白名單補新源 | `lib/data/sources/source_http_policy.dart:34-70,96-125,145-172` | 中 | 會（**host 白名單是字串比對、編譯抓不到、最易漏**） | 否 |
| 6 | 帳號體系（若有）：`AccountServiceAuthLoader` + `account_management_page` + secure storage | `lib/services/account/source_auth_context.dart:31-61`、`lib/ui/pages/settings/account_management_page.dart:129-180` | 中 | 視情況 | 是 |
| 7 | `MediaHandoff` redirect preflight（僅新源也有 302→CDN 需求時） | `lib/services/media/media_handoff.dart:56-135` | 中 | 不會（多數新源走通用 `_prepareHeaders`，安全） | 否 |
| 8 | 排行榜探索頁：`explore_page` tab + `popular_provider` + `ranking_cache_service` | `lib/ui/pages/explore/explore_page.dart:38,63-120`、`lib/providers/search/popular_provider.dart:244-294`、`lib/services/cache/ranking_cache_service.dart:70-127,388-468,488-510` | 難 | 不會（不出榜仍可播放/搜尋） | 是 |
| 9 | 搜尋頁：ChoiceChip + `allDirectSources` + `_SourceBadge` | `lib/ui/pages/search/search_page.dart:184-231,1595-1599`、`lib/providers/search/search_provider.dart:35-39` | 難 | 不會（透過 All 仍可搜到） | 是 |
| 10 | 音質設定頁：`_StreamPrioritySection` + `_AuthForPlaySection`（若暴露設定） | `lib/ui/pages/settings/audio_settings_page.dart`、`lib/i18n/{en,zh-CN,zh-TW,...}/audioSettings.i18n.json` | 難 | 不會 | 是 |
| 11 | `home_page` 字串 switch + home ranking 設定頁 | `lib/ui/pages/home/home_page.dart:211-222,303-314`、`lib/ui/pages/settings/home_ranking_settings_page.dart` | 中 | 不會（否則卡片無預覽、標題顯示 raw id） | 是 |
| 12 | 音源圖示：`icon_helpers` + 多處重複本地 switch | `lib/core/utils/icon_helpers.dart:14-21`、search/home_ranking/import_preview/play_history 頁 | 中 | 不會 | 是 |
| 13 | 下載路徑/掃描：副檔名 + 頭像目錄對映 | `lib/services/download/download_path_utils.dart:38-45,216-233`、`lib/providers/download/download_scanner.dart:178-339` | 中 | 不會（但會誤標） | 是 |
| 14 | i18n：`importPlatform.{en,zh-CN,zh-TW}` 補新源顯示名鍵 + `dart run slang` | `lib/i18n/{en,zh-CN,zh-TW}/importPlatform.i18n.json` | 易 | 會（否則 displayName 缺字串） | 是 |

**重點：** 步驟 1/4/5/14 是「會卡住」的硬門檻；其中 5 的 host 白名單、4 的手寫存取器、8/9/10/12 的 UI 列舉是「編譯器抓不到、漏改會靜默失效」的危險區。

## 3. 發現清單

### D1　`SourceManager.dispose()` 用具體型別 `is` 檢查列舉三源，違反「呼叫端不消費具體 source 型別」並製造資源洩漏風險
- 嚴重度：🟡 Medium　工作量：M
- 證據：`lib/data/sources/source_provider.dart:184-191`（三個 `if (source is BilibiliSource) source.dispose(); ...`）；`:13-21`（預設建構清單硬寫 `[BilibiliSource(), YouTubeSource(), NeteaseSource()]`）。
- 影響：narrow capability 查詢已抽象，唯獨 `dispose()` 與建構式退回三具體型別；新音源若持有資源會洩漏，無編譯警告。
- 建議：`SourceCapability`（或新增 `Disposable` capability）統一暴露 `dispose()`，改 `for (final s in _sources) (s as Disposable?)?.dispose()`。

### D2　per-source 設定全為手寫對稱欄位（streamPriority×3 + authForPlay×3） — 對抗驗證 **partially，High→Medium**
- 嚴重度：🟡 Medium　工作量：L
- 證據：`lib/data/models/settings.dart:185-191`（三獨立持久欄位）、`:269-275`（三個 `useXxxAuthForPlay`）、`:586-608`（`useAuthForPlay`/`setUseAuthForPlay` exhaustive switch）、`lib/data/sources/base_source.dart:44-56`（`AudioStreamConfig.fromSettings` exhaustive switch）、`lib/providers/audio/audio_settings_provider.dart:14-15`（`AudioSettingsState` 只有 youtube/bilibili，**缺 neteaseStreamPriority**——既有破窗）。
- 影響：新音源要加 2 個 Isar 欄位 + 改多個 switch + schema migration；`AudioSettingsState` 連 netease 都沒進 state，新源容易跟著漏 UI 可調性。驗證確認 `database_migration_test.dart:244-344` 覆蓋 `neteaseStreamPriority` 遷移，新增欄位的 schema 成本真實。兩個關鍵 switch 是 exhaustive（編譯保護），故「編譯器抓不到」的標題偏誇大，降 Medium。
- 建議：資料驅動——`Settings`/`State` 用 `Map<SourceType,String>` 或由 `SourceManager.registeredSourceTypes` 衍生；至少先補 `neteaseStreamPriority` 進 state 對齊。

### D3　`SourceHttpPolicy` 三 exhaustive switch + `imageHeadersForUrl` host 白名單 — 對抗驗證 **partially，High→Medium**
- 嚴重度：🟡 Medium　工作量：M
- 證據：`lib/data/sources/source_http_policy.dart:34-70`（`mediaHeaders` exhaustive switch；netease 僅在 `canAttachNeteaseMediaCredentials` 白名單 host 附 Cookie）、`:96-125`（`imageHeadersForUrl` 用 host allowlist 字串比對回 SourceType，未命中 `return null`）、`:145-172`（`apiHeaders` exhaustive switch）；`lib/core/services/image_loading_service.dart:363-371`（null headers 直接帶入 `_NetworkImageRequest.headers`，未知 host 縮圖無 Referer/UA，可能 403）。
- 影響：三 switch 為 exhaustive（編譯保護）；但 `imageHeadersForUrl` host 白名單是字串比對，**編譯抓不到**，新源縮圖 host 漏補會以無 Referer 請求被擋。目前僅三源、無現役漏配，屬維護性防呆缺口。
- 建議：短期補 host 白名單時建立檢查清單；長期把 per-source header policy 抽成註冊表（host pattern → SourceType → headers），資料驅動。

### D4　`homeRankingSourceIds` 字串常數是首頁排序白名單根，新音源 id 不補會被 normalize 靜默丟棄
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/data/models/settings.dart:72-108`（`homeRankingSourceIds=['bilibili','youtube','netease']`、`defaultHomeRankingSourcePriority`、`normalizeHomeRankingSourcePriority` 對 `!contains` 的 source 直接 `continue` 靜默丟棄、`normalizeDisabledHomeRankingSources` 同樣以白名單過濾）。
- 影響：新音源 id 不補進常數，使用者任何含新 id 的排序/停用設定會被 normalize 靜默丟棄，新音源無法被排序或停用——且無任何錯誤；字串白名單編譯器完全不保護。
- 建議：把 `homeRankingSourceIds` 改由 `SourceManager.registeredSourceTypes.map(.name)` 衍生（單一真相）；normalize 對未知 id 記 warning 而非靜默丟棄；或至少補測試守護白名單與 enum 同步。

### D5　排行榜探索頁 `explore_page` 三源 tab 硬編碼（`length:3` + 三個 `_buildXxxTab` + TabBar 列舉） — 對抗驗證 **partially，High→Low**
- 嚴重度：🟢 Low　工作量：L
- 證據：`lib/ui/pages/explore/explore_page.dart:38`（`TabController(length:3)`）、`:63-67`（`currentTracks switch(_activeTabIndex)` 0/1/_ → 三源）、`:90-120`（TabBar 與 TabBarView 三源列舉，在 normal/selection 兩個 AppBar 各列舉一次，共三處）；`lib/services/cache/ranking_cache_service.dart:488-510`（provider 顯式抓三源 `rankingSource`，缺即 `throw StateError`，把動態註冊降回靜態三源）；`lib/providers/search/popular_provider.dart:244-294`（每源一份具名 provider，但內部已用相對動態的 `tracksFor(SourceType.x)` select）。
- 影響：第 4 個音源不會自動長出排行榜 tab/preview/cached provider。驗證指出：因 `SourceType` enum 是封閉型別，新增屬跨模型/adapter/persistence 的重大變更而非單純 UI 接線；length:3 不會造成靜默越界（exhaustive 會報錯），屬 DRY/維護負擔，故降 Low。
- 建議：把 `explore_page`/`popular_provider`/`ranking_cache_service` 改為遍歷 `SourceManager.registeredSourceTypes`（搭配 `Provider.family<SourceType>` 取 `tracksFor(type)`），讓新源註冊即自動出現。

### D6　搜尋頁音源 ChoiceChip 與直播 chip 硬編碼三源
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/ui/pages/search/search_page.dart:184-231`（四個手寫 ChoiceChip：All/bilibili/YouTube/netease，各寫死 `SourceType` 與 `setFilters`）；`:244-278`（直播 chip 全部 `sourceType: SourceType.bilibili`，直播 UI 實質 Bilibili 專屬）；`lib/providers/search/search_provider.dart:746-747`（`liveSource` 硬綁 `SourceType.bilibili`）。
- 影響：第 4 個音源不會自動出現在搜尋 chip（透過 All 仍可搜，因 `searchService` 走 `registeredSourceTypes`）；直播若新源也支援無法複用篩選 UI。
- 建議：搜尋 chip 改遍歷 `registeredSourceTypes`；直播 `liveSource` 改遍歷註冊源找 `LiveSource`（或把 chip 標註為 Bilibili-only 的刻意決策並寫進 AGENTS.md）。

### D7　`loadVideoPagesForTrack` 與 `search_page` 分P載入用「音源身份」而非「能力是否存在」做守護（能力被身份綁死）
- 嚴重度：🟡 Medium　工作量：S　[未個別驗證]
- 證據：`lib/services/search/search_service.dart:146-159`（`if (track.sourceType != SourceType.bilibili) return const [];` 且錯誤訊息寫死 `SourceType.bilibili.name`）；`lib/ui/pages/search/search_page.dart:837-839`（`if (track.sourceType != SourceType.bilibili) return;`）。
- 影響：新音源若實作 `PagedVideoSource`，此 UI/service 仍不為其觸發載入，錯誤訊息誤報 bilibili；抽象 leak。
- 建議：改以 `sourceManager.pagedVideoSource(track.sourceType) != null` 判斷能力存在性，錯誤訊息用 `track.sourceType.name`。

### D8　`play_history_page` 雙源三元判斷把 netease（與任何新音源）誤顯示為 YouTube 圖示 — ⚠️ **現存可見 bug，非僅擴充性問題**
- 嚴重度：🟡 Medium　工作量：S　[未個別驗證]
- 證據：`lib/ui/pages/history/play_history_page.dart:666-672`（`Icon(history.sourceType == SourceType.bilibili ? SimpleIcons.bilibili : SimpleIcons.youtube)`——二元三元，netease 落入 else 顯示成 YouTube）；`lib/core/utils/icon_helpers.dart:14-21`（已有 `getImportSourceIcon(SourceType)` 集中映射三源，但此處未使用）。
- 影響：播放歷史中 Netease 與任何新音源曲目被顯示成 YouTube 圖示——這是**現存使用者可見錯誤**，破壞單一真相。
- 建議：改用 `getImportSourceIcon(history.sourceType)`，順帶讓新音源只要在 helper 補一個 case 即正確顯示。**（快速修，建議優先）**

### D9　`SearchState.allDirectSources` 靜態常數硬編碼三源，與 `SearchService` 走 `registeredSourceTypes` 的口徑不一致
- 嚴重度：🟢 Low　工作量：S　[未個別驗證]
- 證據：`lib/providers/search/search_provider.dart:35-39`（`static const List<SourceType> allDirectSources = [bilibili, youtube, netease];` 用作「全部音源」基準）；`lib/services/search/search_service.dart:95`（`searchAll` 預設 `sourceTypes ?? _sourceManager.registeredSourceTypes`，動態）。
- 影響：新源漏補 `allDirectSources`，All 模式的本地結果過濾口徑（舊三源）與 `searchService`（新四源）不一致，可能造成 local 結果在新源上被誤過濾。
- 建議：`allDirectSources` 改由 `sourceManagerProvider.registeredSourceTypes` 衍生，消除兩處口徑分歧。

### D10　`SourceType` enum 三值 + `displayName` exhaustive switch 是所有分支根源，但被 Dart exhaustive 機制強制保護
- 嚴重度：🟢 Low　工作量：M　[未個別驗證]
- 證據：`lib/data/models/track.dart:8-20`（`enum SourceType { bilibili, youtube, netease }` 與 `displayName` switch `t.importPlatform.<name>`）。
- 影響：exhaustive switch 補 enum 值後編譯失敗、強制顯式處理全庫每個 switch（相對安全、可預期）；但 `displayName` 直接綁 `t.importPlatform.<name>`，i18n 鍵漏補會在 runtime 缺字串。屬必要根因，非缺陷。
- 建議：保留 enum 作封閉 key；可考慮在 enum 旁加中繼資料表（displayName key/icon/rankingRequest 預設）集中，減少下游散落 switch；i18n 鍵補充納入新增音源檢查清單。

### D11　`AccountServiceAuthLoader` 三具體帳號服務欄位 + exhaustive switch
- 嚴重度：🟢 Low　工作量：M　[未個別驗證]
- 證據：`lib/services/account/source_auth_context.dart:31-61`（持 `_bilibiliAccountService`/`_youtubeAccountService`/`_neteaseAccountService`，`load()` exhaustive switch 分派）；`:177-182`（`authForPlay` 透過抽象 loader + `Settings.useAuthForPlay`，gate 本身 source-agnostic）。
- 影響：新音源若有帳號體系，需在 loader 加欄位+switch case 接其 `AccountService`，並在 `account_management_page`/secure storage 各加分支；gate 邏輯不用改。
- 建議：loader 改 `Map<SourceType, AccountService>` 或由 `AccountService.platform` 動態收集；帳號登入機制差異大，每源客製不可避免。

### D12　`MediaHandoff` 通用層硬寫 Netease 專屬 redirect preflight 與憑證 allowlist
- 嚴重度：🟢 Low　工作量：M　[未個別驗證]
- 證據：`lib/services/media/media_handoff.dart:56-106`（`DefaultMediaHandoff.preparePlayback` 對 `SourceType.netease` 做 redirect preflight，`_shouldPreflightNeteasePlayback` 只認 netease）；`:114-117`（`_prepareHeaders` 的 `credentialsMayAttach` 寫死 `sourceType==netease`）。
- 影響：byte 請求接縫設計良好（新音源預設走通用 `_prepareHeaders`，不會被捲入 Netease 特例，安全）；但若新音源媒體 URL 也有「API URL 302 到 CDN、憑證只跟第一跳」需求，無法用 capability 表達，必須在通用層再加 source 分支。
- 建議：未來有第 2 個此類音源時，把 redirect 憑證策略抽象成 per-source policy（如 `SourceCapability` 提供 `needsRedirectPreflight` + credentialAllowlist）。目前單源特例可接受，標註為刻意決策。

### D13　下載檔名硬編碼 `.m4a` 副檔名與頭像二元對映，新音源容器不符或頭像誤歸類
- 嚴重度：🟡 Medium　工作量：S　[未個別驗證]
- 證據：`lib/services/download/download_path_utils.dart:38-45`（單P `'audio.m4a'`、多P `'P{nn}.m4a'` 硬編副檔名）；`:216-233`（`getAvatarPath`/`ensureAvatarDirExists` 的 `platform = sourceType==bilibili ? 'bilibili' : 'youtube'`——三元 else 把 netease 與新音源頭像歸到 `'youtube'` 子目錄）。
- 影響：`AudioStreamResult` 已含 `container` 欄位卻沒被用——新音源若回傳 mp3/webm/opus，存檔仍強制 `.m4a`，檔名與實際容器不符；頭像子目錄用三元 else，新音源創作者頭像誤歸 youtube 目錄。掃描端只認 `.m4a` 形成隱性契約。
- 建議：檔名副檔名改從 `AudioStreamResult.container` 推導；頭像 platform 子目錄改用 `sourceType.name` 動態產生；掃描器 `.m4a` 過濾隨之放寬。

## 4. 重構結論：目前架構是否需要重構以支援新音源？

**needed = true（中幅重構，非推翻重寫）。**

**理由：** FMP 的核心抽象（`SourceManager` + narrow capability + 共用 quality fallback + `MediaHandoff`/`SourceHttpPolicy` 嚴守 auth 邊界）做得相當好：runtime 播放/下載/搜尋主路徑幾乎不消費具體 source，新音源只要 `implements AudioStreamSource` 等介面並加入建構清單，就能被搜尋（透過 All）、串流、下載自動發現——**這部分不需要重構，推翻重寫會破壞已驗證的邊界**。

真正需要重構的是「往外每一層的三源列舉硬編碼」。下游混雜兩類風險：
- **(A) exhaustive switch**（`Settings.useAuthForPlay`、`AudioStreamConfig.fromSettings`、`SourceHttpPolicy` 三 switch、`AccountServiceAuthLoader.load`）——補 enum 值後編譯強制改，**相對安全可預期**。
- **(B) 純字串/具名欄位 hardcode**（`homeRankingSourceIds` 常數、per-source Settings 欄位、UI ChoiceChip/帳號卡/串流優先級區、`allDirectSources`、`download_path_utils` 副檔名與頭像對映、`imageHeadersForUrl` host 白名單）——**編譯器完全不保護**，漏改會靜默失效（新源 id 被 normalize 丟棄、頭像誤歸 youtube 目錄、搜尋 chip 不出現、排行榜 tab 不長出）。

### 方案選項

| 方案 | 說明 | 取捨 | 工作量 |
|------|------|------|--------|
| **1. 最小修補（不重構）** | 保留抽象不動；新增音源時照 exhaustive 編譯提示 + 人工檢查清單補 enum/欄位/switch/UI/i18n/host | 工作量最省、零架構風險；但每源需動 8–12 處，字串/具名欄位漏改只能靠人工與測試守護，長期隨音源數線性膨脹 | M |
| **2. 中幅重構：以 `registeredSourceTypes` 驅動清單式列舉** | `homeRankingSourceIds`/`allDirectSources`/explore tab/popular provider/search chip/audio_settings 串流優先級 UI 改遍歷 `registeredSourceTypes`；`SourceManager.dispose` 改走 `Disposable` capability；`AccountServiceAuthLoader` 改 `Map<SourceType,AccountService>` | 新音源在搜尋 chip/排行榜 tab/首頁排序/帳號卡自動出現，改動點從 ~12 降到 ~4；需重寫 explore/popular/audio_settings UI 結構，有一定回歸風險，需搭配 widget 測試 | L |
| **3. 較深重構：SourceType 中繼資料表 + per-source 設定映射 + header policy 註冊表** | 新增 `SourceMetadata`（displayNameKey/icon/rankingRequest 預設/streamPriority 預設/headerPolicy）；Settings per-source 欄位改 `Map<SourceType,String>`；`SourceHttpPolicy` 改 host-pattern 註冊表；歌詞引入 `LyricsSource` 抽象+註冊表 | 最徹底消除三源 hardcode（含字串白名單與 header policy），新音源幾乎只改 enum+中繼資料+一個 adapter；但觸及 Isar schema、i18n 鍵、header policy、歌詞子系統，工作量最大、需完整遷移與備份相容性測試 | L |
| **4. 漸進式：先補隱性 bug + 字串鍵統一（★ 推薦）** | 優先消除「編譯器抓不到、會靜默失效」的字串/具名欄位：`homeRankingSourceIds`/`allDirectSources` 改由 `registeredSourceTypes` 衍生、`SourceManager.dispose` 改 `Disposable`、`play_history_page` 改用 `getImportSourceIcon`（D8 現存 bug）、`loadVideoPagesForTrack` 改能力判斷（D7）、下載副檔名/頭像目錄改資料驅動（D13）；UI 清單式列舉（chip/explore tab/audio_settings 區）暫保留手動補 | 用中等工作量先移除最危險（靜默失效/實際 bug）的 hardcode，exhaustive switch 類暫留給編譯器保護；不更動 schema/header policy 大架構，回歸風險低；UI 全自動化留待未來 | M |

**推薦方案 4（漸進式）：** 以 `SourceManager.registeredSourceTypes` 為單一真相，先消除會靜默失效與實際可見 bug 的字串 hardcode（D4/D8/D7/D9/D13/D1）；exhaustive switch 類因有編譯保護可暫時手動補、低風險。之後再視新音源需求決定是否進一步把 UI 清單式列舉（D5/D6/D2）改為遍歷 `registeredSourceTypes`。**勿推翻 `SourceManager`/Capability 核心抽象。**

## 5. 本面向優先級 Top 3

1. **D8** — `play_history_page` 圖示 bug（**現存可見錯誤**，一行修；最該先做）
2. **D2** — per-source Settings 欄位資料驅動化（含補 neteaseStreamPriority 進 state 的既有破窗）
3. **D3 + D4 + D13 + D1** — 收斂「會靜默失效」的 hardcode 叢（host 白名單、homeRankingSourceIds、下載副檔名/頭像、dispose 型別檢查）—— 即方案 4 的核心

> 註：原 Top 候選 D5 經對抗驗證降為 Low（enum 封閉型別下非靜默越界風險，屬 DRY 負擔），故以「隱性 bug 叢」遞補為優先。
