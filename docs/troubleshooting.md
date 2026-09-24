# 疑難排解

已知的 runtime 噪音、以及已查明「修不掉、只能繞過」的行為與其成因。這裡的結論都對照過一手來源；標明「不要做」的就不要再花時間。

## Windows：`Failed to update ui::AXTree`

`flutter run -d windows` 輸出這行時：

```text
[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)] Failed to update ui::AXTree, error: <N> will not be in the tree and is not the new root
```

**它不是無害的噪音。** 看到它，就代表 Windows 的無障礙樹已經停在舊狀態，Narrator 讀不到 App 內容。這是 Flutter engine 的 bug（`flutter/flutter#182444`，僅 Windows，截至 2026-09 仍 OPEN），但 FMP 可以避開已知的觸發點。

### 後果（2026-09-24 實測，Flutter 3.47.1）

- `AccessibilityBridge::CommitUpdates()` 遇到這種 update 會整批丟掉，而且**不會在下一個 frame 自己修好**。沒送進去的節點之後每一次更新都會再失敗，錯誤一路連鎖。
- 修正前的 FMP：
  - 框架的語意樹有 93 個節點，送到 Windows 的只有 7 個：標題列三顆按鈕，加上一個空的路由容器；
  - 視窗已最大化，按鈕仍標著「最大化」；
  - 用 oleacc 走 MSAA 可以看到這些，debug 與 release 都一樣。
- release 開著 Narrator 操作約 5 分鐘沒有結束程序。上游另有人回報 release 會因同一個損壞狀態終止程序，沒有重現。
- C++ `FML_LOG` 寫到 platform stderr，不會進 `AppLogger` 或 app 內的 Log Viewer；release 沒有 console，所以使用者那邊完全看不到。

### 已知觸發點

兩者都是同一個機制：`OverlayPortal` 的內容實體上掛在 Overlay 底下，走訪順序卻嫁接回觸發它的元件。落在 Navigator 的 Overlay 時，bridge 就收不下。

- **Material `Slider`（已避開）**
  - `Slider` 與 `RangeSlider` 一建立就把數值指示器放進最近的 Overlay，所以只要畫面上有 Slider 就會壞。
  - 實測兩個入口：桌面迷你播放列的音量 Slider，啟動時就壞；播放頁的進度與音量 Slider，打開播放頁就壞。
  - FMP 的避法：所有 Slider 都走 `lib/ui/widgets/controls/scoped_slider.dart`（`ScopedSlider`）。它用 `Overlay.wrap` 讓指示器留在自己的 Overlay。
  - 閘門：`test/ui/static_rules/slider_overlay_static_rule_test.dart` 擋直接建 `Slider(`。
- **滑鼠 hover 彈出的 Tooltip（未避開）**
  - Tooltip 顯示的那一刻，同樣把內容放進 Navigator 的 Overlay。
  - 實測（Slider 已修）：啟動、開播放頁、收起，做兩輪，每次點擊前滑鼠都停在有 tooltip 的按鈕上。結果累計 104 行錯誤，節點數最後剩 8 個。同一條路徑全域關掉 tooltip：0 行，首頁 129 個、播放頁 34 個節點，每次都跟著頁面切換。
  - 只用鍵盤操作（Narrator 的一般用法）不會 hover，所以不會觸發。
  - 不能直接關掉 tooltip：它也是 `IconButton` 的無障礙名稱來源。
- 用 `flutter create` 的範本加 Slider 重現不出來，FMP 外殼還有別的條件，所以還沒回報上游。

### 再看到這行時

先找出是哪個節點。用 VM Service 的 `ext.flutter.debugDumpSemanticsTreeInInverseHitTestOrder` 倒出語意樹，對照錯誤裡的 `<N>`。帶 `traversalChildIdentifier: _OverlayPortalState` 的節點，就是某個 `OverlayPortal` 的內容嫁接到了 Navigator 的 Overlay。找到那個元件，替它包一層本地 Overlay。

### 這些沒有用，不要做

- 只為了這個而升級 Flutter、`desktop_multi_window` 或 `window_manager`。包含 master 在內，尚無任何 Flutter 版本修好它。
- 對主視窗全域 `setSemanticsEnabled(false)`：會全 app 停掉 Narrator / NVDA 無障礙支援。
- 使用 `FLUTTER_A11Y=off` 環境變數或 `FlutterWindows.instance?.setSemanticsEnabled(...)`。**這兩個都不是真實存在的 Flutter API**（論壇捏造，engine 與 framework 都查無此物）。
- 把 `IconButton` 包進 `Tooltip(child: ...)`。
- 把 `ExcludeSemantics` 包在觸發元件外面。overlay 節點不在它底下，實測沒有效果。

### 只想降低終端機噪音（例如別的視窗仍在觸發）

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

## Windows 可攜版：搬動資料夾後的第一次開機不會自啟

- **症狀**：可攜版（`fmp-<tag>-windows.zip`）把解壓資料夾搬到別的位置之後，**下一次開機**不會自動啟動 FMP，而設定頁的開關仍然顯示為開啟。**繞法**：手動開一次 FMP 就好了 —— 之後每一次開機都正常。開關顯示為開沒有說謊，它讀的是使用者自己存下來的設定，不是登錄檔。登錄檔項目在每次啟動時就被 `LaunchAtStartupNotifier._applyToSystem()` 用目前的執行檔路徑重寫過，所以「搬完之後有開過一次」與「搬完之後還沒開過」的差別只在那一次開機。

這一段修不掉：要改寫登錄檔項目就得有一個正在跑的 FMP，而問題正是那一次開機 FMP 沒有被啟動。程式碼能做的只有把它講出來 —— 可攜版的開機自啟開關副標題多一行提示（`settings.launchAtStartup.portableHint`，安裝版不顯示）。安裝版沒有這個問題：安裝目錄不會被使用者搬走。

## Android：換手機時 FMP 的資料不會跟著系統備份走

- **症狀**：新手機用 Google 帳號「還原應用程式資料」把 FMP 裝回來之後，歌單、播放紀錄、設定與登入全是空的。**原因**：manifest 刻意設了 `android:allowBackup="false"`。系統備份會把 shared preferences 原樣還原到另一台裝置，但那台的 keystore 沒有原本的金鑰，`flutter_secure_storage` 解不開還原回來的憑證，之後每一次帳號讀取都拋例外，app 停在永久載入態（issue #35）。與其還原到一半、留一個打不開的 app，不如整個不還原。
- **換機的做法**：舊手機在「設定 → 資料管理 → 資料備份」匯出 JSON，新手機匯入，再重新登入三個音源。備份檔本來就不含登入憑證與下載檔案。

這一條由 `test/support/android_manifest_static_rule_test.dart` 守著：改回 `true` 或把屬性拿掉都會紅。

## Windows：某個串流在 Android 能播、在 Windows 開不起來

Windows 的解碼器是 `libmpv-2.dll` 與它內建的 FFmpeg，而那是 **2023-09-24 的快照，沒有升級路徑**：產出它的 `media-kit/libmpv-win32-audio-build` 已於 2024-10-09 封存，`media_kit_libs_windows_audio` 1.0.9（2023-09-27）至今仍是最新版。`flutter pub upgrade` 換不到更新的 mpv 或 FFmpeg。

所以兩個平台對同一條串流說法不同時，先懷疑 Windows 的舊 FFmpeg 不認得那個格式或容器，而不是 FMP 的解析層。Android 走 ExoPlayer，不受影響。FMP 不自建這個二進位；授權細節見 `THIRD_PARTY_LICENSES.md`。

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
