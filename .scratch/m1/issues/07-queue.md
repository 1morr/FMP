# 07: 佇列與佇列頁

Status: done
Blocked by: 02、06
讀: brief §6；`GLOSSARY.md`〈佇列〉；`docs/design/DESIGN.md` §6.1、§6.3；`docs/design/queue.html`；architecture〈依賴規則〉〈測試策略〉；spec〈共同規則〉

## What to build

有佇列：搜尋結果的選單可以「加入佇列」「下一首播放」，播完自動接下一首，迷你播放器、播放膠囊有上一首、下一首；佇列頁照稿列出播放順序，開啟時捲到正在播的那首，點標頭「佇列」捲回去，可以拖動排序、用 × 移除（移除正在播的那首時接著播下一首）、清空（要確認，清空後停止播放），空佇列照稿。

開工前（擁有者在場）：檢查 `winpc` 硬體（Windows 記憶體診斷要重開機），順便追 MSB8066 的根因（`docs/development.md`〈`winpc` 的 Dart 偶發當掉〉）；在四個平台親耳聽一次播放。結果記在 Comments。

佇列的規則是純 Dart，介面用 `mattpocock-skills:codebase-design` 設計，要能接 08 的隨機與循環、09 的臨時播放、10 的持久化；這張票只做不隨機、不循環。搜尋頁照稿在 14，這張票在佔位搜尋加上選單項目即可。

## 驗收

- [x] 開工前的硬體檢查與四平台親耳聽已做，結果在 Comments。
- [x] 佇列的規則有單元測試：加入、下一首播放、播完接下一首、上一首、下一首、拖動、移除正在播的那首、清空後停止。
- [x] 佇列頁的截圖和 `queue.html` 對得上（捲到正在播放、拖動、空佇列、清空確認、桌面右鍵）。
- [x] 四平台實跑：加入兩首、播完第一首自動接第二首，讀回佇列頁。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
開工前・`winpc` 硬體檢查（2026-11-17，擁有者在場）：重開前今天有兩次 Kernel-Power 41：03:29:46（BugcheckCode 0，沒有藍屏）與 13:24:41（BugcheckCode 59，P1 `0xc0000005`）；13:24:54 BugCheck `0x3B`（`0xc0000005`，`0xfffff800197b9f23`，`0xffffa1803f01e640`，0），minidump `111726-19359-01.dmp`。14 天內 10 次 Kernel-Power 41、9 次藍屏；WHEA 沒有紀錄；今天另有 8 次 `dartaotruntime.exe`（`0xc0000409`，位移 `0x332aa1`）、1 次 `gen_snapshot.exe`、`CL.exe`、`sppsvc.exe`、`powershell.exe`（clr.dll）存取違規。環境：i9-13900HX、BIOS KWCN54WW、microcode `0x12E`、SK Hynix DDR5-5600 16 GB ×2、VBS 開著、背景跑 Lenovo Legion Toolkit
開工前・minidump：用 cdb `!analyze -v` 讀 `C:\Windows\Minidump\` 的 5 個檔，每次落在不同模組：11-12 `0x20001` intelppm!HvRequestIdle（NMI 路徑）、11-13 `0x1E` nt!KeContextFromKframes（NMI 路徑）、11-14 `0x1E` WdFilter、11-15 `0xA` `IP_MISALIGNED_GenuineIntel.sys`、11-17 `0x3B` FLTMGR!FltpPerformPreCallbacksWorker（行程 sshd.exe）。沒有共同的驅動，指令指標錯位、NMI 中斷，像硬體不穩，不像某個驅動的 bug
開工前・記憶體診斷：擁有者同意後經 SSH `bcdedit /bootsequence {memdiag}`、`shutdown /r /t 60`；14:11 關機、14:36 開進 Windows（標準測試約 25 分鐘），擁有者 15:14 登入。`MemoryDiagnostics-Results` 事件沒有寫出（System 與它的 Debug 頻道都是 0 筆；手動執行 `ProcessMemoryDiagnosticEvents` 結束碼 0 也沒寫）。結果只留在 `HKLM\SYSTEM\CurrentControlSet\Control\MemoryDiagnostic` 的 `Results`：開始時間 2026-11-17 14:11:24，兩輪各 6 項測試，每項的錯誤數欄位都是 0（格式沒有官方文件，是 Agent 自己解讀的）
開工前・MSB8066 根因：還沒定位。記憶體標準測試沒找到錯誤、5 個 minidump 不共用驅動，剩下處理器（電壓、microcode）、BIOS 或 Legion Toolkit 的電源設定。可以再查：Lenovo 有沒有比 KWCN54WW 新、帶較新 microcode 的 BIOS；Legion Toolkit 有沒有降壓或超頻；需要時跑延伸記憶體測試或 CPU 壓力測試。閘門照 docs/development.md〈其他已知怪癖〉照實報紅、重跑
開工前・四平台親耳聽（2026-11-17）：每個平台由 Agent 啟動 App、搜尋「lofi」、播第一首（BV1G9sZ6UEQw），再問擁有者聽到的聲音
決定：macOS 有聲音、正常（使用者定）
決定：iOS 模擬器（iPhone 18 Pro）有聲音、正常（使用者定）
決定：Android 模擬器（Medium Phone）選「有聲音，正常」；其實有點雜音和斷續，但舊版在模擬器開發時也這樣、實機正常，所以算正常（使用者定）
決定：Windows（`winpc`）有聲音、正常（使用者定）
發現：macOS 點下到出聲約 18 秒，log 有 `Playback stalled: buffering for over 15000 ms`；屬 M0 留下的「macOS 點下到出聲慢」，交給失敗處理與預載的票
發現：iOS 模擬器的鍵盤是注音，`orca emulator type` 打不了英文；改用 `simctl pbcopy` 再長按欄位（`orca emulator gesture` 的 begin、end 兩點，end 加 `delayMs`）叫出「貼上」，`orca emulator type $'\n'` 送出
閘門：`dart run tool/check.dart` 完整版（98f83681）除了 Windows 都綠，含四平台的 `integration_test/queue_test.dart`；`build windows` 與 Windows 的 `queue_test` 紅在建置階段的 MSB8066（〈其他已知怪癖〉的 winpc Dart 當掉）。照 docs/development.md〈Windows〉持鎖重跑：`queue_test` `All tests passed`、`exit test=0`、有 `=== done`（那輪建置是 `exit codegen=1`）；再跑建置 `exit build=0`、有 `=== done`。每一步都在這份程式碼綠過
決定：開工前的硬體檢查與親耳聽在動工前、擁有者在場時先做（使用者定）
決定：winpc 經 SSH 排 Windows 記憶體診斷（標準）並重開機（使用者定）
四平台實跑（2026-11-17，真的 B 站，每平台搜一次「lofi」）：從選單加兩首（佇列空著時第一首直接開始播），按下一首切到第二首，讀回播放狀態與佇列頁
- macOS（1280×800 深色）：第二首「播放中 0:23 / 49:00」；佇列頁「已播放 1 首」、正在播的列、摺線「接下來 1 首」；右鍵選單（玻璃 `.gmenu`）三項；清空確認框；960×720 窄視窗的清空鈕在標題列、快速鍵提示在下一行；空佇列
- iOS 模擬器（iPhone 18 Pro 深色）：第二首「播放中 0:18」到 0:22；佇列頁「2 首 · 1 小時 48 分」、已播放 1 首、正在播的列有等化器
- Android 模擬器（Medium Phone 淺色、英文）：第二首「Playing 0:06」；佇列頁 1 played、Up Next；長按把手拖到正在播的上面變成「2 played」；清空確認框，確定後換成空佇列、迷你播放器收起
- Windows（winpc 1280×800 淺色）：第二首 0:07 到 0:15；佇列頁、快速鍵寫成 Alt↑ Alt↓ Enter；第一次建置撞到〈其他已知怪癖〉的 MSB8066，重跑通過
- 播完自動接下一首：B 站的曲太長，改用 `integration_test/queue_test.dart`（本機假 CDN 的 3 秒音檔）在四平台的真音訊後端跑，完整閘門涵蓋
截圖比對（和 `queue.html` 同狀態並排看過，截圖留在本機暫存目錄）：捲到正在播（手機、桌面）、拖動（Android 拖完的結果）、空佇列（手機、桌面）、清空確認（手機、桌面）、桌面右鍵
已知差異：頂列背後沒有 `.edge-top` 漸層；拖起來的列 × 沒有隱藏；拖動「進行中」的畫面工具截不到，只讀回拖完的結果；隨機、循環切換鈕與列末「循環關閉…」那行、臨時播放區塊等票 08、09
發現：`orca computer hotkey` 送 ⌥↓ 時 App 收不到 Alt（`HardwareKeyboard.isAltPressed` 是假），改用 `osascript` 的 System Events `key code 125 using option down` 就正常；鍵盤操作本身沒問題
發現：iOS 模擬器的鍵盤是注音，`orca emulator type` 打不了英文；改用 `simctl pbcopy`、長按欄位（`orca emulator gesture` 兩點、end 加 `delayMs`）叫出「貼上」，`orca emulator type $'\n'` 送出
code-review 未處理：選單貼邊往左、往上翻沒有測試；`'Delete'` 字面值寫在兩處，Alt 與 Enter 卻由 `WindowChrome` 給
code-review 未處理：判斷題的 smell 沒改：`queue_rows.dart` 塞了觸控列、表格列、摺線、空狀態等多種東西；佇列總時長算在 `queue_layout.dart` 而不在 `Queue`；`playNow` 的規則湊在控制器；`SkipButton(forward:)` 旗標參數；`density == Density.touch` 散在多處；`app_shell.dart` 兩處幾乎一樣的 `ShellTopBar`；依 `QueueLayout` 的 switch 三處
code-review 未處理：表格用 ⌥↑／⌥↓ 把選取的列移出畫面時，捲動不會跟著走
閘門（e6131bda，只改佇列規則與控制器，照協調者指示不整輪重跑）：quick 全綠；`integration_test/queue_test.dart` 在 macOS、iOS 模擬器、Android 模擬器 `All tests passed`；Windows 照 docs/development.md〈Windows〉持鎖同步、建置（`exit build=0`）、跑 `queue_test`（`exit test=0`、有 `=== done`）
Session 紀錄：2026-11-17 開工前檢查 winpc 硬體與四平台親耳聽；做佇列（domain 的 Queue、playback 的 QueueController）、佇列頁三種寬度、玻璃選單與確認框，四平台實跑真 B 站加兩首、下一首並讀回佇列頁
決定：測試接縫四層：domain 的 Queue、playback 的控制器、佇列頁 widget 測試、integration_test（協調者代答）（Agent 定）
決定：票 09 之前點搜尋結果一首＝插在正在播的後面並馬上播，佇列永遠含正在播的那首（協調者代答）（Agent 定）
決定：沒有目前曲目（佇列空，或 × 移除正在播的最後一首後）時加入才播新加的；有目前曲目（暫停、播完、重啟後還原）時不換、不自動播（協調者代答）（Agent 定）
決定：用 × 移除正在播的最後一首就停止播放、沒有目前曲目，剩下的都算播過，迷你播放器收起（協調者代答）（Agent 定）
決定：每平台另用真 B 站加兩首、按下一首、讀回播放狀態與佇列頁；播完接下一首交給 integration_test（協調者代答）（Agent 定）
決定：桌面右鍵照 DESIGN.md 的選單做玻璃 `.gmenu`（觸控、滑鼠兩種密度），不留 Material 選單（協調者代答）（Agent 定）
決定：佇列是 `domain/` 的不可變 `Queue`，位置帶 id、同首可排多次；`playback/` 的 `QueueController` 依目前那首叫播放（Agent 定）
決定：沒有上一首、下一首時鈕停用（40% 透明）；迷你播放器照稿只有下一首，播放膠囊有上一首與下一首（Agent 定）
決定：`Playback` 加 `stop()`（清空與移除最後一首用）；載入中收到後端的 completed 當成上一首遲到的狀態不收（Agent 定）
決定：`ShellInsets` 加 `ShellTopBar` 告訴頁面頂列的位置，右端已讓出詳情面板鈕與 Windows 視窗鈕（Agent 定）
決定：沒有接下來的曲目時不畫摺線；曲目時長全都未知時只寫「n 首」（Agent 定）
決定：按鈕、確認框、玻璃選單、等化器放 `ui/common/`；確認框照 `.alert` 不分密度圓角 26（Agent 定）
決定：搜尋頁的 ⋮ 與右鍵也用玻璃選單；手機照稿的底部 sheet 留給搜尋頁照稿的票（Agent 定）
決定：快速鍵符號由 `platform/` 的 `WindowChrome` 給（macOS ⌥、⏎，其他 Alt、Enter）（Agent 定）
決定：中文的複數規則（一律取 other）在 `buildRoot` 設定，App、測試與 integration_test 都經過它（Agent 定）
決定：表格刪掉選取的列後選取移到下一列；「移到下一首」對正在播或緊接在後的列停用（Agent 定）
變更：Added｜佇列｜搜尋結果的選單可以「下一首播放」「加入佇列」；沒有正在播的曲目時加入會直接開始播
變更：Added｜播放控制｜一首播完自動接下一首；迷你播放器有下一首鈕，播放膠囊有上一首、下一首
變更：Added｜佇列｜佇列頁照播放順序列出播過的、正在播的與接下來的，打開時捲到正在播的那首，點標題捲回
變更：Added｜佇列｜佇列頁可以拖動排序、用 × 移除（移除正在播的接著播下一首）、清空（要確認，清空後停止播放）；桌面有右鍵選單與鍵盤操作
變更：Changed｜搜尋｜點搜尋結果的一首會插在正在播的那首後面並馬上播
