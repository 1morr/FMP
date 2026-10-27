# U 執行計畫

- 規則：`app/AGENTS.md` § 驗證（每個 PR 至少跑第一列）、§ 實機驗證（ADR 0027）。
- 決定與設計：ADR 0035、`design.md`；視覺：`research/design/`。
- 實作交給 sonnet 的 `trellis-implement`，附這份的對應段落；遇到計畫外的設計決定就停下回報。
- 每個 PR 由 opus 的 `trellis-check` 審查。
- 每個 PR 都是 tracer bullet 順序裡的一步，合併後 App 都能用。

## 共通

- 驗證（在 `app/`）：`dart format --output=none --set-exit-if-changed .`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`。
  - 改翻譯先 `dart run slang`；改 table 先 `dart run build_runner build --delete-conflicting-outputs`，並存 schema 快照。
  - 改版面的 golden 用 `flutter test --update-goldens <檔>`，看過 `goldens/ci/` 的圖再提交。
- Mac 上完整的 `flutter test` 要等 PR 1 才可靠；在那之前本機跑改到的測試檔，完整套件看 CI。
- 實機：每個 PR 在 Android 模擬器驗（手機直向，寬版用橫向 914dp），模式是重播（測試插件）。標「Windows」的 PR 另在 Windows 電腦上驗：虛擬機跑不了，見 `research/mac-environment.md`。
- 截圖與回報不含個人資訊；設計稿裡的假資料不要寫進 fixture 以外的地方。
- Windows 實機驗證批次做（擁有者 2026-10-25）：標「Windows」的 PR 在 Android 驗過、CI 綠了就合併，把要驗的項目記在下面的待驗清單；
  累積幾個後（PR 6 之後、里程碑驗收時）在 Windows 電腦上一次驗完，有問題開修正 PR。

## Windows 待驗清單

- [ ] PR 2：外觀頁的 6 個 Windows 字型實際換字（正黑體、雅黑、新細明體、標楷體、Yu Gothic UI、Meiryo），中文字形正常；主題色與自訂色。
- [ ] PR 5：側欄 hover、展開與收合的動畫、記住狀態；搜尋頁多選時按 Ctrl+F 退出多選並聚焦搜尋框。
- [ ] PR 6：播放列細線滑鼠移入變 6dp、把手與時間泡泡、拖曳中移出播放列；Tab 到細線的焦點框與 ←／→；播放列在展開與收合的側欄下方；面板只在有曲目時出現、「下一首」、加入歌單對話框；840 邊界。
- [ ] PR 12：首頁一排卡片滑鼠移入時兩端漸層與左右箭頭、捲到頭的箭頭收起、滑鼠拖曳捲動、移出後箭頭消失；右鍵開歌單卡與電台卡選單；漸層下的卡片點得到、滾輪捲得動；電台網格 hover。
- [ ] PR 13：音樂庫格狀約 7 欄（1400 寬）、卡片 hover、用滑鼠拖封面角的把手排序；頂圖在寬視窗的版面。

## 偶發失敗的測試

完整套件在 Linux 負載下偶發、單獨跑都過；PR 18 之前一起收斂（先找出等待條件，改成等明確的事件）。

- `test/ui/tracks/part_display_test.dart`「the player bar shows the composed title」卡住到逾時（PR 5 的一輪完整跑）。
- `test/data/cache/image_cache_manager_test.dart`「two plugins downloading the same URL at once keep separate staging files and separate entries」：`eventually` 50 輪內沒成立（PR 12 合併 main 後的一輪）。

## PR 清單

| # | 內容 | 需求 | 平台驗證 |
|---|---|---|---|
| 0 | 文件：ADR 0035 改「已採納」；ADR 0018、0024、0033 被推翻的段落加補充；`milestones.md` 的 U 段；`docs/README.md` 的 ADR 索引（有的話） | — | — |
| 1 | Mac 開發環境：完整 `flutter test` 能在 Mac 上跑 | — | — |
| 2 | 主題與外觀 | R1.5、R1.6、R2.3（Windows、Android 清單）、ADR 0035 §12 的 `primaryColor`、`fontFamily` | Android、Windows（字型） |
| 3 | 導覽六項與佇列頁 | R1.1、R4.4 | Android |
| 4 | 匯入進度與取消 | R7.1–R7.4 | Android |
| 5 | 舊版側欄與置中 AppBar | R1.2、R1.3、ADR 0035 §12 的 `railExpanded` | Android、Windows（hover、展開） |
| 6 | 播放列橫跨與進度細線、右側面板 | R1.4、R1.8（不含 `webUrl`） | Android、Windows（hover、面板） |
| 7 | 播放頁 | R3 | Android（直向、橫向、矮版） |
| 8 | 佇列頂部、每列、打亂、正在播放遮罩 | R4.1–R4.3 | Android |
| 9 | 歷史 | R5 | Android |
| 10 | 曲目清單共用：正在播放標示、時長固定欄、多選補項、自動載入 | R6.1、R6.4、R6.8、R6.11（時長） | Android |
| 11 | 搜尋歷史 | R6.3、ADR 0035 §12 的搜尋歷史 | Android |
| 12 | 首頁、電台、探索、狀態元件、直播間列 | R6.6、R6.7、R6.9、R6.10、R6.11（直播間） | Android、Windows（首頁箭頭與拖曳） |
| 13 | 音樂庫與歌單詳情 | R7.5–R7.10 | Android |
| 14 | 設定摘要與音質說明 | R7.11 | Android |
| 15 | Windows 標題列、修飾鍵能力、iOS 的 Dart 側慣例 | R1.7、R2.2、R2.4 | Windows（兩個 flavor 同開、拖曳、最大化、單一實例） |
| 16 | 宿主 API 的 `viewCount`、`webUrl`，加上 fmp-plugins 對應 PR | R6.5、R1.8（`webUrl`） | Android；真實連線各音源搜尋一次（ADR 0027 §決定 2） |
| 17 | 全部音源搜尋 | R6.2 | Android；真實連線一次（多音源） |
| 18 | 驗收：`research/u-acceptance.md`、`milestones.md` 勾選 | 驗收條件 | Android、Windows 完整流程 |

順序的理由：主題先做，後面每頁的外觀都建在它上面；導覽與佇列頁是外殼的骨架。匯入進度是擁有者最痛的點，排在骨架之後立刻做。插件介面（16）與全部音源（17）成本最高、和其他無關，放最後。

## 各 PR 的要點

### PR 0 文件

- ADR 0024 的 §決定 1、3、4、5、8，ADR 0033 的 §決定 5，ADR 0018 的 §決定 5：各加一行「補充（2026-10-24，ADR 0035）：…」，寫被改成什麼。不刪原文（ADR 0024 的既有補充是同樣寫法）。
- `milestones.md`：
  - U 段寫範圍與 PR 數；
  - 「舊版頁面對照」表的佇列、播放頁兩列改成 ADR 0035；
  - 順序改成 U → macOS → iOS → M6（擁有者 2026-10-24）：M6 的依賴改成 iOS，macOS 依賴 U，iOS 依賴 macOS，並寫明原因；Linux 不變。

### PR 1 Mac 開發環境

- 問題（2026-10-24 實測）：Mac 上 `flutter test` 有 995 項失敗。
  - 插件執行環境：QuickJS 只有 Windows／Linux 的原生庫，同一個檔案裡後面的測試也被連帶拖垮，`debug_plugin_dev_test.dart` 會卡死。
  - `libisar.dylib` 不在。
  - `windows_identity_test` 要 cmake。
  - `apple_identity_test` 被 CocoaPods 改過的 `project.pbxproj` 弄紅。
- 做法：在 OrbStack 建一台 amd64 Ubuntu（和 CI 的 runner 同架構，擁有者已選 OrbStack 當 Linux 機），裝和 CI 同版的 Flutter 與套件，在共用的 repo 路徑跑完整的 `flutter test`。
  - Mac 本機只跑不碰插件執行環境的測試檔。
  - 寫進 `app/AGENTS.md` § 驗證，含 Pods 改動的處理：跑 `apple_identity_test` 前還原 `ios/`、`macos/` 的工具改動，或改跑 OrbStack。
- 做不到（例如 Rosetta 下 flutter_tester 不穩）就回報，改成「Mac 只跑改到的檔，完整套件看 CI」，同樣寫進 AGENTS.md。

### PR 2 主題與外觀

- `theme_presets.dart`（9 色）、`buildAppTheme(seed, fontFamily)`、舊版元件主題。
- 平台層 `fontChoices`：Windows、Android 兩份；Apple 平台宣告空清單。
- `appearance_settings` 加 `seed_color`、`font_family`，要做 migration 並存快照；外觀頁有主題模式、9 色、自訂色、字型、語言。
- 舊資料：`primaryColor`、`fontFamily` 改成會匯入（`legacy_settings_converter.dart`），`UnimportedSetting` 刪掉這兩項。
- 測試：`app_theme_test`（種子、字型）、外觀頁 widget 與 guideline、migration 三種、轉換測試（含不在清單的字型）。

### PR 3 導覽六項與佇列頁

- `ShellDestination.queue`；佇列頁沿用 `QueueView` 的列表，先不改頂部與每列（PR 8 才改）；手機整頁。
- Ctrl+Q 改成切到佇列目的地；播放頁拿掉「佇列」入口與分頁中的佇列（分頁整個在 PR 7 拿掉）。
- 測試：`app_shell_test` 改成六項，巢狀導覽、返回鍵、焦點區照改；`queue_view_test` 的底部面板改佇列頁。

### PR 4 匯入進度與取消

- `ImportProgress {count, total?, expectedTotal?, currentTitle?}`；`ImportCancel` 接 `RefreshTrigger.isCurrent`。
- 新匯入取消就整張刪掉（不論寫了幾頁）；既有歌單的重新匯入取消照 `partial` 處理（`design.md` §8，2026-10-25 擁有者決定）。
- 網址匯入對話框、帳號匯入全頁（新 `account_import_page.dart`）、刷新的卡片轉圈與詳情頁計數、外部匯入的目前曲名。
- 測試：importer 的單元測試，包含 n／M 的來源優先序、兩種取消、`partial`；對話框與全頁的 widget 與 guideline。實機以測試插件的長歌單驗。測試插件沒有長歌單 fixture 時，在 `test/fixtures/plugins/test_plugin/` 加一個（例如 `long-1200`），不連網。

### PR 5 舊版側欄與置中 AppBar

- `LegacySideRail`（72／256）、`PageAppBar`；`layout_state` 加 `rail_expanded`（要做 migration）；舊資料 `railExpanded` 改成會匯入。`player_tab` 留到 PR 7 拿掉分頁時再刪（播放頁到那時都還在用它）。
- 每頁的頁頂換成 `PageAppBar`，多選時的選取列行為不變。

### PR 6 播放列與面板

- 播放列移到外殼最外層，橫跨整個寬度；`ThinProgressBar`；三段控制不變。
- 面板沒有曲目時不顯示；加「下一首」、加入歌單鈕。
- golden：播放列三張、面板兩張重產。

### PR 7 播放頁

- 寬（M7 前單欄）、窄、矮三種版面；控制區照舊版；頂列（加入歌單、音量、輸出裝置、資訊、⋯）；曲目詳細面板；上滑轉場；封面圓角與陰影。
- 刪 `_PlayerTabs`、`glass_panel.dart`、extraLarge 三欄，以及 `layout_state.player_tab`（migration）。
- golden 換成寬、窄、矮三張；`player_page_test` 的 tabs、glass 刪除。

### PR 8 佇列

- `QueueModel.shuffleEntries`、`PlaybackController.shuffleQueue`。測試：目前這首在第一位、Mix 時擋下、隨機開著時重建一輪、持久化。
- 頂部（跳頂／底、橫幅、Mix 標題、打亂、清空確認）、空佇列引導、Mix 續取轉圈、每列「×」、`NowPlayingOverlay`、列高 72。

### PR 9 歷史

- `play_history_repository.dart` 的 `stats`、帶條件的 `page`、`deleteAllForTrack`、`deleteMany`；需要的索引走 migration。
- 統計卡、篩選列、日曆、搜尋、排序、時間軸標頭與折疊、每列時長與音源圖示、刪除此曲所有紀錄、多選刪除、載入與重試。

### PR 10 曲目清單共用

- `currentTrackKeyProvider` 與標示：搜尋、排行、探索、歌單詳情、分 P。
- 時長固定欄寬；多選加「下一首播放」與「取消全選」；搜尋捲到底自動載入。
- U 新增的數量字串（佇列、歷史、匯入進度等）改用 slang 的複數語法（ADR 0024 §決定 6）：PR 3–9 為了避開複數寫成「1 songs」「1 plays」「1 in queue」這類英文；以 `translations_test` 或新測試守住 en 的單數。

### PR 11 搜尋歷史

- `search_history` 表與 repository，含 migration、快照與備份歸類；搜尋框的歷史清單；舊資料的搜尋歷史改成會匯入。

### PR 12 首頁、電台、探索、狀態元件

- 首頁卡片底色、箭頭與漸層、滑鼠拖曳、卡片選單、「建立歌單」；電台網格與開播優先、排序模式；探索下拉重新整理。
- `EmptyState` 的 error 與 compact 樣式、`LoadingState`；直播間列的未開播樣式。

### PR 13 音樂庫與歌單詳情

- 全寬度格狀、來源圖示、連結圖示、載入與重試；280dp 頂圖、總時長、來源徽章。
- 從歌曲封面選；加入歌單的資訊卡，手機用底部面板；`showDestructiveConfirm` 換掉現有的刪除確認，刪除項目上色；網址匯入的來源圖示；帳號歌單全選與底部動作鈕。

### PR 14 設定

- 分組列摘要（例：主題：深色）、音質說明。

### PR 15 Windows 標題列與修飾鍵

- 先用 context7 查 `window_manager` 現況再選版本。
- 平台層 `window_chrome` 與 `shortcutModifier`；`WindowTitleBar`；播放頁頂端的拖曳區。
- 快捷鍵改讀修飾鍵；Apple 平台用 ⌘，開佇列用 ⌥⌘U。測試以假的平台能力跑兩組。
- Ctrl+Q 現在是導覽類（切到佇列目的地），決定要不要像 Ctrl+F、Ctrl+, 一樣搬進 `navigationShortcuts`，在輸入框內也有效（PR 3 審查提出）。
- PR 7 審查留下：Ctrl+L 在 M7 之前不做事（ADR 0035 §決定 7），外殼的對應要拿掉。
- PR 7 審查留下（改版前就有）：播放頁開著時視窗跨過外殼斷點，外殼重建巢狀 Navigator 會把焦點搶進被蓋住的內容區，播放頁之後收不到 Esc、F6。先寫會紅的測試再修 `app_shell.dart`。
- PR 7 審查留下：寬版開著曲目詳細面板時，Android 返回鍵直接關整頁（Esc 是先關面板）。照 `app/AGENTS.md` 的 PopScope 規則評估要不要讓返回鍵也先關面板。
- iOS 的 `CupertinoPageTransitionsBuilder` 與安全區域。用 `TargetPlatform.iOS` 的 widget 測試驗，實機留給 iOS 平台任務。
- Windows 實機：自繪標題列的拖曳、雙擊最大化、三顆鈕；dev 與 prod 同時開時各自單一實例。

### PR 16 宿主 API

- FMP：`sourceDtoShapes` 加 `viewCount`、`TrackDetail.webUrl`；解析測試；曲目列與排行顯示播放數；面板與詳細可點開原網頁。
- 直播間的分區標籤（B-27，PR 12 留下）：`LiveRoom` 加選填的 `area`，直播間列有值時顯示。動手前先和擁有者確認，並在 ADR 0035 加一行補充。
- fmp-plugins（`1morr/fmp-plugins`）：三個插件有值就填，契約 fixture 重錄。只錄不需要登入的案例（`app/AGENTS.md` § 驗證）。
- 兩個 repo 的合併順序：先 FMP（選填欄位，舊插件照常），再 fmp-plugins。

### PR 17 全部音源搜尋

- `AllSourcesSearch`（同時最多 3 個）、分組結果、各自的游標與錯誤；來源 chip「全部」排第一並預設。
- 測試：兩個假插件，一個成功、一個失敗；各自的分頁。

### PR 18 驗收

- 兩平台照 `prd.md` 的驗收條件走完整流程；以 1000 首以上的歌單驗匯入進度與取消（測試插件的長歌單）。
- `research/u-acceptance.md`、`milestones.md` 勾選；擁有者以 dev 版試用後認可才算完成。

## 回退點

- 每個 PR 獨立可 revert。
- 有 migration 的 PR（2、5、9、11）revert 後，新欄位留在 dev 資料庫，舊程式碼不讀它，不影響使用。要乾淨就 `pm clear com.personal.fmp.dev`，或刪 Windows 的 `userdata-dev`（先備份）。
- PR 16 的 fmp-plugins 改動與 FMP 解耦：欄位是選填。

## 開工前

- 擁有者核可這份規劃摘要。
- PR 0 合併後再 `task.py start`。
