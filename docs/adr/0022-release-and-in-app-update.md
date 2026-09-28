# 0022 — 發版與應用內更新：release-please 自動發版、沿用舊版檔名、手動檢查與必驗 SHA-256、各平台以改名替換

- 狀態：已採納
- 日期：2026-09-28
- 影響範圍：`app/` 的版本號與 `CHANGELOG.md`、發版 workflow、發佈物與檔名、平台能力 `appUpdate`、更新模組（檢查、下載、驗證、安裝、清理）、
  Windows 免安裝版的更新程式、切換時舊版使用者的升級路徑

## 背景

舊專案（`.trellis/tasks/archive/2026-09/09-28-design-release-update/research/current-state.md`，已以程式碼核對）：

- 更新只有手動入口；打 GitHub Releases API，未處理 rate limit；版本比較只比三段。
- SHA-256 只在 release 附 checksums 檔時才驗，否則只比大小（B8）。
- Windows 免安裝版解到 Temp，以 bat＋vbs＋`robocopy /MIR` 覆蓋，部分成功會留下半套檔案（B7）。
- Android 按一次就下載並跳安裝器，沒有「下載完選安裝或刪除」（B9）。
- Linux、macOS 沒有實作。
- 發版要先手動改 pubspec、合併後再打 tag，順序錯就失敗；沒有 `CHANGELOG.md`；Windows 不簽章。

本 ADR 延續舊 ADR 0004（不上架商店）與 0006（驗過直接發布、不留人工閘門），適用於 `app/`；這兩份仍描述根目錄舊專案。
與舊做法的差異：版本號與發佈說明改由 release-please 產生。

擁有者已定（`phase2-plan.md` §4）：
- 只手動檢查，不在啟動或定時檢查；
- 由使用者點「下載」，下載完選「安裝」或「刪除」，點安裝才安裝；
- 重啟後清除舊安裝包；
- 自動發布，說明由 CHANGELOG 或 commit 產生。

2026-09-28 另定：release-please、Linux 只發 AppImage、macOS 發未公證 zip、Windows 不簽章、第一版 2.0.0。

## 考慮過的選項

- **手動改 pubspec＋打 tag（舊版）**：否決。順序錯就失敗，也沒有 CHANGELOG。
- **Linux 發 Flatpak 或 deb**：否決。由系統或套件管理器負責更新，App 不能自己換檔，還要維護上架流程。
- **macOS 付費公證（$99／年）**：暫不採用。代價是新使用者第一次要到系統設定按「仍要打開」。
- **Windows 經 SignPath Foundation 免費簽章**：暫不採用。條款要求「Every release needs manual approval for signing」，與自動發布衝突；發行者顯示為 SignPath Foundation；簽章也不保證 SmartScreen 不警告。列為之後的選項。
- **`desktop_updater`、`auto_updater`**：否決。前者 Linux 仍是 candidate、3.x 破壞性變更頻繁；後者沒有 Linux 且停滯。
- **免安裝版解到 Temp 後 `robocopy` 覆蓋（舊版）**：否決，部分成功會留下半套檔案。
- **只在有 checksums 檔時才驗（舊版）**：否決（B8）。
- **自動檢查更新、預發佈頻道**：否決（擁有者要求只手動；功能凍結）。

## 決定

1. **發版流程**：
   - release-please 以 manifest 模式、`dart` 策略管理 `app/`。每次 commit 進 main 就維護一個發版 PR：依 Conventional Commits 算下一版、改 pubspec、寫 `app/CHANGELOG.md`。
   - 合併發版 PR 是唯一的人工動作。同一個 workflow 接著打 tag `v{版本}`、建置、驗證、上傳 asset 並轉為正式發布。
     GitHub 預設 token 建的 tag 不會觸發其他 workflow，所以放在同一個 workflow。
   - 第一版以 `Release-As: 2.0.0` 指定。
   - versionCode 沿用 `major*1000000 + minor*1000 + patch`，由 workflow 從 tag 算出。
   - 舊 `pubspec_version_test` 改為「pubspec 版本等於 release-please manifest」。
   - 發版一律 `--flavor prod`（ADR 0015）；重寫期間不發版。
2. **發佈說明**：取 `CHANGELOG.md` 中該版段落，同一段也是 App 內更新對話框的內容，保持短、markdown 淺。
3. **發佈物**（GitHub Release）：
   - Android：`fmp-v{版本}-android-{arm64-v8a,armeabi-v7a,x86_64,universal}.apk`；
   - Windows：`fmp-v{版本}-windows-installer.exe`（Inno Setup）、`fmp-v{版本}-windows.zip`；
   - Linux：`fmp-v{版本}-linux-x86_64.AppImage`（Linux 平台任務加入）；
   - macOS：`fmp-v{版本}-macos.zip`（未公證，macOS 平台任務加入）；
   - 另有 `fmp-v{版本}-checksums.sha256` 與 `fmp-latest-*` 別名（與版本化檔逐位元相同）。
   
   iOS 沒有發佈物，散佈方式由 iOS 平台任務決定。Windows 不簽章。
4. **切換相容**：舊版 v1.x 更新器依上述 Android、Windows 檔名挑檔、驗 checksums、以 `unins000.exe` 判斷安裝版、只比三段版本號。
   - 新 App 沿用這些檔名、Inno AppId、Android 簽名金鑰（ADR 0008）；
   - 免安裝版 zip 的內容就是完整程式目錄；
   - 版本 2.0.0 大於 1.11.0。
   - verify job 加「舊版更新器相容」檢查：以舊版的選檔與 checksums 解析規則跑本次產物。
5. **能力與入口**：
   - 平台層能力 `appUpdate` 宣告安裝類型：`androidApk`（附 ABI）、`windowsInstaller`、`windowsPortable`、`linuxAppImage`、`macosApp`、`none`（ADR 0009）。
   - 判斷方式：
     - Windows：程式目錄有 `unins000.exe` 為安裝版；
     - Linux：有 `APPIMAGE` 環境變數；
     - iOS、dev flavor 與其他安裝方式：`none`，只顯示「前往下載頁」。
   - 入口只有「設定 → 關於 → 檢查更新」（ADR 0017）。
6. **檢查**：
   - 經網路層一般 client（ADR 0012，不帶憑證）打 `releases/latest`；以 `pub_semver` 比版本（含 build number）。
   - 403／429 且剩餘次數為 0 時轉成 `RateLimited`，附重置時間（ADR 0013）。
   - 依能力挑 asset：Android ABI 缺就退 `universal`；找不到就說明「這一版沒有你的平台」。
7. **下載與驗證**（B8）：
   - 使用者按「下載」才下載，經 ADR 0020 的下載引擎存到快取目錄 `updates/`，可暫停續傳。
   - checksums 檔必須存在並列出該檔；SHA-256 與大小必須相符；GitHub asset 的 `digest` 有值時也必須相同。
   - 驗證失敗刪檔並告知。
   - 驗證通過後提供「安裝」「刪除」；已下載的更新跨重啟保留。
8. **安裝**：
   - Android（B9）：經 `PermissionGateway` 取得安裝未知應用的授權（ADR 0020），以 FileProvider＋`ACTION_VIEW` 開系統安裝器。
   - Windows 安裝版：detached 執行 `/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /DIR=<目前目錄> /LOG=<updates/install.log>`，然後結束 App。
   - Windows 免安裝版（B7）：
     1. 新版解壓到程式目錄旁的 `<目錄>.new`；
     2. 程式目錄內附 Dart 編譯的 `fmp_updater.exe`，複製到 Temp 後執行；
     3. 更新程式等原 PID 結束，把 `<目錄>` 改名為 `.old`、`<目錄>.new` 改名為 `<目錄>`，任一步失敗就改回，最後啟動新版。
     
     上層不可寫時改提供「前往下載頁」。使用者資料在 `Documents\FMP`，不受影響（ADR 0010）。
   - Linux AppImage：新檔下載到同資料夾的 `.new`，驗證、加執行權限，舊檔改名 `.old`、新檔改成原名，執行新檔並結束。資料夾不可寫時改提供「前往下載頁」。
   - macOS：解壓到快取，由小腳本等 App 結束後把舊 `.app` 改名 `.old`、放上新的、再開啟。
9. **清理**（登記在啟動維護清單，ADR 0017）：
   - 刪除 `updates/` 中版本不大於目前版本的安裝檔、`.part`、安裝 log（先把內容寫進 log）；
   - 刪除 `.old` 目錄或檔案；
   - 比目前新但尚未安裝的保留。
10. **狀態與錯誤**：狀態為 `Idle`、`Checking`、`UpToDate`、`Available`、`Downloading`、`Downloaded`、`NeedsPermission`、`Installing`、`Failed(AppError)`，以操作代際防競態。
    錯誤依 ADR 0013 分類；網址寫 log 前經 ADR 0011 遮蔽。

採用的慣例：
- release-please 的 `dart` 策略與 manifest 模式；
- GitHub Releases API 為更新來源（Spotube、Hiddify、Harmonoid、Namida）；
- LX Music、electron-updater 的「下載後由使用者決定安裝」；
- Obtainium 的完整性檢查精神與 GitHub asset digest；
- Inno Setup 官方命令列參數。

## 後果

- 好的：
  - 發版只需合併一個 PR，版本號與 CHANGELOG 不再手動；
  - 所有更新檔都必驗 SHA-256；
  - 免安裝版不再留下半套檔案；
  - 舊版使用者能在 App 內直接升上新 App；
  - Linux、macOS 也有更新路徑。
- 壞的：
  - Windows 不簽章，新使用者第一次安裝可能看到 SmartScreen 警告；
  - macOS 第一次安裝要手動放行；
  - 多一個要維護的 `fmp_updater.exe`；
  - 版本號由 commit 類型決定，commit 分類錯會影響版號。
- 之後要注意：
  - SignPath 或 Apple 公證若日後需要，另立決定；
  - release-please 草稿與建 tag 的確切選項在落地時以官方文件確認。

## 如何確認

- 單元測試：
  - 版本比較（含 build number）；
  - 依能力挑 asset 與 ABI 退回；
  - checksums 解析、缺檔拒絕、digest 不符拒絕；
  - rate limit 轉成 `RateLimited`；
  - 狀態機與操作代際；
  - 清理只刪不大於目前版本的檔案；
  - 更新程式的改名替換與失敗回復（以暫存目錄模擬）；
  - zip-slip 防護。
- workflow 測試：
  - release-please 輸出為否時不建置；
  - verify 的檔名集合、checksums、別名一致、APK 版本、PE 標頭、舊版更新器相容；
  - pubspec 版本等於 manifest。
- 依賴方向（`fmp_layer_imports`，ADR 0015）：安裝相關的平台呼叫只在平台層。
- 延後實測：
  - 切換 PR 前，以舊版 v1.11.0 實際更新到新 App（Android、Windows 安裝版與免安裝版）；
  - Windows App 自行下載的安裝檔不帶 Mark of the Web；
  - macOS App 自行下載的更新不帶 quarantine；
  - Linux AppImage 的改名替換。
