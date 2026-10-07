# M2 PR 18b：佇列分頁與底部面板

依據：
- M2 `design.md` §7.3（佇列的使用者入口）、§9.3（播放頁 B）、§3.3（`auto_scroll_to_current`）；
- ADR 0018 §決定 5（隨機以位置為單位）與 §後果（隨機語意要在佇列頁說清楚）；
- ADR 0024 §決定 4、8。

依賴 PR 10（佇列模型）、PR 18a（播放頁）。右側「正在播放」面板在 PR 19。

## 目標

在播放頁上編輯佇列：
- 寬版版面在佇列分頁上編輯；
- 手機與 medium 在底部面板上編輯；
- 編輯包括點選跳到、拖曳重排、移到下一首、移除、清空；
- 隨機開著時說清楚拖曳的語意；
- 可以設定切歌時自動捲到目前這首。

## 要做的

### 共用的佇列清單（`QueueView`）

佇列分頁（expanded 以上）與底部面板（compact、medium）用同一個 widget。

- **標題列**：
  - 首數；
  - 「清空佇列」：只有圖示的按鈕，以 tooltip 當名稱，按了跳確認框；
  - 隨機開著時，下面多一行說明：「隨機順序跟著位置；拖曳只換歌，不改順序」（design §7.3）。
- **每列**：
  - 封面、曲名、上傳者、時長；
  - 目前這首以主色標示（照 18a：臨時播放中不標）；
  - 點一下 `jumpTo`；
  - 尾端依序是「⋯」選單與拖曳把手。
- **拖曳**：
  - `ReorderableListView.builder`，`buildDefaultDragHandles: false`，只有把手（`ReorderableDragStartListener`）能拖。手機的長按留給選單（design §7.3：右鍵、長按、「⋯」是同一份選單）。
  - 放下時呼叫 `PlaybackController.move(from, to)`，注意 Flutter `onReorder` 的 `newIndex` 在往下拖時多 1。
  - 一萬首也只建看得到的列，維持 18a 的固定列高。
- **選單**（右鍵、長按、尾端「⋯」同一份）：
  - 「下一首播放」：把這首移到目前這首之後，見下面「移到下一首」。目前這首本身沒有這一項。
  - 「從佇列移除」：`removeAt`，不提示。照擁有者在歷史頁定的「移除單筆不提示」（PR 15）。
- **清空**：確認後呼叫 `clear`，提示「已清空佇列」。照歷史頁「清除全部才提示」。佇列空了，播放頁照 18a 自己關閉；底部面板開著時一起關。
- **開啟時的捲動**：照 18a，從目前這首的前兩列開始。
- **列選單共用**：搜尋結果、歷史、佇列三處的選單機制抽成一個 widget，放在 `lib/ui/tracks/`。
  - 抽出的是：`MenuAnchor`、與按鈕共用的 `childFocusNode`、右鍵與長按的辨識器、「⋯」按鈕、Esc 關閉。
  - 選單項目由呼叫端傳入。
  - 這是 PR 15 留下的項目。搜尋頁與歷史頁既有的選單測試照舊要過。

### 移到下一首（`QueueModel`／`PlaybackController.moveToNext(int index)`）

- **語意**：等同「把這個位置移除，再以下一首播放加回」，但項目是同一個實例（`QueueEntry` 不換）、不檢查上限。
  - **在清單上**：移到目前這首之後，接在之前連續「下一首播放」的後面（`_playNextRun` 加 1）。
  - **隨機時**：它的排序也移到同一處，所以下一首（或接著的那幾首之後）一定播它。這和 `move` 的「只換歌、不改順序」不同，選單的這一項就是要它下一首播。
  - **臨時播放中**：排在快照那首（`currentIndex`）之後，照 `playNext`。
  - **不可用**：`index` 是目前這首，或佇列沒有目前這首時，不做事。
- 控制器照其他編輯：做完呼叫 `_queueEdited()`，所以前瞻會重新準備，`QueueStore` 也會存。

### 底部面板（compact、medium）

- **入口**：播放頁右上角的圖示鈕，與左上角的收合鈕對稱（擁有者決定）。
  - tooltip「佇列（Ctrl+Q）」，三語言；
  - 只有 compact、medium 有這顆鈕，寬版用分頁。
- **形式**：`showModalBottomSheet`，可拖動高度（`DraggableScrollableSheet`），內容是 `QueueView`。
- **關閉**：返回鍵與 Esc 關面板，不關播放頁（面板是自己的 route）。
- **Ctrl+Q**：
  - 播放頁開著時：compact、medium 開面板（取代 18a「不做事」的那一支）；
  - 播放頁沒開時：外殼照 18a 開播放頁；compact、medium 接著開面板，寬版切到佇列分頁。
- **佇列變空**：播放頁照 18a 自己關閉，面板也要一起關，不能留下一個蓋在外殼上的面板。

### 「切歌時捲到目前歌曲」（`auto_scroll_to_current`）

- **設定**：「播放」組的 Notifier 加 `autoScrollToCurrent`，預設關（design §3.3，欄位在 schema v3 已建好）、setter，以及設定頁一列開關，放在「播放歷史保留筆數」之後。三語言。
- **行為**：開著時，佇列清單（分頁或面板）開著而目前這首換了，就把清單捲到目前這首的前兩列，照開啟時的同一個位置。
  - 「換了」指 `currentIndex` 指的項目換了；拖曳讓它換位置不算。
  - 關著時切歌不捲。開啟時的捲動不受這個設定影響。
  - 使用者正在拖曳時不捲。

### 文件

- `app/AGENTS.md`：
  - § 播放：控制器入口加 `moveToNext`；佇列的隨機語意加一條「移到下一首」，附閘門。
  - § 介面：「播放頁」改寫佇列分頁、底部面板、Ctrl+Q、列選單共用，每條附閘門。
  - § 設定：「播放」組的欄位清單加這一列。
- `.trellis/spec/app/{ui,playback,settings}/` 需要時更新。
- 搜尋頁與歷史頁的 spec 原本寫「改一邊看另一邊」，抽成共用 widget 後改寫。

## 驗收

- **`QueueModel.moveToNext`**（`queue_model_test.dart`）：
  - 不隨機；
  - 隨機時下一首就是它；
  - 連續兩次移到下一首，依操作順序播；
  - 和 `playNext` 混用；
  - 臨時播放中；
  - 目前這首與空佇列不動；
  - 之後換歌時 `_playNextRun` 重來；
  - 把 `moveToNext` 加進 `a seeded run of edits…` 的操作清單，仍是「每個位置一輪恰好播一次」。
- **控制器**：`moveToNext` 之後前瞻換成新的下一首（`editing the queue prepares the look-ahead again` 群組加一例），並會存檔。
- **佇列清單**（widget）：
  - 每個動作都經控制器：點選、拖曳（往上與往下各一例，驗 `newIndex` 的換算）、選單的兩項、清空的確認與取消；
  - 目前這首沒有「下一首播放」；
  - 隨機開著時才有說明；
  - 一萬首只建看得到的列；
  - 右鍵、長按、「⋯」是同一份選單，用滑鼠打開的選單 Esc 關得掉。
- **隨機時拖曳**：開隨機後拖曳，畫面上的下一首與 `QueueModel` 一致；用控制器的 `next` 驗證實際播的那首。
- **底部面板**：
  - compact、medium 有入口鈕，寬版沒有；
  - 鈕與 Ctrl+Q 都會開；
  - 返回與 Esc 只關面板；
  - 佇列清空時面板與播放頁都關；
  - 播放頁沒開時，Ctrl+Q 在 compact 開頁加面板、在寬版開頁並切到佇列。
- **自動捲動**：
  - 開著時，切歌捲到目前這首；
  - 關著時不捲；
  - 拖曳換位置不算切歌；
  - 設定頁那一列寫入欄位（`playback_controls_test.dart`），Notifier 的預設與 `stored`（`playback_settings_test.dart`）。
- **guideline**：淺色、深色 × 400、1000 寬：佇列分頁（有隨機說明）與底部面板，加進 `test/ui/guidelines_test.dart`。
- **golden**：`player_page_large.png` 這次多了標題列、選單與把手，`--update-goldens` 後由主對話看圖。
- **既有測試**：搜尋頁、歷史頁的選單測試在抽出共用 widget 後照舊通過。
- **本機**：`dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全綠；Windows 上跑 `install_search_play_test.dart`（改到控制器）、`toast_layering_test.dart`（改到外殼）。
- **實機**（重播，測試插件）：
  - 兩平台：在佇列分頁或底部面板拖曳、移到下一首、移除、清空、點選跳到；開隨機後拖曳，確認接下來播的與畫面一致；
  - Windows：以鍵盤操作佇列（Tab 到列、Enter 跳到、「⋯」選單）；
  - Android：底部面板的入口、拖動高度、返回鍵只關面板。

## 範圍外

- 右側「正在播放」面板（PR 19）。
- 多選、批次移除、佇列搜尋：舊版沒有，M2 不做。
- 鍵盤重排：Flutter 的 `ReorderableListView` 給輔助技術「上移、下移」的語意動作，桌面鍵盤的重排快捷鍵不另做。Ctrl+↑／↓ 已是音量。
