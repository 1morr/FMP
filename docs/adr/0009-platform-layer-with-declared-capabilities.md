# 0009 — 平台差異收進單一平台層，由平台宣告能力

- 狀態：已採納
- 日期：2026-09-27
- 影響範圍：`app/lib/platform/`、所有依平台顯示或運作的 UI 與 service、平台相關依賴、CI 的平台矩陣

## 背景

舊專案有 88 處平台判斷、三種寫法並存（`Platform.isWindows`、`isDesktopPlatform`、`AudioRuntimePlatform`），
結果 macOS／Linux 會出現半套桌面 UI、沒有標題列、推測無法播放（`docs/audit/platforms.md` §0–§2）。
重寫的長期目標是 Android、Windows、Linux、macOS、iOS 五平台；第一版只做 Android＋Windows，其餘之後加入
（`docs/audit/questions.md` A1）。擁有者希望各平台功能與體驗盡量一致，做不到才放棄。

研究（`.trellis/tasks/archive/2026-09/09-27-design-platform/research/`）確認：沒有一套套件能涵蓋五平台，
系統媒體控制、多視窗、登入 WebView 都要依平台拼接；同類 Flutter 播放器（Spotube、Finamp、Harmony Music、Namida）
都把平台差異集中在一層。

## 考慮過的選項

### 選項 A：沿用散落的平台判斷，只統一寫法

把三種寫法換成一種 helper。改動最小，但「哪些功能在哪個平台有」仍分散在各處，加一個平台就要全 repo 搜尋。

### 選項 B：只按 Android／Windows 設計抽象

以「行動／桌面」二分設計介面。第一版最快，但只有兩個平台時介面容易變成 if Windows／else Android 的包裝，
Linux、macOS 加入時要回頭改介面。

### 選項 C：單一平台層、每個平台宣告能力（採用）

見下方決定。

### 附帶否決：為還沒驗證的平台先寫實作

先寫好 Linux／macOS／iOS 的實作「等之後驗證」。否決：沒人跑過的程式碼只會製造假的完成感。

## 決定

1. **平台層**：`app/lib/platform/`，每個能力一個目錄——`<能力>.dart`（介面與工廠）、`<能力>_<平台>.dart`（實作）。
   能力包括托盤、視窗與標題列、全域快捷鍵、開機自啟、單一實例、桌面歌詞視窗、系統媒體控制、目錄規則、
   應用內更新、登入 WebView、執行期權限。平台套件（`tray_manager`、`window_manager`、`hotkey_manager`、
   `smtc_windows`…）只在實作檔 import。
2. **能力宣告**：每個平台一份不可變的 `PlatformCapabilities`。UI 依它決定是否顯示入口；service 只呼叫介面。
   要在執行期才能判斷的（例如 Linux 在 Wayland 下沒有全域快捷鍵）由實作在啟動時寫進宣告。
   宣告也包含音訊後端與可播格式（容器、編碼、是否支援 FLV／HLS），見 ADR 0018；權限由平台層 `PermissionGateway` 統一請求，見 ADR 0020；桌面歌詞的穿透與置頂、Android 懸浮歌詞、iOS Live Activity 歌詞的能力見 ADR 0021；應用內更新的安裝類型（`appUpdate`）見 ADR 0022。
3. **平台層以外禁止** `dart:io` 的 `Platform.isX`、`defaultTargetPlatform`、`TargetPlatform` 與平台套件的 import。
4. **不寫空實作**：未驗證的平台宣告全部能力為「沒有」、沒有實作檔；該平台的 child task 開始時才加入實作。
5. **原生呼叫**：新的 MethodChannel 一律用 Pigeon 產生型別安全介面。
6. **套件**（各能力×平台的完整表在 design.md §3）：系統媒體控制用 `audio_service`（Android／iOS／macOS）＋
   Windows SMTC＋Linux `audio_service_mpris`；托盤、視窗、快捷鍵、多視窗沿用現有套件並擴到其他桌面平台；
   `connectivity_plus`、`file_picker`、`path_provider` 五平台共用。桌面套件需要修補時用 git 依賴鎖 commit，並註明上游 issue。
7. **目錄**：Android 私有目錄；Windows 安裝版 application support（`%APPDATA%`）、Portable 版程式旁 `data/`；
   Linux `~/.local/share`；macOS／iOS 沙盒 Application Support；開發版另用目錄與身分。舊 `Documents\FMP` 首次啟動時搬遷。
8. **外觀**：Windows、Linux 用自訂標題列；macOS 保留系統紅綠燈按鈕。CJK 字型不內建，依平台 fallback。
9. **上線順序**：Android、Windows 從第一個里程碑起全面驗證；Linux、macOS、iOS 從第一個里程碑起在 CI 編譯
   （iOS 加模擬器測試）；Linux 在第一個里程碑後開 child task 於虛擬機實機驗證，之後每個里程碑冒煙測試；
   macOS、iOS 取得設備後各開 child task。各平台在實機驗證完成後才發佈。平台任務的時程與測試環境見 ADR 0026。

### 平台政策（決定的前提，免得重新研究）

- iOS：不能自行安裝更新；App Store Guideline 5.2.3 與下載第三方媒體衝突，不上架；經 GitHub 發 IPA、以
  AltStore／SideStore 側載，免費 Apple ID 需 7 天重簽、最多 3 個 App；背景播放需 `UIBackgroundModes: audio`。
- macOS：Sequoia 起未公證 App 無法以 Control-click 繞過 Gatekeeper，一般使用者順利安裝需付費開發者帳號公證。
- Android：Google Play 不允許音樂播放器使用 `MANAGE_EXTERNAL_STORAGE`；FMP 不上 Play。
- Linux：只有 AppImage 適合應用內自我更新；Flatpak 交給系統、deb 沒有機制。
- 系統限制：Linux Wayland 不允許應用程式攔截全域按鍵（協定設計），只能經 portal 且功能縮水。

採用的慣例：Namida `lib/controller/platform/` 的每能力一目錄結構；Flutter 官方 federated plugin 的
「共用介面＋各平台實作」；Flutter 官方對平台分支的建議（`defaultTargetPlatform`、platform channel、Pigeon）。

## 後果

- 好的：加一個平台＝加實作檔＋改一份宣告；「哪個平台有什麼」一眼可查；未驗證平台不會有假裝能用的功能。
- 壞的：每個能力多一層介面；Linux／macOS／iOS 在其 child task 完成前只有核心功能。
- 之後要注意：登入 WebView 在 Linux 的選型、Android 下載儲存、音訊後端、Linux 打包與各平台更新機制分別在
  網路與帳號、下載與權限、播放核心、發版與更新的 ADR 決定，並更新本 ADR 的套件表引用。
- 更正（2026-09-29）：§決定 7 的 Portable 版資料夾改名為程式旁的 `userdata/`（開發版 `userdata-dev/`）。Flutter 的 Windows 產物本身在程式旁放 `data/`（`flutter_assets`、`app.so`），同名會讓使用者資料混進程式目錄，更新時有被覆蓋的風險；擁有者 2026-09-29 選定（M1 PR 2）。

## 如何確認

- 平台層以外禁止平台判斷與平台套件 import：lint `fmp_platform_checks` 與 `fmp_layer_imports`（ADR 0015）。
- 能力宣告與 UI 一致：每個平台 child task 的驗收包含「宣告為沒有的能力，UI 不出現入口」。
- CI：從第一個里程碑起建置矩陣含 Linux、macOS、iOS（不簽名）。
