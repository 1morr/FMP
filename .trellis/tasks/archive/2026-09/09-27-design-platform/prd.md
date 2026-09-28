# 設計第 10 項：平台層

## 目標

把所有平台差異收進單一平台層：平台宣告自己有哪些能力，UI 與 service 依能力運作，平台層以外不出現
`Platform.isX`／`defaultTargetPlatform`。選定各能力在五個平台上的套件，寫明平台政策限制與平台上線順序。

需求來源：parent `prd.md` 階段二第 10 項；`questions.md` A1、A4、§8（使用者：各平台體驗盡量一致，做不到可以放棄）；ADR 0008。

## 已確認的前提

- 第一版 Android＋Windows；Linux、macOS、iOS 之後加入（A1）。iOS 經 GitHub Release 發 IPA 供側載（phase2-plan §6）。
- 不替還無法驗證的平台寫空實作（parent prd 第 10 項）。
- 資料位置：安裝版用系統 App 資料目錄；Portable 版放程式旁；舊 `Documents\FMP` 自動搬（A4，按推薦）。
- 單一實例保留；開發版用不同身分與資料目錄（E18、U9）。

## 現況（證據）

- 88 處平台判斷、三種寫法並存；macOS／Linux 會出現半套桌面 UI（`docs/audit/platforms.md` §0–§2）。
- 平台綁定功能與各平台阻礙：`platforms.md` §3、§6。

## 研究結論（`research/platform-packages.md`、`research/platform-policy-and-peers.md`）

- **沒有一套套件能覆蓋五平台**：系統媒體控制、多視窗、登入 WebView 都要依平台拼接。
- 系統媒體控制：`audio_service`（Android／iOS／macOS）＋ Linux `audio_service_mpris`（Spotube、Finamp、Harmony 都用）＋ Windows `smtc_windows`（現用，無 seek）或 `audio_service_win`（待評估）。
- 托盤 `tray_manager`、視窗 `window_manager`、快捷鍵 `hotkey_manager`、多視窗 `desktop_multi_window`：三個桌面平台都支援，現在只接了 Windows。Linux Wayland 下全域快捷鍵是協定層限制，不是套件問題。
- 開機自啟：`auto_start_flutter` 五平台都支援、機制透明（macOS 需 13+）；`launch_at_startup` 現用。
- 單一實例：`flutter_single_instance` 涵蓋三個桌面平台，機制未公開（推測 gRPC＋檔案），需讀原始碼再決定。
- 登入 WebView：`flutter_inappwebview` 無 Linux、2024-10 後未發版；桌面端能讀 cookie 的只有 `webview_cef`（較新、社群訊號小）；`desktop_webview_window` 訊號好但沒有 cookie API。
- 權限：`permission_handler` 不支援 macOS、Linux（這兩個平台本來就沒有 Android 式執行期權限）。
- `path_provider`、`file_picker`、`connectivity_plus`：五平台可用。
- 更新：Android APK、Windows installer／portable、macOS Sparkle（`auto_updater`）、Linux 只有 AppImage 適合自我更新、iOS 不可。
- 政策：App Store 5.2.3 與下載第三方媒體衝突；iOS 側載免費帳號 7 天重簽、3 個 App 上限；macOS Sequoia 起未公證 App 無法用 Control-click 繞過 Gatekeeper；Google Play 不允許音樂播放器用 `MANAGE_EXTERNAL_STORAGE`。
- 同類播放器：都把平台差異集中在一層；Namida 最徹底（`lib/controller/platform/` 每能力一目錄：`_base.dart`＋各平台實作＋工廠）。三家把桌面音訊／SMTC 套件改用 fork 或本地 path。
- Flutter 官方：純 Dart 的平台分支用 `defaultTargetPlatform`；要呼叫原生 API 才用 platform channel，建議用 Pigeon 產生型別安全的介面；federated plugin 是官方認可的「共用介面＋各平台實作」切法。

## 已決定

- D1（使用者 2026-09-27）：Linux 從第一個里程碑起 CI 編譯並跑單元測試；第一個里程碑完成後開 Linux child task
  在虛擬機實機跑，之後每個里程碑做一次虛擬機冒煙測試；切換前不發 Linux 版。macOS、iOS 從第一個里程碑起在 CI
  做不簽名編譯（iOS 加模擬器測試），取得設備後各開 child task。
- 其餘（平台層形狀、各能力套件、資料目錄、標題列、字型、政策）依研究結論與使用者「按推薦」寫入 design.md。

## 需求

- R1 平台差異只存在於平台層；平台層以外不出現 `Platform.isX`、`defaultTargetPlatform`、`TargetPlatform`，也不 import 平台套件；以 lint 守（第 8 項落實）。
- R2 每個平台一份 `PlatformCapabilities` 宣告；UI 依宣告顯示入口，service 只呼叫介面。
- R3 未驗證的平台只宣告「沒有」，不寫實作檔。
- R4 新的原生呼叫用 Pigeon。
- R5 平台政策限制寫進 ADR。

## 驗收標準

- [x] design.md 涵蓋：平台層形狀、不寫空實作的做法、各能力×五平台的套件表、資料與下載目錄、平台政策、標題列與字型、上線順序與驗證、預期的平台 child task。
- [x] `docs/adr/0009-*.md` 依範本寫成，含被否決的選項與「如何確認」。
- [x] `phase2-plan.md` 標記第 10 項完成。

## 延後到其他項目

- 各音源的登入方式與 Linux 登入 WebView 選型 → 第 12 項。
- Android 下載儲存（ADR 0004 去留）→ 第 11 項。
- 音訊後端 → 第 13 項。Linux 打包格式與各平台更新機制 → 第 19 項。
