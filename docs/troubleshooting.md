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

## 建置時的無害雜訊

一次成功的 `flutter build windows --release` 過程中，會看到下面三則訊息。它們都不代表建置失敗，初次建置者看到也不需要排查。

### `resolve_symlinks.ps1` 的 `Get-Item : 找不到 ... AppData`

`smtc_windows` 套件的 cargokit 建置腳本會用 `cargokit/cmake/resolve_symlinks.ps1` 逐段解析路徑以找出符號連結目標；第 25 行對每個路徑片段呼叫 `Get-Item`：

```powershell
$item = Get-Item $realPath
```

當路徑片段落在 `AppData` 這類隱藏/特殊 reparse point 上時，`Get-Item` 會對這個中繼路徑丟出一個非終止性錯誤（找不到路徑），並印到終端機。因為呼叫沒有加 `-ErrorAction Stop`，PowerShell 只是把錯誤寫到 stderr 就繼續往下解析剩餘的路徑片段，不會中斷腳本或讓建置失敗。只要後續 build 步驟成功，這則訊息可以忽略；若 build 真的失敗，優先檢查 `cargo` / `rustc` 是否可用，而不是這則訊息本身。

### media_kit 的 CMake `CMP0175` 警告

`media_kit_libs_windows_audio` 套件的 `windows/CMakeLists.txt` 宣告 `cmake_minimum_required(VERSION 3.14)`，並用較舊的 `add_custom_command(TARGET ... PRE_BUILD ...)` 寫法下載/準備原生依賴。CMake 3.31 起新增的 `CMP0175` 政策，對 `add_custom_command()` 的引數做了更嚴格的檢查；用較新版 CMake（本機或 CI 上常見）建置這個套件時，就會印出 `CMP0175` policy 警告，提示引數用法在未來版本可能不被接受。這只是警告，不是錯誤——CMake 仍會依照舊行為執行該指令，建置照樣成功。修好它需要等上游套件更新其 `CMakeLists.txt`，不是 FMP 這邊能處理的事。

### flutter_inappwebview 的 C4819（codepage 950）警告

MSVC 編譯 `flutter_inappwebview_windows` 外掛的原生程式碼時，若原始檔以不含 BOM 的 UTF-8 儲存且內含非 ASCII 字元，而系統的作用中字碼頁是 950（繁體中文 Big5，本機常見於繁體中文 Windows 環境），編譯器會針對該檔案輸出 C4819：「The file contains a character that cannot be represented in the current code page (950). Save the file in Unicode format to prevent data loss.」這只是編譯期警告，提醒的是「如果之後用非 Unicode 感知的工具重新開啟該檔案可能會誤讀」，不影響這次編譯出的二進位正確性，建置一樣會成功。
