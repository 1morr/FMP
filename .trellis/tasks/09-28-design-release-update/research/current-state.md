# 舊專案現況：發版與應用內更新

- 查證日：2026-09-28
- 查證方式：直接讀 repo 檔案（`lib/`、`android/`、`.github/workflows/`、`docs/`、`test/`、`pubspec.yaml`），行號為當下 `docs/audit` 分支工作樹的行號。工具：Read／Grep／`git log`。**未執行 App、未打任何平台 API**。
- 範圍：發版流程（CI／release workflow）、版本號與 CHANGELOG、應用內更新服務（檢查／下載／驗證／安裝／清理）、相關 ADR／audit 文檔、相關測試與 static-rule。
- 標記約定：**事實**＝有 `檔案:行號` 佐證；**推測**＝依程式碼推論但未實測；**查不到**＝找過沒找到。

---

## 1. 應用內更新服務

### 1.1 檔案與入口

| 檔案 | 角色 | 證據 |
|---|---|---|
| `lib/services/update/update_service.dart`（904 行） | GitHub API 呼叫、版本比較、asset 選擇、下載、驗 SHA-256、各平台安裝、清理 | `update_service.dart:1-904` |
| `lib/providers/system/update_provider.dart`（238 行） | Riverpod `Notifier` 狀態機（`UpdateStatus` 8 態） | `update_provider.dart:13-238` |
| `lib/ui/widgets/dialogs/update_dialog.dart`（379 行） | 更新對話框；含 release notes 的 markdown 攤平 | `update_dialog.dart:100-379` |
| `lib/ui/pages/settings/widgets/settings_about.dart` | 唯一 UI 入口：「設定 → 關於 → 檢查更新」 | `settings_about.dart:42-88` |
| `android/app/src/main/kotlin/com/personal/fmp/MainActivity.kt` | Android MethodChannel：安裝來源權限 | `MainActivity.kt:22-34,150-168` |

- **事實**：只有一個入口，且只有手動。`checkForUpdate` 的 UI 呼叫點只有 `settings_about.dart:70`；啟動時與定時都不檢查。`features.md §13.5` 記「沒有自動更新」。
- **事實**：啟動時只在 Windows 清理上一次的殘留檔（`main.dart:230-231` → `UpdateService.cleanupOldWindowsUpdateFiles`，`update_service.dart:259-292`）。
- **事實**：`autoCheckUpdates` 設定在 2026-09 被移除，grep 只剩註釋（`lib/services/backup/backup_service.dart:29-30`、`lib/data/database/database_migration.dart:224`；`features.md §11` 註）。

### 1.2 檢查來源與 rate limit

- **事實**：`GET https://api.github.com/repos/1morr/FMP/releases/latest`，只帶標頭 `Accept: application/vnd.github.v3+json`（`update_service.dart:18-19,396-399`）。
- **事實**：**沒有** token、**沒有** ETag／`If-None-Match`、**沒有** 條件式請求、**沒有** rate limit 處理或退避。Dio 只設 `connectTimeout` 15 秒（`AppConstants.updateConnectTimeout`）與 `receiveTimeout`（`app_constants.dart:121`；`update_service.dart:217-223`）。
- **事實**：HTTP 404 被當成「沒有 release」回 `null`（`update_service.dart:500-503`）；其他錯誤（含可能的 403 rate limit）直接 rethrow，由 provider 顯示「檢查更新失敗：<原因>」（`update_service.dart:504-509`；`update_provider.dart:95-107`）。
- **事實**：未認證 GitHub API 有速率上限，這是既有風險但程式未處理（**推測**：未認證每小時 60 次／每 IP，官方文件；本專案每次手動檢查只打一次，正常使用不會撞到）。

### 1.3 版本比較

- **事實**：`tag_name` 去 `v` 前綴得 `latestVersion`（`update_service.dart:406-409`）；當前版本取自 `PackageInfo.fromPlatform().version`（**不含** build number）（`:412-413`）。
- **事實**：`_isNewerVersion` 只把 `current`／`latest` 以 `.` 切開、`int.tryParse`（失敗視為 0），補到 3 段後逐段比較，**不比第 4 段、不比 build number、不比 `+` 後綴**（`update_service.dart:689-712`）。→ 後果：`1.2.3+1002003` 與 `1.2.3` 視為相同。
- **事實**：沒有用 `pub_semver`；`pubspec.yaml` 沒有 `pub_semver` 直接依賴（`grep pub_semver pubspec.yaml` 無命中）。

### 1.4 Asset 選擇（平台／ABI／安裝版 vs 免安裝版）

- **事實**：檔名分類（`update_service.dart:432-465`）：
  - APK：regex `fmp-.+-android-(.+)\.apk$` 取 ABI；不符這個格式的 `.apk` 當 `universal`（`:433,440-451`）。
  - `-windows-installer.exe` 結尾 → installer；`-windows.zip` 結尾 → portable（`:452-461`）。
  - `-checksums.sha256` 結尾 → checksum manifest（`:462-464`）。
- **事實**：別名 `fmp-latest-*` 與版本化檔落在同一格，**誰在 assets 清單裡排在後面誰贏**（`engineering.md §1.4`；`update_service.dart:435-465`）。
- **事實**：Android ABI 用 `Process.run('getprop', ['ro.product.cpu.abi'])` 取得，白名單 `arm64-v8a`／`armeabi-v7a`／`x86_64`，否則 `universal`（`update_service.dart:64-77`）。
- **事實**：選不到對應 ABI 時退回 `universal`；連 `universal` 都沒有 → 丟 `UpdateAssetUnavailableException`（`update_service.dart:151-173`）。
- **事實**：Windows 安裝版判定＝`Platform.resolvedExecutable` 同目錄存在 `unins000.exe`（`update_service.dart:53-58`）。安裝版選 installer、免安裝版選 zip（`update_service.dart:175-197`）。
- **事實**：`checkForUpdate` 內會先觸發一次 `info.selectedAsset` 以求 checksum 問題在檢查階段就爆（`update_service.dart:494-497`）。

### 1.5 下載位置與完整性驗證

- **事實**：下載目錄都是 `getTemporaryDirectory()`（Android／Windows 的 cache／Temp）（`update_service.dart:229,545-547,592-594,629-631`）。
- **事實**：檔名為 `fmp-<tag>-android-<abi>.apk`、`fmp-<tag>-windows-installer.exe`、`fmp-<tag>-windows.zip`（`update_service.dart:97-104,165,187-189`）。
- **事實**：下載一律先寫 `<檔名>.part`，驗證通過才 `rename` 成正式檔；失敗刪 `.part`（`update_service.dart:714-752`）。
- **事實**：`_validateDownloadedAsset` 先驗檔案存在，再驗 `size`（若 GitHub 有回報），最後驗 SHA-256（`update_service.dart:800-828`）。
- **事實**：**SHA-256 只有 release 附 `*-checksums.sha256` 才驗**。manifest 不存在 → `assetSha256s` 為空、`checksumManifestAvailable=false`，只驗 size（`update_service.dart:467-470,776-783`）。B8 現況即此。
- **事實**：manifest 存在但缺該檔名的 hash → 直接丟 `UpdateIntegrityException`（`update_service.dart:776-783`）。
- **事實**：manifest 格式＝`sha256sum` 風格 `^([a-fA-F0-9]{64}) [ *](.+)$`，key 取 `basename`、hash 轉小寫（`update_service.dart:785-798`）。
- **事實**：Android 若有已下載且通過完整性檢查的檔，會重用不再下載；不通過就刪掉（`update_service.dart:226-245`）。

### 1.6 Windows 安裝版流程

- **事實**：下載 `fmp-<tag>-windows-installer.exe` 到 Temp，用 `Process.start(..., mode: detached)` 帶參數 `/SILENT /DIR=<目前程式目錄> /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS` 啟動，然後 `exit(0)`（`update_service.dart:587-621`）。
- **事實**：`/DIR=` 是為了強制覆蓋安裝到「目前執行檔所在目錄」，避免裝到預設 Program Files（`update_service.dart:612` 註）。
- **事實**：**沒有** code signing（見 §3.3）；安裝檔來自 Inno Setup（見 §3.2）。

### 1.7 Windows 免安裝版流程

- **事實**：下載 `fmp-<tag>-windows.zip` → 在 worker isolate 以串流方式解壓到 `Temp/fmp_update`（**不可整包讀進記憶體**：release ZIP 約 200 MB，`update_service.dart:877-879` 註）→ 寫出 `fmp_updater.bat` 與 `fmp_updater.vbs` → `Process.start('wscript', [vbsPath], detached)` 隱藏視窗執行 → `exit(0)`（`update_service.dart:624-686`）。
- **事實**：解壓有 zip-slip 防護：拒絕絕對路徑、`..`、Windows 磁碟機前綴（`update_service.dart:359-385`）。
- **事實**：bat 內容（`_buildPortableUpdaterBatch`，`update_service.dart:830-875`）：
  1. `chcp 65001`、等原 PID 結束（`tasklist /FI "PID eq <pid>"` 迴圈）；
  2. `robocopy "%DST%" "%BACKUP%" /MIR /XD fmp_update_backup` 備份程式目錄；
  3. `robocopy "%SRC%" "%DST%" /E` 覆蓋；
  4. `errorlevel 8` 以上 → `goto rollback`，從備份 `robocopy ... /MIR` 還原再啟動；
  5. cleanup 刪 `fmp_update`、備份、vbs 與自己（`update_service.dart:838-874`）。
- **事實**：vbs 只有一行 `CreateObject("WScript.Shell").Run """<bat>""", 0, False`（`update_service.dart:675-676`）。
- **推測**：免安裝版的自我覆蓋靠「等 PID 結束 + robocopy」；若程式目錄不可寫、防毒攔截、或 robocopy 部分成功（`errorlevel` 1–7 不觸發 rollback）會留下半套檔案。phase2-plan §5 明說要「改成更穩的做法」。

### 1.8 Android 安裝流程

- **事實**：下載 APK 到 cache（`update_service.dart:540-564`），下載前先刪同目錄其他 `fmp-*.apk`（`:549-550,567-584`）。
- **事實**：安裝前檢查「允許此來源安裝應用程式」：`MethodChannel('com.personal.fmp/platform')` 的 `canRequestPackageInstalls`；未授權時 provider 進 `installPermissionRequired` 狀態並提供「開啟安裝設定」按鈕（`update_service.dart:295-306`；`update_provider.dart:183-193`；`update_dialog.dart:290-309,342-349`）。
- **事實**：實際安裝用 `OpenFilex.open(filePath)` 開系統安裝器（ACTION_VIEW），**不是** `PackageInstaller` API（`update_service.dart:247-254`）。安裝器返回後狀態恢復 `readyToInstall`，可再按一次（`update_provider.dart:194-198`）。
- **事實**：`AndroidManifest.xml` 宣告 `REQUEST_INSTALL_PACKAGES`（`AndroidManifest.xml:14`）；`<queries>` 有 `VIEW` + `application/vnd.android.package-archive` 讓 open_filex 能解析（`AndroidManifest.xml:95-99`）。
- **事實**：原生 `canRequestPackageInstalls`：API < O 直接回 true，否則查 `packageManager.canRequestPackageInstalls()`；`openInstallPermissionSettings`：API ≥ O 開 `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES`（逐 App），否則開 `ACTION_SECURITY_SETTINGS`（`MainActivity.kt:150-168`）。
- **事實**：目前流程是「按一次立即更新 = 下載 + 立刻跳安裝器」，**沒有**獨立的「下載完成後選擇安裝或刪除」這一步（`update_dialog.dart:330-369` 的 actions）。與 phase2-plan §4 的新需求（下載後可選安裝／刪除）不同。

### 1.9 舊安裝包清理

- **事實**：Windows：啟動時 `cleanupOldWindowsUpdateFiles` 掃 `getTemporaryDirectory()`，刪 `fmp-*.exe`、`fmp-*.zip`、`fmp_updater.bat`、`fmp_updater.vbs`、`fmp_update/` 目錄（`update_service.dart:259-293`；`main.dart:230-231`）。
- **事實**：Android：下載前刪同目錄其他 `fmp-*.apk`（保留目標檔名）（`update_service.dart:567-584`）。
- **事實**：**沒有**跨平台統一的「重啟後清舊安裝包」機制；Android 的清理綁在下載動作上，不是啟動時。

### 1.10 錯誤處理

- **事實**：`UpdateStatus` 8 態：`idle / checking / updateAvailable / downloading / readyToInstall / installPermissionRequired / installing / error / upToDate`（`update_provider.dart:13-23`）。
- **事實**：`UpdateNotifier` 用遞增 `_operationId` 守競態：舊操作完成不能覆寫新狀態（`update_provider.dart:66-77`；測試 `test/providers/update_provider_test.dart:11-42`）。
- **事實**：錯誤訊息統一走 `failureMessage()`（`lib/core/errors/user_message.dart`）後綴 i18n 前綴（`update_provider.dart:97-107,163-172,200-211`）。
- **事實**：下載進度只在變化 ≥ 1% 或完成時更新狀態，避免過多 UI 重建（`update_provider.dart:140-146`）。

---

## 2. CI 與 release workflow

### 2.1 `ci.yml`（`.github/workflows/ci.yml`，155 行）

| 項目 | 內容 | 證據 |
|---|---|---|
| 觸發 | PR → `main`、push `main`、`workflow_dispatch`；**無** path filter（刻意：純文檔 commit 也要跑 validate） | `ci.yml:3-15` |
| 權限 | `contents: read` | `ci.yml:17-18` |
| 併發 | PR 以 ref、main／手動以 SHA 分組；`cancel-in-progress: true` | `ci.yml:23-25` |
| 環境 | Flutter `3.47.1`、Java 17 temurin | `ci.yml:27-30` |
| Action 版本 | 全部以 commit SHA 釘住 | `ci.yml:40,48,98,174` |
| secrets | 無 | 全檔 |

- **事實** job：
  - `validate`（ubuntu，15 分）：`fetch-depth: 0`（`pubspec_version_test` 要 tag）→ `pub get` → `dart format --set-exit-if-changed lib test tool` → `build_runner build` → `slang` → `flutter analyze` → `flutter test --coverage --exclude-tags live`；上傳 `coverage-lcov`（保留 14 天）（`ci.yml:33-85`）。
  - `build-android`（needs validate）：`flutter build apk --release --target-platform android-arm64` 冒煙；**沒有** `key.properties` 時 gradle 退回 debug 簽名（`ci.yml:87-122`；`android/app/build.gradle.kts:46-50`）。
  - `build-windows`（needs validate，windows-2022）：`flutter build windows --release` 冒煙（`ci.yml:124-155`）。

### 2.2 `release.yml`（`.github/workflows/release.yml`，520 行）

| 項目 | 內容 | 證據 |
|---|---|---|
| 觸發 | push `v*` tag；或 `workflow_dispatch` 輸入已存在的 `vX.Y.Z` tag | `release.yml:3-12` |
| 權限 | workflow 預設 `contents: read`；只有 `release` job 拿 `contents: write` | `release.yml:14-15,425-426` |
| 併發 | 同 ref 排隊、不取消 | `release.yml:17-19` |
| secrets | `KEYSTORE_BASE64`、`KEYSTORE_PASSWORD`、`KEY_PASSWORD`、`KEY_ALIAS`（Android）；`GITHUB_TOKEN`（release） | `release.yml:117-141,520` |

- **事實**：`prepare` 檢查 tag 符合 `^v[0-9]+\.[0-9]+\.[0-9]+$` 且存在；`version_code = major*1000000 + minor*1000 + patch`；`version_with_code = "<version>+<version_code>"`（`release.yml:44-72`）。
- **事實**：`validate`（needs prepare）：`flutter analyze` + `flutter test --exclude-tags live`；**沒有** format 檢查、**沒有** coverage（與 ci.yml 不同）（`release.yml:180-214`）。
- **事實** `build-android`（matrix 4 格：`arm64-v8a`/`armeabi-v7a`/`x86_64`/`universal`）：用 `sed` 把 tag 版本寫進 `pubspec.yaml`（**不回寫 repo**）→ base64 解 keystore 到 `android/release.keystore` 與 `android/key.properties`（缺任一 secret 就 `exit 1`）→ 建 APK → 改名 `fmp-<tag>-android-<abi>.apk`，`arm64-v8a` 與 `universal` 另複製 `fmp-latest-android-<abi>.apk`（`release.yml:74-178`）。
- **事實** `build-windows`（windows-2022）：pwsh 改寫版本 → `flutter build windows --release` → 把 `LICENSE`／`THIRD_PARTY_LICENSES.md`／`licenses/` 放到 exe 旁 → 壓 `fmp-<tag>-windows.zip` ＋ `fmp-latest-windows.zip` → `choco install innosetup` → `dart run inno_bundle:build --release --no-app --no-installer` 產 ISS → regex 改寫 ISS → **驗證改寫生效（F8 gate，缺 `AppUserModelID` 或 `DefaultGroupName` 就紅）** → `ISCC.exe` 編譯 → `fmp-<tag>-windows-installer.exe` ＋ `fmp-latest-windows-installer.exe`（`release.yml:216-357`）。
- **事實** ISS 改寫內容：刪 `icelandic` 語言、加 `DefaultGroupName=FMP`、加 `AppUserModelID: "com.personal.fmp"`、把 `Flags: nowait postinstall skipifsilent` 的 `skipifsilent` 拿掉（**讓靜默更新也能重啟 App**）（`release.yml:296-315`）。
- **事實**：**Windows 產物沒有任何 code signing**（無 signtool／azure-signing 步驟；A6 現況亦如此）。
- **事實** `verify`（needs prepare + 兩個 build）：**刻意 checkout workflow 的 ref，不是 tag**（`release.yml:368` 註）→ 下載全部 artifact 合併 → 產生 `fmp-<tag>-checksums.sha256`（只含 6 個版本化檔：4 APK + zip + installer；**排除** `fmp-latest-*`）（`release.yml:390-399`）→ `AAPT2=… dart run tool/release/verify_release_assets.dart release-assets <tag> <version_code>`（`release.yml:401-409`）→ 上傳 `release-assets`（`release.yml:411-417`）。
- **事實** `release`（needs prepare + verify）：下載 `release-assets` → `git describe --tags --abbrev=0 <tag>^` 找前一個 tag → 從 `<prev>..<tag>` 的 commit 依 Conventional Commits 前綴產生 body → `softprops/action-gh-release@v3.0.3` 以 `draft: false`、`prerelease: false` 直接發布，只上傳 `release-assets/*`（`release.yml:419-520`）。
- **事實** Release notes 產生（`release.yml:452-506`）：
  - `git log --no-merges --pretty=format:"%s|%h" <range>`；
  - 分四段 `Features`（`^feat`）／`Fixes`（`^fix`）／`Performance`（`^perf`）／`Dependencies`（`^(chore|build)\(deps`）；
  - `refactor`／`docs`／`test`／`ci`／`style` 刻意不列（留給 compare 連結）；
  - 四段全空時退回列出全部 commit；
  - 結尾 `**Full Changelog**: .../compare/<prev>...<tag>`；
  - 用 `uuidgen` 產的隨機 delimiter 寫進 `$GITHUB_OUTPUT`（避免 body 撞到固定 EOF；`release_workflow_test.dart:64-83` 釘住）。
- **事實**：ADR 0006 記一個 Release 現為 **11 個 asset**（v1.11.0 起多了 `fmp-latest-android-arm64-v8a.apk`）；10 個的時代是 v1.10.2（`docs/adr/0006…md:23-34`）。

### 2.3 Release 驗證工具 `tool/release/verify_release_assets.dart`（211 行）

- **事實**：檢查（`verify_release_assets.dart:28-165`）：
  1. 檔案集合**剛好**等於 `expectedAssets(tag)`＝6 版本化 + 4 別名 + checksums＝11 個，缺一或多一都報錯（`:18-41,56-65`）；
  2. checksums 每行格式、涵蓋全部 6 個版本化檔、不含別名、hash 相符（`:75-104`）；
  3. 每個 `fmp-latest-*` 與同後綴版本化檔**逐位元相同**（`:109-119`；理由是 App 可能下載別名、卻用版本化檔名查 hash）；
  4. 以 `aapt2 dump badging` 讀每個 APK 的 `versionName`／`versionCode` 對 tag（`:122-141,168-176`）；
  5. Windows 安裝檔的 `MZ` + `PE\0\0` 簽章（`:143-165`；註解自承截斷檔擋不下）。
- **事實**：只擋結構性錯誤，**不擋**執行期才會壞的 build（`:6-8`、ADR 0006）。

---

## 3. 版本號、CHANGELOG、commit 慣例

### 3.1 版本號

- **事實**：`pubspec.yaml:5` 現值 `version: 1.11.0+1011000`。
- **事實**：tag 格式 `v{major}.{minor}.{patch}`；`+{versionCode}` 由 tag 算 `major*1000000 + minor*1000 + patch`（`release.yml:64-67`；`build-and-release.md:118-130`）。
- **事實**：**版本號的補寫是手動的**：發版前先把 `pubspec.yaml` 版本升上去、合併進 main，再在合併後的 commit 打 tag push；順序反了 release 會紅（`build-and-release.md:154-180,269-287`）。
- **事實**：`test/workflows/pubspec_version_test.dart` 守「committed 版本不得低於最新可達 tag」（允許超前、擋落後），並守 build number 公式（`:13-46`）。
- **事實**：不用 `github.run_number` 當 build number（會導致降級拒裝）（`build-and-release.md:128-130`；`release_workflow_test.dart:115-125`）。
- **事實**：Android `versionName`／`versionCode` 取自 `flutter.versionName`／`flutter.versionCode`（`docs/adr/0006…md:12-13`）。

### 3.2 Windows 安裝檔

- **事實**：用 `inno_bundle`（pubspec `^0.12.0`，`pubspec.yaml:101`）產生 Inno Setup 腳本，再由 `ISCC.exe` 編譯（`release.yml:289-342`）。
- **事實**：`inno_bundle` 設定（`pubspec.yaml:110-126`）：`id: BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA`（AppId，註明**發布後不可更改**，改了使用者機器會當成另一個 App）、`name: FMP`、`publisher: FMP`、`installer_icon`、**`admin: false`**（非提權安裝）。

### 3.3 簽章

- **事實**：Android release 簽章用 GitHub Secrets 的 keystore（`KEYSTORE_BASE64` 等 4 個），解到 `android/release.keystore` + `android/key.properties`（`release.yml:117-141`）。
- **事實**：本機無 `key.properties` 時 gradle 退回 **debug 簽名**（`android/app/build.gradle.kts:46-50`）。
- **事實**：**Windows 無 code signing**（A6 現況、release.yml 全檔無簽章步驟）。

### 3.4 CHANGELOG 與 commit 慣例

- **事實**：**repo 沒有 `CHANGELOG.md`**（`ls CHANGELOG*` 無檔）。
- **事實**：release notes 一律由 commit 訊息自動產生（`release.yml:452-506`），**沒有**手寫 notes 檔這條路（`release_workflow_test.dart:88-89` 斷言不含 `docs/release-notes/`）。
- **事實**：commit 用 Conventional Commits（`git log` 觀察：`chore(task):`、`docs(adr):`、`feat`、`fix`、`perf`、`chore(deps)`）。
- **事實**：release body 同時餵給 App 內更新對話框（`data['body']` → `releaseNotes`，`update_service.dart:472`），所以 body 要短、markdown 要淺（`release.yml:450-451` 註；`build-and-release.md:257-267`）。

---

## 4. ADR 與 audit 文檔要點（更新相關）

| 文檔 | 要點 | 出處 |
|---|---|---|
| ADR 0004 | 擁有者決定**永不上架任何商店**，只從 GitHub Releases 散佈；Android 用 `MANAGE_EXTERNAL_STORAGE` + 裸路徑 | `docs/adr/0004…md:34-49,58` |
| ADR 0006 | Release 驗過產物**直接發布**，不留草稿等人按；`verify` job 的 4 項檢查；body 不再有人先讀（知情取捨）；11 個 asset | `docs/adr/0006…md:40-99` |
| ADR 0008 | App 身分沿用舊版：Android `applicationId com.personal.fmp`、**同一把簽名金鑰**、Windows AppUserModelID `com.personal.fmp`；改身分會斷自動遷移，須另立 ADR | `docs/adr/0008…md:47-51,67,73` |
| ADR 0015 | flavor `dev`／`prod`，`default-flavor: dev`，發版帶 `--flavor prod`；dev 用 `applicationIdSuffix ".dev"`、AppUserModelID `com.personal.fmp.dev`、名稱「FMP Dev」、資料目錄／單一實例鎖／secure storage 命名空間加 `-dev` | `docs/adr/0015…md` 第 8 點（`sed -n '67,71p'`） |
| ADR 0017 | 背景排程器；**明確排除**「更新檢查與插件更新：只手動」；一次性啟動維護登記在「啟動維護清單」 | `docs/adr/0017…md:27-38` |
| ADR 0020 | `PermissionGateway` 依能力宣告權限，含「安裝更新（`REQUEST_INSTALL_PACKAGES`）」；流程：說明 → 請求 → 被拒說明影響並給「前往系統設定」→ 回 App 重查 | `docs/adr/0020…md` 第 9 點（`sed -n '65,72p'`） |
| audit `questions.md` A6 | 發佈管道：各平台都勾 GitHub Release；iOS「不確定」；維持自動發布；備註要求「不要手動發佈或手動設置文案，依 CHANGELOG 或 commit 信息生成」 | `docs/audit/questions.md:87-104` |
| audit `questions.md` B7/B8/B9 | B7 Windows 自動更新（installer `/SILENT`／portable bat+vbs+robocopy）勾「不確定」；B8 SHA-256 勾「修改：強制驗」；B9 Android 下載 APK 開系統安裝器勾「不確定」 | `docs/audit/questions.md:121-123` |
| audit `questions.md` E17 | 應用內更新：保留 | `docs/audit/questions.md:255` |
| audit `features.md` §11 | 檢查更新只有手動一個入口；下載安裝三平台流程；啟動時清 Temp 舊更新檔 | `docs/audit/features.md:261-264` |
| audit `features.md` §13.5 | **沒有**自動更新 | `docs/audit/features.md:361-363` |
| audit `features.md` §15.3 | 會自己下載或執行東西的行為（Windows 安裝版／免安裝版、Android、完整性、`getprop`） | `docs/audit/features.md:423-432` |
| audit `engineering.md` §1 | CI／release 逐 job 表；§1.3 驗證腳本；§1.4 自動更新時序圖 | `docs/audit/engineering.md:13-81` |
| audit `platforms.md` §6 | Linux／macOS／iOS 卡關點：`open_filex` 無 Linux／macOS；更新流程在該兩平台沒有實作（`update_service.dart:521`）；iOS 2.5.2 禁止自行下載可執行碼 → 整個 `UpdateService` 不成立 | `docs/audit/platforms.md:343-399`（Linux 列 12、macOS 列 30、iOS 列 47） |
| `docs/build-and-release.md` | §4 發布流程、CI 流程、Release Notes、版本號規則、產物命名；§5 應用內更新機制 | `docs/build-and-release.md:152-372` |
| `phase2-plan.md` §4／§5 | 新需求：只手動檢查；檢查後點「下載」；下載完可選「安裝」或「刪除」；點安裝才安裝；重啟後清舊安裝包；Release 維持自動發布、說明自動產生。§5 傾向：安裝檔一律驗 SHA-256；免安裝版自我覆蓋改成更穩的做法；應用內更新 iOS 除外 | `.trellis/tasks/09-26-fmp-rewrite/phase2-plan.md:166-167,185,205` |

---

## 5. 相關測試與 static-rule

| 檔案 | 測什麼 | 證據 |
|---|---|---|
| `test/workflows/pubspec_version_test.dart` | committed 版本不落後最新 tag；build number 公式 | 全檔 |
| `test/workflows/release_workflow_test.dart` | release gate：`verify` 等所有 `build-*`、`release` 等 `verify`、只上傳 `release-assets`；body 分組與隨機 delimiter；build number 公式 | 全檔 |
| `test/workflows/release_assets_verification_test.dart` | 以假產物證明 `verify_release_assets.dart` 每一項會紅、無關差異不紅（15 個 test） | 全檔 |
| `test/workflows/dependabot_group_static_rule_test.dart` | 0.x 直接依賴必須列在 dependabot `exclude-patterns`；`flutter_secure_storage` major 必須 ignore | 全檔 |
| `test/services/update/update_service_zip_test.dart` | zip-slip 防護；ABI fallback 時用 universal checksum | `update_service_zip_test.dart:8-60+` |
| `test/providers/update_provider_test.dart` | `_operationId` 競態；reset 取消延遲回寫；Android 等安裝權限 | `update_provider_test.dart:11-80+` |
| `test/ui/widgets/dialogs/update_dialog_release_notes_test.dart` | `plainTextReleaseNotes` 不留下 markdown 記號 | 全檔 |

- **事實**：**沒有**專門守更新服務的 static-rule（`test/support/*static_rule*` 無 update 相關命中）。release 相關的「靜態規則」是 `release_workflow_test.dart`／`release_assets_verification_test.dart` 這種讀 workflow 與工具原始碼的測試。
- **事實**：`test/services/update/` 只有一個檔案（`update_service_zip_test.dart`）；`update_service.dart` 的 `checkForUpdate`／下載／SHA-256 路徑本身**沒有**直接單元測試（只有 `@visibleForTesting` 的選檔與 manifest 解析間接覆蓋）。
