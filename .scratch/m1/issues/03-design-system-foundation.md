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

- [x] `lib/` 沒有 `package:flutter/material.dart` 的 import；`material_ui` 的版本寫進 ARCHITECTURE〈主要依賴〉。
- [x] token 的數值和 `DESIGN.md` §2、§3 對得上，有測試讀主題比對幾個代表值（深淺色各一）。
- [x] 寬度分級的邊界（600、1200）與密度有單元測試；畫面拿得到，不自己判斷平台。
- [x] 依賴規則的兩條新規則：造違規證明會紅、改無關的命名證明不紅，ARCHITECTURE〈依賴規則〉已改。
- [x] 四平台實跑佔位畫面，深淺色各一張截圖。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments

依賴的公開簽名檢查：掃過所有依賴的 `lib/`，`flutter_riverpod` 已改用 `material_ui`；只有 `flutter_localizations` 用內建 Material（`GlobalMaterialLocalizations` 回傳內建的 `MaterialLocalizations`）。改用 `material_ui` 自帶的同名類別、移除 `flutter_localizations` 直接依賴後，沒有依賴在公開簽名收或回傳內建 Material 型別，不需要 `MaterialUiCompatibilityBridge`。`flutter_driver`、`leak_tracker_flutter_testing` 也用內建 Material，但只在測試工具鏈。

code-review 未處理的發現：
- 焦點外框（DESIGN.md §10：2px 強調色、offset 2）沒有 token，留給第一張做可聚焦元件的票（05 起）。
- 字型沒指定 Windows 的 Segoe UI Variable 與 CJK 字型（DESIGN.md §3.1），用 Flutter 各平台的預設字型；Windows 上是 Segoe UI。
- `ThemeData.platform` 以寫法認（規則不做型別解析）：`Theme.of(context).platform`、以它初始化的變數、名稱含 theme 的變數；把 `ThemeData` 存進名稱不含 theme 的參數或欄位再讀 `.platform` 擋不到。
- `FormFactor` 在 `lib/` 還沒有呼叫端，外殼票 05 第一個用。
- 判斷題，不改：密度的三元運算在 `FmpText.of`、`FmpRadii.of` 等處重複；三個 `ThemeExtension` 的 `copyWith` 回傳自己；無強調色時深色按鈕底的判斷寫在 `FmpColors.of` 而不是 `Accent`；程式註解引用設計稿的章節標題（沿用既有寫法）。

Session 紀錄：2026-11-15 改用 `material_ui`、加設計系統 token 與 `platform/` 的寬度分級與密度、依賴規則補三條，四平台深淺色實跑，完整閘門綠
決定：token 是 `app/theme/` 的三個 ThemeExtension（`FmpColors`、`FmpText`、`FmpMetrics`），間距與動態是靜態常數，畫面經 `context.fmpColors` 等讀（Agent 定）
決定：深色 label-2/3/4 照 `fmp.css` 用 rgba(238,236,247,…)（DESIGN.md 寫「白」）；title2 的字距照 DESIGN.md 用 -0.01em（CSS 沒有）（Agent 定）
決定：依賴規則多一條：`lib/` 不得 import 內建 `material.dart`、`cupertino.dart`，防 IDE 自動 import 帶回來（Agent 定）
決定：`domain/` 沿 `package:fmp/` 的 import 走整條鏈都不得出現 Flutter，鏈上純 Dart 的檔可以 import（Agent 定）
決定：讀 `ThemeData.platform`（`Theme.of(context).platform`、theme 變數的 `.platform`）也算判斷平台，`platform/` 以外不得用（Agent 定）
決定：移除 `flutter_localizations` 直接依賴，在地化改用 `material_ui` 的 `GlobalMaterialLocalizations`（Agent 定）
決定：`platform/` 給的密度也設進 `ThemeData` 的 `visualDensity`、`materialTapTargetSize`，不讓 Material 依平台自己猜（Agent 定）
決定：手機內容邊距取 16（設計稿寫 16–20，取下限）（Agent 定）
變更：Changed｜外觀｜畫面改用新設計系統的配色與字級，深淺色跟著系統切換
