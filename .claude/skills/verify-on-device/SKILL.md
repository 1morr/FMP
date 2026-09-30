---
name: verify-on-device
description: >-
  在 Android 模擬器與 Windows 桌面版實機驗證 `app/`（新 App）的改動：啟動、操作、讀畫面
  與 log、收尾。`app/` 的使用者看得到的改動（UI、播放、下載、歌詞、設定、原生身分、
  平台能力）在回報前都要用它驗，Android 與 Windows 各一次；也用在被要求在裝置上跑、
  截圖、點、觀察新 App 時。根目錄舊專案（`lib/`）的緊急修正改用 `verify-legacy-on-device`。
---

# 實機驗證 `app/`

閉環：**啟動 → 執行 → 觀察 → 操作 → 收尾。** 規則來源是 ADR 0027 與 `app/AGENTS.md` §
驗證；做不到哪一步就具名回報 blocker，不要略過不提。

| 何時讀 | 檔案 |
|---|---|
| Android 模擬器、安裝、帶參數啟動、log、音訊焦點、截圖 | `references/android.md` |
| Windows 建置、單一實例、MSAA 讀畫面與點按鈕、視窗截圖、SMTC | `references/windows.md` |
| 資料目錄、資料庫、log 格式、清成乾淨狀態、開發入口的參數 | `references/runtime-state.md` |

## 模式與平台

- **預設是重播**：dev flavor 加內附測試插件（`--fmp-dev-playback`，三首 2 秒的本機音檔、
  不連網）。App 還沒有每插件的重播開關（ADR 0015 §決定 5 只做到契約測試），目前重播就是
  測試插件。
- **真實連線只在**：改動本身是插件、網路層、登入，或正在錄 fixture。只做最少的操作（搜尋
  一次、播一首），不批次、不迴圈。上游改版交給 Debug 頁的健康檢查，不靠每個 PR 的實機驗證。
- **平台**：Android 模擬器與 Windows 每個使用者看得到的 PR 都驗。Linux、macOS、iOS 在各自的
  平台任務加進 `references/`，現在不驗。
- UI 還沒有入口的功能，用開發入口（`references/runtime-state.md` § 開發入口）。

## 前置

- `adb` 在 `PATH`；`emulator.exe` 不在，用 `$ANDROID_HOME/emulator/emulator.exe`。
- 只用 dev flavor（`com.personal.fmp.dev`、視窗標題 `FMP Dev`）。**不要動模擬器上的舊版
  `com.personal.fmp`，也不要把 prod APK 裝上去**：它放著舊版的測試資料。
- `app/` 沒有 slang，drift 的 `*.g.dart` 已提交：建置前不必跑 codegen（改了 table 才跑
  `dart run build_runner build`）。
- Git Bash 會改寫 `/data/...` 這類路徑：`adb shell` 前加 `MSYS_NO_PATHCONV=1`。Python 單行指令前加
  `PYTHONIOENCODING=utf-8`。
- 有 Orca 時，`orca skills get computer-use`／`orca-cli` 取得與版本相符的指令參考；不靠記憶。

## 1. 啟動

- Android：模擬器開機、`flutter build apk --flavor dev --debug`、`adb install -r`、`am start`。
  細節與陷阱見 `references/android.md`。模擬器要**分離**啟動，放在會結束的背景工作裡會被
  連帶關掉。
- Windows：`flutter build windows --flavor dev --debug`，直接跑產物 `fmp.exe`。Dev 是單一實例，
  先確認沒有別的 FMP Dev（包括別的 worktree）在跑。

要讓行程跨越多輪對話、並收得到熱重載按鍵時，`flutter run -d <裝置>` 放進 Orca terminal
（`orca terminal create --worktree active --command "cd app && flutter run -d <裝置>" --json`；
terminal 從 repo 根目錄開始）。

## 2. 觀察

| 訊號 | 做法 |
|---|---|
| 畫面文字與座標（Android） | `scripts/ax_flatten.py`（經 `orca emulator ax`；沒有 Orca 時加 `--adb`） |
| 畫面文字與座標（Windows） | `scripts/msaa_tree.ps1`（MSAA） |
| 截圖（Android） | `adb exec-out screencap -p > <檔>` |
| 截圖（Windows） | `scripts/window_shot.ps1`：只截 App 視窗 |
| App 的 log | 資料目錄的 `logs/fmp.jsonl`；Android debug build 也可 `adb logcat -s flutter` |
| 播放焦點、媒體工作階段 | `dumpsys audio`（Android）、`scripts/smtc_probe.ps1`（Windows，M2 起才有東西） |

優先讀文字（語意樹、log），畫面問題（版面、溢出、主題）才截圖。**截圖與貼進回報的內容不得含
個人資訊**：Windows 的身分頁會印出資料目錄的完整路徑，含使用者名稱；這種截圖不要貼出，只回報文字觀察。
只截 App 視窗，不截整個桌面。截圖一律存到 session 暫存目錄，不進 repo。

## 3. 操作

Android 用 `orca emulator tap/type/button`（座標是 0..1 的正規化值），沒有 Orca 時用
`adb shell input tap <px> <py>`（`ax_flatten.py` 的 `center=` 像素座標）；Windows 用
`msaa_tree.ps1 -Click '<名稱>'`（它是真的滑鼠點擊，先用 `-Filter` 確認名稱；只對標題是
`FMP Dev` 的視窗）。畫面變動後座標與索引都失效，下一步前重新讀一次。

## 4. 收尾

除非被要求留著：關掉自己開的 `fmp.exe`（先確認是 FMP Dev）與 run terminal，`adb emu kill`
關掉你開的模擬器。還原為驗證改過的東西（安裝的 APK、推到裝置的檔案、`userdata-dev` 的資料），
用 `adb devices`、`tasklist` 確認。

## 回報格式

每一份實機驗證回報都要有：

- **平台**：Android 模擬器（AVD 名稱、SDK）或 Windows；兩個平台分開寫。
- **模式**：重播／測試插件，或真實。真實時列出做了哪些請求（哪個插件、哪個操作、幾次）。
- 觀察：引用 log 行或語意樹節點，或給截圖路徑（截圖需已確認不含個人資訊）。本機路徑以
  佔位符寫（`<資料目錄>`、`<暫存目錄>`），不寫出使用者名稱。
- 模擬器若以 `-no-audio` 啟動，註明聽不到聲音，播放只能以 log 與 `dumpsys` 判斷。
- 每個略過或被擋下的步驟，與擋下它的原因。
