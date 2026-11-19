# 16b: macOS 原生測試偶發崩潰（Impeller 空指標）

Status: ready-for-agent
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

- [ ] 修之前的 repro：連跑 N 次的紅的比例寫在 Comments；根因寫在 Comments。
- [ ] 修之後同一個 repro 連跑至少 20 次全綠。
- [ ] 若是產品會走到的路：macOS 實跑那個操作，讀回畫面、沒崩潰。
- [ ] 票 15 那次「沒連上」分清是不是同一件事；若是測試產物過期，`check.dart` 的原生測試步驟能自己避免（或 development.md 寫清楚手動重跑的正確指令）。
- [ ] 全部檢查綠燈（`dart run tool/check.dart --skip-windows`，winpc 恢復前）。

## Comments
