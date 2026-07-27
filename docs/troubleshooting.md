# 疑難排解

已知的良性 runtime 噪音與其成因。這裡的結論已對照上游一手來源查證，**不要**再花時間「修好」它們。

## Windows：`Failed to update ui::AXTree` log 洪水

`flutter run -d windows` 會反覆輸出：

```text
[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)] Failed to update ui::AXTree, error: <N> will not be in the tree and is not the new root
```

這是**已知的 Flutter engine bug，不是 FMP 缺陷，而且無害**。以下每一條都在 2026-07 對照一手來源（engine 原始碼、`flutter/flutter` GitHub、Flutter 3.44 release notes）查證過。

### 成因

- **Engine 行為**：`AccessibilityBridge::CommitUpdates()` 無法在單次 update 內序列化 semantics node 的 reparent，於是執行 `FML_LOG(ERROR) ... ; return;`，丟棄該次 update，並在下一個 frame 重送修正後的 tree。不會 crash，也沒有功能影響。
- **上游追蹤**：`flutter/flutter#182444`（ListView + Tooltip + OverlayPortal，僅 Windows，截至 2026-07 仍 OPEN）與 `flutter/flutter#188662`（bridge 洩漏其 `AXTreeManager`）。包含 master 在內，尚無任何 Flutter 版本修好它。
- **為何 FMP 特別容易觸發**：每個 `desktop_multi_window` 子視窗都跑自己的 Flutter engine（各自有一份 `AccessibilityBridge`），而自訂標題列與歌詞標題列使用 `IconButton` tooltip 搭配 `Semantics` / `ExcludeSemantics`——正好是 `#182444` 的 reparent 模式。該套件放大了觸發面積，但它本身不是 bug 來源。
- **影響範圍**：這行是 C++ `FML_LOG` 寫到 platform stderr。它不會進入 `AppLogger` 或 app 內的 Log Viewer，release build 也看不到（沒有掛載 console）。它只汙染開發用終端機。

### 這些都「修不好」，不要做

- 只為了這個而升級 Flutter、`desktop_multi_window` 或 `window_manager`。
- 對主視窗全域 `setSemanticsEnabled(false)`（會全 app 停掉 Narrator / NVDA 無障礙支援）。
- 使用 `FLUTTER_A11Y=off` 環境變數或 `FlutterWindows.instance?.setSemanticsEnabled(...)`——**這兩個都不是真實存在的 Flutter API**（論壇捏造，engine 與 framework 都查無此物）。
- 把 `IconButton` 包進 `Tooltip(child: ...)`——那正是 `#182444` 的 OverlayPortal 反模式。

### 只想降低終端機噪音

```bash
# Git Bash 直接過濾（注意：這會讓 flutter run 失去 hot-reload 互動）
flutter run -d windows 2>&1 | grep -vF "Failed to update ui::AXTree"

# PowerShell——必須先設 UTF-8，否則中文輸出會被 GBK 解碼成亂碼；同樣有 hot-reload 限制
[Console]::OutputEncoding = [Text.Encoding]::UTF8
flutter run -d windows 2>&1 | Select-String -NotMatch "Failed to update ui::AXTree"

# 保留 stdout/stdin 互動，只把 stderr 導到檔案（推薦）
flutter run -d windows 2> run.log
```

Windows PowerShell 5.1 透過 `Select-String` pipe 時中文會變亂碼（UTF-8 位元組被系統代碼頁 GBK/CP936 解碼），先設 `[Console]::OutputEncoding` 即可修正（如上）。PowerShell 7（`pwsh`）預設 UTF-8，不受影響。

VS Code 整合終端機沒有原生的「隱藏符合樣式的行」功能（已驗證至 v1.107）。請用上面任一種 pipe、把 stderr 導到檔案，或改用擷取後過濾的擴充套件（例如 *Better Terminal Logs*）。*Filter Lines* 擴充套件只作用於編輯器文件，不作用於即時終端機，因此不適用。
