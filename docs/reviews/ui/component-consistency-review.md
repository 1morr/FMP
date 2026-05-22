# FMP UI 元件一致性審查

## Findings

### 1. 播放列表卡片選單在 Home 與 Library 重複維護

- 類型：重構機會
- 嚴重度：中
- 位置：
  - `lib/ui/pages/library/library_page.dart:530`
  - `lib/ui/pages/library/library_page.dart:595`
  - `lib/ui/pages/home/home_page.dart:1213`
  - `lib/ui/pages/home/home_page.dart:1278`

`LibraryPage` 與 `HomePage` 各自實作同一組播放列表操作：`play_mix`、`add_all`、`shuffle_add`、`edit`、`refresh`、`delete`，也各自用 `switch` 分派到對應方法。這不是 common track action 的違規，因為它處理的是 playlist，不是單曲；但目前兩頁的使用者流程實質相同，變更匯入歌單刷新、Mix 歌單播放、刪除確認或錯誤處理時容易只改到其中一頁。

### 2. 同頁播放列表選單同時存在桌面 context menu 與底部 sheet 的重複項目

- 類型：重構機會
- 嚴重度：低
- 位置：
  - `lib/ui/pages/library/library_page.dart:530`
  - `lib/ui/pages/library/library_page.dart:620`
  - `lib/ui/pages/home/home_page.dart:1213`
  - `lib/ui/pages/home/home_page.dart:1304`

每個播放列表卡片同時有 `PopupMenuEntry` 版本與 bottom sheet `ListTile` 版本，兩套都列出同一批 playlist 操作。這會讓桌面右鍵/更多選單與觸控長按 sheet 在後續功能調整時有分歧風險，例如某個操作的 enabled 狀態、刷新中的 icon、或錯誤色文字只更新其中一邊。

### 3. 三個遠端加入歌單對話框複製同一套歌曲摘要與遠端歌單列 UI

- 類型：重構機會
- 嚴重度：中
- 位置：
  - `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:402`
  - `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:538`
  - `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:427`
  - `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:562`
  - `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:389`
  - `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:525`

Bilibili、YouTube、Netease 的「加入遠端歌單」sheet 都各自複製歌曲摘要 header、遠端播放列表封面、已選/部分選取狀態、loading spinner、`selectedTileColor` 與 tap 切換邏輯。這些是跨來源相同的操作模型；目前各來源仍有不同 id 型別與 service 呼叫，但視覺與選取狀態元件可抽成共用 widget，避免單一來源修正後另外兩個來源留下舊互動。

### 4. 補充記憶文件的 UI constants 對照已落後目前程式碼

- 類型：文檔問題
- 嚴重度：低
- 位置：
  - `.serena/memories/ui_coding_patterns.md:704`
  - `.serena/memories/ui_coding_patterns.md:740`
  - `.serena/memories/ui_coding_patterns.md:754`

`.serena/memories/ui_coding_patterns.md` 描述 `AppRadius.borderRadiusXl` 是 12dp、`AppRadius.borderRadiusLg` 是 8dp，並提到 `AppRadius.borderRadiusXxxl`、`AppSizes.queueItemHeight`、`AppSizes.downloadTileHeight`、`AppSizes.sidePanelMinWidth`、`AppSizes.sidePanelMaxWidth`。目前 `lib/core/constants/ui_constants.dart:18` 到 `lib/core/constants/ui_constants.dart:32` 的實作是 `lg = 12.0`、`xl = 16.0`，且沒有上述 `Xxxl` 與 AppSizes 成員。依任務分類，這份 memory 只能作補充；若 agent 依它做自動化替換，會產生不存在的 symbol 或錯誤半徑語意。

## Evidence

- 已讀規範：`AGENTS.md`、`lib/ui/AGENTS.md`、`lib/services/AGENTS.md`、`lib/providers/AGENTS.md`、`docs/README.md`。補充讀取 `.serena/memories/ui_coding_patterns.md`、`.serena/memories/code_style.md`、`.serena/memories/refactoring_lessons.md`，其中與 AGENTS 或目前程式碼衝突者不作為權威。
- `rg -n "Image\\.(network|file)\\(" lib test`：UI 程式碼沒有直接 `Image.network()` / `Image.file()` 命中；唯一命中是 `lib/ui/AGENTS.md:10` 的規範文字。
- `rg -n "TrackThumbnail|TrackCover|ImageLoadingService\\.load(Image|Avatar)" lib/ui test/ui`：目前 UI 使用共享圖片路徑；統計上 `lib/ui` 有 23 個 `TrackThumbnail(`、4 個 `TrackCover(`、29 個 `ImageLoadingService.loadImage(`。
- 另用括號深度掃描全部 `lib/ui` 的 `ImageLoadingService.loadImage(` 呼叫，未發現缺少 `width`、`height` 或 `targetDisplaySize` 的呼叫。`test/ui/static_rules/ui_consistency_static_rule_test.dart:48` 目前只保護部分已知固定尺寸呼叫，不是完整全域規則。
- `rg -n "ListTile\\s*\\(|leading:\\s*Row" lib/ui test/ui`：唯一 `leading: Row(` 命中為 `lib/ui/pages/library/library_page.dart:58`，上下文是 `AppBar.leading`，不是 `ListTile.leading`。`test/ui/static_rules/list_tile_leading_static_rule_test.dart:16` 已用靜態規則保護 `ListTile(... leading: Row(`。
- `flutter test test/ui/static_rules`：5 個 static rule tests 全部通過，包含 ListTile leading、cover picker/import preview stable key、部分圖片 display-size hint、download path unset color。
- `rg -n "existsSync\\(|await .*\\.exists\\(\\)|File\\(" lib/ui test/ui/static_rules`：UI runtime 的直接檔案存在檢查主要出現在刪除/管理流程，例如 `lib/ui/pages/library/downloaded_category_page.dart:30` 的 isolate 刪檔 helper 與 `lib/ui/pages/settings/developer_options_page.dart:141` 的資料庫大小讀取；沒有發現用 direct IO 取代歌曲封面/頭像渲染路徑的違規。
- `rg -n "buildCommonTrackActionMenuItems|buildTrackActionPopupMenuEntries|TrackActionCoordinator" lib/ui`：單曲 common actions 大多已走共用建構與 `TrackActionCoordinator`。例如 `lib/ui/pages/explore/explore_page.dart:348`、`lib/ui/pages/home/home_page.dart:661`、`lib/ui/pages/library/downloaded_category_page.dart:852`、`lib/ui/pages/library/playlist_detail_page.dart:1573`。`lib/ui/pages/search/search_page.dart:880` 與 `lib/ui/pages/search/search_page.dart:1415` 的 switch 是多 P / group 專屬批次行為，不列為違規。

## User impact

- 播放列表操作分散在 Home、Library、桌面 context menu、觸控 bottom sheet 四個位置，會增加「同一個播放列表操作在不同入口行為不同」的機率。對音樂播放器使用效率來說，這會直接影響新增隊列、隨機加入、刷新匯入歌單與刪除歌單這類高頻管理流程。
- 遠端加入歌單 sheet 的重複 UI 會讓 Bilibili、YouTube、Netease 的選取狀態與視覺回饋容易不同步。使用者在跨平台整理歌單時，最容易感受到的是 partial selection、loading、已選狀態與封面 fallback 不一致。
- 補充 memory 的 constants 對照落後會誤導後續 agent，在本來已經用 `ui_constants.dart` 集中的區域重新引入錯誤常量名稱或錯誤半徑語意。

## Suggested direction

- 先抽 playlist card action 的資料模型與 dispatcher，例如 `PlaylistCardAction` / `buildPlaylistActionMenuEntries()` / `PlaylistActionCoordinator`，讓 Home 與 Library 共用同一份 action 定義；頁面只傳入 playlist、refreshing state 與對應 callback。
- 對同一頁內的 popup menu 與 bottom sheet，讓兩種外觀都由同一份 action list 轉換，不要分別手寫 `PopupMenuItem` 與 `ListTile`。這能保留桌面與觸控入口差異，同時讓 action 可用狀態與文案一致。
- 將遠端加入歌單 sheet 的來源無關部分抽成共用 UI：歌曲摘要 header、遠端播放列表列、selected / partial / loading 狀態呈現。來源特有部分只保留 playlist id 型別轉換、載入資料與提交 service。
- 若要補強測試，優先增加 static rule 或結構測試來保護「所有 `ImageLoadingService.loadImage()` 都傳尺寸 hint」，因為現有測試只保護幾個已知檔案片段。

## Instruction docs accuracy notes

- `lib/ui/AGENTS.md` 與目前 `lib/core/constants/ui_constants.dart` 對 `AppRadius.borderRadiusXl` 是 `static final` 的描述一致。
- `.serena/memories/ui_coding_patterns.md` 的 UI constants 對照表與目前程式碼不一致；此文件應更新或縮減，避免與 `lib/ui/AGENTS.md`、`lib/core/constants/ui_constants.dart` 競爭權威。
- `test/ui/static_rules/list_tile_leading_static_rule_test.dart` 已覆蓋 `ListTile.leading Row` 規則，且目前無違規。若規範希望禁止 `AppBar.leading` 放複合 `Row`，那是另一條規則；現有 AGENTS 僅禁止 `ListTile.leading`。
- `test/ui/static_rules/ui_consistency_static_rule_test.dart` 已覆蓋部分圖片尺寸 hint，但不是完整全域掃描。這次審查用額外搜尋補足了全域檢查，未發現目前違規。
