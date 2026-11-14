# 04: 玻璃元件

Status: ready-for-agent
Blocked by: 03
讀: brief §11；`docs/design/DESIGN.md` §1；`docs/design/system.html`；事實 K10、K21、K23、K24；architecture〈主要依賴〉〈風險與回寫點〉；`scripts/experiments/glass/`；spec〈共同規則〉

## What to build

一個玻璃元件包住三級：折射級（`liquid_glass_easy` 的 `LiquidGlassLens`）、standard（它的 lite glass）、minimal（自己畫的實心填色），每個實例都能在執行期切換級數；一個 App 層級的「玻璃效果」狀態（完整、輕量、關閉）讓所有玻璃一起切換。設定頁的入口在 19，這張票先用記憶體裡的狀態和測試切換。只有這個元件可以 import `liquid_glass_easy`。

第一步（擁有者定）：用 `scripts/experiments/glass/` 在 Windows 量 lite glass 模糊 5、10、18 的幀時間，選看起來仍是模糊玻璃、又比折射級快的值，截圖與數字給擁有者看，定了之後改 `DESIGN.md`（現在 16、18、「不比折射級大」三種說法並存），數字寫進 `docs/research/`。

## 驗收

- [ ] 「輕量」的模糊值擁有者已定，`DESIGN.md` 只剩一種說法，量到的數字在 `docs/research/`。
- [ ] 三級與三種變體（`DESIGN.md` §1.3）照稿；切換「玻璃效果」時所有實例一起換，有 widget 測試。
- [ ] 依賴規則：`liquid_glass_easy` 只在玻璃元件裡 import，測試守著。
- [ ] `liquid_glass_easy` 的版本照當時的 stable 重查，寫進 ARCHITECTURE〈主要依賴〉。
- [ ] 四平台實跑一個示範畫面，三級各一張截圖。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
