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

2026-10-28 在擁有者的 Windows 11 電腦（150% 縮放）驗過，逐項結果見 `research/u-acceptance.md` § Windows 實機。驗到時發現播放頁的背景模糊蓋住自繪標題列，已在 #345 修正。

- [x] PR 2：6 個 Windows 字型都能切換並套用；主題模式與主題色。
- [x] PR 5：側欄展開與收合；搜尋頁多選時 Ctrl+F 退出多選並聚焦搜尋框。
- [x] PR 6：細線 hover 變粗、把手與時間泡泡；播放列在側欄下方；面板只在有曲目時出現；加入歌單對話框；840 邊界。
- [x] PR 12：卡片列 hover 的漸層與箭頭、捲到頭收起、移出消失；右鍵開歌單卡選單。
- [x] PR 13：格狀欄數、卡片 hover、拖封面角把手排序。
- [x] PR 15：自繪標題列（淺深色、150%）、三邊與四角縮放（頂邊不行）、拖曳與雙擊、視窗鈕與 Win 鍵、貼邊、Debug 頁與對話框與播放頁（#345 後）開著時標題列都在、tooltip、同一 flavor 單一實例、播放頁跨 600／840、Ctrl+Q／Ctrl+L、Alt+F4 與關閉鈕、SMTC 不殘留。
- [x] 根 route 焦點：播放頁開著時跨 600 後 Esc 仍有效；搜尋框跨 600 時文字保留。

第二輪（同日）補驗：重啟後記住側欄展開；細線在播放中是播放列第一個焦點（變粗、把手、時間泡泡、焦點框），拖曳中移出播放列仍跟著游標；卡片列滑鼠拖曳捲動、漸層下的卡片點得到；電台網格（開播在前）、電台卡 hover 與右鍵選單（電台頁與首頁）；歌單頂圖在一般與最大化寬度；對話框開著時拖曳標題列；Debug 頁跨 600 再拉回。

只剩要擁有者親自看的：

- [ ] 啟動時有沒有先閃一個空白或帶系統標題列的視窗。
- [ ] 側欄 hover 與展開、收合動畫的觀感。
- [ ] dev 與 prod 同時開各自單一實例（prod 與舊版共用 AppUserModelID 與單一實例，沒有在擁有者的電腦上跑）。

沒有驗、也不另外驗的：細線的 ←／→（一次 5 秒，測試曲只有 2 秒，看不出來；由 widget 測試守）。

## 偶發失敗的測試

完整套件在 Linux 負載下偶發、單獨跑都過；PR 18 之前一起收斂（先找出等待條件，改成等明確的事件）。
等待的寫法收進 `.trellis/spec/app/testing/index.md` § 等非同步進度。

- **已解決**：`test/data/cache/image_cache_manager_test.dart`「two plugins downloading the same URL at once keep separate staging files and separate entries」（PR 12 合併 main 後的一輪）。
  - 原因：`pumpUntil` 等請求到 adapter，上限 20 輪 `pumpEventQueue`；請求先經快取庫（drift 的背景 isolate）查索引、在檔案 I/O 的執行緒上建暫存檔。
    輪數只量主 isolate，量不到那邊。
  - 證據：不加負載時用到 1–11 輪（約 5ms）；VM 裡 44 條忙迴圈時到 58 輪。同樣負載下整個檔 6 次紅 1 次（同組的 `share one download`，`pump_until.dart` 的 `condition never became true`）。
  - 修法：`FakeHttpAdapter.received(n)` 等第 n 個請求送到；沒有事件可等的（暫存檔出現、flutter_cache_manager 不等的索引寫入）用 `pollUntil`，上限是實際時間。
    `cache_harness.dart` 的 `eventually`（50 輪）刪掉，改用它。修後同樣負載 8 次全綠。
- **已解決**：`test/ui/plugins/plugin_onboarding_test.dart` 在負載下紅（2026-10-27 重現；segfault 那一次另見下一項）。
  - 原因：`PluginPageHarness.settle` 只給約 180ms 實際時間，第二個插件在背景 isolate 建 QuickJS、載入還沒完，測試就斷言了。
    那個安裝留在假時間 zone 裡永遠不會接著跑，runtime 沒人釋放。
  - 證據：40 份副本同時跑、加 11 條忙迴圈：480 項紅 2 項，都是 `one confirmation lists every selected plugin…` 的 `Set:['plugin-a']`。
  - 修法：`PluginPageHarness.settleUntil` 等 App 的狀態：`_open` 等插件清單載入完，`_confirm` 等 `onboardingProvider` 的 `working` 變回 false。修後同樣條件 480 項全綠。
- **未解決**：`plugin_onboarding_test.dart` 的 flutter_tester segmentation fault（PR 15 合併 main 後的一輪）。原本的 log 沒留下。
  - 重現不出來：修之前的程式碼，每輪跑全部 QuickJS 測試檔、加 10 份 onboarding 副本、開 core dump。
    沒加負載 3 輪、加 11 條忙迴圈 3 輪，共約 8000 項，沒有當掉。加負載的 3 輪裡有 2 輪是上一項的斷言紅。
  - 排除的：
    - 結束時行程不是自己退出：flutter_tools 用 SIGKILL 收，-9 不報錯。所以當掉是在檔案還在跑的時候。
    - QuickJS 的 stack 檢查：isolate 換執行緒時，橋接層的 `jsEval`、`jsCall`、`jsExecutePendingJob` 每次都先呼叫 `JS_UpdateStackTop`（反組譯確認）。
    - `Shutdown` 之後：還沒回覆的宿主呼叫不會再完成（`_closed`），排著的 `_pump` 也先檢查 `_closed`。
  - 已知但沒證明是原因：`QuickJsRuntime2.close` 先 `jsFreeContext` 才釋放 Dart 端持有的 JS 值（flutter_js 0.8.7，第三方）。
    還有上一項：負載下測試結束時插件可能還在載入，載入完的 runtime 沒人 dispose，背景 isolate 留到行程結束。
- **未解決**：`test/ui/tracks/part_display_test.dart`「the player bar shows the composed title」卡住到逾時（PR 5 的一輪完整跑，log 沒留下）。
  - 重現不出來：
    - 目前的程式碼：40 份副本同時跑、加 22 條忙迴圈，240 項全過；整個檔在 44 條忙迴圈下跑 5 次也全過。
    - PR 5 當時的程式碼（`15a8ba0b`）：同樣 40 份，全過。
  - 排除的：這個案例全在假時間裡（記憶體資料庫、假插件、假後端），沒有要真的事件迴圈的等待。故意讓它在播放剛開始時失敗，也是乾淨地紅，不會卡住。
  - 順手修的：`ShellHarness.pumpApp` 的註解說先拆樹再關庫，實際上反過來。harness 自己建的記憶體庫是在拆樹的 tearDown 之後才登記，所以先跑。
    改成先取 override 再登記拆樹。現有的測試裡這個順序不會卡住，沒證明和這次卡住有關。

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
- 留給 macOS／iOS 平台任務：宣告 `appleShortcutModifier`；tooltip 字串的「Ctrl+」在 Apple 平台改成 ⌘。
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

- PR 15 審查留下（已完成）：根 route 開著時跨過外殼斷點焦點被搶走，`_keepPlayerFocus` 改成通用的 `_keepCoveringRouteFocus`，測試 `shell_focus_test.dart`。

### PR 18 驗收

- 兩平台照 `prd.md` 的驗收條件走完整流程；以 1000 首以上的歌單驗匯入進度與取消（測試插件的長歌單）。
- `research/u-acceptance.md`、`milestones.md` 勾選；擁有者以 dev 版試用後認可才算完成。

## 驗收後修正

- 觀察 1（`research/u-acceptance.md`）：914dp 橫向、側欄展開加面板時內容區只剩約 290dp，標題被截、觀看數被擠掉。
  規則（ADR 0035 §決定 2 的 2026-10-27 修訂）：內容區至少 `AppLayout.contentMinWidth`（360dp）。
  - 畫面：`railYieldsToPanel`（`now_playing_panel.dart`）為真時外殼把側欄畫成收合；記住的 `rail_expanded` 不改，面板關上或視窗變寬就展開回來。
  - 操作：這時按側欄的展開鈕一併收起面板（`LegacySideRail` 改由外殼傳 `expanded`、`onExpand`、`onCollapse`）。
  - 測試：`now_playing_panel_test.dart`（純函式）、`app_shell_test.dart`（914 與 1400 的整合）。

## 回退點

- 每個 PR 獨立可 revert。
- 有 migration 的 PR（2、5、9、11）revert 後，新欄位留在 dev 資料庫，舊程式碼不讀它，不影響使用。要乾淨就 `pm clear com.personal.fmp.dev`，或刪 Windows 的 `userdata-dev`（先備份）。
- PR 16 的 fmp-plugins 改動與 FMP 解耦：欄位是選填。

## 開工前

- 擁有者核可這份規劃摘要。
- PR 0 合併後再 `task.py start`。
