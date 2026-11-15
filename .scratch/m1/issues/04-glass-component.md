# 04: 玻璃元件

Status: done
Blocked by: 03
讀: brief §11；`docs/design/DESIGN.md` §1；`docs/design/system.html`；事實 K10、K21、K23、K24；architecture〈主要依賴〉〈風險與回寫點〉；`scripts/experiments/glass/`；spec〈共同規則〉

## What to build

一個玻璃元件包住三級：折射級（`liquid_glass_easy` 的 `LiquidGlassLens`）、standard（它的 lite glass）、minimal（自己畫的實心填色），每個實例都能在執行期切換級數；一個 App 層級的「玻璃效果」狀態（完整、輕量、關閉）讓所有玻璃一起切換。設定頁的入口在 19，這張票先用記憶體裡的狀態和測試切換。只有這個元件可以 import `liquid_glass_easy`。

第一步（擁有者定）：用 `scripts/experiments/glass/` 在 Windows 量 lite glass 模糊 5、10、18 的幀時間，選看起來仍是模糊玻璃、又比折射級快的值，截圖與數字給擁有者看，定了之後改 `DESIGN.md`（現在 16、18、「不比折射級大」三種說法並存），數字寫進 `docs/research/`。

## 驗收

- [x] 「輕量」的模糊值擁有者已定，`DESIGN.md` 只剩一種說法，量到的數字在 `docs/research/`。
- [x] 三級與三種變體（`DESIGN.md` §1.3）照稿；切換「玻璃效果」時所有實例一起換，有 widget 測試。
- [x] 依賴規則：`liquid_glass_easy` 只在玻璃元件裡 import，測試守著。
- [x] `liquid_glass_easy` 的版本照當時的 stable 重查，寫進 ARCHITECTURE〈主要依賴〉。
- [x] 四平台實跑一個示範畫面，三級各一張截圖。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments

量測（第一步）：Windows 上 lite glass 模糊 5、10、18 的 raster p50 都是 3.5–3.9 ms、折射級 2.7–3.0 ms、實心 2.0 ms（3 次，`docs/research/glass-lite-blur-2026-11-15.md`）。模糊值不影響成本，lite 一律比折射級慢，所以「比折射級快」的值不存在；擁有者看過截圖與數字選 18。

四平台實跑：示範畫面 `app/tool/glass_demo/main.dart`（用法在 docs/development.md〈平台〉），macOS（深色）、Windows、iOS 模擬器、Android 模擬器（淺色）三級各一張，截圖在 scratchpad 不進 repo。四個平台的折射級都看得到條紋在玻璃邊緣彎曲；切三個按鈕時畫面上 9 個玻璃一起換。和 `docs/design/system.html`〈材質：Liquid Glass〉三級並排比對：standard（模糊 18）與 minimal（實心、保留邊光與陰影）對得上；折射級的邊緣彎曲比設計稿的 SVG 版弱。

code-review 未處理的發現與給擁有者看的：
- 「輕量」選項的說明「只有模糊，比較省效能」（DESIGN.md〈三級與平台〉）在 Windows 不成立，捲動時降到 standard 的退路在 Windows 也省不到效能；手機沒量。票 19 寫選項字串前要擁有者定說明怎麼改。
- 折射強度：套件沒有和設計稿 SVG 位移量一對一的參數，`refractionIndex` 依位移量換算，以 M0 probe 的 dock 大小為基準；看起來比設計稿弱，擁有者在 M1 使用者試「玻璃效果三個選項的外觀」時看，要更強就調 `_refractionIndex` 的係數。
- 自適應色調（DESIGN.md〈自適應色調〉、〈三個變體〉regular 的「依底下內容翻轉明暗」）沒做：還沒有畫面用到，第一個要用的票（05 外殼或 16 播放頁）在玻璃元件加上。
- lite glass 沒有飽和度參數，standard 的 saturate(1.8) 與 thick 的 saturate(1.6) 做不到（事實 K21、DESIGN.md 已記）。
- 名詞表沒有「玻璃效果」「級」「變體」這些詞，程式用 `GlassTier`、`GlassVariant`；補名詞表要擁有者確認，留給 checkpoint。
- `system.html` 的兩處和現行文件不一致，沒改：側欄的折射預模糊寫 6px（DESIGN.md 只寫 ≥ 5，元件一律 5，外殼票 05 做側欄時再看）；「降低透明度」那段還寫跟系統（brief〈介面〉已定不跟）。
- Windows 的 `shot.ps1 -Click` 偶爾第一下只把視窗拉到前景、沒點到（這次三輪裡有一輪），截圖前先多點一下。

完整閘門：`dart run tool/check.dart` 除了 iOS 的兩個 integration_test 都綠；那兩個失敗是閘門跑到一半 iOS 模擬器被關掉（`No running ios simulator/emulator found`），持鎖開回 iPhone 18 Pro 模擬器後照 docs/development.md〈iOS 模擬器〉的閘門指令重跑 `app_test.dart`、`search_and_play_test.dart`，都通過。

Session 紀錄：2026-11-15 Windows 量 lite 模糊 5／10／18 給擁有者定 18，加三級三變體的玻璃元件、「玻璃效果」狀態與依賴規則，四平台實跑示範畫面，閘門綠
決定：「輕量」的模糊值用 18；lite 的成本和模糊值無關，看外觀選（使用者同意）
決定：玻璃元件放 `app/glass/`；「玻璃效果」是 Riverpod 的 `glassEffectProvider`，值直接用 `GlassTier`，不另開設定用的 enum（Agent 定）
決定：實例的 `tier` 是上限，只能比「玻璃效果」低，不能讓單一玻璃高過使用者的選擇（Agent 定）
決定：邊光、頂部光暈、內緣高光、陰影由元件自己照 fmp.css 畫、三級共用；套件只讀 backdrop，關掉它的 specular 與 lite 邊光（Agent 定）
決定：陰影像 CSS box-shadow 只畫在形狀外，不透進半透明玻璃，也不被 backdrop 讀到（Agent 定）
決定：折射強度依位移量換算 `refractionIndex`，以 probe 的 dock（短邊約 60）用 1.1 為基準，小玻璃彎得少、clear 與大玻璃彎得多（Agent 定）
決定：示範畫面放 `app/tool/glass_demo/`，不進 `lib/`、App 裡沒有入口；`build.ps1` 加 `-Target` 換入口（Agent 定）
決定：設計稿 CSS 的 16 一併改 18；brief、ARCHITECTURE 的「降級時模糊不能比折射級大」改成「Windows 上 standard 比較慢，降級前先量」（Agent 定）
變更：無
