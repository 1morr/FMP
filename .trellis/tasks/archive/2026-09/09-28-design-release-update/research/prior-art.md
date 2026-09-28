# Prior Art：成熟產品的發版與應用內更新

- 查證日：2026-09-28
- 查證方式：
  - 別人的公開 repo 一律用 `gh api` 讀取（`repos/<owner>/<repo>/contents/<path>?ref=<sha>`、`.../releases`、`.../git/trees/<sha>?recursive=1`），以 `gh api repos/<owner>/<repo>/commits/<branch> --jq .sha` 取得**查證日當下的 commit SHA**；**下文所有 GitHub permalink 全部釘在固定 40 碼 SHA**，不用 `main`／`master`／`dev` 這種會漂移的 ref。
  - 少數 repo 的完整檔案改用 `codeload.github.com` 抓 tarball 後在本機 `tar` + `grep -rn`（因為 `gh search code` 對所有查詢都回 0 筆，靜默失敗；故此批研究不依賴 GitHub code search）。
  - 官方文檔（release-please／git-cliff／semantic-release／Conventional Commits）以官網與 repo 內 markdown 為準。
  - 版本號、star 數、license 以 `gh api repos/<owner>/<repo>` 與 npm registry API 為準，不憑記憶。
  - 實測外部服務：`https://newpipe.net/api/data.json` 於查證日抓取一次（唯讀 GET）。
  - **本次抽驗**：NewPipe manifest、Obtainium `settings_provider.dart` 預設值、release-please `dart` 策略三項由我重新以 `gh api` 逐字核對，結果與來源一致。
  - 條件：**唯讀**，未改動任何 repo、未 commit、未開 issue/PR、**未執行任何 App**、**未呼叫任何音樂平台 API**。文件中不含任何 token／key 實際值。
- 標記約定：**事實**＝有出處可逐字對上；**推測**＝依原始碼或文檔推論但未實測；**查不到**＝找過沒找到。**僅列事實與對照，不含設計建議。**

## 引用 SHA 對照表

| 專案 | repo | 引用 SHA | 分支 | License |
|---|---|---|---|---|
| LocalSend | `localsend/localsend` | `6f6cd3ee496903e2206c51ffa3a13a5d10bc340b` | — | — |
| AppFlowy | `AppFlowy-IO/AppFlowy` | `5cf3a365dec0d59f64bad1ee4bb1050471a39b93` | — | — |
| AppFlowy（建置／appcast） | `AppFlowy-IO/AppFlowy-Builder` | `1a913f70f893cde6b5fbab1738731a7431488bb3` | — | — |
| Spotube | `KRTirtho/spotube` | `69a310c78f5ceaf4eab7dfee98f187d38211c9ba` | — | — |
| Hiddify | `hiddify/hiddify-app` | `276a7effb0046a039220a745022563740968c0b8` | — | — |
| Finamp | `jmshrv/finamp` | `0aae9d5ed530ffdf3d62ab12dab4f475a67687dc` | — | — |
| Harmonoid | `alexmercerind/harmonoid` | `2b021f7b0b5dbcbe027aec010580977a2939a28d` | — | — |
| Namida | `namidaco/namida` | `acb1e1622600440cc793f389f497e6771c732c5e` | — | — |
| NewPipe | `TeamNewPipe/NewPipe` | `7e5df38aad4b2c035332b3f71aee3064d4fdaae4` | dev | GPL-3.0 |
| LX Music Desktop | `lyswhut/lx-music-desktop` | `ad95d5091c9ed689fa72b5e5c849df65f5a679ce` | master | Apache-2.0 |
| Seal | `JunkFood02/Seal` | `7677f61a20fda4210e84215fef9e9b51d25daa47` | main | GPL-3.0 |
| Obtainium | `ImranR98/Obtainium` | `af286fa8d31d7406d6db167e2314d376d74f7696` | main | GPL-3.0 |
| release-please | `googleapis/release-please` | `edce3d805ef3ac964d1ba2b29b0f42905f2fa412` | main | Apache-2.0 |
| git-cliff | `orhun/git-cliff` | `60e0be97e945f71148172675be82399d382c9677` | main | Apache-2.0 OR MIT |
| semantic-release | `semantic-release/semantic-release` | `e8c2436e5704a6d1fa5b4aa69238f50edbe586bf` | master | MIT |
| conventional-changelog | `conventional-changelog/conventional-changelog` | `f90c80e9fe02146c1018fa1d78dea738809ab102` | master | ISC |

> Namida 的 repo 是 **`namidaco/namida`**（`namida-music/namida` 與 `vfsfitvnm/namida` 皆 404）；beta 版發在 `namidaco/namida-snapshots`。`hiddify/hiddify-next` 是 `hiddify/hiddify-app` 的**別名**（API 回傳 `full_name` 為 `hiddify/hiddify-app`）。

## 一句話總覽

| 專案 | 應用內更新？ | 實際行為 |
|---|---|---|
| LocalSend | 無 | 完全不檢查，只放連結 |
| **AppFlowy** | **有（真正自我更新）** | macOS 走 Sparkle appcast 下載＋替換；Linux 只丟連結；**Windows 有程式碼但官方 release 沒發 appcast，feed 404** |
| Spotube | 半套 | 啟動檢查（含 nightly），只彈對話框丟下載頁連結 |
| Hiddify | 半套 | `upgrader` appcast ＋ 自抓 GitHub API，只丟連結；**appcast 已停更在 0.13.6** |
| Finamp | 無 | 無檢查器；Windows 只產 MSIX |
| Harmonoid | 半套 | 啟動檢查 GitHub `releases/latest`，只丟連結 |
| Namida | 半套 | 啟動檢查（自寫，含 beta 通道與節流），只丟連結 |
| NewPipe | 半套 | 自架 JSON API 檢查，`ACTION_VIEW` 交瀏覽器；**manifest 無 `REQUEST_INSTALL_PACKAGES`** |
| LX Music Desktop | 有（Electron 標準解） | electron-updater 打 GitHub Releases；`autoDownload=false`；`quitAndInstall(true,true)`；**無簽章設定** |
| Seal | 有 | 自寫 updater 打 GitHub `/releases`；**只驗檔案大小**；FileProvider + `ACTION_VIEW` |
| Obtainium | 有 | 自寫，支援約 35 來源；**唯一做 APK 簽章憑證 hash 比對**；四種安裝器 |

**真正做到「下載＋安裝＋重啟」的只有兩類：桌面端的 Electron／Sparkle 系（LX Music、AppFlowy macOS），以及 Android 上自己實作安裝的 Seal／Obtainium。7 個 Flutter 專案中沒有任何一個在 Android 做 in-app 下載安裝 APK。**

---

# Part 1 — Flutter 桌面／行動專案

## 1. LocalSend

- repo `localsend/localsend` @ `6f6cd3ee496903e2206c51ffa3a13a5d10bc340b`

| 項目 | 結論 |
|---|---|
| 更新檢查 | **無**。`app/lib/pages/about/about_page.dart`（[permalink](https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/pages/about/about_page.dart#L1-L222)）全檔 grep `update`／`version`／`PackageInfo` **零命中**，只有官網／GitHub／Codeberg／授權／LicensePage／DebugPage 連結。`app/lib/provider/version_provider.dart` 只用 `PackageInfo.fromPlatform()` 取版本**顯示**，不比較、不連網。 |
| 版本比較 | 無（不適用） |
| 下載／安裝 | 無 in-app。使用者自行到 GitHub Releases／官網／商店取得。 |
| 驗證 | 無 app 內驗證。CI 對 Windows 產物做 **Azure Trusted Signing**（作業系統層信任簽章，非更新簽章）：`build_windows_exe.yml` [L61-L90](https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/.github/workflows/build_windows_exe.yml#L61-L90) 簽 MSIX helper 與 exe/dll，[L107-L130](https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/.github/workflows/build_windows_exe.yml#L107-L130) 以 `/SMySignTool` 讓 Inno 在編譯時同時簽 setup 與內嵌 uninstaller。 |
| Windows | Inno Setup 安裝檔（`support/scripts/compile_windows_exe-inno.iss`）＋ portable zip，`iscc` 見上。**無自我更新**。 |
| Android | manifest 有 `REQUEST_INSTALL_PACKAGES`（[L14](https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/android/app/src/main/AndroidManifest.xml#L14)）與 `QUERY_ALL_PACKAGES`（L13），但 `lib/` 內查不到下載／安裝 APK 的程式碼 —— **該權限用途查不到**（推測與其近場分享／快速設定磚流程有關，未能證實）。 |
| Linux | 無 in-app 更新（查不到任何 AppImage／deb 相關更新邏輯）。 |
| macOS | 查不到（`lib/` 無 Sparkle／appcast）。 |
| Release notes | `release-drafter/release-drafter@v6`（`.github/workflows/release.yml` [L86](https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/.github/workflows/release.yml#L86)），設定 `.github/release-drafter.yml`，模板連向 CHANGELOG.md 與 CODE_SIGNING.md。 |
| 版本策略 | 版本源頭是 `app/pubspec.yaml` [L7](https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/pubspec.yaml#L7) `version: 1.18.2+64`；CI 用 `sed -n 's/^version: \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p'` 抽出 X.Y.Z（[release.yml L78-L82](https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/.github/workflows/release.yml#L78-L82)），tag 為 `v<X.Y.Z>`（**不含 build number**，[L90](https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/.github/workflows/release.yml#L90)）。 |

## 2. AppFlowy（唯一真正的應用內自我更新）

- repo `AppFlowy-IO/AppFlowy` @ `5cf3a365dec0d59f64bad1ee4bb1050471a39b93`

| 項目 | 結論 |
|---|---|
| 更新檢查 | 用 `auto_updater` 套件（pubspec [L32](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/pubspec.yaml#L32) `auto_updater: ^1.0.0`，實際指向 fork `LucasXu0/auto_updater` 的 git 依賴 [L226-L241](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/pubspec.yaml#L226-L241)）。啟動時 `auto_update_task.dart` 建 feed URL：`https://github.com/AppFlowy-IO/AppFlowy/releases/latest/download/appcast-{os}-{arch}.xml`（[L20-L21](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/auto_update_task.dart#L20-L21)），`setFeedUrl` [L71](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/auto_update_task.dart#L71)、`checkForUpdateInformation()` [L72](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/auto_update_task.dart#L72)、`checkForUpdate()` [L98](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/auto_update_task.dart#L98)。**行動端跳過**（同檔以平台判斷 return，推測因 appcast 只服務桌面）。 |
| 自動／定時 | `version_checker.dart` [L28](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/shared/version_checker/version_checker.dart#L28) `autoUpdater.setScheduledCheckInterval(0)` → **關閉套件內建定時檢查**，改由啟動流程與 critical-update 監聽驅動（`isCriticalUpdateNotifier`，`device_info_task.dart` [L36](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/device_info_task.dart#L36)／[L47](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/device_info_task.dart#L47)／[L51](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/device_info_task.dart#L51)）。 |
| appcast 解析 | 自寫：`http.get` 抓 feed、`xml.XmlDocument.parse`、讀 `sparkle:shortVersionString`（`version_checker.dart` [L34-L43](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/shared/version_checker/version_checker.dart#L34-L43)），依賴 `xml: ^6.5.0`（pubspec [L146](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/pubspec.yaml#L146)）。 |
| 版本比較 | `version: ^3.0.2`（pubspec [L145](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/pubspec.yaml#L145)），比較式 `Version.parse(latestVersion) > Version.parse(applicationVersion)`（`device_info_task.dart` [L35](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/device_info_task.dart#L35)）。 |
| 下載／安裝 | macOS／Windows 由 `auto_updater`（Sparkle 系）下載並替換、需重啟；**Linux 明確只丟連結**：`checkForUpdate()` → `afLaunchUrlString('https://appflowy.com/download')`（`version_checker.dart` [L66-L71](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/shared/version_checker/version_checker.dart#L66-L71)）。 |
| 驗證 | **macOS**：Sparkle EdDSA `sparkle:edSignature`，`dart run auto_updater:sign_update -f PRIVATE_KEY app.dmg` 後寫入 appcast（AppFlowy-Builder `auto_update.yaml` [L102](https://github.com/AppFlowy-IO/AppFlowy-Builder/blob/1a913f70f893cde6b5fbab1738731a7431488bb3/.github/workflows/auto_update.yaml#L102)／[L115](https://github.com/AppFlowy-IO/AppFlowy-Builder/blob/1a913f70f893cde6b5fbab1738731a7431488bb3/.github/workflows/auto_update.yaml#L115)／[L144](https://github.com/AppFlowy-IO/AppFlowy-Builder/blob/1a913f70f893cde6b5fbab1738731a7431488bb3/.github/workflows/auto_update.yaml#L144)，arm64 為 [L219-L261](https://github.com/AppFlowy-IO/AppFlowy-Builder/blob/1a913f70f893cde6b5fbab1738731a7431488bb3/.github/workflows/auto_update.yaml#L219-L261)）。**Windows**：DSA `sparkle:dsaSignature`，`dart run auto_updater:sign_update app.exe`（[L375](https://github.com/AppFlowy-IO/AppFlowy-Builder/blob/1a913f70f893cde6b5fbab1738731a7431488bb3/.github/workflows/auto_update.yaml#L375) 起）。金鑰以 secret 名稱傳入（`WINDOWS_AUTO_UPDATE_PRIVATE_KEY`／`PRIVATE_KEY`），本檔不記錄其值。**Linux appcast 無 enclosure、無簽章**（[L492](https://github.com/AppFlowy-IO/AppFlowy-Builder/blob/1a913f70f893cde6b5fbab1738731a7431488bb3/.github/workflows/auto_update.yaml#L492) 只寫 `sparkle:os="linux"`）。appcast 另有 `sparkle:criticalUpdate` 支援（[L136-L137](https://github.com/AppFlowy-IO/AppFlowy-Builder/blob/1a913f70f893cde6b5fbab1738731a7431488bb3/.github/workflows/auto_update.yaml#L136-L137)）。 |
| Windows 關鍵落差 | 程式碼要求 feed `appcast-windows-x86_64.xml`（[L398](https://github.com/AppFlowy-IO/AppFlowy-Builder/blob/1a913f70f893cde6b5fbab1738731a7431488bb3/.github/workflows/auto_update.yaml#L398)），但實查 release `0.13.0`／`0.14.0`／`0.14.5` 的 assets **都只有** `appcast-macos-{x86_64,arm64}.xml` 與 `appcast-linux-x86_64.xml`，**沒有** Windows appcast（0.14.5 assets 共 16 個，含 `AppFlowy-0.14.5-windows-x86_64.exe` 與 `.zip`，仍無 appcast）。**Windows 的 auto_updater feed URL 會 404，Windows 的應用內更新實際上不會觸發。**（appcast 產生是手動 `workflow_dispatch`。） |
| Windows 安裝 | CI 用 Inno Setup，`iscc /F... inno_setup_config.iss /DAppVersion=<tag>`（AppFlowy `release.yml` [L102](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/.github/workflows/release.yml#L102)）。 |
| Android | release 有 `AppFlowy-0.14.5-android.apk`，但程式碼在行動端跳過 auto updater；in-app APK 安裝路徑**查不到**。 |
| Linux | 供 AppImage／deb／rpm／tar.gz（見 0.14.5 assets），更新走官網連結。 |
| macOS | dmg／zip ＋ appcast（EdDSA 簽章如上）。 |
| Release notes | 從 CHANGELOG.md 以 sed 抽當前 tag 段落（`release.yml` [L26](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/.github/workflows/release.yml#L26)），非工具產生。 |
| 版本策略 | **矛盾且未解**：release tag 為 `0.14.5`，但 pubspec [L7](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/pubspec.yaml#L7) 仍寫 `version: 0.11.4`；app 內版本取自 `ApplicationInfo.applicationVersion = packageInfo.version`（`device_info_task.dart` [L75](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/appflowy_flutter/lib/startup/tasks/device_info_task.dart#L75)）→ **推測**版本號在 build 時注入（`build_flowy.dart run . <tag>`，`release.yml` [L168](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/.github/workflows/release.yml#L168)／[L395](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/.github/workflows/release.yml#L395)），但 `tool.dart` 只把 tag 當 `--env APP_VERSION=$appVersion` 傳給 cargo make（[L41](https://github.com/AppFlowy-IO/AppFlowy/blob/5cf3a365dec0d59f64bad1ee4bb1050471a39b93/frontend/scripts/flutter_release_build/tool.dart#L41)），**沒有改寫 pubspec**；`package_info_plus` 在 macOS 讀 Info.plist、Windows 讀 exe 版本資源，兩者是否被注入**查不到**。 |

## 3. Spotube（檢查 → 丟連結）

- repo `KRTirtho/spotube` @ `69a310c78f5ceaf4eab7dfee98f187d38211c9ba`

| 項目 | 結論 |
|---|---|
| 更新檢查 | 啟動時 post-frame 呼叫 `ServiceUtils.checkForUpdates`（`lib/modules/root/use_global_subscriptions.dart` [L23](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/modules/root/use_global_subscriptions.dart#L23)）。實作 `lib/utils/service_utils.dart` [L229](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/utils/service_utils.dart#L229) 起。 |
| 雙通道 | nightly：打 GitHub Actions workflow-runs API，比 `run_number` 與 `packageInfo.buildNumber`（[L244-L265](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/utils/service_utils.dart#L244-L265)）。stable：`https://api.github.com/repos/KRTirtho/spotube/releases/latest`（[L271](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/utils/service_utils.dart#L271)）。 |
| 開關 | `Env.enableUpdateChecker => kIsFlatpak \|\| _enableUpdateChecker == "1"`（`lib/collections/env.dart` [L34-L35](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/collections/env.dart#L34-L35)）→ 可用 dart-define 關閉；**Flatpak 一律開啟**（推測：Flatpak 無法自行更新，故強制提示）。 |
| 版本比較 | `version` 套件 `Version.parse`（[L277-L279](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/utils/service_utils.dart#L277-L279)），並對 pre-release 標籤做不匹配防護與 `latestVersion <= currentVersion` 早退。 |
| 下載／安裝 | **無自動下載**。對話框只有按鈕 `launchUrlString`，目標 `https://spotube.krtirtho.dev/downloads`（`lib/modules/root/update_dialog.dart` [L17-L24](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/modules/root/update_dialog.dart#L17-L24)），nightly 另有 `/downloads/nightly`。 |
| 驗證 | release 附 md5／sha256 checksums（`.github/workflows/spotube-release-binary.yml`），**app 端不驗**（程式碼無雜湊／簽章比對）。 |
| Windows | Inno Setup（`windows/packaging/exe/inno_setup.iss`）；使用者下載 exe 自行安裝。 |
| Android | manifest **無** `REQUEST_INSTALL_PACKAGES`（實測 grep 命中 0）→ 走 GitHub／F-Droid／商店。 |
| Linux | Flatpak 強制檢查（見上），結果同樣只給下載頁連結。 |
| macOS | 查不到（推測：dmg 連結，未在樹內找到對應處理）。 |
| Release notes | release 由 `ncipollo/release-action@v1` 建立（nightly tag `nightly`，stable tag `v$PUBSPEC_VERSION`）；notes 內容產生方式查不到（推測手寫或 GitHub 自動）。 |
| 版本策略 | 版本源頭 `pubspec.yaml`；CI 抽出後 tag `v<version>`；nightly 用固定 tag `nightly`（非語意版本）。 |

## 4. Hiddify（`upgrader` appcast ＋ 自抓 API，但 appcast 已死）

- repo `hiddify/hiddify-app` @ `276a7effb0046a039220a745022563740968c0b8`

| 項目 | 結論 |
|---|---|
| 更新檢查 | 兩條並存：(a) `upgrader` 套件——`UpgraderAppcastStore(appcastURL: Constants.appCastUrl)` 依平台選 store（`lib/features/app_update/notifier/app_update_notifier.dart` [L23](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/lib/features/app_update/notifier/app_update_notifier.dart#L23)）；(b) 自寫 `check()`（[L50](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/lib/features/app_update/notifier/app_update_notifier.dart#L50) 起）打 GitHub releases API。 |
| 觸發點 | 啟動時 `UpgradeAlert(upgrader: upgrader, ...)`（`lib/features/app/widget/app.dart` L62／L94）；About 頁有「檢查更新」tile → `appUpdateNotifierProvider.notifier).check()`（`lib/features/about/widget/about_page.dart` [L44-L50](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/lib/features/about/widget/about_page.dart#L44-L50)）。 |
| 常數 | `githubReleasesApiUrl = "https://api.github.com/repos/hiddify/hiddify-next/releases"`、`appCastUrl = "https://raw.githubusercontent.com/hiddify/hiddify-next/main/appcast.xml"`（`lib/core/model/constants.dart` [L9-L11](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/lib/core/model/constants.dart#L9-L11)）。 |
| 自我抓取邏輯 | `httpClient.get<List>(Constants.githubReleasesApiUrl)`（`app_update_repository.dart` [L32](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/lib/features/app_update/data/app_update_repository.dart#L32)），`releases.firstWhere((e) => e.preRelease == false)`（[L43](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/lib/features/app_update/data/app_update_repository.dart#L43)）。 |
| 版本比較 | `Version.parse(remote.version)`（`app_update_notifier.dart` [L68](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/lib/features/app_update/notifier/app_update_notifier.dart#L68) 起），另有 `ignored_release_version` 忽略已略過的版本。 |
| 下載／安裝 | **無**。對話框「Update now」→ `UriUtils.tryLaunch(Uri.parse(newVersion.url))`（`lib/core/router/dialog/widgets/new_version_dialog.dart` [L60](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/lib/core/router/dialog/widgets/new_version_dialog.dart#L60)）→ 丟連結。 |
| 驗證 | appcast 項目**無簽章欄位**；GitHub release 亦查不到簽章。 |
| 通道差異 | `lib/core/model/environment.dart`：`Release.general \| googlePlay`，`allowCustomUpdateChecker => this == general`；`isPortable` 為 build flag（影響 Windows 是否用可攜版）。 |
| Windows | `flutter_distributor` 產 `exe,msix,zip`；MSIX 以 `windows/packaging/msix/make_config.yaml` 設定簽章。 |
| Android | manifest **無** `REQUEST_INSTALL_PACKAGES`（grep 0）；`Release.googlePlay` 走 `UpgraderPlayStore`。 |
| Linux／macOS | 走 `UpgraderAppcastStore`（appcast 有 mac 項目）／App Store 走 `UpgraderAppStore`。 |
| Release notes | **`gitchangelog` ＋ mustache 模板**：CI `pip install gitchangelog pystache mustache markdown`、取上一個 latest tag、`gitchangelog "${prelease}.." >> release.md`（`.github/workflows/build.yml` [L401-L404](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/.github/workflows/build.yml#L401-L404)），模板 `.release_notes.tpl`、設定 `.gitchangelog.rc`；release 以 draft／prerelease 建立（[L413-L428](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/.github/workflows/build.yml#L413-L428)、[L465-L466](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/.github/workflows/build.yml#L465-L466)）。 |
| 版本策略 | tag 形如 `v4.1.1`（實查 `releases/latest`）；pubspec 為版本源頭。 |
| **關鍵負面事實** | repo 根 `appcast.xml`（app 實際讀的那份）內容**停在 `sparkle:version="0.13.6"`**、`pubDate` 為 `Sun, 7 Jan 2024 22:00:00 +0000`（[L7](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/appcast.xml#L7) 與 [L1-L40](https://github.com/hiddify/hiddify-app/blob/276a7effb0046a039220a745022563740968c0b8/appcast.xml#L1-L40)），共 5 個項目、**無簽章**，其中一個 url 還寫成 `hhttps://`（壞的）。當前實際 latest 是 `v4.1.1` → **appcast 路徑實際上不會觸發更新**，真正會動的是自寫的 GitHub API 檢查。 |

## 5. Finamp（無應用內更新；Windows 只有 MSIX）

- repo `jmshrv/finamp` @ `0aae9d5ed530ffdf3d62ab12dab4f475a67687dc`

| 項目 | 結論 |
|---|---|
| 更新檢查 | **查不到任何更新檢查器**（`lib/` 內無 update checker／GitHub API 呼叫）。 |
| 版本比較 | 無 |
| 下載／安裝 | 使用者自商店／GitHub 取得。README 列 Play Store、F-Droid、App Store、GitHub APK（[L92-L105](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/README.md#L92-L105)、[L125-L126](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/README.md#L125-L126)），並註明 F-Droid 一天只建一次。 |
| 驗證 | app 端無。CI 建 MSIX 帶 `--install-certificate false`（`build.yml` [L391](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/.github/workflows/build.yml#L391)）→ 為未簽章／自簽流程；Android 由商店簽。 |
| Windows | **只產 MSIX**：`dart run msix:create --install-certificate false`（[L370-L395](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/.github/workflows/build.yml#L370-L395)），且有 TODO：**沒有傳統安裝器**（原文註解 "would be nice to have an old-school installer…"，[L395](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/.github/workflows/build.yml#L395)）。pubspec `build_windows: false`（[L280](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml#L280)）因 `msix:create` 內建 build 有 bug（註解 [L279](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml#L279)）；另有 `windows/runner/resources/MSIX_LOCAL_CERTIFICATE.pfx`。 |
| Android | 商店／APK 手動安裝；manifest **無** `REQUEST_INSTALL_PACKAGES`（grep 0）。 |
| Linux | `flutter build linux --release`（[L279](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/.github/workflows/build.yml#L279)），**無** AppImage／deb／rpm 打包。 |
| macOS | `build.yml` 有 macOS 區塊但被註解（[L442](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/.github/workflows/build.yml#L442) 附近）；使用者走 App Store。 |
| Release notes | assets 由 `alexellis/upload-assets@0.5.0` 在 tag push 時上傳（[L318](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/.github/workflows/build.yml#L318)、[L410](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/.github/workflows/build.yml#L410)）；notes 產生方式查不到（推測手寫）。另有 `beta-release.md` 與 `fastlane/metadata/android` 供商店文案。 |
| 版本策略 | pubspec `version: 1.0.1+201`（[L18](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml#L18)），但 `msix_config.msix_version: 1.0.1.0`（[L261-L265](https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/pubspec.yaml#L261-L265)）→ **Windows 版本號要另外手動同步**（四段式，與 pubspec 不同格式）。 |

## 6. Harmonoid（檢查 → 丟連結）

- repo `alexmercerind/harmonoid` @ `2b021f7b0b5dbcbe027aec010580977a2939a28d`

| 項目 | 結論 |
|---|---|
| 更新檢查 | constructor 內 `unawaited(check())`（`lib/features/update/state/update_notifier.dart` [L26](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/update/state/update_notifier.dart#L26)），`check()` [L34](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/update/state/update_notifier.dart#L34) 起；抓 `api.github.com/repos/harmonoid/harmonoid/releases/latest`（`lib/features/update/api/latest_release_get.dart` [L16](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/update/api/latest_release_get.dart#L16)）。 |
| 版本比較 | 用 `identity` 套件的 `compareVersions`（子模組 `external/identity`，**tarball 內不存在，實作查不到**）。版本常數 `kVersion = 'v0.3.34'`（`lib/utils/constants.dart` [L7](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/utils/constants.dart#L7)）。 |
| 略過機制 | 已提示版本記在 `Configuration.instance.updateCheckVersion`（[L48](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/update/state/update_notifier.dart#L48)、[L53](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/update/state/update_notifier.dart#L53)）；release body 若含 `SKIP_IN_APP_UPDATE_DIALOG` 則整個對話框略過（常數 [L20](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/update/state/update_notifier.dart#L20)）。 |
| 下載／安裝 | **無**。依平台丟連結：`kDownloadUrl = 'https://harmonoid.com/downloads'`（[L21](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/update/state/update_notifier.dart#L21)）、Android Play Store（[L22](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/update/state/update_notifier.dart#L22)）、iOS App Store（[L23](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/update/state/update_notifier.dart#L23)）。 |
| 驗證 | app 端無。macOS CI 有 codesign／notarize／`xcrun stapler`（`.github/workflows/master.yml` [L97-L127](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/.github/workflows/master.yml#L97-L127)）。 |
| Windows | Inno Setup（`Harmonoid_InnoSetup_x64.iss`，MyAppVersion `0.3.34.0`）；使用者自行下載安裝。 |
| Android | Play Store 連結；in-app APK 安裝查不到。 |
| Linux／macOS | 官網下載頁連結；macOS dmg 有公證。 |
| Release notes | `softprops/action-gh-release@v1`；**stable 先發到另一個 repo**（`secrets.REPOSITORY_2`，draft、tag `vnext`，[L130-L136](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/.github/workflows/master.yml#L130-L136)），snapshot 發到 `harmonoid/snapshots`（prerelease、tag `snapshot`，[L141-L147](https://github.com/alexmercerind/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/.github/workflows/master.yml#L141-L147)）；notes 產生方式查不到（推測 GitHub 自動／手寫）。 |
| 版本策略 | `kVersion` 常數與 `.iss` 的 `0.3.34.0` **手動同步**；tag 形式查不到（stable 走 draft `vnext`，推測發佈流程在另一 repo 完成）。 |

## 7. Namida（自寫檢查器最完整：雙通道＋節流）

- repo `namidaco/namida` @ `acb1e1622600440cc793f389f497e6771c732c5e`

| 項目 | 結論 |
|---|---|
| 更新檢查 | `VersionController` 啟動即抓；`Uri.https('api.github.com', '/repos/namidaco/$repoName/releases$endpoint', ...)`（`lib/controller/version_controller.dart` [L87-L89](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/controller/version_controller.dart#L87-L89)），`repoName = isBeta ? 'namida-snapshots' : 'namida'`（[L88](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/controller/version_controller.dart#L88)）→ **beta 通道走另一個 repo**。`/latest` 見 [L104](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/controller/version_controller.dart#L104)。 |
| 匿名／節流 | `const String? token = null`（[L90](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/controller/version_controller.dart#L90)）→ **匿名 API，未帶 token**（受 60 req/h 限制）；重抓節流 `Duration(hours: 2)`（[L61](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/controller/version_controller.dart#L61)）。另有分頁抓取與 422 處理。 |
| 版本比較 | **完全自寫** `VersionWrapper`（`lib/class/version_wrapper.dart` [L4](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/class/version_wrapper.dart#L4)）：build number 為 `yyMMddHHP` 格式 → 解析成 `DateTime`（[L44](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/class/version_wrapper.dart#L44)、[L49](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/class/version_wrapper.dart#L49)），`isAfter` 為逐段比對（[L66](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/class/version_wrapper.dart#L66) 起）。 |
| 下載／安裝 | **無**。更新 sheet 的 UPDATE 按鈕依 beta 選 `AppSocial.GITHUB_RELEASES` 或 `GITHUB_RELEASES_BETA`（`lib/ui/widgets/custom_widgets.dart` [L7432](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/ui/widgets/custom_widgets.dart#L7432)），常數 `lib/core/constants.dart` [L1038-L1039](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/core/constants.dart#L1038-L1039) → 丟連結。 |
| 驗證 | 無（無雜湊／簽章比對）。 |
| Windows／Linux／macOS | 查不到（推測：無桌面版；未在樹內找到對應平台發佈流程）。 |
| Android | manifest 有大量權限與 `QUERY_ALL_PACKAGES`（[L19](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/android/app/src/main/AndroidManifest.xml#L19)）、有 FileProvider（[L496-L504](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/android/app/src/main/AndroidManifest.xml#L496-L504)，推測給分享／快取用），但**沒有** `REQUEST_INSTALL_PACKAGES` → **不支援 in-app APK 安裝**。 |
| Release notes | **自寫 Python** `scripts/chlog.py`：依 conventional-commit prefix 分類（`CHANGELOG_PREFIXES = ("feat","core","perf","chore","fix")`，[L41](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/scripts/chlog.py#L41)），固定三個段落 `### ✨ Highlights:`／`### 🎉 New Features:`／`### 🛠️ Bug fixes & Improvements:`（[L52-L54](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/scripts/chlog.py#L52-L54)）。CI `python3 scripts/chlog.py beta --repo <target>`（`.github/workflows/release_beta.yml` [L96-L100](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/.github/workflows/release_beta.yml#L96-L100)），再以 `gen_downloads_table.sh` 併下載表，最後 `softprops/action-gh-release@v3` ＋ `body_path: ./beta_changelog.md`（[L114-L120](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/.github/workflows/release_beta.yml#L114-L120)）。 |
| 版本策略 | pubspec `version: 7.5.0-beta+260927218`（[L4](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/pubspec.yaml#L4)，build number 即上述時戳格式）；`bump_version.dart` 會自動改寫 pubspec version 行（[L13-L59](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/bump_version.dart#L13-L59)）；CI 抽 `version:.*` 後，**stable tag 用 `v<X.Y.Z>`、beta tag 用含 build 的完整 version**（[L90](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/.github/workflows/release_beta.yml#L90)、[L93](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/.github/workflows/release_beta.yml#L93)）。 |

### 1.8 本組橫向比較

**更新能力光譜**

| 光譜位置 | 專案 | 依據 |
|---|---|---|
| 下載＋替換＋重啟（真正自我更新） | AppFlowy（僅 macOS；Linux 是連結） | Sparkle 系 `auto_updater`，appcast 帶 `sparkle:edSignature` |
| 檢查＋提示＋丟下載連結 | Spotube、Hiddify、Harmonoid、Namida | 四者都在啟動時檢查、只開瀏覽器 |
| 完全不檢查 | LocalSend、Finamp | 樹內查不到任何 update checker |

**檢查機制對照**

| 專案 | 來源 | 觸發 | 通道 | 節流／限制處理 |
|---|---|---|---|---|
| AppFlowy | 自家 release 的 appcast XML（`releases/latest/download/...`） | 啟動 task ＋ critical-update 監聽；套件定時檢查關閉（interval 0） | stable 單一 | 關掉自動定時，改事件驅動 |
| Spotube | GitHub `releases/latest`（stable）／Actions runs API（nightly） | 啟動 post-frame | nightly ＋ stable | 可用 dart-define 關；Flatpak 強制開 |
| Hiddify | `upgrader` appcast（**已死**）＋ 自抓 `releases` API | 啟動 `UpgradeAlert` ＋ About 頁按鈕 | general／googlePlay 變體 | `ignored_release_version` |
| Harmonoid | GitHub `releases/latest` | constructor 即檢查 | stable | `updateCheckVersion`；body 可 `SKIP_IN_APP_UPDATE_DIALOG` |
| Namida | GitHub `releases/latest` | 啟動即抓 | **beta repo 分離**（`namida-snapshots`） | 2 小時節流、匿名 token=null、422 處理、分頁 |

**版本比較實作**

| 做法 | 專案 |
|---|---|
| `version` 套件 `Version.parse` | AppFlowy、Spotube、Hiddify |
| 完全自寫 | Namida（`VersionWrapper`，把 `yyMMddHHP` 轉時間）、Harmonoid（`identity.compareVersions`，實作查不到） |
| 不做比較 | LocalSend、Finamp |

**Release notes 工具**

| 做法 | 專案 |
|---|---|
| 現成套件 `release-drafter` | LocalSend |
| `gitchangelog` ＋ mustache 模板 | Hiddify |
| 自寫 Python（conventional prefix 分類＋固定段落） | Namida |
| 直接 sed 抽 CHANGELOG.md 段落 | AppFlowy |
| 只上傳 assets，notes 方式查不到 | Spotube、Finamp、Harmonoid |

**Windows 打包**

| 做法 | 專案 |
|---|---|
| Inno Setup（＋程式碼簽章） | LocalSend（Azure Trusted Signing）、Spotube、AppFlowy、Harmonoid |
| 只有 MSIX、明說沒有傳統安裝器 | Finamp |
| exe／msix／zip（flutter_distributor） | Hiddify |

**Android in-app APK 安裝**

**七個專案都做不到／沒做**：Spotube、Hiddify、Finamp、Namida 的 manifest 均**無** `REQUEST_INSTALL_PACKAGES`；LocalSend 有該權限但樹內查不到對應安裝程式碼；AppFlowy 有發 APK 但行動端跳過 updater。**沒有任何一個示範了程式內下載並觸發系統安裝 APK 的完整流程。**

**本組事實層面觀察**

- 這 7 個專案中，**只有 1 個（AppFlowy，且只在 macOS）**真的做到下載＋替換；其餘 6 個即使有檢查器也止於「開瀏覽器」。
- 「檢查更新」的**主流來源是 GitHub Releases API**（Spotube、Hiddify、Harmonoid、Namida 四家），而非自架後端；代價是匿名 60 req/h 與需要節流（只有 Namida 有 2 小時節流）。
- **release notes 自動化在桌面／行動 OSS 並不普遍**，且做法分歧（release-drafter／gitchangelog／自寫 Python／sed 抽 CHANGELOG 各一家）。
- **Windows 自我更新是公認的痛點**：這批專案要嘛只做 Inno 安裝檔（無更新），要嘛（AppFlowy）連 feed 都沒發出來。
- **Android in-app 安裝 APK 沒人做**，全部走商店或叫使用者自己去 GitHub 抓。

---

# Part 2 — Android 原生與 Electron 桌面

## 8. NewPipe（TeamNewPipe/NewPipe，Android 原生）

### 8.1 更新檢查的來源：自架 API，不是 GitHub Releases

- **事實**：檢查端點是寫死的常數 `https://newpipe.net/api/data.json`：
  [`NewVersionWorker.kt#L162`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/NewVersionWorker.kt#L162)
  `private const val NEWPIPE_API_URL = "https://newpipe.net/api/data.json"`
- **事實**：因此**不是** GitHub Releases、**不是** `teamnewpipe.github.io`、也**不是** F-Droid 的 index（API 只是把 F-Droid 的 APK 路徑轉發出來）。APK 由 `archive.newpipe.net` 托管。
- 查證日實抓 `https://newpipe.net/api/data.json` 的回應結構（摘錄）：

```
flavors.newpipe = { apk: "https://archive.newpipe.net/fdroid/repo/NewPipe_v0.29.1.apk",
                    hash: "18447bfb…", hash_type: "sha256",
                    version: "0.29.1", version_code: 1015 }
另有 flavors.fdroid、flavors.github.stable、stats
```

### 8.2 解析流程

- **事實**：[`NewVersionWorker.kt#L130-L135`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/NewVersionWorker.kt#L130-L135)：`response.responseBody()).getObject("flavors")` → 取 `getString("version")`、`getInt("version_code")`、`getString("apk")`。
- **事實（關鍵）**：用戶端只讀 `version` / `version_code` / `apk` 三個欄位，**完全沒有讀 `hash` / `hash_type`** —— API 提供了 sha256，但 App 不做任何 checksum 驗證。（以該檔全文為依據。）

### 8.3 只對「官方簽章版」啟用檢查

- **事實**：[`ReleaseVersionUtil.kt#L15`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/util/ReleaseVersionUtil.kt#L15) 定義官方 release 憑證公鑰 SHA-256（值不在此轉錄）；
  [`L19-L26`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/util/ReleaseVersionUtil.kt#L19-L26) `isReleaseApk` 用 `PackageInfoCompat.hasSignatures(pm, packageName, certificates, false)` 搭配 `PackageManager.CERT_INPUT_SHA256` 比對。
- **事實**：[`NewVersionWorker.kt#L93`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/NewVersionWorker.kt#L93) `if (!ReleaseVersionUtil.isReleaseApk) return` —— 官方簽章以外的任何 build（含 F-Droid 版、自編版）直接跳過更新檢查。
- **事實（區分）**：這裡的簽章檢查是**自我識別用**（判斷自己是不是官方版），**不是下載物驗證**。

### 8.4 檢查頻率與快取

- **事實**：[`L102`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/NewVersionWorker.kt#L102) `isLastUpdateCheckExpired(expiry)`；[`L117`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/NewVersionWorker.kt#L117) `coerceUpdateCheckExpiry(response.getHeader("expires"))`；[`L119`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/NewVersionWorker.kt#L119) 寫入 `update_expiry_key`。
- **事實**：[`ReleaseVersionUtil.kt#L46-L50`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/util/ReleaseVersionUtil.kt#L46-L50)：`nowPlus6Hours` 為下限、`nowPlus6Hours.plusHours(66)` 為上限 → 伺服器給的 `expires` 被夾在 **6h～72h**。檢查頻率由伺服器控制，非使用者設定。
- **事實**：有測試覆蓋 `app/src/test/java/org/schabi/newpipe/NewVersionManagerTest.kt`（5 個測試，涵蓋到期與未到期、6h/72h 夾取）。

### 8.5 使用者設定與首次同意

- **事實**：[`app/src/main/res/xml/update_settings.xml`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/res/xml/update_settings.xml)：一個 `SwitchPreferenceCompat`（key `update_app_key`，預設 **false**）＋ 一個 `Preference`（key `manual_update_key`，手動檢查）。**沒有「檢查頻率」選項**。
- **事實**：[`UpdateSettingsFragment.java`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/settings/UpdateSettingsFragment.java)：`askForConsentToUpdateChecks()` / `wasUserAskedForConsent`（key `update_check_consent_key`）負責首次進入時的同意對話框。
- **事實**：[`MainActivity.java#L197`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/MainActivity.java#L197) 同意閘門、[`L200`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/MainActivity.java#L200) 呼叫 `askForConsentToUpdateChecks`、[`L224`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/MainActivity.java#L224) 入列 `enqueueNewVersionCheckingWork(app, false)`。

### 8.6 不做安裝 —— 交棒給瀏覽器

- **事實**：[`NewVersionWorker.kt#L59`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/NewVersionWorker.kt#L59)：`val intent = Intent(Intent.ACTION_VIEW, apkLocationUrl?.toUri())`，包進 notification 的 `PendingIntent`。→ App 只「開一個 URL」，下載與安裝都交給系統瀏覽器，自己不經手 APK 檔案。
- **事實**：版本比較與通知邏輯在同檔 [`L39`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/java/org/schabi/newpipe/NewVersionWorker.kt#L39) `compareAppVersionAndShowNotification`；已是最新版時（手動觸發 `IS_MANUAL`）跳 `app_update_unavailable_toast`。

### 8.7 權限與 FileProvider

- **事實**：[`app/src/main/AndroidManifest.xml#L6-L14`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/AndroidManifest.xml#L6-L14) 宣告的權限：`INTERNET`、`WAKE_LOCK`、`ACCESS_NETWORK_STATE`、`WRITE_EXTERNAL_STORAGE`、`SYSTEM_ALERT_WINDOW`、`FOREGROUND_SERVICE`（含 `DATA_SYNC` / `MEDIA_PLAYBACK`）、`POST_NOTIFICATIONS`。**沒有 `REQUEST_INSTALL_PACKAGES`**（本次抽驗逐行確認，與「不在 App 內安裝」的設計一致）。
- **事實**：[`#L157-L164`](https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/app/src/main/AndroidManifest.xml#L157-L164) 有宣告 FileProvider（`android:authorities="${applicationId}.provider"`、`exported=false`、`android:resource="@xml/nnf_provider_paths"`）。
- **事實（本次抽驗確認）**：`@xml/nnf_provider_paths` 指向的檔案在該 SHA 的**完整遞迴 tree 中不存在**（`truncated: false`；以 `nnf_provider|provider_paths` 比對全部路徑無命中），直接取 `app/src/main/res/xml/nnf_provider_paths.xml` 回 **404**。→ 該 SHA 處於一個**懸空引用**的狀態。此為事實陳述，非推測。

### 8.8 「忽略版本」

- **事實**：在該 SHA 的 `app/src/main/res/values/strings.xml` 中搜不到 ignore-version 相關字串（僅有無關的 `ignore_hardware_media_buttons_*`）。**NewPipe 沒有「忽略此版本」功能**。

### 8.9 小結

| 面向 | NewPipe 做法 |
|---|---|
| 來源 | 自架靜態 JSON API（`newpipe.net/api/data.json`），非 GitHub |
| 驗證 | 只驗「自己是不是官方簽章版」；**不驗下載物**（API 給了 sha256 但沒用） |
| 安裝 | 不做；`ACTION_VIEW` 開瀏覽器 |
| 權限 | 無 `REQUEST_INSTALL_PACKAGES` |
| 頻率 | 伺服器 `expires` 標頭，夾在 6–72h；使用者只能開/關 |
| 忽略版本 | 無 |

## 9. LX Music Desktop（lyswhut/lx-music-desktop，Electron + electron-updater）

### 9.1 Feed 來源：GitHub Releases

- **事實**：[`build-config/build-pack.js#L46-L52`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/build-config/build-pack.js#L46-L52)：

```
publish: [{ provider: 'github', owner: 'lyswhut', repo: 'lx-music-desktop' }]
```

electron-builder 的 publish provider 指向 GitHub Releases → electron-updater 讀 `latest.yml`。

### 9.2 打包目標

- **事實**：同檔 [`L59`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/build-config/build-pack.js#L59) `win:`、[`L64`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/build-config/build-pack.js#L64) `nsis: { oneClick: false, language: '2052', allowToChangeInstallationDirectory: true, shortcutName: 'LX Music' }`、[`L78`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/build-config/build-pack.js#L78) `linux:`、[`L98`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/build-config/build-pack.js#L98) `appImage:`、[`L108`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/build-config/build-pack.js#L108) `mac:`、[`L113`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/build-config/build-pack.js#L113) `dmg:`。
- **事實**：`createTarget` 對應：`setup`→`nsis`、`green`→`7z`、`win7_setup`→`nsis`、`win7_green`→`7z`、`portable`→`portable`；Linux 有 `deb` / `appImage` / `pacman` / `rpm`；**macOS 只有 `dmg`，沒有 `zip`**。
- **推測**：macOS 的 electron-updater 自動更新通常需要 `zip` 目標才能自我替換 App bundle；只有 `dmg` 時 macOS 端自動更新很可能不可用（或只能引導手動下載）。此為從打包設定推得，未在官方文檔找到明確說明。

### 9.3 簽章設定：repo 內完全沒有

- **事實**：在 `build-pack.js` 與 `build-config/` 下搜不到 `certificateSubjectName`、`publisherName`、`notarize`、`verifyUpdateCodeSignature` 任何一項。→ Windows/macOS 都沒有程式碼簽章設定。
- **推測**：electron-updater 對 Windows 的 `verifyUpdateCodeSignature` 預設行為未從本 repo 原始碼確認（該邏輯在 electron-updater 套件內，不在本 repo）；由於專案未簽章，任何依賴簽章驗證的路徑都無法生效。**未確認**。

### 9.4 更新流程（主行程）

- **事實**：[`src/main/modules/winMain/autoUpdate.ts`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winMain/autoUpdate.ts)：
  - [`L8`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winMain/autoUpdate.ts#L8) `autoUpdater.autoDownload = false` → 不自動下載，等使用者按。
  - [`L113`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winMain/autoUpdate.ts#L113) `if (!autoUpdater.isUpdaterActive()) return`；[`L114`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winMain/autoUpdate.ts#L114) `downloadUpdate()`；[`L121`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winMain/autoUpdate.ts#L121) `quitAndInstall(true, true)`（`isSilent=true, isForceRunAfter=true`）。
  - **事實**：[`L140-L145`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winMain/autoUpdate.ts#L140-L145)：註解「由于集合安装包中不包含win arm版…」→ Windows ARM 直接回報 `update_error: 'failed'`；其餘平台依 `global.lx.appSetting['common.tryAutoUpdate']` 決定 `autoDownload` 後 `checkForUpdates()`。

### 9.5 第二條獨立的版本資訊管道（renderer）

- **事實**：[`src/renderer/utils/update.js#L9-L17`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/utils/update.js#L9-L17)：除 electron-updater 外，另有一份 `publish/version.json` 的鏡像清單（3 次重試、10 秒 timeout）：
  `raw.githubusercontent.com`（master）、`registry.npmjs.org/lx-music-desktop-version-info/latest`、jsdelivr 三個節點（cdn / fastly / gcore）、`registry.npmmirror.com`、`gitee.com/lyswhut/lx-music-desktop-versions`、`http://cdn.stsky.cn/lx-music/desktop/version.json`。
- **事實**：此設計對應「中國境內可達性」需求 —— 同時維護 GitHub、npm、jsdelivr、npmmirror、gitee、自架 CDN 六類來源。

### 9.6 使用者設定、忽略版本、失敗節流

- **事實**：[`src/renderer/core/useApp/useUpdate.ts`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/core/useApp/useUpdate.ts)：
  - `getIgnoreVersion()` → `if (result.version === ignoreVersion) return` —— **有「忽略此版本」**。
  - `localStorage` key `update__check_failed_tip`，節流 **7 天**（`7 * 86400000`）才再提示一次檢查失敗。
  - 下載 1 小時 timeout 的 modal；用 `compareVer` 偵測降級（downgrade）；changelog 取自 `versionInfo.newVersion.history` 中對應版本。
- **事實**：[`src/renderer/views/Setting/components/SettingUpdate.vue`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/views/Setting/components/SettingUpdate.vue)：公開設定只有 `common.tryAutoUpdate`（嘗試自動更新）與 `common.showChangeLog`（顯示更新日誌）；**沒有檢查頻率設定**。畫面顯示當前/最新版本、commit id 與日期、下載進度。

### 9.7 發佈流程與 changelog 產生方式

- **事實**：[`.github/workflows/release.yml`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/.github/workflows/release.yml)：4 個 job（Windows：`publish:win:7z:x64`、`7z:arm64`、`setup:arm64`、`setup:x64`；Windows_7；Mac：`publish:mac:dmg` x64+arm64；Linux：deb amd64/arm64/armv7l、appImage、rpm、pacman）。用 `GITHUB_TOKEN` 與 `BT_TOKEN`，最後用 `Get-FileHash -Algorithm MD5` / `md5sum` 產生 release 附件。
- **事實**：[`publish/utils/updateChangeLog.js`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/publish/utils/updateChangeLog.js)：**changelog 是手寫的**（`publish/changeLog.md`），由腳本攤平進 `publish/version.json`（`desc` ＋ 前插 `history[]`）並 bump `package.json` 版本。
- **事實**：[`publish/utils/parseChangelog.js`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/publish/utils/parseChangelog.js)：以 regex 解析 `CHANGELOG.md` 中 `## [x.y.z](url) - YYYY-MM-DD` 形式的標題。`publish/index.js` 負責編排，失敗時把 `version.json` / `package.json` 回滾。
- **事實**：LX Music **完全沒有用** Conventional Commits 工具鏈，changelog 純人工撰寫。

### 9.8 小結

| 面向 | LX Music Desktop |
|---|---|
| 機制 | electron-updater（Electron 標準解） |
| Feed | GitHub Releases（`latest.yml`）＋ 6 類鏡像的 `version.json` |
| 自動下載 | 預設關（`autoDownload=false`），使用者按才下 |
| 安裝 | `quitAndInstall(true, true)` 靜默 + 裝完自動啟動 |
| 簽章 | repo 內**完全沒有**簽章/公證設定 |
| 忽略版本 | 有 |
| 檢查頻率 | 無設定；失敗提示節流 7 天 |
| changelog | 手寫，非 Conventional Commits 工具鏈 |

## 10. Seal（JunkFood02/Seal，Android）

### 10.1 自寫 updater，沒有第三方套件

- **事實**：[`app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt) 全自寫（OkHttp + kotlinx.serialization）。repo 內**沒有** `android-updater`、`com.github.javiersantos` 之類的第三方 updater 依賴。

### 10.2 來源：GitHub Releases API

- **事實**：[`L43-L45`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L43-L45) `requestForLatestRelease` → `https://api.github.com/repos/JunkFood02/Seal/releases/latest`（**宣告但未使用**，dead code）。
- **事實**：[`L48-L49`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L48-L49) `requestForReleases` → `https://api.github.com/repos/JunkFood02/Seal/releases`（實際使用）；[`L78`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L78) `client.newCall(requestForReleases)`；[`L80`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L80) 依 `UPDATE_CHANNEL`（`STABLE`）；[`L84`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L84) `maxByOrNull { it.name.toVersion() }` 取最新；[`L88`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L88) `checkForUpdate()`。

### 10.3 下載與 ABI 選擇

- **事實**：[`L142`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L142) `downloadApk()`；[`L162`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L162) `preferredArch = Build.SUPPORTED_ABIS.firstOrNull()`；[`L167-L169`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L167-L169) 以 `it.name?.contains(preferredArch)` 挑 asset，取 `browserDownloadUrl`。
- **事實**：存到 `getExternalFilesDir("apk")/latest.apk`；若已下載的 APK 其 `versionName >= release.name.toVersion()` 則跳過重下。

### 10.4 驗證：只有檔案大小

- **事實**：[`L212-L213`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L212-L213)：只檢查 `progressBytes < totalBytes` → "missing bytes"、`progressBytes > totalBytes` → "too many bytes"。→ **沒有 checksum 驗證、沒有簽章驗證**。
- **事實**：自寫的 `Version` sealed class（Alpha / Beta / ReleaseCandidate / Stable，帶數值權重），regex `v?(\d+)\.(\d+)\.(\d+)(-(\w+)\.(\d+))?`。另有一支獨立的 `updateYtDlp()`（走 `YoutubeDL.UpdateChannel.STABLE / NIGHTLY`，更新 youtubedl-android 的 binary，與 App 自身更新無關）。

### 10.5 安裝：FileProvider + ACTION_VIEW

- **事實**：[`L107-L117`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/util/UpdateUtil.kt#L107-L117) `installLatestApk()`：`FileProvider.getUriForFile(this, getFileProvider(), getLatestApk())` ＋ `Intent(ACTION_VIEW)` 配 `setDataAndType(contentUri, "application/vnd.android.package-archive")` 與 `FLAG_GRANT_READ_URI_PERMISSION`。
- **事實**：**不是** `PackageInstaller` session，也沒有 `setRequireUserAction`／安裝器-of-record 靜默安裝。

### 10.6 權限與「未知來源」引導

- **事實**：[`app/src/main/java/com/junkfood/seal/ui/page/AppUpdater.kt#L50`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/ui/page/AppUpdater.kt#L50) `canRequestPackageInstalls()`；[`L53`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/ui/page/AppUpdater.kt#L53) 以 `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` ＋ `package:${context.packageName}` 引導使用者開權限；[`L94`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/ui/page/AppUpdater.kt#L94) `launcher.launch(Manifest.permission.REQUEST_INSTALL_PACKAGES)`。
- **事實**：[`L64`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/ui/page/AppUpdater.kt#L64) 先檢查 `isNetworkAvailableForDownload()` 與 `isAutoUpdateEnabled()`；[`L69`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/ui/page/AppUpdater.kt#L69) `UpdateUtil.checkForUpdate()`。
- **事實**：[`AndroidManifest.xml#L15`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/AndroidManifest.xml#L15) `<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />`；[`#L121-L129`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/AndroidManifest.xml#L121-L129) FileProvider `${applicationId}.provider` 配 `@xml/provider_paths`。

### 10.7 Product flavors —— F-Droid 版關掉 updater

- **事實**：[`app/build.gradle.kts#L117`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/build.gradle.kts#L117) `flavorDimensions += "publishChannel"`，三個 flavor：`generic`（預設）、`githubPreview`（`.preview` 後綴，名稱 "Seal Preview"）、`fdroid`（versionName 後綴 `-(F-Droid)`）。同檔 [`L50`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/build.gradle.kts#L50) `versionCode = 200_000_150`；`applicationVariants` 內加 ABI 代碼，產物名 `Seal-${versionName}-${name}.apk`。
- **事實**：[`app/src/main/java/com/junkfood/seal/App.kt#L222`](https://github.com/JunkFood02/Seal/blob/7677f61a20fda4210e84215fef9e9b51d25daa47/app/src/main/java/com/junkfood/seal/App.kt#L222) `fun isFDroidBuild(): Boolean = BuildConfig.FLAVOR == "fdroid"`；`UpdatePage.kt` 中 `showUnavailableDialog = App.isFDroidBuild()`。→ F-Droid 版一律停用應用內更新器。
- **事實**：`UpdatePage.kt` 的設定：`AUTO_UPDATE`、`UPDATE_CHANNEL`（預設 `STABLE`）、`PRE_RELEASE`。repo 另有 `fastlane/metadata/android/<locale>/changelogs/<versionCode>.txt`（F-Droid 的 changelog 慣例）與 `CHANGELOG.md`。

### 10.8 小結

| 面向 | Seal |
|---|---|
| 機制 | 全自寫（OkHttp + kotlinx.serialization），無第三方 updater |
| 來源 | GitHub Releases API（`/releases`，非 `/latest`） |
| 驗證 | **只有檔案大小**；無 checksum、無簽章 |
| 安裝 | FileProvider + `ACTION_VIEW`，非 PackageInstaller |
| 權限 | `REQUEST_INSTALL_PACKAGES` + 引導 `ACTION_MANAGE_UNKNOWN_APP_SOURCES` |
| flavors | `generic` / `githubPreview` / `fdroid`；**fdroid 版停用更新器** |
| ABI | 用 `SUPPORTED_ABIS.first()` 挑 asset |

## 11. Obtainium（ImranR98/Obtainium，Android）

Obtainium 本身即「從 GitHub Releases 更新 App」的工具，其自我更新路徑與它給其他 App 用的路徑同源。

### 11.1 GitHub 檢查：API、分頁、認證

- **事實**：[`lib/app_sources/github.dart`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart)：
  - [`L855-L874`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L855-L874) `getLatestAPKDetails`：URL `…/${useTagUrl ? 'tags' : 'releases'}?per_page=100` —— **只發一次請求，沒有分頁迴圈**；`tags` fallback 只在 `trackOnly == true` 時使用。
  - [`L310-L311`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L310-L311) `getAPIHost` → `https://api.github.com`。
  - [`L241-L264`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L241-L264) `getRequestHeaders`：[`L253`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L253) `headers[HttpHeaders.authorizationHeader] = 'Token $token'`；[`L256`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L256) 下載 APK 時 `accept = 'application/octet-stream'`。
  - **事實**：**沒有 `If-None-Match` / ETag 條件請求、沒有 `Cache-Control`**（以該檔與 `app_source.dart` 全文為依據）→ 每次檢查都實打 API，消耗 rate limit。
  - **事實**：認證來源 [`L31`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L31) `github-creds`（密碼欄位，helpUrl 指向 GitHub fine-grained PAT 文檔）；[`L39`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L39) `GHReqPrefix`（預設提示 `gh-proxy.com`，helpUrl 指向 `sky22333/hubproxy`）；[`L61`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L61) `checkRepoRename`。

### 11.2 Rate limit 與認證失敗的 fallback

- **事實**：[`L957-L970`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L957-L970) `rateLimitErrorCheck`：`if (res.headers['x-ratelimit-remaining'] == '0')` → 由 `x-ratelimit-reset` 算重試時間（fallback 為 now + 3600，見 [`L15`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L15) `_fallbackCacheSeconds = 3600`）→ `throw RateLimitError(remainingMinutes)`。注意該常數是**重試時間的 fallback**，不是回應快取。
- **事實**：[`L976-L992`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L976-L992) `githubErrorCheck`：先判 rate limit，再判非 rate limit 的 401/403 → `ObtainiumError`；[`L315-L325`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L315-L325) `_isAuthRejection`：401/403 且 body message 含 "access token" / "bad credentials"。
- **事實**：[`L329-L345`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L329-L345) `_sourceRequestWithAuthFallback`：**去掉 token 重試一次**（`skipAuth=true`，對應 issue #3211）—— 「token 過期不該讓更新完全失敗」的設計。
- **事實**：[`L266-L288`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L266-L288) `getTokenIfAny`（清掉舊格式的 `username:` 前綴）；[`L292`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L292) `getSourceNote` 在沒 token 時給提示。代理：[`L302-L307`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L302-L307) `generalReqPrefetchModifier` 把請求改寫走 GHReqPrefix。repo 改名：[`L347-L351`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L347-L351) `convertStandardUrlToAPIUrl`；[`L360-L406`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L360-L406) `checkForRepositoryRename`（`followRedirects: false`，≥300 就讀 `Location` → 取 `html_url` → 丟 `RepositoryRenamedError`）。
- **事實**：[`L690-L826`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/app_sources/github.dart#L690-L826) `_fetchReleaseDetails`：排序、prerelease fallback、regex 標題/內文過濾、`effectiveMinUpdateAgeDays`、`verifyLatestTag`（打 `/latest` 驗證）、`NoReleasesError` / `NoVersionError`。
- **事實**：來源層設定包括 `includePrereleases`、`fallbackToOlderReleases`、`filterReleaseTitlesByRegEx`、`filterReleaseNotesByRegEx`、`verifyLatestTag`、`sortMethodChoice`（date / smartname / none / smartname-datefallback / name）、`useLatestAssetDateAsReleaseDate`、`releaseTitleAsVersion`。

### 11.3 四個專案中唯一做真實驗證的

- **事實**：[`lib/utils/signing_cert_utils.dart`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/utils/signing_cert_utils.dart)：
  - [`L13-L19`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/utils/signing_cert_utils.dart#L13-L19) `formatCertHash` = SHA-256 of DER → 大寫、冒號分隔。
  - [`L25-L28`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/utils/signing_cert_utils.dart#L25-L28) `certHashesFromSigningInfo`：多簽章者用 `signingInfo.apkContentSigners`，否則用 `signingCertificateHistory`。
  - [`L43`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/utils/signing_cert_utils.dart#L43) `apkFilesSigningCertHashes`：base + split APK 取聯集。
  - [`L66`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/utils/signing_cert_utils.dart#L66) `parseAllowedSigningCertHashes`；`_certHashHex = RegExp(r'^[0-9a-fA-F]{64}$')`。
- **事實**：[`lib/providers/apps_provider_install.dart#L1305-L1400`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/apps_provider_install.dart#L1305-L1400) `_verifyDownloadedApkSignatures` 的三段邏輯：
  1. `userHashes` = 該 App 的 `allowedSigningCertHashes`（使用者預先設定）→ **不符即硬封鎖，無覆寫**（`SigningCertMismatchError(hardBlock: true)`）；若 `apkHashes.isEmpty` 而使用者有設定，也封鎖。
  2. 若 `settingsProvider.verifySigningCertHashes`（[`settings_provider.dart#L870-L875`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L870-L875)，**預設 true**；本次抽驗確認原始碼為 `_getBool('verifySigningCertHashes') ?? true`）且已安裝版本有 hash，而新 APK 不一致 → 軟性對話框 `SigningCertMismatchDialog(hardBlock: false)`，可「仍然安裝」（背景情境則封鎖）。
  3. [`L1317`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/apps_provider_install.dart#L1317) 用 `parseAllowedSigningCertHashes`；[`L1320`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/apps_provider_install.dart#L1320) `appEntry.certificateHashes`；[`L1454-L1455`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/apps_provider_install.dart#L1454-L1455) `apkSigningCertHashes` / `apkFilesSigningCertHashes`。
- **事實（範圍）**：**這仍是簽章比對，不是「發佈者提供的 checksum」驗證。** 全 repo 搜不到 checksum 相關實作；出現的 hash 只有「簽章憑證 hash」與「部分下載／ETag 的識別碼」兩類。
- **事實（非驗證的臨近機制）**：[`lib/providers/apps_provider.dart#L229-L249`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/apps_provider.dart#L229-L249) `checkPartialDownloadHashDynamic`：對同一 URL 發兩次 `Range: bytes=0-N` 比對 hash，用途是**偵測遠端檔案已變更**（續傳正確性）。同檔 [`L280-L306`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/apps_provider.dart#L280-L306) `checkETagHeader` 把 ETag 字串 hash 成 12 碼當識別碼用，**不是**條件請求。

### 11.4 下載重試與安裝器

- **事實**：[`lib/providers/apps_provider.dart#L172-L217`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/apps_provider.dart#L172-L217) `downloadFileWithRetry`：對 `ClientException` / `SocketException` / `TimeoutException` / `HttpException` 與 429、≥500 重試；[`L42`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/apps_provider.dart#L42) `_retryDelaySeconds = 5`。
- **事實**：安裝器抽象在 `lib/installers/`（`Installer` 有 `modeKey`、`canInstallSilently`、`installApk`），實作有 `stock_installer.dart`、`external_installer.dart`、`root_installer.dart`、`shizuku_installer.dart`。
- **事實**：[`lib/installers/stock_installer.dart`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/installers/stock_installer.dart)：[`L3`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/installers/stock_installer.dart#L3) 引入 `android_package_installer`；[`L13`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/installers/stock_installer.dart#L13) `_androidApiLevelS = 31`；[`L25-L73`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/installers/stock_installer.dart#L25-L73) `canInstallSilently`：拒絕 Obtainium 自身的變體、要求 installer-of-record 是 Obtainium 變體、SDK ≥ 31、且目標 App `targetSdkVersion >= sdk-3`；[`L94`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/installers/stock_installer.dart#L94) `AndroidPackageInstaller.installApk(apkFilePath: apkFilePaths.join(','))`（split APK 以逗號串接）。
- **事實**：[`android/app/src/main/kotlin/dev/imranr/obtainium/MainActivity.kt`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/kotlin/dev/imranr/obtainium/MainActivity.kt)：[`L30`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/kotlin/dev/imranr/obtainium/MainActivity.kt#L30) `APK_MIME = "application/vnd.android.package-archive"`；[`L46`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/kotlin/dev/imranr/obtainium/MainActivity.kt#L46) 與 [`L204-L225`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/kotlin/dev/imranr/obtainium/MainActivity.kt#L204-L225) 用 `Intent.EXTRA_RETURN_RESULT` 取得安裝結果；[`L308-L311`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/kotlin/dev/imranr/obtainium/MainActivity.kt#L308-L311) 用 `ACTION_VIEW` / `ACTION_INSTALL_PACKAGE` 探測裝置支援哪種；[`L323-L325`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/kotlin/dev/imranr/obtainium/MainActivity.kt#L323-L325) `FileProvider.getUriForFile(...)`。InstallWatcher 追蹤 package-add broadcast，有取消寬限與 5 分鐘上限。

### 11.5 更新節奏與供給鏈延遲設定

- **事實**：[`lib/providers/settings_provider.dart`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart)：

| 設定 | 位置 | 預設 |
|---|---|---|
| `updateInterval` | [`L242-L248`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L242-L248) | **360 分鐘**（抽驗：`_getInt('updateInterval') ?? 360`） |
| `updateIntervalSliderVal` | [`L252-L258`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L252-L258) | 6.0 |
| `checkOnStart` | [`L262-L267`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L262-L267) | false |
| `onlyCheckInstalledOrTrackOnlyApps` | [`L754-L759`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L754-L759) | false |
| `minimumUpdateAgeDays` | [`L781-L786`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L781-L786) | 0（抽驗：`?? 0`） |
| `verifySigningCertHashes` | [`L870-L875`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L870-L875) | **true**（抽驗：`?? true`） |
| `enableCertificatePinning` | [`L600-L605`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L600-L605) | false |
| `externalInstallerPackage` | [`L168`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L168) | — |
| `getInstallPermission({enforce})` | [`L342`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/providers/settings_provider.dart#L342) | — |

- **事實**：[`lib/utils/min_update_age.dart`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/lib/utils/min_update_age.dart)：`effectiveMinUpdateAgeDays`（單一 App 的設定覆寫全域）、`isReleaseTooYoung`、`applyMinAgeSuppression`（把「太新」的 release 壓回抑制狀態，等它夠舊再提示，並同步更新 APK URL 的版本）。→ 屬於**供給鏈攻擊緩解**：新版本發佈後先等 N 天再讓人裝。

### 11.6 權限

- **事實**：[`android/app/src/main/AndroidManifest.xml`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/AndroidManifest.xml)：[`L61`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/AndroidManifest.xml#L61) FileProvider authority `${applicationId}`；[`L86`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/AndroidManifest.xml#L86) `REQUEST_INSTALL_PACKAGES`；[`L87`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/AndroidManifest.xml#L87) `UPDATE_PACKAGES_WITHOUT_USER_ACTION`；[`L90`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/AndroidManifest.xml#L90) `REQUEST_DELETE_PACKAGES`；[`L91`](https://github.com/ImranR98/Obtainium/blob/af286fa8d31d7406d6db167e2314d376d74f7696/android/app/src/main/AndroidManifest.xml#L91) `ENFORCE_UPDATE_OWNERSHIP`；另有 `RECEIVE_BOOT_COMPLETED`、`WAKE_LOCK`、`QUERY_ALL_PACKAGES`、`FOREGROUND_SERVICE`、`POST_NOTIFICATIONS`。
- **事實**：支持的來源約 35 個（`lib/app_sources/`）：github、gitlab、codeberg、sourcehut、sourceforge、fdroid、fdroidrepo、izzyondroid、html、direct_apk_link、telegramapp、apkmirror、aptoide、uptodown、jenkins、rockmods、rustore、samsunggalaxystore、huaweiappgallery、vivoappstore、coolapk、liteapks、apkpure 等。

### 11.7 小結

| 面向 | Obtainium |
|---|---|
| 來源 | GitHub Releases API（＋約 35 個其他來源） |
| 分頁 | 單次 `per_page=100`，**無分頁迴圈** |
| 快取 | **無 ETag / 條件請求** |
| Rate limit | 讀 `x-ratelimit-remaining` / `x-ratelimit-reset`；401/403 去 token 重試 |
| 驗證 | **簽章憑證 hash 比對**（四者唯一）＋ `minimumUpdateAgeDays` 延遲 |
| 安裝 | `android_package_installer`（可靜默，條件嚴格）／外掛安裝器／root／Shizuku |
| 頻率 | 預設 360 分鐘；`checkOnStart` 預設關 |
| 忽略版本 | 由 `min_update_age` 與 `includePrereleases` 等來源層設定組合達成 |

### 11.8 本組驗證方式對照（事實）

| 專案 | 讀取的來源 | 下載物驗證 | 是否自行安裝 | 安裝權限 |
|---|---|---|---|---|
| NewPipe | 自架 JSON API | 無（API 有 sha256 未用） | 否（`ACTION_VIEW` 交瀏覽器） | 無 `REQUEST_INSTALL_PACKAGES` |
| LX Music Desktop | GitHub Releases（electron-updater）＋6 類鏡像 JSON | 無簽章設定 | 是（`quitAndInstall`） | N/A（桌面） |
| Seal | GitHub `/releases` API | **只有檔案大小** | 是（FileProvider + `ACTION_VIEW`） | `REQUEST_INSTALL_PACKAGES` |
| Obtainium | GitHub `/releases?per_page=100` | **APK 簽章憑證 hash 比對** | 是（`android_package_installer` 等 4 種） | `REQUEST_INSTALL_PACKAGES` |

- **事實**：四個專案**沒有一個**驗證「發佈者公佈的 checksum」；只有 Obtainium 做真實的簽章憑證 hash 比對。

---

# Part 3 — 發版說明工具與版號策略

## 12. release-please（googleapis/release-please）

- **事實（版本與 metadata）**：最新 release **v17.11.2**（2026-08-24）；star 7559；push 於 2026-09-14；License **Apache-2.0**（`gh api repos/googleapis/release-please`）。固定 SHA `edce3d805ef3ac964d1ba2b29b0f42905f2fa412`。

### 12.1 做什麼

- **事實**：[`README.md#L8-L12`](https://github.com/googleapis/release-please/blob/edce3d805ef3ac964d1ba2b29b0f42905f2fa412/README.md#L8-L12)：讀 git 歷史中的 Conventional Commit 訊息，自動產生 CHANGELOG、GitHub Release 與版號 bump。
- **事實**：[`README.md#L18-L43`](https://github.com/googleapis/release-please/blob/edce3d805ef3ac964d1ba2b29b0f42905f2fa412/README.md#L18-L43)「What's a Release PR?」：維護一個 **Release PR**；squash merge 與 merge commit 兩種都支援。合併該 PR 會 (a) 更新 changelog 檔與語言特定檔案、(b) 打 tag、(c) 建立 GitHub Release。生命週期標籤：`autorelease: pending` / `autorelease: tagged` / `autorelease: published`。

### 12.2 可發版單位與策略

- **事實**：[`README.md#L143-L151`](https://github.com/googleapis/release-please/blob/edce3d805ef3ac964d1ba2b29b0f42905f2fa412/README.md#L143-L151)：可觸發發版的 prefix 是 `feat`、`fix`、`deps`（`chore` / `build` **不算**）；Java / Python 另認 `docs`。
- **事實**：[`README.md#L185-L202`](https://github.com/googleapis/release-please/blob/edce3d805ef3ac964d1ba2b29b0f42905f2fa412/README.md#L185-L202) 策略表，其中 **`dart` = "A repository with a pubspec.yaml and a CHANGELOG.md"**（**本次抽驗逐字確認，見 README 第 186 行**）。其他策略：`simple`（version.txt）、`node`、`python`、`rust`（workspaces 需 manifest-driven release ＋ `cargo-workspace` plugin）、`go`、`java`、`php`、`ruby`、`helm`、`bazel`、`terraform-module`、`krm-blueprint`、`ocaml`、`sfdx`、`elixir`、`expo`。
- **事實**：Monorepo — [`README.md#L228-L231`](https://github.com/googleapis/release-please/blob/edce3d805ef3ac964d1ba2b29b0f42905f2fa412/README.md#L228-L231)「Supporting Monorepos via Manifest Configuration」→ `docs/manifest-releaser.md`（官方支援）。Bootstrap：[`README.md#L221`](https://github.com/googleapis/release-please/blob/edce3d805ef3ac964d1ba2b29b0f42905f2fa412/README.md#L221) → `docs/cli.md#bootstrapping`。

### 12.3 GitHub Actions 整合

- **事實**：`googleapis/release-please-action`（Apache-2.0，push 於 2026-08-28）。README 給的基本 workflow：

```yaml
on:
  push:
    branches: [main]
permissions:
  contents: write
  issues: write
  pull-requests: write
jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ secrets.MY_RELEASE_PLEASE_TOKEN }}
          release-type: simple
```

- **事實**：進階版加 `config-file: release-please-config.json` 與 `manifest-file: .release-please-manifest.json`。Action inputs 另有 `path`、`target-branch`、`include-component-in-tag`（monorepo tag 前綴）、`versioning-strategy`、`release-as`、`skip-github-release`、`skip-github-pull-request`。

## 13. git-cliff（orhun/git-cliff）

- **事實（版本與 metadata）**：最新 **v2.14.2**（2026-09-18）；star 12271；License **Apache-2.0 OR MIT**（雙授權；`gh api` 的主 license 欄位回報 Apache-2.0）。固定 SHA `60e0be97e945f71148172675be82399d382c9677`。
- **事實**：[`README.md#L28`](https://github.com/orhun/git-cliff/blob/60e0be97e945f71148172675be82399d382c9677/README.md#L28)：用 conventional commits 與 regex 自訂 parser，從 git 歷史產生 changelog 檔；模板以 config 檔完全可自訂。
- **事實**：[`README.md#L44`](https://github.com/orhun/git-cliff/blob/60e0be97e945f71148172675be82399d382c9677/README.md#L44) 只連到一篇外部 Substack 文章「Git-cliff and monorepos」→ **官方網站文檔中沒有 monorepo 專章（查不到）**。
- **事實**：[`README.md#L96`](https://github.com/orhun/git-cliff/blob/60e0be97e945f71148172675be82399d382c9677/README.md#L96)：'Licensed under either of Apache License Version 2.0 or The MIT License at your option.'
- **事實（monorepo 實際機制）**：[`website/docs/configuration/git.md#L44-L45`](https://github.com/orhun/git-cliff/blob/60e0be97e945f71148172675be82399d382c9677/website/docs/configuration/git.md#L44-L45)：

```toml
include_paths = ["src/", "doc/**/*.md"]
exclude_paths = ["unrelated/"]
```

→ git-cliff 的 monorepo 支援是**用路徑過濾切分**（每個子專案跑一次不同 config），不是 manifest 驅動的版本管理。
- **事實**：同檔 [`L168-L226`](https://github.com/orhun/git-cliff/blob/60e0be97e945f71148172675be82399d382c9677/website/docs/configuration/git.md#L168-L226) 有 commit preprocessor 與 `commit_parsers`（可用 `{ body = ... }`、`{ footer = "^changelog: ?ignore", skip = true }`、`{ message = ..., body = ..., group = "Deprecation" }`）。[`website/docs/configuration/changelog.md`](https://github.com/orhun/git-cliff/blob/60e0be97e945f71148172675be82399d382c9677/website/docs/configuration/changelog.md)：`header`、`header_marker`、`body`、`trim`、`footer` 等模板欄位。
- **事實（GitHub Actions）**：`website/docs/github-actions/git-cliff-action.md` 的範例：`actions/checkout@v3` 配 `fetch-depth: 0`，再 `uses: orhun/git-cliff-action@v4`，參數 `config: cliff.toml`、`args: --verbose`，env `OUTPUT: CHANGELOG.md`、`GITHUB_REPO: ${{ github.repository }}`；文檔提到專案自己的 `cd.yml` 用這個 action 設定 GitHub release notes。`orhun/git-cliff-action` 為 Apache-2.0，push 於 2026-09-18。
- **事實（形態）**：git-cliff 是**離線／CI 皆可**的單一 binary（Rust），不綁 Node 生態；輸出是檔案 ＋ 可選的 GitHub release notes。

## 14. semantic-release（semantic-release/semantic-release）

- **事實（版本與 metadata）**：最新 **v25.0.9**（2026-08-05）；star 24070；License **MIT**；push 於 2026-09-26。固定 SHA `e8c2436e5704a6d1fa5b4aa69238f50edbe586bf`。
- **事實**：[`README.md#L29-L44`](https://github.com/semantic-release/semantic-release/blob/e8c2436e5704a6d1fa5b4aa69238f50edbe586bf/README.md#L29-L44)：全自動發版 —— 決定下一個版號、產生 release notes、發佈套件。依 git merge 決定要發到哪些 distribution channel（npm dist-tags）。透過 plugins 支援任何套件管理器／語言。npm provenance on GitHub Actions。
- **事實**：[`README.md#L66-L73`](https://github.com/semantic-release/semantic-release/blob/e8c2436e5704a6d1fa5b4aa69238f50edbe586bf/README.md#L66-L73)：設計上在 CI 上於 release branch 的每次成功 build 後執行；master/main/next/beta 這類分支上每個 commit 都會觸發。
- **事實**：[`README.md#L75-L102`](https://github.com/semantic-release/semantic-release/blob/e8c2436e5704a6d1fa5b4aa69238f50edbe586bf/README.md#L75-L102) 發版步驟表：Verify Conditions → Get last release → Analyze commits → Verify release → Generate notes → Create Git tag → Prepare → Publish → Notify。
- **事實**：[`README.md#L104-L110`](https://github.com/semantic-release/semantic-release/blob/e8c2436e5704a6d1fa5b4aa69238f50edbe586bf/README.md#L104-L110) 需求：git repo、能設 credentials 的 CI、git CLI、符合版本要求的 Node.js。**README 中沒有 monorepo 專章（查不到官方 monorepo 支援）**。
- **事實（commit 慣例與版號對映）**：[`README.md#L52-L64`](https://github.com/semantic-release/semantic-release/blob/e8c2436e5704a6d1fa5b4aa69238f50edbe586bf/README.md#L52-L64)：**預設用 Angular Commit Message Conventions**，可用 `@semantic-release/commit-analyzer` / `@semantic-release/release-notes-generator` 的 `preset` / `config` 改。

| Commit | 版號 |
|---|---|
| `fix(pencil): …` | Patch |
| `feat(pencil): …` | Minor |
| `perf(...)` ＋ footer `BREAKING CHANGE:` | Major |

（表中註明 `BREAKING CHANGE: ` token 必須在 **footer**。）
- **事實（內部常數）**：`lib/definitions/constants.js`：`RELEASE_TYPE = ["patch", "minor", "major"]`、`FIRST_RELEASE = "1.0.0"`、`FIRSTPRERELEASE = "1"`、`COMMIT_NAME = "semantic-release-bot"`、`RELEASE_NOTES_SEPARATOR = "\n\n"`。`lib/definitions/plugins.js`：只有 `analyzeCommits` 有明確預設（`["@semantic-release/commit-analyzer"]`）；其 `preprocess` 會過濾符合 `/\[skip\s+release]|\[release\s+skip]/i` 的 commit —— 這是「跳過發版」的官方語法。
- **事實（plugin 分工）**：`@semantic-release/changelog`：step `prepare`「Create or update a changelog file in the local project directory」；`changelogFile` 預設 `CHANGELOG.md`；其 README 帶一段**質疑「把 release notes 寫進檔案是否值得這個複雜度」**的警告。`@semantic-release/github`：step `publish`「Publish a GitHub release, optionally uploading file assets」；`addChannel` 更新 release 的 pre-release 欄位；`success` / `fail` 對 issue/PR 留言或開關 issue；需 `GITHUB_TOKEN` 或 `GH_TOKEN`。`@semantic-release/commit-analyzer` 與 `@semantic-release/release-notes-generator` 底層皆為 conventional-changelog。`@semantic-release/npm`：`verifyConditions`（NPM_TOKEN/.npmrc）、`prepare`（更新 package.json 版本、建立 tarball）。
- **事實（GitHub Actions）**：來源 `https://semantic-release.org/recipes/ci-configurations/github-actions/`。**限制聲明**：該頁 YAML **無法由擷取工具逐字重現**（工具做了摘要／重建），以下為**重建的結構**，非逐字引用：一個 "Verify and Release" workflow；`verify` job（`actions/checkout@v4` `fetch-depth: 0` → `actions/setup-node@v4` → `npm clean-install` → `npm audit signatures` → `npm test`）；`release` job（權限 `contents: write`、`issues: write`、`pull-requests: write`、`id-token: write`；`run: npx semantic-release`；`env: GITHUB_TOKEN`）。用 trusted publishing 可免 NPM_TOKEN。警告：不要在 setup-node 設 `registry-url`（會導致 `EINVALIDNPMTOKEN`）。另有使用 `actions/create-github-app-token@v1` 的變體。

## 15. conventional-changelog（conventional-changelog/conventional-changelog）

- **事實（metadata）**：License **ISC**；star 8511；push 於 2026-09-25。repo 採**逐套件 tag**，最新 tag 為 `template-v1.4.0`（2026-08-18），非單一主版本號。固定 SHA `f90c80e9fe02146c1018fa1d78dea738809ab102`。npm 實測（registry.npmjs.org）：`conventional-changelog` latest = **8.1.3**；`conventional-changelog-cli` latest = **5.0.0**。
- **事實**：[`README.md#L9`](https://github.com/conventional-changelog/conventional-changelog/blob/f90c80e9fe02146c1018fa1d78dea738809ab102/README.md#L9)：'Generate a CHANGELOG from git metadata.'
- **事實**：README 推薦的上層工具：**`commit-and-tag-version`**（npm `version` 指令的 drop-in replacement）、`semantic-release`、`simple-release-action`（README 描述其「Supports monorepos and extensibility via addons」）。
- **事實**：README 列出的模組：`conventional-changelog`（full-featured CLI）、`standard-changelog`（Angular 格式 CLI）、`conventional-recommended-bump`，加上 `conventional-changelog-angular`、`conventional-changelog-conventionalcommits`、`conventional-changelog-preset-loader`、`conventional-changelog-writer`、`conventional-commits-filter`、`conventional-commits-parser`、`@conventional-changelog/git-client`、`@conventional-changelog/template`。
- **事實**：README 內附一個 agent skill `conventional-commit-message`（在 `skills/` 下），可用 `npx skills add conventional-changelog/conventional-changelog --skill conventional-commit-message` 安裝。
- **事實**：本身是套件 monorepo，但**沒有內建的 monorepo「發佈」支援**；monorepo 需求由 README 指向 `simple-release-action`。

### 15.1 standard-version 已 deprecated

- **事實**：`conventional-changelog/standard-version` README **第 3 行**逐字：「**`standard-version` is deprecated**. If you're a GitHub user, I recommend [release-please]… you can use the [commit-and-tag-version] fork.」
- **事實**：該 repo `archived=false`，最後 push 2026-07-16，最新 tag v9.5.0（2022-05-15），License ISC。
- **事實**：**npm registry 的 `standard-version` 沒有 `deprecated` 欄位**，`dist-tags.latest = 9.5.0`（實測）→ deprecation 只在 README 宣告，`npm install` 不會警告。
- **事實**：官方推薦的後繼者 `absolute-version/commit-and-tag-version`：ISC，push 於 2026-09-21，最新 v13.2.1（2026-09-14）。

### 15.2 四個工具的取捨對照

| 工具 | 語言／生態 | 輸出 | Monorepo | 備註（事實） |
|---|---|---|---|---|
| release-please | 語言無關（Node action） | Release PR → tag ＋ GitHub Release（可含 changelog 檔） | 官方 manifest 支援 | **有 `dart` 策略**（pubspec.yaml + CHANGELOG.md）；Release PR 模式讓版本變更可審 |
| git-cliff | Rust binary | changelog 檔 ＋ 可選 release notes | 路徑過濾（非 manifest） | 可本機與 CI 跑；模板自訂彈性最大 |
| semantic-release | Node | npm/其他 channel 發佈 ＋ 可選 changelog 檔 ＋ GitHub Release | **無官方支援** | 綁 Node 生態；強項在「發佈套件」 |
| conventional-changelog | Node 函式庫 | changelog 檔（函式庫層） | 無（指向 `simple-release-action`） | 適合作為底層 parser |

## 16. Conventional Commits 1.0.0 spec

- 來源：官方網站 `https://www.conventionalcommits.org/en/v1.0.0/`；原始 markdown 在 `conventional-commits/conventionalcommits.org`（SHA `7d293dc59e88abc8ce6c6698344d4da518ff3f27`，`content/v1.0.0/index.md`）。
- **事實（格式）**：`L21`：`<type>[optional scope]: <description>`；`L44`：scope 寫在括號內，例 `feat(parser): add ability to parse arrays`。
- **事實（型別與版號對應）**：`L33` `fix:` → **PATCH**；`L34` `feat:` → **MINOR**；`L35` **BREAKING CHANGE** —— footer 含 `BREAKING CHANGE:`，或**在 type/scope 後加 `!`**，代表破壞性 API 變更（對應 **MAJOR**）；BREAKING CHANGE 可屬於任何 type。
- **事實**：`L37-L38` 其他型別（依 `@commitlint/config-conventional`，源自 Angular 慣例）：`build:`、`chore:`、`ci:`、`docs:`、`style:`、`refactor:`、`perf:`、`test:` 等；`L42`：這些額外型別**沒有隱含的 semver 效果**。
- **事實（規範細節）**：`L119-L122` BREAKING CHANGE footer 必須大寫 ＋ 冒號 ＋ 空格 ＋ 描述；若寫在 prefix，必須是「緊接在 `:` 前加 `!`」，此時 footer 可省略。`L125-L126`：單位（unit）**不得**被視為大小寫敏感，**唯獨 BREAKING CHANGE 必須大寫**；`BREAKING-CHANGE` 作為 footer token 時與 `BREAKING CHANGE` 同義。

---

# 跨專案事實對照

1. **來源**：多數專案從 GitHub Releases 或自架靜態 JSON 讀版本。NewPipe 的自架 API 是唯一「與 GitHub 解耦」的例子，代價是自維托管。LX Music 的六類鏡像清單對應「中國可達性」需求。
2. **驗證**：11 個應用專案中，**只有 Obtainium** 做真實的簽章憑證 hash 比對；**沒有任何一個**驗證發佈者公佈的 checksum（Spotube 的 release 附 checksums 但 app 端不驗；NewPipe 的 API 給 sha256 但 app 端不讀）。
3. **下載＋安裝的實現率**：桌面端由 Electron／Sparkle 系承擔（LX Music、AppFlowy macOS）；Android 端只有 Seal 與 Obtainium 自己裝。**7 個 Flutter 專案（Part 1）無一在 Android 做 in-app 下載安裝 APK。**
4. **Android 安裝權限**：NewPipe 完全不做安裝（`ACTION_VIEW` 交棒瀏覽器，manifest 無 `REQUEST_INSTALL_PACKAGES`）；Seal 與 Obtainium 自己裝，都要 `REQUEST_INSTALL_PACKAGES` ＋ 引導 `ACTION_MANAGE_UNKNOWN_APP_SOURCES`。
5. **F-Droid 管道**：Seal 用 product flavor 讓 F-Droid 版停用應用內更新器（`isFDroidBuild()`）。
6. **頻率與忽略**：NewPipe 把節奏交給伺服器（`expires` 夾 6–72h）、無忽略版本；LX Music 有忽略版本、失敗提示節流 7 天；Obtainium 有完整間隔設定（預設 360 分）＋ `minimumUpdateAgeDays` 供給鏈延遲；Namida 有 2 小時節流與 beta 獨立 repo。
7. **GitHub API 的使用品質**：Obtainium 對 GitHub API 單次 `per_page=100`、無分頁迴圈、無 ETag；Namida 匿名（`token = null`）＋2 小時節流；Spotube／Hiddify／Harmonoid 皆匿名打 `releases/latest`。
8. **發版工具**：`release-please` 有現成 `dart` 策略（pubspec.yaml + CHANGELOG.md）與官方 monorepo manifest 支援；`git-cliff` 只產生 changelog 檔、monorepo 靠路徑過濾；`semantic-release` 無官方 monorepo 支援；`standard-version` 已 deprecated（僅 README 宣告，npm 無標記），後繼者為 `commit-and-tag-version`。
9. **Release notes 自動化在 OSS 並不普遍**：LocalSend 用 `release-drafter`、Hiddify 用 `gitchangelog`＋mustache、Namida 自寫 Python 依 conventional prefix 分類、AppFlowy 用 sed 抽 CHANGELOG 段落、LX Music 純手寫；Spotube／Finamp／Harmonoid 的產生方式查不到。
10. **Windows 打包分歧**：Inno Setup（LocalSend、Spotube、AppFlowy、Harmonoid）、只有 MSIX 且明說沒有傳統安裝器（Finamp）、`flutter_distributor` 產 exe/msix/zip（Hiddify）。

---

# 本次查證中最不確定的事實

1. **AppFlowy 的版本號到底是什麼** —— tag `0.14.5` 對上 pubspec `0.11.4`，而 app 內版本取自 `packageInfo.version`。tag 只以 `--env APP_VERSION` 傳給 cargo make（`tool.dart` L41），**沒有改寫 pubspec**；macOS Info.plist／Windows exe 版本資源是否被注入、`VersionChecker` 實際比到哪個數字，**查不到**。若版本注入失敗，appcast 的版本比較可能恆為「有新版本」或永遠不觸發。
2. **AppFlowy Windows 是否真的沒有可用 feed** —— 程式碼指名 `appcast-windows-x86_64.xml`，實查 0.13.0／0.14.0／0.14.5 三個 release 的 assets 都沒有它。但「官方是否在別處（官網 CDN）另發 Windows appcast」**查不到**；目前只能說「release assets 內沒有」。
3. **Hiddify appcast 路徑是否已完全廢棄** —— appcast 停更在 0.13.6（2024-01）、無簽章、含壞 URL，實務上不會觸發更新；但程式碼仍同時掛著 `upgrader`＋appcast 與自寫 API 兩條路徑，**兩者誰先生效／`upgrader` 是否已被停用**，程式碼內沒有明確開關可證。
4. **Harmonoid 的版本比較實作** —— 依賴 `identity` 走 git 子模組 `external/identity`，tarball 內不存在 → `compareVersions` 的實際行為（是否支援前綴 `v`、是否處理 beta）**查不到**。
5. **NewPipe 的 `@xml/nnf_provider_paths` 懸空引用** —— 本次抽驗確認該 SHA 的完整 tree（`truncated: false`）中確實沒有這個檔案、直接取檔回 404，但**為何** manifest 仍引用它（分支改動中間狀態？改名殘留？）**查不到**。
6. **LX Music 的 macOS 自動更新是否可用** —— 打包只有 `dmg` 沒有 `zip`；repo 內完全沒有 `verifyUpdateCodeSignature` / `publisherName`，electron-updater 的 Windows 預設驗章行為在該套件內，**無法從本 repo 確認**。
7. **semantic-release 的 GitHub Actions YAML 無法逐字重現** —— 擷取工具只回摘要，文中為重建結構；另 conventional-changelog 的 monorepo 支援只有 README 連到 `simple-release-action`，官方文檔**查不到**。
