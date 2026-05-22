# UI Documentation Alignment Review

## Findings

### 1. 文件問題 / 低嚴重度 - `docs/development.md` 的路由清單漏列目前設定子路由

- 文件位置：`docs/development.md:127`-`docs/development.md:130`
- 程式碼佐證：`lib/ui/router.dart:51`-`lib/ui/router.dart:58`、`lib/ui/router.dart:218`-`lib/ui/router.dart:260`

`docs/development.md` 的「路由」表列出主要 navigation、詳情頁、設定頁和 developer tools，但目前 `RoutePaths` 與 `GoRoute` 還包含 `/settings/user-guide`、`/settings/account/bilibili-login`、`/settings/account/youtube-login`、`/settings/account/netease-login`。這是描述性內容，不是規範性要求；因為文件宣稱重要路由常量在 `lib/ui/router.dart`，表格應與該檔同步或明確標示為摘要。

### 2. 文件問題 / 中嚴重度 - `lib/ui/AGENTS.md` 把 desktop layout 寫成固定三欄，實作其實是可選詳情面板

- 文件位置：`lib/ui/AGENTS.md:100`-`lib/ui/AGENTS.md:106`
- 程式碼佐證：`lib/ui/layouts/responsive_scaffold.dart:217`-`lib/ui/layouts/responsive_scaffold.dart:264`
- 相關人類文件：`docs/development.md:132`-`docs/development.md:140`

`lib/ui/AGENTS.md` 說 Desktop `>= 1200dp` 是「three-column layout」。實際 `_DesktopLayout` 固定有可收合側欄與主內容，但右側 `TrackDetailPanel` 只在 `currentTrack != null || showRadioPlaybackUi` 時顯示，因此 desktop 初始或無播放上下文時不是三欄。`docs/development.md` 的「可收起側邊導航欄 + 可選詳情面板」較準確；建議讓 scoped UI 指令也採用這個描述。

### 3. 文件問題 / 中嚴重度 - `.serena/memories/ui_coding_patterns.md` 的 ranking provider 模式已過時

- 文件位置：`.serena/memories/ui_coding_patterns.md:224`-`.serena/memories/ui_coding_patterns.md:230`
- 現行規範：`lib/providers/AGENTS.md:7`-`lib/providers/AGENTS.md:13`、`lib/providers/AGENTS.md:21`-`lib/providers/AGENTS.md:24`
- 程式碼佐證：`lib/services/cache/ranking_cache_service.dart:20`-`lib/services/cache/ranking_cache_service.dart:61`、`lib/services/cache/ranking_cache_service.dart:225`-`lib/services/cache/ranking_cache_service.dart:228`、`lib/providers/popular_provider.dart:133`-`lib/providers/popular_provider.dart:138`
- 測試佐證：`test/ui/pages/ranking_ui_state_consumption_test.dart:78`-`test/ui/pages/ranking_ui_state_consumption_test.dart:91`

memory 文件仍把「API 數據 + 緩存」描述成 `CacheService + StreamProvider`，並把首頁、探索頁排行榜列為例子。現行 `lib/providers/AGENTS.md` 已改成 `StateNotifierProvider` + immutable `RankingCacheState`，程式碼也使用 `List.unmodifiable` 與 `rankingCacheServiceProvider.select(...)`。這會讓 agent 在審查或修改 Home/Explore ranking UI 時被過時 memory 帶偏。

### 4. 文件問題 / 低嚴重度 - `.serena/memories/ui_coding_patterns.md` 的 UI 常量規則比現行 AGENTS 更嚴，且與程式碼現況不一致

- 文件位置：`.serena/memories/ui_coding_patterns.md:680`-`.serena/memories/ui_coding_patterns.md:693`、`.serena/memories/ui_coding_patterns.md:696`-`.serena/memories/ui_coding_patterns.md:759`
- 現行規範：`lib/ui/AGENTS.md:69`-`lib/ui/AGENTS.md:85`
- 程式碼佐證：`lib/ui/windows/lyrics_window.dart:542`、`lib/ui/windows/lyrics_window.dart:661`、`lib/ui/windows/lyrics_window.dart:1377`、`lib/ui/widgets/color_palette_button.dart:433`

memory 寫「新代碼禁止使用硬編碼值」並提供硬編碼值替換表；現行 `lib/ui/AGENTS.md` 改成「重複或 design-system values 優先用 shared constants，小型一次性 layout/animation literal 可接受」。程式碼仍有一些局部動畫 duration、繪製用 radius 或 debug page delay。這不是單一 UI bug，但會讓文件審查產生誤報；依 `AGENTS.md:45`-`AGENTS.md:47` 與 `docs/README.md:17`-`docs/README.md:20`，這類核心規則不應在 memory 中保留相衝突版本。

### 5. 文件問題 / 低嚴重度 - `ListTile.leading Row` 規則若被寫成全域搜尋會誤中合法 `AppBar.leading`

- 文件位置：`lib/ui/AGENTS.md:63`-`lib/ui/AGENTS.md:67`
- 程式碼位置：`lib/ui/pages/library/library_page.dart:56`-`lib/ui/pages/library/library_page.dart:75`

`rg -n "leading:\\s*Row"` 在 `lib/ui` 只找到 `LibraryPage` 這一處。它是 `AppBar.leading` 而不是 `ListTile.leading`，因此不違反 `ListTile` 規範本身；但目前的文字「Avoid `Row` inside `ListTile.leading`」若被簡單靜態搜尋，容易把這個合法 `AppBar.leading` 複合 leading 當成例外。建議未來若加靜態測試，pattern 應限定 `ListTile(...)` 區塊內的 `leading: Row`，不要用全域 `leading: Row`。

## Evidence

- 文檔語料已覆蓋：`AGENTS.md`、`lib/ui/AGENTS.md`、`lib/providers/AGENTS.md`、`lib/services/AGENTS.md`、`lib/services/audio/AGENTS.md`、`lib/data/AGENTS.md`、`lib/data/sources/AGENTS.md`、`docs/README.md` 指向的 `docs/development.md` / `docs/build-guide.md` / `docs/build-and-release.md` / `docs/debugging-with-vm-service.md`、`README.md:121`-`README.md:123` 明確引用的現行文檔、`.serena/memories/*.md`。
- `docs/agents/` 不存在。
- `docs/history/refactoring-log.md` 在 `docs/README.md:13`、`docs/README.md:20` 與 `AGENTS.md:56`-`AGENTS.md:58` 都被標示為 archived/background，未作為目前規範使用。
- 規範性要求驗證：
  - AudioController 邊界：`AGENTS.md:98`-`AGENTS.md:102` 與 `lib/services/audio/AGENTS.md:28` 要求 UI 不繞過 `AudioController`；`rg` 在 `lib/ui` 找到的是 `audioControllerProvider`/notifier 使用，未找到 UI 直接調用 `FmpAudioService` 或 `audioServiceProvider`。
  - 圖片組件：`lib/ui/AGENTS.md:5`-`lib/ui/AGENTS.md:12` 禁止 UI 直接 `Image.network()` / `Image.file()`；`rg -n "Image\\.(network|file)\\(" lib/ui lib/core lib/services test/ui` 只有文件命中，未見 UI 程式碼命中。
  - TrackActionCoordinator：`lib/ui/AGENTS.md:39`-`lib/ui/AGENTS.md:48` 與 `lib/ui/handlers/track_action_coordinator.dart:14` 對齊；Home/Explore/Search/Playlist/Downloaded/History 等頁面使用 shared menu builders 與 coordinator。
  - AppBar spacing：`lib/ui/AGENTS.md:56`-`lib/ui/AGENTS.md:61` 與多數頁面 AppBar actions 的 `const SizedBox(width: 8)` 對齊，例如 `lib/ui/pages/settings/database_viewer_page.dart:49`-`lib/ui/pages/settings/database_viewer_page.dart:58`。
  - loading guard：`lib/providers/AGENTS.md:15`-`lib/providers/AGENTS.md:17`，Search/Explore/Library/Playlist detail 等主要 StateNotifier 頁面使用 `isLoading && data.isEmpty` 或等價初始資料 guard，例如 `lib/ui/pages/explore/explore_page.dart:150`-`lib/ui/pages/explore/explore_page.dart:151`、`lib/ui/pages/search/search_page.dart:422`。
  - ranking immutable state：`lib/providers/AGENTS.md:21`-`lib/providers/AGENTS.md:24`、`lib/services/cache/ranking_cache_service.dart:50`-`lib/services/cache/ranking_cache_service.dart:52`、`test/ui/pages/ranking_ui_state_consumption_test.dart:78`-`test/ui/pages/ranking_ui_state_consumption_test.dart:91` 對齊。
  - database viewer coverage：`lib/ui/AGENTS.md:87`-`lib/ui/AGENTS.md:98`、`lib/providers/database_provider.dart:27`-`lib/providers/database_provider.dart:39`、`lib/ui/pages/settings/database_viewer_page.dart:32`-`lib/ui/pages/settings/database_viewer_page.dart:44`、`test/ui/pages/settings/database_viewer_page_coverage_test.dart:56`-`test/ui/pages/settings/database_viewer_page_coverage_test.dart:107` 對齊。

## User impact

- 過時或不精確的描述性文件會讓後續 agent 在 UI 審查時製造假陽性，尤其是 routing、desktop layout、ranking provider pattern、UI constants。
- `desktop = three-column` 的 scoped UI 指令若被當成硬規範，可能促成不必要的 layout 改動，或錯誤地要求無播放內容時也保留空 detail panel。
- `.serena/memories/ui_coding_patterns.md` 仍保留核心 UI 規則的舊版本，與「memory 只放窄補充」的維護方向相衝突；多 agent 同時工作時，引用不同文件會得出不同審查結論。

## Suggested direction

- 把 `lib/ui/AGENTS.md:106` 的 Desktop 描述調整為「可收合側欄 + 主內容 + 播放/電台上下文存在時的可選 detail panel」，與 `docs/development.md` 和實作一致。
- 更新 `docs/development.md` 路由表，補上 user guide 與 account login 子路由；或把表格改寫成「主要路由摘要」並指向 `RoutePaths` 作權威來源。
- 將 `.serena/memories/ui_coding_patterns.md` 降級為歷史參考、刪除或合併仍有效的狹窄補充到 scoped `AGENTS.md`；至少移除 `CacheService + StreamProvider` ranking 描述與「禁止所有硬編碼 UI magic number」的舊規則。
- 若新增 UI 靜態規則測試，對 `ListTile.leading Row` 使用 AST 或區塊限定搜尋，避免把 `AppBar.leading` 的合法 `Row` 納入。

## Instruction docs accuracy notes

- `lib/ui/AGENTS.md` 作為拆分後 UI 指令文件，規範性內容大多準確：圖片元件、TrackActionCoordinator、AppBar trailing gutter、ListTile.leading Row、UI constants、database viewer coverage、breakpoints 都有現有程式碼或測試支撐。
- `lib/providers/AGENTS.md` 對 loading guard、provider invalidation、ranking immutable state、database startup/migration 的規範與目前實作及測試一致。
- `docs/development.md` 是 onboarding 摘要，不應承載完整 agent 規則；目前大方向正確，但 routing 表屬描述性內容，已落後於 `lib/ui/router.dart`。
- `.serena/memories/refactoring_lessons.md` 明確標示 current code/tests 優先，且其 UI 狹窄坑點與 AGENTS 大致一致；`.serena/memories/ui_coding_patterns.md` 則仍像舊版完整 UI 規範，與目前文檔維護邊界不一致。
