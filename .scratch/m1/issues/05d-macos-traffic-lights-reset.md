# 05d: macOS 紅綠燈跑回系統原位、壓到側欄頂邊

Status: done
Blocked by: None
讀: `docs/design/DESIGN.md` §5.2（側欄、細欄的 macOS 紅綠燈）；`docs/design/shell.html`；票 05 的 Comments（紅綠燈那幾行）；`docs/development.md`〈macOS〉的紅綠燈檢查方法；事實 M12；spec〈共同規則〉

2026-11-17 協調者插票（擁有者同意）：擁有者在票 07 實跑時看到 macOS 的紅綠燈貼著側欄頂邊、壓到圓角，像停在系統原位，沒有排到稿上的燈位（離視窗左上 (21,22)，也就是側欄頂邊往下 14）。票 05 與 05b 收尾的 macOS 截圖是對的，所以是某些情況下才發生。`app/macos/Runner/MainFlutterWindow.swift` 只在 `awakeFromNib`、`didResize`、`didExitFullScreen` 重排紅綠燈；系統在其他時機（視窗變成 key／main、失去焦點、切深淺色、改標題、顯示時……）可能把按鈕放回原位。修復票的驗收包含回頭補勾被它卡住的票：沒有。

協調者實測（2026-11-17，票 07 分支建的 Debug 版，視窗 800×600 啟動、不拉大小）：一啟動紅綠燈就在系統原位（第一顆中心約 (16,16)，壓在細欄頂邊上），失去焦點時一樣；用 System Events 把視窗改成 820×600 後立刻排到燈位。所以至少「啟動後沒排到」這條必現。票 05、05b 的截圖都是先把視窗拉到指定大小再拍，`didResize` 剛好把它排好，蓋掉了這個問題；`docs/development.md`〈macOS〉的檢查方法（先拉到 1280×800、960×720 再截圖）也一樣抓不到，要一起改成「啟動後不動視窗先截一張」。

## What to build

先寫出失效條件：找出紅綠燈會跑回原位的情況，做成能重現的 repro（例如腳本開 App、做某個動作、讀三顆按鈕在視窗裡的位置），修之前會紅。懷疑對象至少查上面列的系統事件，以及 App 剛啟動、第一幀畫完、從 Dock 叫回、在別的 App 之間切換。查成熟做法（Electron 的 `trafficLightPosition`、其他自訂紅綠燈位置的 macOS App）怎麼保證按鈕不被系統放回去，說明採用了誰的做法。

- 修根因，不靠計時器反覆重排。
- 查到的系統行為補成事實；`docs/development.md`〈macOS〉的檢查方法照實改。
- Windows、iOS、Android 不受影響。

## 驗收

- [x] 有 repro，修之前紅、修之後綠；根因寫在 Comments（或寫明為什麼查不到）。
- [x] 啟動後不動視窗、失去與取回焦點、切深淺色、縮放、全螢幕進出、寬級與細欄兩種寬度下，紅綠燈都在燈位；截圖和 `shell.html` 對過（深淺色）。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments

根因：Flutter 的 `FlutterAppDelegate.applicationWillFinishLaunching:` 在 `awakeFromNib` 之後把主視窗標題設成 App 名稱；`setTitle` 讓 `NSThemeFrame` 跑 `_tileTitlebarAndRedisplay:`，它的 `_updateTitlebarContainerViewFrameIfNecessary` 與 `_updateButtonPositions` 把標題列容器與三顆按鈕放回系統原位 (9,9)。舊碼只在 `awakeFromNib`、縮放、離開全螢幕時排，所以一啟動就在原位，直到第一次縮放。切深淺色也會重排（容器縮回 32 高、按鈕跑到 y=-4）。查法：對容器與按鈕打開 frame 變動通知，在通知裡印呼叫堆疊。事實 M13。
做法：不照 Electron 一個個事件重排（它在 become／resign key 與 main、縮放、改標題、切主題、離開全螢幕時各排一次），改成看著容器與三顆按鈕的 frame，系統一移動就排回去，任何走到 `_tileTitlebarAndRedisplay:` 的事件都涵蓋。通知是系統移動當下同步發的，這時設正在移動的那顆會被 `_NSThemeWidget setFrameOrigin:ignoreRentry:` 的重入保護吃掉，所以用 `RunLoop.main.perform`（common modes）等這一輪排完再排，沒用計時器。燈位由 Dart 決定：`lib/platform/traffic_lights.dart` 的 `TrafficLightsArea` 包住側欄與細欄頂端那一列，量它在視窗裡的框，經 `fmp/window` 的 `setTrafficLights` 送出照稿的位置與框的左右緣；原生端照稿放，照稿會比在框裡置中還靠右時改成置中。收到第一個燈位之前三顆藏著，不在原位閃。燈位的提供方是掛在 App 根的 `TrafficLights`：每一幀結束時沒有看得到的 `TrafficLightsArea`（沒有側欄或細欄、或被不透明的頁蓋住）就送 null，原生端把三顆放回第一次排之前量下的系統原位並顯示；同一幀內側欄換細欄不會先送 null。
repro：`app/macos/RunnerTests/RunnerTests.swift`，XCTest 跑在 App 裡讀真的視窗（順手修了 `TEST_HOST`，原本指向不存在的 `fmp.app`）。六條：啟動後在細欄內框裡、寬級照稿 (24,22) 且在側欄內框裡、從寬級換回細欄後在細欄內框裡、改標題後、切深淺色後、收到「沒有燈位」時三顆看得到且在系統原位 (9,9)。開工時的 `MainFlutterWindow.swift` 上前五條全紅；第一版修正（兩種寬度都放 x=14）上只有寬級照稿那條紅；原生端忽略 null 時最後一條紅（燈留在 (14,22)）；最終版全綠。Dart 端 `test/ui/app_shell_test.dart` 加四條：macOS 寬級送 {x:24, y:22, minX:16, maxX:248}、細欄送 {x:21, y:22, minX:14, maxX:74}、換寬度會重送、Windows 不送；`test/platform/traffic_lights_test.dart` 五條：沒有燈位的畫面送 null、撤掉最後一個燈位送 null、同一幀內換燈位不送 null、被不透明頁蓋住送 null 且回來重送、其他平台不送。
實跑（macOS 27，Debug 版，System Events 讀 AX 位置；AX 的框比按鈕外擴 1pt，原位讀到 (8,8)）：啟動後不動視窗 800×600、切到 Finder 再切回、切系統深淺色、Window 選單的縮放（2560 寬）與還原、最小化後從 Dock 還原、進出全螢幕、1280×800、960×720，細欄都是 (13,21)、寬級都是 (23,21)；閒置 CPU 1.0%，沒有一直重排。暫時拿掉離開全螢幕的監聽後進出全螢幕兩次照樣回到燈位，所以刪掉它。截圖：寬級 1280×800 與細欄 800×600、960×720，深淺色各一，和 `shell.html` 桌面側欄與細欄的稿（深淺色）並排：寬級燈位對得上；細欄三顆在框內置中，比稿上的燈大、位置左移 7。系統外觀切完還原成深色（讀回確認）。
閘門：`dart run tool/check.dart` 完整版在 d681f5ed 跑，`native tests macos` 與四平台 integration_test 都綠，只有 `build windows` 紅：fjs 的 Rust 依賴 `clang-sys` 編譯失敗（`could not compile clang-sys`、`MSB8066`）。這次沒碰 Windows 或 fjs，同一輪後面三個 Windows integration_test 都過；持鎖重跑 `build.ps1 -Mode debug` 通過（`exit build=0`、`=== done`），歸為 docs/development.md〈其他已知怪癖〉的 `winpc` 不穩。
code-review 未處理的發現：
- `xcodebuild` 那串參數在 `full_gate.dart`、它的測試與 development.md 各寫一次：保留，測試裡的是獨立的預期值。
- 對未公開的 `NSTitlebarContainerView`、`_NSThemeWidget` 打開 `postsFrameChangedNotifications` 且不還原：保留，依賴未公開視圖結構的風險記在事實 M12、M13，升級 macOS 照 development.md〈macOS〉重驗。
- 拖拉縮放時會不會閃一幀原位沒錄影確認：`RunLoop.perform` 的區塊在同一輪 run loop 畫面提交之前執行，靜態截圖與 AX 讀值抓不到閃爍。
- 燈位要等 Dart 送來才露出按鈕：沒有側欄或細欄的畫面會送「沒有燈位」，但 Dart 啟動就崩、一幀都沒畫出來時看不到紅綠燈（協調者同意記成未處理）。
- 真的切換 App 焦點只在實跑驗：xcodebuild 開的 App 不在前景、拿不到 key；直接呼叫 `becomeKey` 這類方法不會觸發重排，修前就綠，那條測試刪了。
Session 紀錄：2026-11-17 找到紅綠燈跑回原位的根因（Flutter 啟動時設標題觸發標題列重排），改成看著按鈕 frame 排回去、燈位由 Dart 依版面告訴原生端，XCTest 進完整閘門
Session 紀錄：2026-11-17 協調者要求不能有畫面讓紅綠燈永遠藏著：加 `TrafficLights` 提供者，沒有側欄或細欄時送「沒有燈位」，原生端回系統原位顯示；quick 閘門與 macOS XCTest 綠
決定：修法是看著標題列容器與按鈕的 frame 變動，被系統移走就在同一輪 run loop 排回去，不照 Electron 逐個事件重排（Agent 定）
決定：repro 寫成 `macos/RunnerTests` 的 XCTest 並加進完整閘門：鎖外 `build-for-testing`、持鎖 `test-without-building`，共用 `build/macos`（Agent 定）
決定：ARCHITECTURE〈測試策略〉加一行：原生程式碼裡 Dart 看不到的行為用該平台的原生測試，macOS 是 `RunnerTests`（使用者同意）
決定：燈位由 Dart 的 `TrafficLightsArea` 量出側欄或細欄頂端那一列，經 `fmp/window` 告訴原生端，Swift 不重抄斷點（Agent 定）
決定：寬級照稿 (24,22)；細欄的原生按鈕（14pt、間距 23）比稿上的燈（11px、間距 6）大，照稿 x=21 會凸出細欄 1pt，改成在細欄內框置中 x=14，比稿左移 7（Agent 定）
決定：收到第一個燈位之前三顆按鈕藏著，不在系統原位閃一下（Agent 定）
決定：刪掉離開全螢幕的監聽，frame 監看已涵蓋；刪掉修前就綠的 key／main 測試（Agent 定）
決定：燈位的提供方 `TrafficLights` 掛在 App 根，沒有看得到的側欄或細欄時明確送「沒有燈位」，原生端把三顆以系統原位顯示，畫面不必各自記得送（Agent 定）
決定：播放頁疊在原畫面上時紅綠燈留在側欄位置，這張票不修，留給票 16（播放頁）；協調者已在 main 的票 16 驗收加一條（faf33d58）（Agent 定）
變更：Fixed｜外觀｜macOS 的紅綠燈不再一啟動、改標題或切深淺色就跑回視窗角落、壓到側欄邊框；寬版在側欄照稿的位置，細欄裡三顆在框內置中
