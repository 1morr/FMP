# 05b: 實驗：玻璃三級的四平台可行性

**What to build:** 決定設計稿的玻璃元件在 Flutter 怎麼做，讓 M1 拆票時知道每個平台做得到哪一級。設計稿把玻璃分成三級（`docs/design/DESIGN.md` §1.4：折射、standard、minimal），和事實 K10 的定義不同；brief §17 的退路（只用 `BackdropFilter`）做不出折射級。這張票重驗 K10、在四平台實測候選做法，結論給擁有者確認後寫回 brief、plan 與 `DESIGN.md`。2026-11-11 D 定稿後補開（plan〈待決〉P5）。

讀：brief §2.3、§11、§15、§17〈玻璃的 Flutter 實作〉、事實 K10；`docs/design/DESIGN.md` §1（材質）、§5（外殼）、〈稿內不一致與實作注意〉第 1 項；plan §1.4、§2、〈待決〉P5；spec〈共同規則〉的實驗規則

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 實驗程式在 `scripts/experiments/` 底下，可重跑，附怎麼跑的說明；換版本時能重量。
- [x] 重驗事實 K10：`cupertino_ui` 是否已在 pub 發佈 Liquid Glass、社群玻璃套件的現況、四個平台各用哪個 renderer；更新 K10 的寫法、出處與查證日期。
- [x] 候選至少包括：已發佈的官方或社群玻璃套件、用核心 Flutter 的 `BackdropFilter` 自己做。每個候選在四平台實測做得到設計稿的哪一級（折射、模糊加飽和、實心退路），結果做成表，含版本號與平台；以讀回的截圖為準。
- [x] 玻璃元件浮在 1000 首以上的列表上方捲動時，用 profile build 量幀時間，對照 brief §15「長列表捲動不掉幀」；量出哪一級可以留在捲動中的列表上方。
- [x] 查四個平台的「降低透明度」系統設定讀不讀得到（`DESIGN.md` §1.4 的 minimal 退路）。
- [x] 結論草稿（用哪個做法、每個平台的最高級、捲動時怎麼降級、已知限制）先給擁有者確認；確認後寫進 brief §18（事實）、brief §17 移除〈玻璃的 Flutter 實作〉並把決定寫進 §11、plan §1.4 與〈待決〉P5 刪除、`DESIGN.md` §1.4、〈9〉與〈稿內不一致與實作注意〉的對應條目改成實測結果。
- [x] 如果沒有一個候選在 iOS、Android 做得出折射級：停下來回報，不自己改設計稿。

## Comments

- 結論（擁有者 2026-11-12 經 AskUserQuestion 確認，看過 `scripts/experiments/glass/results/` 的四平台對照圖後選定）：玻璃元件用 `liquid_glass_easy` 5.2.0（折射級 `LiquidGlassLens`、standard 用 lite glass、minimal 自己畫實心）；捲動中的列表上方不降級，但元件要能在執行期切換級數；iOS、macOS、Windows 跟系統的「降低透明度」退到 minimal，Android 沒有這個系統設定、不提供。我推薦的是自己用 `BackdropFilter` + `ImageFilter.shader` 做，擁有者選了套件；自己做的原型（`own-refract`）留在 probe，寫進 plan §7 當退路。
- 實測摘要：四平台都是 Impeller（Flutter 3.47 起 macOS、Windows 也預設），`liquid_glass_easy` lens 與自己做的折射在 iOS 模擬器、Android 模擬器、macOS、Windows 都看得到折射；`liquid_glass_widgets` 1.17.2 在 Windows 照 README 初始化後整個 App 白屏（事實 K20）。捲動：macOS、Windows（profile，160 Hz）折射級浮在 1500 列的列表上方 0 幀超過 16.7 ms。「降低透明度」：Flutter 讀不到，iOS、macOS、Windows 用原生 API 實測開與關都讀得到（事實 K21）。細節與表在 `scripts/experiments/glass/README.md`。
- 驗收第 4 條只部分達成：手機的幀時間量不到。iOS 模擬器 Flutter 不能建 profile（debug 的數字是 Mac GPU 畫的）；Android 模擬器的 GPU 是 SwiftShader、只有 1 核，連實心畫面的 raster 中位數都約 24 ms（plan §2 已記）。擁有者選了「不降級、元件可切級」，里程碑量效能時再看；手機要用實機或有 GPU 加速的模擬器量（plan §7）。
- 文件：brief 事實 K10 改寫，新增 K19–K22；brief §11 寫入決定、§17 的玻璃條刪除；plan §1.4 加 `liquid_glass_easy`、§2 記 Android 模擬器的軟體 GPU、§7 加風險、〈待決〉P5 刪除；`DESIGN.md` §1.4、§5.2、〈9〉、〈稿內不一致與實作注意〉第 1 項與 `PRODUCT.md`、`system.html`、`shell.html`、`index.html`、`player.html` 裡「Windows 最高到標準」的說法都改成實測結果。`docs/design/audit-2026-11-11.md` 是快照，沒改。
- 實驗中的意外：
  - 自己做的折射照 `ImageFilter.shader` 的 dartdoc 在 GLES 翻 Y 軸，Android 模擬器上顏色整個錯；拿掉翻轉才對（事實 K22），Android 重跑了一輪。
  - Windows 第一輪截圖全白：先懷疑截圖方法（改用 `PrintWindow` 加螢幕複製各一張），再用 debug 建置排除 profile，最後用 `--plain` 執行期參數確認是 `liquid_glass_widgets` 的初始化讓整個 App 白屏。`windows.json` 留著當證據（它的幀時間不算數），表格用 `windows-plain.json`。沒有細分是 `initialize`、`wrap`、`LiquidGlassScope` 三樣中的哪一樣。
  - iOS 模擬器在實驗途中變成關機（共用裝置鎖當時在這個 worktree，不是別人關的），用 `xcrun simctl boot` 開回同一台 iPhone Duo。
  - macOS 的「減少透明度」用 `defaults write com.apple.universalaccess` 寫不進去（系統保護），改用 `orca computer` 按系統設定的開關；iOS 模擬器用 `orca emulator` 按「設定」App；Windows 改登錄值。三個平台測完都切回原值並讀回確認。
- code-review（795d8c9e 起）已處理：`DESIGN.md` 還指向已刪的 brief §17、`player.html` 留著「Windows 只到標準」；README 的「每個候選都過 16.7 ms」不精確（Windows `lgw-minimal` 有 1 幀）；K22 出處不全；K19「lite 慢是因為模糊半徑大」改標推測；Windows a11y 的重跑說明與登錄值指令、`winpc` 目錄的清理、Windows 建置也持鎖的說明補進 README；K10 補 `liquid_glass_renderer`、`oc_liquid_glass` 的現況；降到 standard 時模糊半徑不能比折射級大（lite 用 16 比 lens 用 5 慢）寫進 brief §11、`DESIGN.md` §1.4、plan §7；Windows 出幀數比「應有」多、「> 預算」一欄只能參考寫進 README；`run.py` 的 `IOS_BUNDLE` 改名 `APPLE_BUNDLE`、`main.dart` 註解的 `run.sh` 改 `run.py`、`probe.ps1` 多餘的一行刪掉。
- code-review 未處理（不做，理由：實驗程式可丟棄，不會進 `app/`）：`run.py` 的 `Device` 每個方法都依平台分支（Repeated Switches）；結果檔尾碼規則分散在 `run.py`、`run-windows.sh`、README 三處；`probe.ps1` 的 `Shot` 建 bitmap 存檔寫了兩次。`DESIGN.md` §1.4 的 standard 寫 `blur(18px)`、§1.1 一般玻璃寫 16，稿內本來就有兩個值，留給 M1 照稿切版時統一。
- 沒測：`liquid_glass_renderer`（只有 pre-release，要 Flutter GPU）、`oc_liquid_glass`（沒有 Windows）、`cupertino_ui` 的分支（沒發佈）；設定變更的通知（probe 只在啟動時讀一次）；淺色主題與 adaptive tone；release 建置。
- 閘門：`dart run tool/check.dart` 完整版（795b19f2）除了 `integration_test windows` 全綠（quick 各步、四平台建置、macOS／iOS／Android 的 integration_test）。Windows 那一步在 `winpc` 卡在 `loading` 29 分鐘（三個 dart 行程沒用 CPU，`winpc` 已知的偶發狀況，擁有者決定遇到就重跑），我結束了排程工作 `fmptest` 讓閘門收尾，再照 plan §2 持鎖單獨重跑 `sync.sh`、`build.ps1 -Mode debug`、`test.ps1 -File integration_test/app_test.dart`：`All tests passed!`、`exit test=0`。這張票沒有改 `app/`。
