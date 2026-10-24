# U 設計

決定本身在 ADR 0035；這份寫怎麼落到程式碼：模組邊界、資料與契約、測試的改動、相容性。
視覺規格以設計稿為準：`research/design/`（`*.dc.html`，每張畫板一個檔，`canvas.json` 是畫布配置）。
需求編號 R1–R7 見 `prd.md`。

## 1. 模組邊界

| 區塊 | 位置 | 改動 |
|---|---|---|
| 主題 | `lib/ui/theme/` | `buildAppTheme` 收種子色與字型；舊版元件主題寫在 `app_theme.dart`；新的 `theme_presets.dart` 放 9 個種子色（預設＋8 個 preset，值抄舊版 `lib/ui/theme/theme_preset_colors.dart`） |
| 外觀設定 | `lib/settings/appearance_settings.dart`、`lib/domain/appearance.dart`、`lib/data/repositories/appearance_settings_repository.dart`、`lib/ui/settings/appearance_controls.dart` | 加種子色、字型 |
| 版面狀態 | `lib/data/repositories/layout_state_repository.dart` | 加 `railExpanded`，刪 `playerTab` |
| 字型清單 | `lib/platform/fonts/` | `FontFallback` 旁加 `fontChoices`（每平台一份固定清單），能力宣告照 ADR 0009 |
| 修飾鍵 | `lib/platform/`（新能力 `shortcutModifier`：`control` 或 `meta`） | `lib/ui/shell/*_shortcuts.dart` 改讀它，不自己判斷平台 |
| 標題列 | `lib/platform/window_chrome/`（新） | Windows：`window_manager` 隱藏系統標題列、提供拖曳區與三顆按鈕的動作；其他平台宣告沒有 |
| 外殼 | `lib/ui/shell/` | `ShellDestination` 加 `queue`；`_PermanentDrawer`／`NavigationRail` 換成 `LegacySideRail`（新檔）；播放列移到最外層 |
| 頁頂 | `lib/ui/shell/page_app_bar.dart`（新） | 置中 AppBar；每頁的標題列改用它，多選時換選取列 |
| 播放頁 | `lib/ui/player/` | `player_page.dart` 拆成 `player_layouts.dart`（寬、窄、矮）與 `player_top_bar.dart`；刪 `_PlayerTabs`、`glass_panel.dart` |
| 佇列 | `lib/ui/queue/`（新目錄，從 `player/queue_view.dart` 搬出） | 佇列頁＝導覽目的地；`_QueueSheet` 刪除 |
| 正在播放標示 | `lib/ui/tracks/now_playing_overlay.dart`（新） | 佇列、歷史、搜尋、排行、歌單詳情共用 |
| 歷史 | `lib/ui/history/`、`lib/data/repositories/play_history_repository.dart` | 統計、篩選、搜尋、排序、兩種刪除 |
| 搜尋 | `lib/ui/search/`、`lib/data/repositories/search_history_repository.dart`（新）、`lib/plugins/search/all_sources_search.dart`（新） | 搜尋歷史、自動載入、全部音源 |
| 匯入 | `lib/library/playlist_importer.dart`、`lib/ui/library/import_dialog.dart`、`lib/ui/accounts/account_import_page.dart`（新，取代勾選後的進度區） | n／M 與取消 |
| 打亂 | `lib/playback/queue_model.dart`、`playback_controller.dart` | `shuffleEntries()` |
| 宿主 API | `lib/plugins/source_dto.dart` | 選填 `viewCount`（曲目）、`webUrl`（`TrackDetail`） |
| 舊資料 | `lib/legacy_import/legacy_settings_converter.dart` 等 | 四項設定改成會匯入 |

`lib/ui/` 只經 `lib/platform/` 取得平台差異（`fmp_platform_checks`）；新的字型清單、修飾鍵、標題列都走能力宣告，Android 與 Windows 先實作，macOS／iOS 宣告 `none` 直到平台任務。

## 2. 主題與外觀（R1.5、R1.6、R2.3）

- `ColorScheme.fromSeed(seedColor: settings.seedColor ?? appSeedColor)`；`AppTokens.forScheme` 照舊從 scheme 算語意色，種子變了跟著變。
- 舊版元件主題：卡片底色 `surfaceContainerLow`、圓角 12；輸入框填色加圓角；清單列的密度與選取色；AppBar 置中、捲動時 `surfaceTint`；導覽指示的形狀。數值從設計稿 `Main.dc.html` 的主題畫板與舊版 `lib/ui/theme/app_theme.dart` 取，寫成 `AppLayout`／`AppTokens` 的值（`fmp_design_tokens` 不允許在 `lib/ui/` 寫字面數字）。
- 字型清單（平台層）：
  - Windows：系統預設、微軟正黑體 UI、微軟雅黑 UI、新細明體、標楷體、Yu Gothic UI、Meiryo；
  - Android：系統預設、sans-serif、serif、monospace（舊版清單去掉無效的變體）；
  - macOS／iOS（平台任務接上）：系統預設、蘋方-繁、蘋方-簡、Hiragino Sans。
  - 選了字型時它放在 `fontFamily`，ADR 0024 §決定 2 的 CJK fallback 照舊排在後面。
- 自訂色：色相環＋HEX 輸入的對話框（設計稿 `SettingsWin.dc.html`）；用 `flex_color_picker` 之前先查有沒有成熟維護的套件，沒有再自己寫。

## 3. 外殼（R1.1–R1.4、R1.8）

- 版面樹（medium 以上）：

  ```
  Column
  ├─ WindowTitleBar（Windows 自繪；其他平台不佔位）
  ├─ Expanded(Row: LegacySideRail | 內容區(巢狀 Navigator) | NowPlayingPanelSide（有曲目才出現）)
  └─ PlayerBar（橫跨整個寬度）
  ```

  compact：`Scaffold(body: 內容區, bottomNavigationBar: Column[PlayerBar, NavigationBar])`。
- `LegacySideRail`：收合 72、展開 256（`AppLayout`），展開時顯示 FMP 名稱與文字標籤；底部一顆展開／收合鈕；狀態寫回 `layout_state.rail_expanded`（依裝置）。保留 `FocusTraversalGroup` 的導覽區（F6）。
- `ShellDestination.queue` 的根頁是 `QueuePage`；Ctrl+Q／⌥⌘U 改成切到它；`PlayerPage` 不再開佇列。
- 播放列進度細線：自繪 `ThinProgressBar`（2dp；`MouseRegion` 進入或拖曳時 6dp 加把手，時間浮在把手上方）；觸控上點細線跳轉。讀屏用 `Semantics(slider)` 保留現在的語意。
- 面板：`hasNowPlayingPanel(windowClass) && 有曲目` 才放；內容加「下一首」（讀 `QueueState` 的下一個位置，隨機開著時是隨機順序的下一首）、加入歌單鈕；封面與標題可點開 `TrackDetail.webUrl`（新的選填欄位，插件有提供且過允許主機檢查時；否則不可點）。

## 4. 播放頁（R3）

- 版面選擇：`width >= 840 && height >= 520` → 寬版；`width > height && height < 520` → 矮版；其他 → 窄版。寬版在 M7 前一律單欄（`hasLyrics == false`），內容寬上限 720。
- 轉場：`PageRouteBuilder`，從下往上 `easeOutCubic`，關閉 `easeInCubic`（舊版 `lib/ui/router.dart:103-120`）。
- 曲目詳細：窄版底部面板（`DraggableScrollableSheet`），寬版右側滑入的面板，內容都是 `TrackDetails`。
- 頂列的音量與輸出裝置沿用播放列的 `_MuteButton`、`_VolumeSlider`、`_OutputDeviceButton`（抽成公開元件放 `lib/ui/player/audio_controls.dart`）。

## 5. 佇列與打亂（R4）

- `QueueModel.shuffleEntries(Random random)`：
  - 條件：`mode == normal` 且 `entries.length > 1`；Mix 或直播時回 `blocked`。
  - 把目前這首以外的項目洗牌，目前這首放第一位，`currentIndex = 0`。
  - 隨機開著時重建 `shuffleOrder`，起點是目前這首，本輪已播清空。和 `setShuffle(true)` 同一個產生函式。
  - 持久化與通知走既有的 mutation 路徑。
- `PlaybackController.shuffleQueue()` 轉呼叫；UI 按了提示「已打亂」（舊版 `t.queue.shuffled`）。
- 佇列頁頂部：AppBar（左：跳到頂／底，依捲動位置切換；中：標題，Mix 時「Mix：標題」；右：打亂、清空）；下面「正在播放第 n 首」橫幅（右側「共 m 首」，點了捲到目前）；隨機開著時保留現在的說明列。Mix 續取時列尾 48dp 轉圈。空佇列：圖示、標題、說明、「去搜尋」按鈕（切到搜尋目的地）。
- 每列：48dp 封面（正在播放時疊 `NowPlayingOverlay`）、標題、上傳者、時長、「×」、「⋯」、拖曳把手。列高回到 72（`AppLayout`）。

## 6. 歷史（R5）

- repository 新方法（`play_history_repository.dart`）：
  - `stats(now)`：今日、本週、全部的首數與總時長，一次查詢；
  - `page({source, day, query, sort, cursor})`：`sort` 是新到舊、舊到新、播放次數。播放次數依曲目分組，每組顯示最後一次播放。
  - `deleteAllForTrack(trackKey)`、`deleteMany(ids)`。
  - 查詢條件都要有索引：`played_at`；（`track_key`, `played_at`）若沒有就加，要做 migration。
- UI：統計卡、篩選 chip 列（全部＋每個音源、日期 chip、排序 chip）、AppBar 的日曆與搜尋。日期分組的標頭有圓點、首數、折疊；折疊狀態只存在頁面裡。
- 多選動作加「刪除」（確認框，紅色鈕）。

## 7. 搜尋（R6.1–R6.5）

- `search_history`：`query`（主鍵，trim 後原樣）、`searched_at`。送出搜尋時 upsert；只保留最新 50 筆。搜尋框聚焦且空白時列出，可以刪單筆或清除。備份歸類「帶走」（`test/data/database/backup_format_test.dart` 的表歸類閘門）。
- 全部音源：`AllSourcesSearch` 對每個已啟用、有 `search` 能力的插件各發一次，同時最多 3 個；每個插件一組，各有自己的游標與「載入更多」；單一插件失敗在它那組顯示錯誤與重試。來源 chip 列最前面加「全部」，預設選它（舊版預設）。
- 自動載入：最後一列出現時呼叫 `loadMore()`；失敗時保留「載入更多」按鈕當重試。
- `viewCount`、`webUrl`：`sourceDtoShapes` 的曲目加選填 `viewCount`（非負整數）、`TrackDetail` 加選填 `webUrl`（`Uri` 且過 `allowedHosts`，同 `Artwork.url` 的檢查）；契約測試的 `checks.json` 可以期望它們存在；B 站、YouTube、網易的插件有值就填（fmp-plugins 另一個 PR）。播放數以 `NumberFormat.compact` 顯示。
- 正在播放標示：`currentTrackKeyProvider`（從 `PlaybackState` 取）；比對規則用 `TrackKey`，分 P 用 `formatGroup` 對到群組列與子列。

## 8. 音樂庫與匯入（R7）

- 進度回報：`onProgress(int count)` 改成 `onProgress(ImportProgress p)`，欄位 `count`、`total?`（插件頁面的 `total`）。帳號匯入另有 `expectedTotal`（帳號清單的 `trackCount`）。顯示時 M 優先用 `total`，其次 `expectedTotal`。
- 取消：`ImportCancel`（`bool get isCancelled`）接到 `RefreshTrigger.isCurrent`。
  - 第一頁寫入前取消：刪掉剛建的歌單列，什麼都不留。
  - 寫入一頁以上後取消：保留已寫入的項目，`last_result = partial`，下次刷新照 ADR 0033 §決定 2 補齊。
  - 提示「已取消，保留 n 首」。
- 網址匯入對話框：確定式進度條＋「已匯入 n／M 首」＋目前曲名＋「取消」；第一頁之前照舊顯示「辨識中」與配對選項。
- 帳號匯入全頁：頂部總進度（歌單 n／m），每張歌單一列（名稱、n／M 首、狀態），底部「取消」；完成後列出結果，可開詳情。
- 歌單刷新：卡片上的轉圈、詳情頁的「已更新 n 首」。
- 歌單格狀：所有寬度都用格狀，手機兩欄；卡片角落放來源圖示（插件 manifest 的圖示，沒有就用音源名縮寫）。
- 詳情頂圖：`SliverAppBar(expandedHeight: 280)`，背景是封面模糊加遮罩，捲動後收合成置中標題；標頭加總時長（`PlaylistDetail` 加總和）與來源徽章。
- `showDestructiveConfirm`（`lib/ui/dialogs/`，新）：紅色確認鈕；把現有的刪除確認都換成它。
- 加入歌單：compact 用底部面板，其他用對話框；頂端一張歌曲資訊卡。
- 編輯歌單封面：「從歌曲封面選」格狀選擇器，列出歌單內不重複的封面。

## 9. 首頁、電台、共用狀態元件（R6.6–R6.11）

- 首頁橫向區塊：卡片有底色；桌面有左右捲動箭頭與兩端漸層，可以滑鼠拖曳；歌單卡、電台卡有選單（重用音樂庫與電台的動作）；有「建立歌單」卡。
- 電台：compact 清單、expanded 以上圓形封面網格；平常開播的排前面（穩定排序），AppBar 的排序鈕進入手動排序模式（顯示使用者順序與把手），再按完成。首頁電台區塊也是開播優先。
- `EmptyState` 加 `error` 樣式（error 色圖示）與 `compact` 橫條樣式；`LoadingState`（轉圈＋一行文字）。
- 直播間列：未開播時封面灰階、播放鈕停用、有分區標籤時顯示。

## 10. Windows 標題列（R1.7）

- `window_manager`：`TitleBarStyle.hidden`，`DragToMoveArea` 包住標題列空白處，按鈕呼叫 `minimize`／`maximize`／`unmaximize`／`close`；雙擊標題列切換最大化。
- `windows/runner/main.cpp` 的單一實例以「視窗類別＋標題」找第一個實例：標題不變，所以不受影響。仍要在 Windows 實機驗兩個 flavor 同時開。
- 播放頁的頂端也是拖曳區（舊版 `immersive_player_scaffold.dart:82`）。
- 版本：實作時用 context7 查 `window_manager` 的現況（ADR 0021 §後果：0.5.x 停止維護、0.6.0 改建在 `nativeapi`），選維護中的那一條。

## 11. 舊資料匯入（ADR 0035 §決定 12）

- `primaryColor` → `appearance_settings.seed_color`；`fontFamily` → `font_family`，不在新清單時給 null；`railExpanded` → `layout_state.rail_expanded`；舊搜尋歷史 → `search_history`（取最新 50 筆）。
- `UnimportedSetting` 刪掉這四個常數與對應翻譯；`legacy_settings_converter_test.dart` 照改。

## 12. 測試的改動

| 會壞的測試 | 處理 |
|---|---|
| `test/ui/shell/app_shell_test.dart`（`count, 5` 與目的地順序） | 改成六項；加側欄展開與記住 |
| `test/ui/player/*golden*`（播放頁 3 張、播放列 3 張）、`shell/now_playing_panel_*`（2 張） | 播放頁換成寬、窄、矮三張；播放列三張重產；面板兩張重產 |
| `player_page_test.dart` 的 layouts、tabs、glass | 刪 tabs、glass；layouts 改三種版面 |
| `queue_view_test.dart` 的 bottom sheet | 改成佇列頁 |
| `guidelines_test.dart` | 新畫面都加進去 |
| `test/data/database/backup_format_test.dart` 的表歸類 | 加 `search_history` |
| drift schema 快照 | 新版本 |

## 13. 相容性與回退

- 資料：migration 有 `appearance_settings` 兩欄、`layout_state` 加 `rail_expanded` 刪 `player_tab`、`search_history` 表，可能加歷史索引。除了刪 `player_tab`（只存播放頁分頁，拿掉分頁後沒有讀者）都是只加不改；回退＝不讀新欄位，舊版 App 不受影響（新版資料庫與舊版分開）。
- 宿主 API：`viewCount` 是選填，舊插件不填照常運作；`hostApiVersion` 不變。
- 每個 PR 可以單獨 revert：PR 之間的相依只在 `implement.md` 的順序裡。
