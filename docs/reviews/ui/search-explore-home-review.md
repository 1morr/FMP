# Search / Explore / Home UI review

## Findings

1. 類型：UX 問題；嚴重度：Medium；位置：`lib/ui/pages/home/home_page.dart:151`

   首頁排行榜區塊在 `isInitialLoading == true` 時直接顯示整塊 spinner，即使 `bilibiliTracks` 或 `youtubeTracks` 已有資料。`RankingCacheService._refreshAll()` 會並行刷新兩個來源，單一來源可先在 `state` 中寫入 tracks，但 `isInitialLoading` 要到兩個刷新都結束後才變成 false。這會讓已取得的排行榜被較慢或卡住的另一個來源遮住，違反 provider 指引中「`isLoading` 必須搭配資料為空才顯示全頁 loading」的模式。

2. 類型：代碼風格問題；嚴重度：Low；位置：`lib/ui/pages/search/search_page.dart:491`、`lib/ui/pages/search/search_page.dart:708`

   搜尋結果中 `_LocalGroupTile` 和直播間 `_LiveRoomTile` 的 Sliver list item 沒有穩定 key。線上歌曲列和展開的本地分 P 列已有 `ValueKey`，但本地分組主列與直播間列仍靠位置 diff。搜尋結果重新排序、載入更多或直播狀態變動時，Flutter 較容易重用錯誤 row element，影響選取/展開/右鍵選單這類互動狀態的可靠性。

## Evidence

- Source chip 邏輯符合期望：`SearchState.allDirectSources` 明確是 Bilibili、YouTube、Netease，`sourceTypesForSearch` 在 `selectedSource == null` 時回傳三者，單一 chip 時只回傳該 source（`lib/providers/search_provider.dart:37`、`lib/providers/search_provider.dart:75`）。`search()` 把這個列表傳給 `SearchService.searchOnline()`（`lib/providers/search_provider.dart:251`、`lib/providers/search_provider.dart:255`），`setSource()` 只更新 chip 狀態並重新搜尋（`lib/providers/search_provider.dart:491`）。
- 搜尋頁 chip UI 對應 provider 狀態：All/Bilibili/YouTube/Netease 的 `ChoiceChip` 分別呼叫 `setFilters()` 設定或清除 `sourceType`（`lib/ui/pages/search/search_page.dart:178`、`lib/ui/pages/search/search_page.dart:189`、`lib/ui/pages/search/search_page.dart:200`、`lib/ui/pages/search/search_page.dart:211`）。
- 沒發現 Settings 隱藏全域搜尋音源 filter：用 `rg` 查 `enabledSources`、`searchSources`、`SourceType`、`Search.*Settings` 等，Settings 相關命中是帳號、匯入、播放授權、歌詞來源或歷史篩選，未見一般搜尋音源啟用/停用設定。`test/data/models/audio_settings_defaults_test.dart:25` 也驗證 legacy `enabledSources` backup field 會被忽略。
- 相關測試支持 chip 規則：`test/providers/search_pagination_stale_test.dart:208` 驗證 All chip 搜三個 direct sources；`test/providers/search_pagination_stale_test.dart:231` 驗證單一 Netease chip 只搜 Netease。
- Ranking cache UI 沒有讀 mutable service snapshot：`RankingCacheState` 以 `List.unmodifiable` 產生 immutable list（`lib/services/cache/ranking_cache_service.dart:50`）。Home 透過 `homeBilibiliMusicRankingProvider` / `homeYouTubeMusicRankingProvider` watch `rankingCacheServiceProvider.select(...)`（`lib/providers/popular_provider.dart:134`、`lib/providers/popular_provider.dart:231`），Explore 透過 cached ranking providers 和 `rankingCacheServiceProvider` state 顯示 loading/error（`lib/ui/pages/explore/explore_page.dart:121`、`lib/ui/pages/explore/explore_page.dart:122`）。刷新只透過 notifier（`lib/ui/pages/explore/explore_page.dart:128`、`lib/ui/pages/explore/explore_page.dart:140`）。
- Ranking state consumption 有測試：`test/ui/pages/ranking_ui_state_consumption_test.dart:78` 檢查 Home 只 select `isInitialLoading`，`test/ui/pages/ranking_ui_state_consumption_test.dart:19` 覆蓋 Explore selection mode 切 tab 後全選使用可見 tab tracks。
- 臨時播放符合頁面語義：Search/Explore/Home 排行與歷史入口都呼叫 `audioControllerProvider.notifier.playTemporary()`，未見 UI 直接呼叫 `audioServiceProvider` 或 `FmpAudioService`。範例位置：`lib/ui/pages/search/search_page.dart:499`、`lib/ui/pages/explore/explore_page.dart:235`、`lib/ui/pages/home/home_page.dart:811`。Home queue preview 是隊列語境，使用 `playAt()`（`lib/ui/pages/home/home_page.dart:1603`）。
- 公共 track action 大致一致：Search/Explore/Home 都使用 `buildCommonTrackActionMenuItems()` 和 `TrackActionCoordinator.handleSingle()`；Search 的多 P 主列有頁面特定批量處理，但單 track fallback 仍回到 coordinator（`lib/ui/pages/search/search_page.dart:931`、`lib/ui/pages/explore/explore_page.dart:347`、`lib/ui/pages/home/home_page.dart:916`）。
- 圖片組件符合硬邊界：在 `lib/ui/pages/search`、`lib/ui/pages/home`、`lib/ui/pages/explore` 用 `rg -n "Image\\.network|Image\\.file"` 沒有命中；歌曲封面使用 `TrackThumbnail`，直播間圖片使用 `ImageLoadingService.loadImage()` 並傳 `width` / `height`（`lib/ui/pages/search/search_page.dart:1690`）。
- Loading/empty/error 狀態大多存在：Search online 使用 loading/error/empty/all-loaded 狀態（`lib/ui/pages/search/search_page.dart:422`、`lib/ui/pages/search/search_page.dart:426`、`lib/ui/pages/search/search_page.dart:590`）；live room 也有 loading/error/empty/all-loaded（`lib/ui/pages/search/search_page.dart:632`、`lib/ui/pages/search/search_page.dart:636`、`lib/ui/pages/search/search_page.dart:658`）；Explore ranking 有 loading/error/empty/retry（`lib/ui/pages/explore/explore_page.dart:150`、`lib/ui/pages/explore/explore_page.dart:154`、`lib/ui/pages/explore/explore_page.dart:162`）。
- URL/直接播放入口在本範圍內主要是直播間：搜尋直播結果 `_openLiveRoom()` 轉 `RadioStation` 後走 `radioControllerProvider.notifier.play()`（`lib/ui/pages/search/search_page.dart:747`），加入電台用標準 Bilibili live URL 呼叫 `radioControllerProvider.notifier.addStation()`（`lib/ui/pages/search/search_page.dart:771`）。未見 search/home/explore 對任意音訊 URL 直接呼叫 backend 播放。

## User impact

- Finding 1：使用者進首頁時，如果某一個排行榜已回來但另一個來源還在等網路，首頁仍只看到 spinner，不能先點已可用的熱門歌曲。音樂播放器的常用入口被較慢來源拖住，降低啟動後立即播放的效率。
- Finding 2：搜尋或直播結果變動時，未 keyed 的 row 可能被 Flutter 依位置重用。現階段風險偏低，但在載入更多、結果刷新、切換搜尋模式或未來加入 row-local 狀態時，會增加選取、展開、右鍵選單顯示錯位的機率。

## Suggested direction

- Home ranking loading guard 改成只在兩個排行榜都沒有資料時顯示整塊 loading，例如以 `isLoading && !hasBilibiliData && !hasYoutubeData` 控制 spinner；已有任一來源資料時先渲染可用 ranking card，必要時用較小的 inline refresh indicator 表示仍在載入。
- Search list key 補齊到分組和直播列：`_LocalGroupTile` 可用 `ValueKey(group.groupKey)` 或包含 source/page 的 group identity；`_LiveRoomTile` 可用 `ValueKey('live-room-${room.roomId}')`。同時讓這兩個 widget constructor 接 `super.key`，維持與 `_SearchResultTile`、`_LocalTrackTile` 一致。
- 若修正 finding 1，建議補一個 widget/static test 覆蓋「`isInitialLoading == true` 且已有任一 ranking list 時不顯示全區 spinner」；若修正 finding 2，可擴充 `test/ui/pages/search/search_page_phase2_test.dart` 既有 stable key static test。

## Instruction docs accuracy notes

- `AGENTS.md`、`lib/ui/AGENTS.md`、`lib/providers/AGENTS.md` 對本次審查重點基本準確：source chip ownership、禁止 Settings 隱藏 filter、ranking UI watch immutable state、公共 track action、圖片組件等都能在當前程式碼或測試找到對應。
- `.serena/memories/ui_coding_patterns.md` 的「API 數據 + 緩存 = CacheService + StreamProvider」描述已不完全符合目前 ranking cache 實作；目前權威規則是 `lib/providers/AGENTS.md` 的 `StateNotifierProvider + immutable RankingCacheState`，程式碼也採用這個方向。
- `.serena/memories/ui_coding_patterns.md` 對「新代碼禁止硬編碼 UI 魔法數字」比目前 `lib/ui/AGENTS.md` 更嚴格；本報告未把 search/home/explore 中既有 one-off padding/size literal 當作 finding，因為 root/scoped AGENTS 允許小型局部 layout literal。
