# 03: 設計系統基礎

Status: ready-for-agent
Blocked by: None
讀: brief §11；`docs/design/DESIGN.md` §2、§3、§5.3、§10；`docs/design/system.html`；事實 T1；architecture〈依賴規則〉〈主要依賴〉；spec〈共同規則〉

## What to build

App 改用 `material_ui`，並有照 `DESIGN.md` 的主題：中性色與功能色 token（深淺色）、強調色（預設無，可選堇紫、靛藍、青綠）、字級、間距、圓角、動態時長；寬度分級（窄、中、寬）與密度（觸控、滑鼠）由 `platform/` 提供給畫面。這是照稿切版的第一張票，之後的畫面都讀這裡的 token，不寫死數值。

- 遷移照事實 T1：`dart fix --apply --code=migrate_design_widgets`；逐一檢查依賴有沒有在公開簽名裡收或回傳內建 Material 型別（`MaterialUiCompatibilityBridge` 解決不了這種），有的話在 Comments 記下怎麼處理。Flutter 維持 3.47.5，不升級。
- 依賴規則補兩條，加進依賴規則測試並做雙向變異驗證，同票改 ARCHITECTURE〈依賴規則〉：`platform/` 以外不得用 `defaultTargetPlatform`（畫面要的平台差異由 `platform/` 提供）；`domain/` 不得 import Flutter。
- 佔位畫面改用新主題，深淺色跟系統走（主題設定在 19）。

## 驗收

- [ ] `lib/` 沒有 `package:flutter/material.dart` 的 import；`material_ui` 的版本寫進 ARCHITECTURE〈主要依賴〉。
- [ ] token 的數值和 `DESIGN.md` §2、§3 對得上，有測試讀主題比對幾個代表值（深淺色各一）。
- [ ] 寬度分級的邊界（600、1200）與密度有單元測試；畫面拿得到，不自己判斷平台。
- [ ] 依賴規則的兩條新規則：造違規證明會紅、改無關的命名證明不紅，ARCHITECTURE〈依賴規則〉已改。
- [ ] 四平台實跑佔位畫面，深淺色各一張截圖。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
