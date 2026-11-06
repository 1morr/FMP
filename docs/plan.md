# FMP 新版實作計劃

> 狀態：第一版定稿（2026-11-06）。`/to-tickets docs/plan.md` 以〈里程碑任務〉為輸入，拆票後以票為準。決定的來源是 `docs/design-brief.md`，兩者衝突時以 brief 為準。

## 0. 工程慣例

- 一張票一個分支，在本機 `git merge --no-ff` 合回 main 再 push，不開 PR（`AGENTS.md`）。
- 每張票在四個平台做完並驗收，合併前跑 `dart run tool/check.dart`（完整版）。
- 新字串在同一張票補齊 zh-TW、zh-CN、en 三種語言。
- 依賴的版本開工時查 pub.dev 決定，寫進〈主要依賴〉，不憑記憶寫。
- 命名用 `GLOSSARY.md` 的詞。

## 1. 架構總覽

### 1.1 執行形態

單一 Flutter App。插件在 JS 引擎裡執行，引擎與 isolate 的配置由 M0 實驗定。音訊在原生播放器裡（ExoPlayer、AVPlayer、libmpv）。

### 1.2 目錄結構

新版放在 `app/`，根目錄舊版不動；建好後補進 `AGENTS.md`〈目錄〉。

```text
app/
  lib/
    app/        組裝、路由、主題、i18n
    domain/     曲目、歌單、存取等級等模型（純 Dart）
    core/       log、遮蔽、錯誤分類、網路
    plugins/    JS 引擎、宿主 API、插件管理
    playback/   佇列、臨時播放、音訊後端介面與兩個實作
    library/    本地歌單、匯入歌單、刷新、遠端寫入
    accounts/   帳號、登入、會員狀態
    lyrics/     歌詞匹配與顯示用的資料
    data/       drift 資料庫
    platform/   平台能力
    ui/<頁面>/  畫面與 view model
  plugins/      官方插件原始碼：bilibili、youtube、netease、lrclib
  test/
  integration_test/
  tool/check.dart
```

### 1.3 依賴規則

- `ui` 只能依賴功能模組與 `domain`，不能直接碰 `data`、`plugins` 的內部，也不能碰平台套件。
- 只有 `data/` 能 import drift，只有 `platform/` 能 import 平台套件；平台層以外不得用 `Platform.isXxx`。
- 音源專屬的邏輯只能在 `app/plugins/` 裡；Dart 端不得出現音源識別碼的字面值分支（ADR 0038）。
- 由一支掃 import 與識別碼的 Dart 測試強制，並在測試檔內做雙向變異驗證；不自寫 analyzer lint 套件（flutter/flutter#187999）。M0 票 01 接上。
- 模組的實際介面在 M0 用 codebase-design skill 細化。

### 1.4 主要依賴

確切版本由 M0 寫入。

| 用途 | 依賴 | 理由 |
| --- | --- | --- |
| 狀態管理 | flutter_riverpod 3（手寫 provider） | 舊版與上一輪都用；自動重試全域關閉（brief 事實 K5） |
| 路由 | go_router | flutter.dev 官方維護，舊版用過；外殼用 `ShellRoute` |
| 資料庫與設定 | drift 加 sqlite3 | schema 快照與升級測試；設定也存這裡，不用 shared_preferences |
| HTTP | dio | 插件請求都經宿主網路層，統一限流、重試、遮蔽 |
| 音訊 | just_audio（Android、iOS、macOS）、media_kit（Windows） | brief §6、事實 K1 |
| 媒體控制 | audio_service、audio_session、smtc_windows | macOS 由 M0 實驗定 |
| 登入 WebView | flutter_inappwebview 6.1.5 | 唯一涵蓋四平台的穩定版（事實 R1） |
| 憑證 | flutter_secure_storage 11.2.0 | brief §8 |
| 圖片 | cached_network_image | |
| i18n | slang | 舊版用過 |
| JS 引擎 | M0 實驗定 | brief §17 |
| 插件建置 | TypeScript 加 esbuild（需 Node） | ADR 0038 |

## 2. 平台

每個平台一節：用的框架與套件、怎麼建置、怎麼實跑驗證。M0 建好各平台後補齊。

驗證工具的已知怪癖（上一版文件，用到時重驗）：

- **Windows 遠端**：SSH 的 session 0 沒有桌面，`flutter build windows` 會失敗，要用排程工作在桌面工作階段跑；PowerShell 5.1 讀無 BOM 的 `.ps1` 用 cp950；`$ErrorActionPreference='Stop'` 會把 CMake 的 stderr 警告當錯誤。出處：archive 的 `references/windows.md`。
- **Windows 自動化輸入**：`SendKeys` 與掃描碼為 0 的 `keybd_event` 會讓 Ctrl 組合鍵失效；中文輸入法會吃掉英數字；跨行程最小化與還原會讓 lifecycle 卡在 `inactive`。
- **integration_test**：一次只能給一個檔；Android 不加 `--no-uninstall` 時可能刪掉模擬器上同 applicationId 的 App 連同資料。
- **Android 模擬器**：音訊比實際快約 1.7 倍，不能拿來量時長；`adb shell input text` 打不了中文；畫面持續更新時 `uiautomator dump` 會失敗；Claude Code 的沙箱擋 `adb` 連 5037。
- **macOS**：macOS 27 不讓第三方讀 Now Playing，媒體控制只能目測；Flutter 的語意樹不經 macOS AX 暴露，要用截圖加座標。
- **iOS 模擬器**：沒有可截圖的鎖定畫面與控制中心，Now Playing 只能讀系統 log；不要用 `orca emulator kill`。
- **無害的建置雜訊**：`media_kit_libs_windows_audio` 的 CMake `CMP0175` 警告、`flutter_inappwebview_windows` 在 cp950 下的 C4819、`resolve_symlinks.ps1` 的 `Get-Item` 錯誤。

## 3. 測試策略

- 預設零聯網：`live` tag 預設跳過；`HttpOverrides` 讓任何真實連線直接報錯。
- `domain`、`playback`、`library` 用單元測試，音訊後端用 fake。
- 每個插件套同一套契約測試，用 fixture 重播；錄製工具寫檔前經過遮蔽函式。
- 每個里程碑的主要流程有一條 `integration_test`，四個平台都跑。
- 聯網冒煙測試：每個音源每種插件能力最多一條，手動執行，不擋合併；用真實帳號時照 `AGENTS.md` 的最少操作規則。

## 4. 開發環境與閘門

- `dart run tool/check.dart --quick`：format、analyze、單元測試；commit 改到 `app/` 時由 `.githooks/pre-commit` 執行。
- `dart run tool/check.dart`（完整版）：quick 之外，再做 macOS、iOS 模擬器、Android 模擬器、Windows（SSH 同步工作樹到 `winpc`、以排程工作執行，不靠 push）的建置與 `integration_test`，並檢查插件打包產物是否最新。每張票合併前跑完整版。
- GitHub Actions：新版平常不跑。`app-v*` tag 觸發 `app-release.yml`，跑完整閘門後發佈。舊版的 `ci.yml` 照舊，M0 要確認它不受 `app/` 影響。
- 環境：Flutter 3.47.5（Mac 與 `winpc`）、Xcode 27.1、iOS 27.1 模擬器、Android 模擬器 `Medium_Phone_API_37.0`、Node（開發插件用）。

## 5. 里程碑任務

### 5.1 M0 骨架與 tracer bullet

已開工：[`.scratch/m0/spec.md`](../.scratch/m0/spec.md)。

### 5.2 D 設計稿

和 M0 並行，只產出文件。目標：brief §11 的第一版頁面全部有定稿。

- 先定設計系統（色彩、字級、間距、寬度分級），再做每頁的手機版與桌面版、深淺色。
- 有爭議的地方給 A／B 方案。

驗收：擁有者逐頁確認；M1 開工前完成。

### 5.3 M1 三音源與播放核心

目標：三個音源都能搜尋、播放，播放核心完整。

- youtube、netease 插件的搜尋與串流解析。youtube 插件的線索：tag `archive/youtubejs-probe-20261106`（把 YouTube.js 打包成插件的實驗，先查證再沿用）。
- 佇列、臨時播放、播放模式、持久化、串流過期重解析、預載、失敗處理。
- 背景播放與系統媒體控制。
- 照設計稿實作：App 外殼、搜尋頁、迷你播放器、播放頁、佇列頁；錯誤 Toast。

驗收：四個平台上，三個音源各搜尋並播放一首；臨時播放與四種模式照 brief §6 運作；背景播放與媒體控制可用。

### 5.4 M2 帳號與存取等級

目標：三個音源都能登入，會員狀態與存取等級正確呈現。

- 三音源的 QR 與 WebView 登入（YouTube 用 WebView 加貼 cookie）、憑證存放、登出。
- 會員狀態、存取等級徽章、音質選擇、試聽處理（brief §5.4）。
- 照設計稿實作帳號頁。

驗收：四個平台上，三個音源都登入成功；VIP、試聽歌曲的標示與播放行為照 brief §5.4。

### 5.5 M3 音樂庫與遠端歌單

目標：本地歌單、匯入歌單、遠端寫入都可用，並能搬入舊版資料。

- 本地歌單、匯入歌單與刷新、複製成本地歌單。
- 遠端寫入與寫入前確認。
- 照設計稿實作：音樂庫、歌單詳情、加入歌單對話框。
- 匯入舊版 JSON 備份。

驗收：用擁有者指定的測試歌單做遠端加入、移除各一次；匯入一份真實的舊版備份，筆數對得上。

### 5.6 M4 歌詞

目標：播放頁顯示歌詞。

- netease、lrclib 插件的歌詞能力。
- 自動匹配、手動搜尋、偏移調整、翻譯並排。

驗收：四個平台上，三個音源的曲目都能顯示同步歌詞。

### 5.7 M5 第一版發佈

目標：發佈 `app-v2.0.0` prerelease，交給擁有者試用。

- 設定頁、匯出診斷、插件更新（brief §5.1）、三語補齊。
- 效能量測（brief §15）。
- `app-release.yml` 與四個平台的安裝檔（brief §16）。
- 重新開啟 `.github/dependabot.yml` 的 GitHub Actions 版本更新（2026-11-06 因舊版凍結而關閉）。

驗收：四個平台的安裝檔都裝得起來並能播放；效能達標；擁有者試用後同意發佈。

### 5.8 之後的里程碑

照 brief §5.2，第一版發佈後再排序，開工時才寫細節。

## 6. 待決

定了方向、細節未定的事。每條寫明卡在哪、怎麼定；定案後移到對應的章節，這裡刪掉。

- **P1 取代舊版的方式**：同 brief §17。卡在新版功能還沒齊全，到「取代舊版」的里程碑由擁有者決定。
- **P2 JS 引擎、macOS Now Playing、Windows 截圖傳回**：由 M0 實驗定，定案後寫進 §1.4、§2。

## 7. 風險與回寫點

- YouTube 的 client 會變（事實 F8）：解析串流準備候選序列；壞了就更新插件。
- B 站風控（事實 F2）：網路層依音源限流；登入後要確實帶憑證。
- `flutter_inappwebview` 的穩定版停在 2024-10（事實 R1、K8）：登入票先實測四個平台。
- Windows 的 libmpv 是舊快照（事實 W3）：遇到 Windows 獨有的播放失敗先懷疑它。
- iOS 的中斷與 Now Playing（事實 I2、I5）：模擬器驗不到的部分記在票的 Comments。
- 實作時發現與 brief 不符：停下來問擁有者，改 brief 並在 progress.md〈偏差與決定〉記一行。
