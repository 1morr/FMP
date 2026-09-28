# 設計：發版與應用內更新（階段二第 19 項）

## 目標

為 `app/` 定下版本號與發版流程、發佈說明的產生方式、各平台的發佈格式，以及應用內更新（檢查、下載、驗證、安裝、清理）。產出 ADR 0022。技術設計見 `design.md`，執行步驟見 `implement.md`。

依據：parent `prd.md` 階段二第 19 項；`docs/audit/questions.md` A6、B7–B9、E17；`phase2-plan.md` §4「應用內更新流程」與 §5 的 B7–B9 方向；
ADR 0004（不上架商店）、0006（驗過就直接發布）、0008（App 身分沿用）、0009（平台能力）、0015（dev／prod flavor、CI 分專案）、0017（更新檢查只手動）、0020（`PermissionGateway` 含安裝權限）。

## 現況（`research/current-state.md`，已以程式碼核對）

- **檢查**：只有「設定 → 關於 → 檢查更新」手動一個入口；打 `api.github.com/repos/1morr/FMP/releases/latest`，未認證、無 rate limit 處理（`update_service.dart:396-399,500-509`）。
  版本比較自寫、只比三段、不比 build number（`:689-712`）。
- **選檔**：依檔名 `fmp-{tag}-android-{abi}.apk`、`fmp-{tag}-windows-installer.exe`、`fmp-{tag}-windows.zip`；ABI 用 `getprop`、找不到退 `universal`；
  Windows 以程式目錄有 `unins000.exe` 判斷安裝版（`:53-58,93-104,151-197`）。
- **驗證**：先寫 `.part`、驗證後改名；**SHA-256 只在 release 附 `*-checksums.sha256` 時才驗**，否則只比大小（B8，`:767-828`）。
- **Windows 安裝版**：Inno Setup，`/SILENT /DIR=<目前目錄> /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS` 後 `exit(0)`（`:587-621`）。
  **免安裝版**：解壓到 Temp，產 bat＋vbs，bat 等 PID 結束 → `robocopy /MIR` 備份與覆蓋，`errorlevel ≥ 8` 才回滾（`:624-686,830-875`）；1–7 的部分成功會留下半套檔案（推測）。
- **Android**：`OpenFilex.open`（ACTION_VIEW）開系統安裝器，先檢查「安裝未知應用」逐 App 授權；按一次＝下載＋立刻跳安裝器，**沒有「下載完選安裝或刪除」**（B9，`:247-254,540-584`）。
- **清理**：Windows 啟動時清 Temp 殘留；Android 在下一次下載前清。沒有跨平台的「重啟後清」。Linux／macOS 沒有實作（`update_service.dart:521`）。
- **發版**：`release.yml` 由 `v*` tag 觸發；validate → 4 個 ABI 的 APK（keystore 來自 secrets）＋ Windows zip 與 Inno 安裝檔（**無 code signing**）→ verify（11 個 asset、checksums、別名逐位元相同、aapt2 版本、PE 標頭）→ 直接發布。
  versionCode ＝ `major*1000000 + minor*1000 + patch`。**版本號要手動先改 pubspec、合併後才打 tag**，`pubspec_version_test` 擋落後。
  發佈說明由 `prev..tag` 的 commit 依 Conventional 前綴分四段自動產生；同一段文字也顯示在 App 的更新對話框。**repo 沒有 `CHANGELOG.md`**。
- 目前只發 Android 與 Windows；Linux、macOS、iOS 沒有發佈物。

## 研究結論（`research/prior-art.md`、`research/packages-and-platform.md`，關鍵項已抽查）

- **成熟產品**：LocalSend、Finamp 完全不檢查；Spotube、Hiddify、Harmonoid、Namida 檢查後只開瀏覽器；真正自我更新只有 AppFlowy（僅 macOS，Sparkle）與 LX Music（electron-updater）。
  7 個 Flutter 專案沒有一個在 Android 應用內下載安裝 APK；Android 自己裝的是 Seal、Obtainium。檢查來源幾乎都是 GitHub Releases API。
  **驗證 checksum 的幾乎沒有**：只有 Obtainium 比對 APK 簽章憑證。
- **發佈說明工具**：`release-please` 有現成 `dart` 策略（改 pubspec 版本＋寫 `CHANGELOG.md`，以「release PR」合併後打 tag），支援 monorepo 路徑；
  `git-cliff` 只產 changelog；`standard-version` 已棄用。各家做法分歧：release-drafter、自寫腳本、手寫都有。
- **套件**：`desktop_updater` 3.2.0（2026-09-22，三平台、Ed25519，但 Linux 仍是 candidate、3.x 破壞性變更頻繁）；`auto_updater` 1.0.0（2024-10，無 Linux、停滯）；
  `ota_update` 7.1.0（Android 專用）；`pub_semver` 2.2.1 的比較**含 build number**（`1.2.3+4 > 1.2.3`）。
- **Android**：Play 政策禁止用 `REQUEST_INSTALL_PACKAGES` 做自我更新（FMP 不上架，不受限）；升級必須同簽章；Android 14 起不能安裝 targetSdk < 23 的 APK。
- **Windows**：SmartScreen 是信譽制，**EV 憑證自 2024 起也不給即時信譽**；SignPath Foundation 對開源專案免費簽章（需申請、在 CI 建置）；Azure Artifact Signing 要付費訂閱、不發 EV。
  Inno Setup exit code 8＝需重開機。
- **macOS**：未公證的 App 在 Sequoia 起不能右鍵開啟，要到系統設定按「仍要打開」；公證需 $99／年的開發者帳號。Sparkle 2 用 EdDSA。
- **Linux**：AppImage 可內嵌更新資訊（`gh-releases-zsync`）並以 zsync 差量更新；Flatpak 的 App 目錄唯讀、只能由系統更新；deb／rpm 由套件管理器管理。
- **iOS**：Guideline 2.5.2 禁止下載執行改變功能的程式碼；側載免費帳號 7 天到期、付費 1 年。
- **GitHub**：未認證 60 次／小時；`releases/latest` 不含 prerelease 與 draft；**每個 asset 自 2025-06 起有 `digest`（`sha256:…`），FMP v1.11.0 的 11 個全都有**（已實測）；
  下載經兩次 302 到簽章網址（約 50 分鐘有效），支援 Range 續傳。有社群回報同名重傳後 digest 會變——但重傳需要 repo 寫入權，這種人也能改 checksums 檔，兩者防護等級相同。

## 已確定的方向

- 更新流程（擁有者已定，`phase2-plan.md` §4）：不在啟動或定時檢查，只有手動；檢查到後使用者點「下載」；下載完可選「安裝」或「刪除」；點安裝才安裝；重啟後清除舊安裝包。
  Release 維持 tag 後自動發布，發佈說明由 CHANGELOG 或 commit 訊息自動產生、不手寫。
- 安裝檔一律驗 SHA-256（B8）；免安裝版的自我覆蓋改成更穩的做法（B7）；應用內更新 iOS 除外；不上架商店（ADR 0004）。
- **切換相容（由 ADR 0008 推得）**：舊版 v1.x 的更新器依檔名挑 asset、驗 checksums、以 `unins000.exe` 判斷安裝版、只比三段版本。
  新 App 的第一個版本必須沿用這些檔名、Inno AppId、Android 簽名金鑰，且版本號大於 1.11.0，舊版使用者才能在 App 內直接升上來。

## 已決定

1. **改用 `release-please`（2026-09-28，按建議）**：commit 進 main 時機器人維護「發版 PR」（依 Conventional Commits 算下一版、改 pubspec、寫 `CHANGELOG.md`）；
   合併該 PR 即打 tag 並接續建置、驗證、發布；發佈說明與 App 內更新對話框取 CHANGELOG 中該版段落。只看 `app/` 路徑。
2. **Linux 只發 AppImage、macOS 發未公證的 zip（2026-09-28，按建議）**：
   - Linux：App 內下載驗證後，按「安裝」把舊檔改名、放上新檔、重啟，下次啟動刪舊檔；所在資料夾不可寫時說明並提供「打開下載頁」。不發 Flatpak、deb。
   - macOS：暫不付 Apple 開發者年費；第一次安裝要到系統設定按「仍要打開」；App 內下載驗證後替換整個 App 並重啟。
     「App 自己下載的檔案不帶 quarantine、更新後不必再放行」為推測，列入 macOS 平台任務的實測。

## 待決定

1. Windows 程式碼簽章（SignPath Foundation 申請）。
2. 新 App 第一個版本的版本號。

## 不在範圍

- 上架任何商店；iOS 的應用內更新。
- 自動檢查更新、預發佈頻道（功能凍結）。

## 驗收條件

- [ ] ADR 0022 記錄：版本號與發版流程、發佈說明、各平台發佈格式、更新的檢查／下載／驗證／安裝／清理、各平台差異、切換相容、dev flavor 行為。
- [ ] A6、B7、B8、B9、E17 各自對到決定。
- [ ] `phase2-plan.md` §3 第 19 項標 ✅ 與 ADR 編號。
