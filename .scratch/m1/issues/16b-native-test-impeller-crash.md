# 16b: macOS 原生測試偶發崩潰（Impeller 空指標）

Status: done
Blocked by: None
讀: `docs/development.md`〈開發環境與閘門〉（原生測試 `native tests macos`）、〈平台〉的 macOS 一節；票 05d（紅綠燈與 `TrafficLights`）、票 15、16 的 Comments（native tests 那幾行）；`app/macos/RunnerTests/`；spec〈共同規則〉

2026-11-19 協調者插票（擁有者定）：票 16 的完整閘門發現 `TrafficLightsTests.testLightsShowInTheSystemSpotWithoutASidebarOrRail()` 偶發紅。測試用的 host App（FMP Dev）跑這一項時崩潰，xcresult 寫 `Crash: FMP Dev`、耗時 0.000 秒；五份 `.ips` 堆疊相同：`EXC_BAD_ACCESS` 讀位址 0x0，執行緒 `io.flutter.raster`，最上層 `impeller::Canvas::SetupRenderPass()`，往下 `impeller::RenderToTarget`、`EmbedderExternalViewEmbedder::SubmitFlutterView`、`Rasterizer::DrawToSurfaceUnsafe`。main（ff6fdc77）與票 16 分支交替各跑 10 次：main 紅 3、分支紅 2，所以是 main 既有的，和播放頁無關。票 15 那次「第一個案例 0.000 秒失敗、test runner 沒連上」可能是另一件事（integration_test 重建 App 讓測試產物過期），要一起分清。

修復票的驗收包含回頭補勾被它卡住的票：沒有（票 16 已照擁有者決定收）。

## What to build

先寫出失效條件，不要先改：

- 穩定的 repro：用閘門同樣的指令（先 `xcodebuild build-for-testing`）把這一項連跑 N 次，量出紅的比例；能縮到單一案例更好。
- 分清是產品還是測試的問題：這一項做了什麼（拆掉側欄與細欄、換掉 Flutter 視圖或視窗內容？）時 raster 執行緒還在畫；App 平常操作會不會走到同一條路（例如視窗縮小到沒有側欄的寬度、播放頁蓋住側欄）。會的話是產品的崩潰，用實跑驗。
- 查根因並修。若證實是 Flutter／Impeller 本身的 bug、只能繞開，寫明繞法、Flutter 版本與上游 issue（有的話），繞法要有理由，不是只加等待或重試。
- 查到的引擎行為寫成事實（`docs/research/facts-*.md`，附來源）。

## 驗收

- [x] 修之前的 repro：連跑 N 次的紅的比例寫在 Comments；根因寫在 Comments。
- [x] 修之後同一個 repro 連跑至少 20 次全綠。
- [x] 若是產品會走到的路：macOS 實跑那個操作，讀回畫面、沒崩潰。
- [x] 票 15 那次「沒連上」分清是不是同一件事；若是測試產物過期，`check.dart` 的原生測試步驟能自己避免（或 development.md 寫清楚手動重跑的正確指令）。
- [x] 全部檢查綠燈（`dart run tool/check.dart --skip-windows`，winpc 恢復前）。

## Comments

修前 repro：閘門同樣的指令（先 `build-for-testing`，持鎖 `test-without-building -only-testing:RunnerTests`）閒置連跑 20 次 0 紅，CPU 全核滿載 10 次 1 紅；縮到單一案例：`RunnerTests` 裡不等畫面、連續把視窗在 960×720 與 1280×800 間來回，400 次 5/5 紅、20 次 3/5、2 次 0/5，每次間隔 100 ms 則 20 次 0/5。紅的都是 `Crash: FMP Dev`、案例 0.000 秒；當天 19 份 `.ips` 的主執行緒都在 `TrafficLightsTests.setUp()` 的 `resize(to:)` → `ResizeSynchronizer.beginResize`（同步縮放、等 raster 執行緒畫新尺寸），所以觸發點是縮放，不是被記到的那一項。
根因：Flutter 3.47.5 引擎的 `FlutterBackBufferCache.removeSurfaceForSize:` 在尺寸 A→B→A 快速來回、A 的畫布還被 WindowServer 佔著時，交出 B 尺寸的畫布；Impeller 包它時尺寸不合，默默丟掉顏色附件，`Canvas::SetupRenderPass` 讀到空指標（反組譯崩點是 `color0.texture` 的 `ldr x8, [x0]`；App 的 stderr 有 `texture and its descriptor disagree about its size`）。上游 flutter/flutter#185394（開著）、修正 PR #192522（已核准未合併，3.50 不含）。事實 M17。成串出現是因為要 WindowServer 還佔著舊畫布，負載高時才容易碰到（票 16 那時協調者同時在建置別的 worktree）。
產品會走到：不經 XCTest、用 System Events 連續改正式 App 的視窗大小，修前第 11 次 `Segmentation fault: 11`（同樣兩行 Impeller log）；修後 200 次 App 活著，截圖是 960×720 的細欄版面、紅綠燈在細欄裡、首頁畫得完整。
修後：完整原生套件閒置 20/20、CPU 滿載 20/20 綠；新的 `WindowResizeTests` 修前 3/6 紅、修後 6/6 綠；把 `FlutterSurface.size` 的檢查改成錯的屬性名（突變，未 commit）時「裝上了」那項以斷言紅。
票 15 的「沒連上」是同一件事，不是測試產物過期：票 15 收票（12:22）前 11:56 有一份同堆疊的 `.ips`（XCTest 中、啟動後 4.9 秒、主執行緒在 setUp 的縮放裡）；XCTest 把崩掉的案例記成 0.000 秒，再換新行程跑剩下的案例，看起來像沒連上。`check.dart` 不改，development.md〈macOS〉寫了怎麼認、去哪讀堆疊、ReportCrash 限流時怎麼看 stderr。
code-review 的發現都已處理（`size` 屬性的檢查、測試共用 `AppWindow`、註解改成實測數字、M17 補版本與 1000 次的數字）；剩下的限制：閃退那項約一半機率抓得到，補丁失效靠「裝上了」那項確定地紅。
Session 紀錄：2026-11-19 查到 macOS 原生測試偶發崩潰是 Flutter 引擎在視窗快速來回縮放時拿錯尺寸的畫布（事實 M17），App 啟動時補尺寸檢查並加 `WindowResizeTests`
決定：繞法用 App 內補尺寸檢查（`BackBufferCacheSizeCheck` 換掉引擎內部方法），不關 Impeller（玻璃會失去折射）、不只改測試（正式 App 照樣閃退）；升 Flutter 時查上游收錄了沒，收錄後刪（使用者同意）
決定：檢查補在取出端（`removeSurfaceForSize:` 拿到尺寸不對就回 nil 讓引擎新建），不照上游 PR 補在 `returnSurfaces:`：取出端不必知道快取現在是哪個尺寸，實測 10/10 不崩（Agent 定）
決定：回歸測試兩項：補丁裝上了沒（類別、方法或 `size` 屬性找不到就紅，確定性）與連續來回 1000 次不閃退（Agent 定）
決定：票 15 的「沒連上」判為同一個崩潰，`check.dart` 不改，只在 development.md 寫怎麼認（Agent 定）
決定：兩組原生測試共用的視窗工具抽成檔內的 `AppWindow`（Agent 定）
變更：Fixed｜外殼｜macOS 快速來回拉大縮小視窗時 App 不再閃退
