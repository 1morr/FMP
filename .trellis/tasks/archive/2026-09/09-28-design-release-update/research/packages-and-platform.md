# 套件與平台事實：發版與應用內更新

- 查證日：2026-09-28
- 查證方式：
  - **套件（第 1 節）**：pub.dev 官方 API `https://pub.dev/api/packages/<name>`、`/score`、`/publisher` 即時取得版本與發布日；套件能力讀 GitHub 原始碼（`README`／`pubspec.yaml`／`podspec`／`CMakeLists.txt`／`AndroidManifest.xml`），以**固定 commit SHA 的 permalink** 為準；repo 活躍度取 GitHub repo metadata（`archived`／`pushed_at`／最後 release 日）。context7 對這批 pub 套件幾乎沒有收錄（只有 `jonasbark/flutter_in_app_update`），故以原始碼與官方文件為主。
  - **平台（第 2–7 節）**：官方文件頁（Apple／Google／Microsoft／Inno Setup／Sparkle／AppImage／Flatpak／GitHub Docs）、GitHub Changelog、`gh api`、`gh attestation verify --help`、以及對 `https://github.com/1morr/FMP/releases/...` 的實際 HTTP 標頭觀測（`curl`）。
  - **未執行 App；未呼叫任何音樂平台 API。**
- 標記約定：**事實**＝有出處可逐字對上；**推測**＝依文件或原始碼推論但未實測；**查不到**＝找過沒找到。網頁出處附 URL；GitHub 外部 repo 出處附固定 SHA permalink。

---

## 1. Flutter／Dart 套件

### 1.1 總覽

| 套件 | latest | 發布日 | 平台 | 維護狀態 | pub 分數 / likes |
|---|---|---|---|---|---|
| `auto_updater` | 1.0.0 | 2024-10-27 | macOS、Windows（**無 Linux**） | 未 archived，但最後 commit 2025-03-29、最後 release 2024-10 → **趨於停滯** | 130/160 · 218 |
| `desktop_updater` | 3.2.0 | 2026-09-22 | macOS、Windows、Linux | **活躍**（最後 commit 2026-09-22） | 140/160 · 53 |
| `ota_update` | 7.1.0 | 2025-12-03 | **Android only** | **活躍**（最後 commit 2026-02-25） | **160/160** · 335 |
| `open_filex` | 4.7.0 | 2025-03-06 | pub tag 只列 Android／iOS；原始碼另有桌面路徑 | 低度維護（最後 commit 2025-03-06，與 last release 同日） | 140/160 · 435 |
| `install_plugin` | 2.1.0 | 2023-07-11 | Android、iOS | **停滯且高風險**（`compileSdkVersion 28`） | 150/160 · 79 |
| `flutter_install_plugin` | 1.0.0 | 2019-11-19 | Android、iOS | **廢棄**（`sdk: >=2.1.0 <3.0.0`，Dart 3 無法解析） | 30/160 · 0 |
| `install_plugin_plus` | — | — | — | **pub.dev 上不存在** | — |
| `package_info_plus` | 10.2.1 | 2026-07-15 | 全平台（含 web） | **活躍**（fluttercommunity，最後 commit 2026-09-27） | 150/160 · **2805** |
| `upgrader` | 13.7.0 | 2026-08-18 | 全平台宣告；**自動支援僅 Android／iOS** | **活躍**（最後 commit 2026-08-20） | 150/160 · 2489 |
| `pub_semver` | 2.2.1 | 2026-08-28 | 純 Dart（全平台） | **活躍**（Dart 官方 team） | **160/160** · 172 |

- **事實**：以上沒有一個在 pub.dev 被標記 `discontinued`（以 `/score` 的 tags 與頁面內容確認）。
- **事實**（FMP 對照）：`pubspec.yaml` 已依賴 `package_info_plus: ^9.0.1`、`open_filex: ^4.5.0`；`version: 1.11.0+1011000`；CI 使用 Flutter `3.47.1`，Dart SDK 約束 `>=3.9.0 <4.0.0`。

### 1.2 `auto_updater` 1.0.0

- 出處：`https://pub.dev/api/packages/auto_updater`；repo `https://github.com/leanflutter/auto_updater`（publisher `leanflutter.dev`）。
- **事實**：平台 `macos` ✔️、`windows` ✔️、**`linux` 不支援**（README 平台表與 pub tags 一致）。`sdk: >=3.0.0 <4.0.0`、`flutter: >=3.3.0`。
- **事實**：monorepo 拆為 `packages/auto_updater`（主）、`auto_updater_macos`、`auto_updater_windows`、`auto_updater_platform_interface`。
- **事實（macOS 底層 Sparkle）**：`macos/auto_updater_macos.podspec` 只寫 `s.dependency 'Sparkle'`（**未鎖版本**）；example 的 `Podfile.lock` 實際解析到 **Sparkle 2.5.2**；`s.platform = :osx, '10.11'`。
- **事實（macOS 簽章）**：需 `dart run auto_updater:generate_keys` 產生金鑰，公鑰 `SUPublicEDKey` 寫進 `macos/Runner/Info.plist`；appcast 每個 `enclosure` 帶 `sparkle:edSignature`；金鑰須在 macOS 與 Windows **各自分開產生**。
- **事實（macOS sandbox）**：quick-start 的 troubleshooting 要求 entitlements 內 `com.apple.security.app-sandbox = false`，並開 `network.client` / `network.server`。→ **推測**：不能用于 Mac App Store 上架版（Sandbox 是 MAS 必要條件，且 Sparkle 2 官方文件說明其不支援 sandboxed app）。
- **事實（Windows 底層 WinSparkle）**：`packages/auto_updater_windows/windows/CMakeLists.txt` 綁 prebuilt **WinSparkle 0.8.1**（`set(WIN_SPARKLE_DIR ".../WinSparkle-0.8.1")`、連結 `x64/Release/WinSparkle.lib`、bundled `WinSparkle.dll`）。上游 WinSparkle 已到 **0.9.4（2026-07-21）**，插件內綁的版本明顯偏舊。**推測**：0.8.1 為 2020 年前後版本。
- **事實（Windows 簽章）**：`generate_keys` 產生 `dsa_priv.pem` / `dsa_pub.pem`，公鑰以 `DSAPub DSAPEM "../../dsa_pub.pem"` 寫進 `windows/runner/Runner.rc`；appcast 帶 `sparkle:dsaSignature`（**DSA，非 EdDSA**）；建置機需安裝 `openssl`。
- **事實（更新來源）**：Feed 為 **Sparkle appcast.xml**（RSS 2.0 + `sparkle:` namespace），同一 appcast 可用 `sparkle:os` 區分 macos / windows 兩個 enclosure。
- **事實（API）**：`setFeedURL(url)` → `checkForUpdates()` → `setScheduledCheckInterval(sec)`；排程間隔**預設 86400 秒、最小 3600、0 代表停用**。**無內建 UI**：叫起原生 Sparkle / WinSparkle 更新視窗。

### 1.3 `desktop_updater` 3.2.0

- 出處：`https://pub.dev/api/packages/desktop_updater`；repo `https://github.com/MarlonJD/flutter_desktop_updater`；pub publisher `radlof.com`（作者 MarlonJD）。
- **事實**：共 **53** 個版本；平台 tags `macos`／`windows`／`linux` 三者齊；`sdk: ^3.6.0`、`flutter: >=3.3.0`；30 天下載 5333、52 stars、1 open issue。
- **事實（更新流）**：簽章式 schema-v3：`app-archive.json` → `release.json` → `app.zip`（或安裝檔）；客戶端抓精確 URL 並驗長度與 SHA-256，不需公開目錄列表。
- **事實（簽章）**：**Ed25519（EdDSA）公鑰釘選** — `trustedReleasePublicKeys` 為每個 controller 的**必填**；同一份 key map 同時驗 `app-archive.json` 與選中的 `release.json`，且在政策選擇與下載前就驗。
- **事實（CLI）**：`dart run desktop_updater:release keygen` / `publish` / `doctor`（含 `--platform`、`--initialize-feed`、`--package-id`）；有上傳 provider 時會「先傳 versioned 檔 → 驗證 → 最後才傳 `app-archive.json`」。
- **事實（UI）**：內建 `DesktopUpdateWidget`、`DesktopUpdateDirectCard`、`DesktopUpdateSliver`、`UpdateDialogListener`；也可自訂 UI 讀 `controller.state`。
- **事實（更新政策）**：政策存在 `app-archive.json` 內（舊 client 不用重編就能改）：optional（可略過）、mandatory（持續提示、隱藏略過）、`supportPolicy`（最低支援版本 + 截止日，逾期 fail closed）、`freshInstall`（導向重新下載）。
- **事實**：`recoveryStore` 為 **3.1 起必填**（app 自有的 pending-install marker 儲存轉接器，需自行複製 repo 的 `JsonFileUpdateRecoveryStore` 到 app 的 support 目錄）。`additionalFiles` 可帶非 Flutter 產物。package ID 必須精確符合平台預設：macOS `macos/Runner/Configs/AppInfo.xcconfig` 的 `PRODUCT_BUNDLE_IDENTIFIER`／Windows `pubspec.yaml` 的 `name`／Linux `linux/CMakeLists.txt` 的 `APPLICATION_ID`。
- **事實（平台信任建議）**：macOS 建議 Developer ID + hardened runtime + notarize + staple；Windows 建議 Authenticode，可發 direct zip 或 **Inno Setup** 安裝檔。
- **事實（限制）**：**Linux 為 `preview` / candidate-only，非 production-ready**，且只支援 direct-ZIP；AppImage、deb/APT、rpm/DNF、Flatpak、Snap 明確**不在**本版範圍。跨平台原生 runtime preview 亦標 candidate-only（只有 macOS production path 有獨立驗證證據）。Microsoft Store / MSIX 為**規劃中**的獨立通路，尚未實作。3.x 有多次破壞性變更（1.x→2.0、2.x→3.0、3.0→3.1 三份 migration guide）。

### 1.4 `ota_update` 7.1.0

- 出處：`https://pub.dev/api/packages/ota_update`；repo `https://github.com/4Q-s-r-o/ota_update`（publisher `4q.eu`）。共 35 版、192 stars、5 open issues。
- **事實**：平台 tag 只有 `platform:android`。README 明說 iOS「opens safari with specified ipa url **(not yet functioning)**」→ 實質 Android-only。
- **事實（能力）**：下載 APK 並在 Flutter 端回報下載進度（`OtaEvent`），下載完成後觸發安裝 intent。
- **事實（7.1.0 新增）**：支援 `PackageInstaller` 方法，需 `usePackageInstaller: true` 才啟用（**預設關閉**）。一般 app 透過插件回報安裝進度、完成後有通知（成功時 OS 可能重啟 app），**沒有系統原生安裝進度 UI**；系統 app（預裝於 `/system/` 或用平台憑證簽章）可**靜默安裝**。
- **事實（狀態列舉）**：`DOWNLOADING` / `INSTALLING` / `INSTALLATION_DONE`（僅 PackageInstaller）/ `INSTALLATION_ERROR`（僅 PackageInstaller）/ `ALREADY_RUNNING_ERROR` / `PERMISSION_NOT_GRANTED_ERROR` / `DOWNLOAD_ERROR` / `CHECKSUM_ERROR` / `INTERNAL_ERROR` / `CANCELED`。
- **事實（manifest 需求）**：插件**不會**自動幫 app 加權限；README 要求在 `AndroidManifest.xml` 自加 `WRITE_EXTERNAL_STORAGE` 與 `REQUEST_INSTALL_PACKAGES`。另需 `<application>` 內加 provider `sk.fourq.otaupdate.OtaUpdateFileProvider`（authority `${applicationId}.ota_update_provider`）、receiver `sk.fourq.otaupdate.InstallResultReceiver`（intent-filter action = `${applicationId}.ACTION_INSTALL_COMPLETE`）、以及 `android/src/main/res/xml/filepaths.xml`（`<files-path name="internal_apk_storage" path="ota_update/"/>`）。
- **事實**：插件自身 manifest 帶 `INSTALL_PACKAGES`（供系統 app 靜默安裝）；對一般 app，Android 會無害忽略，走標準安裝流程。
- **事實（限制）**：7.0.0+ 需 core library desugaring（`multiDexEnabled true`、`coreLibraryDesugaringEnabled true`、`com.android.tools:desugar_jdk_libs:2.0.3`）。自 4.0.0 起不用 `DownloadManager`，檔案存 app 內部目錄 → **沒有系統下載通知**。支援 `sha256checksum` 參數與 `--split-per-abi`。**不在套件範圍**：更新主機託管、版本檢查邏輯、更新伺服器認證。預設不允許 cleartext HTTP（APK 須走 https 或自加 `network_security_config.xml`）。README 註記 Google Play Protect 有時會干擾安裝。

### 1.5 `open_filex` 4.7.0

- 出處：`https://pub.dev/api/packages/open_filex`；repo `https://github.com/javaherisaber/open_file`（`open_file` 的 fork，主要為拿掉 `REQUEST_INSTALL_PACKAGES` 與修 Android 13／Gradle 8 問題）。共 22 版、38 stars、8 open issues。
- **事實（平台實況）**：pub tags 只列 `android`／`ios`，但原始碼支援桌面：`lib/src/platform/open_filex.dart` 對非 iOS／Android 走 `dart:io` — macOS `Process.start('open', [filePath])`、Windows `Process.start('cmd', ['/c', 'start', '', filePath])`、Linux `Process.start("$linuxDesktopName-open", [filePath])`（預設 `xdg-open`）。**無 web 路徑**（README 宣稱的 `web(dart:html)` 與「PC(ffi)」已過時）。
- **事實（能否開 APK 安裝器）**：可以。副檔名對照 `".apk" → "application/vnd.android.package-archive"`；`OpenFilePlugin.java` 建 `Intent(Intent.ACTION_VIEW)` + `setDataAndType(uri, typeString)`，URI 走它自己的 FileProvider（authority `${applicationId}.fileProvider.com.crazecoder.openfile`）並加 `FLAG_GRANT_READ_URI_PERMISSION`；Android 系統套件安裝器接管該 intent → 跳安裝提示。
- **事實（關鍵限制）**：`open_filex` **刻意移除**自身的 `REQUEST_INSTALL_PACKAGES`（README「Notice」第一條，理由為符合 Google Play 政策）；因此 **app 必須自己宣告**該權限，否則 API 26+ 上安裝 intent 會被擋。它只「發出 intent」，**不能靜默安裝、不會回報安裝結果**。
- **事實（FileProvider 範圍）**：`android/src/main/res/xml/filepaths.xml` 內含 `external-path`／`external-cache-path`／`external-files-path`／`files-path`／`cache-path`／`root-path`（皆 `path="."`）。若與其他插件的 FileProvider 衝突，需用 `tools:replace="android:authorities"` / `tools:replace="android:resource"` 覆蓋。

### 1.6 `install_plugin` 與同類

- **事實**：`install_plugin` 2.1.0（2023-07-11，publisher `heyongjian.com`，repo `https://github.com/hui-z/flutter_install_plugin`）：未 archived，但最後 commit 2023-10-17、110 stars、14 open issues。API 為 `InstallPlugin.installApk(apkFilePath, appId)`、`installApkSilent(...)`、`gotoAppStore(...)`。它的 Android manifest **直接宣告 `REQUEST_INSTALL_PACKAGES`**（透過 manifest merge 自動加給 app）。`android/build.gradle` 為 `compileSdkVersion 28`、AGP 7.3.0、Kotlin 1.7.10、依賴 `androidx.legacy:legacy-support-v4`。→ **推測**：現代 Flutter（FMP 用 3.47.1，要求 compileSdk 34/35）極可能無法乾淨建置，需自行 fork 修 gradle。**未實跑建置驗證。**
- **事實**：`flutter_install_plugin` 1.0.0（2019-11-19）— `environment.sdk: >=2.1.0 <3.0.0`，**與 Dart 3 不相容**；pub 分數 30/160、0 likes；description 仍是樣板字「A new flutter plugin project.」。
- **查不到**：`install_plugin_plus` — `https://pub.dev/api/packages/install_plugin_plus` 回 **404 / NoSuchKey**。搜尋命中的最接近者是無關的 `package_installer_plus`（`ScalinoDev`，1.0.0，2024-11-19）。
- **事實（其他同類，皆低採用度）**：`app_installer` 1.3.1（2024-12-03，`BytesZero/app_installer`，最後 commit 2025-01-24）、`android_package_installer` 0.0.3（2025-05-04）、`flutter_app_installer` 2.0.0（2026-03-19）、`package_installer_plus` 1.0.0（2024-11-19）、`r_upgrade` 0.4.2（2023-03-10，停滯）。

### 1.7 `package_info_plus` 10.2.1

- 出處：`https://pub.dev/api/packages/package_info_plus`；repo `https://github.com/fluttercommunity/plus_plugins`（monorepo，publisher `fluttercommunity.dev`）。共 62 版；monorepo 最後 commit 2026-09-27。
- **事實**：平台 `android`／`ios`／`windows`／`linux`／`macos`／`web` 全列。`sdk: >=3.10.0 <4.0.0`、**`flutter: >=3.38.1`** → 與 FMP 的 Flutter 3.47.1 相容；但 FMP 目前 pin 在 `^9.0.1`，升到 10.x 是 **major bump**。
- **事實（欄位）**：`PackageInfo.fromPlatform()` 回傳 `appName`、`packageName`、`version`（pubspec `version:` 的 `+` 之前）、`buildNumber`（`+` 之後）、`buildSignature`（Android 簽章金鑰 SHA-256 hex，其他平台空字串）、`installerStore`（**透過哪個商店安裝**，Android）、`installTime` / `updateTime`（非全平台）。
- **事實（對 FMP 的實值）**：`1.11.0+1011000` → `version == '1.11.0'`、`buildNumber == '1011000'`。

### 1.8 `upgrader` 13.7.0

- 出處：`https://pub.dev/api/packages/upgrader`；repo `https://github.com/larryaasen/upgrader`（publisher `larryaasen.com`）。共 158 版；640 stars、76 open issues。
- **事實（支援矩陣，README 平台表）**：ANDROID 自動 ✅ / appcast ✅；IOS 自動 ✅ / appcast ✅；FUCHSIA／LINUX／MACOS／WEB／WINDOWS 自動 ❌ / appcast ✅。
- **事實**：Android 自動支援 = **抓取公開 Google Play 頁面**（README 明說**不使用**原生 Android In-App Updates API，也不用 Huawei AppGallery API）；iOS 自動支援 = App Store lookup。`UpgraderStoreController` 可逐平台換來源（`onAndroid` 預設 `UpgraderPlayStore()`、`oniOS` 預設 `UpgraderAppStore()`、其餘預設 `null`）。
- **事實（最小版本強制）**：在商店描述欄位塞魔法字串 — Android `[Minimum supported app version: 1.2.3]`、iOS `[:mav: 1.2.3]`；生效後自動隱藏 Ignore / Later 按鈕。
- **事實（GitHub 可達性）**：**沒有內建 GitHub 來源**。`UpgraderAppcastStore(appcastURL: ..., osVersion: Version(0, 0, 0))` 允許把 appcast URL 指向任何位置（含 GitHub raw URL 或放在 GitHub Releases 的 XML，XML 由自己產生）；也可 subclass `UpgraderStore` 自訂來源。**`upgrader` 只負責「比對 + 提示」**：`UPDATE NOW` 只是把使用者導去 App Store / Google Play 頁面，**不下載、不驗簽、不安裝**。
- **事實（桌面侷限）**：`onWindows` / `onLinux` / `onMacOS` 預設皆 `null`，不給 appcast 就什麼都不做；即使給了 appcast，桌面也只能提示 + 開連結。iOS 非 US 商店須自帶 `countryCode`。
- **推測**：README 只示範用一個測試用 raw GitHub URL 的 `UpgraderAppcastStore`；「能否穩定吃 GitHub Releases」是依「URL 可自訂」推論，未找到官方文件或範例正式宣告支援。

### 1.9 `pub_semver` 2.2.1

- 出處：`https://pub.dev/api/packages/pub_semver`；repo `https://github.com/dart-lang/tools/tree/main/pkgs/pub_semver`（publisher `tools.dart.dev`，屬 `dart-lang` 官方組織）。共 30 版；`dart-lang/tools` 最後 commit 2026-09-24。純 Dart，`sdk: ^3.4.0`。
- **事實（與 vanilla semver 不同，重點）**：`Version.parse('1.2.3+4')` → `major=1`、`minor=2`、`patch=3`、`build=['4']`、`preRelease=[]`。`operator ==`（`lib/src/version.dart`，SHA `d87eaf79…`，第 172-178 行）**把 `build` 一起比**：`Version.parse('1.2.3+4') == Version.parse('1.2.3')` → **`false`**。`compareTo`（第 309-329 行）**也把 build 納入排序**，原始碼註解「Builds always come after no build string」：`1.2.3+4 > 1.2.3`、`1.2.3+1 < 1.2.3+2`。`Version.allows(other)` = `this == other`，同樣 build-sensitive。README 明文承認：「**Version ordering does take build suffixes into account.** This is unlike semver 2.0.0 but like earlier versions of semver.」
- **事實**：`Version.parse` 對格式錯誤會 **throw**，不回 null。其他 API：`canonicalizedVersion`、`isPreRelease`、`nextBreaking`（pre-1.0 用 minor）、`nextMajor` / `nextMinor` / `nextPatch`、靜態 `Version.prioritize(a, b)`。

---

## 2. Android

### 2.1 權限與安裝 API

- **事實（Play 政策原文）**：「Apps targeting API level 26 or newer must hold this permission in order to use `Intent.ACTION_INSTALL_PACKAGE` or the `PackageInstaller` API.」以及「The `REQUEST_INSTALL_PACKAGES` permission **may not be used to perform self updates**, modifications, or the bundling of other APKs in the asset file unless for device management purposes. All updates or installing of packages must abide by Google Play's Device and Network Abuse policy and must be initiated and driven by the user.」出處：`https://support.google.com/googleplay/android-developer/answer/12085295?hl=en`（Use of the REQUEST_INSTALL_PACKAGES permission）。
- **事實（許可的 core functionality 清單）**：Web browsing or search／Communication services that support attachments／File sharing, transfer or management／Enterprise device management／Backup and restore／Device migration or phone transfer。另「To use this permission, your app's core functionality must include: Sending or receiving app packages, AND Enabling user-initiated installation of app packages.」出處同上（另轉述見 `https://orangeoma.zendesk.com/hc/en-us/articles/5872194238492-Google-Play-policy-on-Request-Install-Packages-permission`）。→ **事實**：音樂播放器不在許可清單內；**推測**：若上 Google Play，這條是硬阻擋；若僅以 GitHub Releases 側載散布則不受此政策約束。
- **事實（宣告義務）**：自 2022-09-29 起，manifest 含 `REQUEST_INSTALL_PACKAGES` 的 app 必須完成 new sensitive permission declaration，否則無法提交更新審查（須聲明許可功能、描述用到該權限的 core feature、並提供展示影片）。出處同上。
- **事實**：`Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` — **Added in API level 26**；常數值 `"android.settings.MANAGE_UNKNOWN_APP_SOURCES"`；「Activity Action: Show settings to allow configuration of trusted external sources」；Intent 的 data URI 可指定 `package:com.my.app` 直接跳到該 app 的設定頁。出處：`https://developer.android.com/reference/android/provider/Settings`。
- **事實**：`PackageManager.canRequestPackageInstalls()` 存在（文件有該方法的條目，Added in API level 26）。出處：`https://developer.android.com/reference/android/content/pm/PackageManager`。
- **事實**：`PackageInstaller` 以 session 為單位安裝；文件對多個 API 標注「Requires `Manifest.permission.INSTALL_PACKAGES` or `Manifest.permission.REQUEST_INSTALL_PACKAGES`」。出處：`https://developer.android.com/reference/android/content/pm/PackageInstaller`。
- **事實**：`Manifest.permission.INSTALL_PACKAGES` 的常數值為 `"android.permission.INSTALL_PACKAGES"`。相鄰的 `INSTALL_PACKAGES_AS_REGISTERED_APP_STORE` 標示 `Protection level: role`。出處：`https://developer.android.com/reference/android/Manifest.permission`。**未逐字取得**：`INSTALL_PACKAGES` 本身的 protection level 那一行在抓取時被截斷 → **推測**：其為 `signature|privileged`（第三方 app 無法取得），依據是 `ota_update` README 的敘述（系統 app 才能靜默安裝）與一般 Android 權限設計，**未從官方頁面逐字確認**。

### 2.2 安裝的最低 targetSdk

- **事實**：Android 官方「Behavior changes: all apps」原文 —「**Starting with Android 14, apps with a `targetSdkVersion` lower than 23 can't be installed.** Requiring apps to meet these minimum target API level requirements improves security and privacy for users.」安裝失敗時 Logcat 訊息為 `INSTALL_FAILED_DEPRECATED_SDK_VERSION: App package must target at least SDK version 23, but found 7`。裝置升級到 Android 14 時，既有 targetSdk < 23 的 app 會保留安裝。測試可用 `adb install --bypass-low-target-sdk-block FILENAME.apk`。出處：`https://developer.android.com/about/versions/14/behavior-changes-all`。

### 2.3 Android developer verification（側載相關）

- **事實（官方時間表）**：
  - 2026-08：Developer APIs、limited distribution accounts、power user advanced flow 上線（全球）。
  - **2026-09-30**：巴西、印尼、新加坡、泰國的**參與商店**（Google Play、HONOR App Market、OPPO App Market、Galaxy Store、Palm Store、V-Appstore、GetApps）之 app 註冊成為必需；「Unregistered apps can be sideloaded with Android Debug Bridge (adb) or advanced flow.」
  - 2027 起：擴展到**所有** certified 裝置上的所有 app。
  出處：`https://developer.android.com/developer-verification`、`https://android-developers.googleblog.com/2026/06/android-developer-verification.html`、`https://support.google.com/android-developer-console/answer/16561738?hl=en`。
- **事實**：所稱「certified device」= 出廠搭載 GMS 的裝置；未搭載 GMS 的裝置與 custom ROM 不受影響（轉述自 `https://forum.f-droid.org/t/google-will-require-developer-verification-to-install-android-apps-including-sideloading/33123` 對官方公告的引用）。
- **事實（2026-09-30 的實際範圍）**：直接側載（adb、advanced flow）**未**被切斷；被切的只是「參與商店的安裝來源」要對應已驗證開發者。出處：官方 blog 同上。

---

## 3. Windows

### 3.1 Inno Setup（安裝程式）

- **事實（命令列，逐字）**：`/SILENT`「Instructs Setup to be silent or very silent.」— silent 模式「the wizard and the background window are not displayed but the installation progress window is」；very silent（`/VERYSILENT`）連進度視窗也不顯示。`/DIR="x:\dirname"`「overrides the default directory name displayed on the Select Destination Location wizard page. A fully qualified pathname must be specified.」。`/CLOSEAPPLICATIONS`「Instructs Setup to close applications using files that need to be updated by Setup if possible.」。`/RESTARTAPPLICATIONS`。「`/LOG`」在 TEMP 建立 log；`/LOG="filename"` 同義但固定路徑（覆寫既有檔）。`/NORESTART`「Prevents Setup from restarting the system following a successful installation」。`/SUPPRESSMSGBOXES`「Instructs Setup to suppress message boxes. Only has an effect when combined with /SILENT or /VERYSILENT.」。`/RESTARTEXITCODE=exit code`「Specifies the custom exit code that Setup is to return when a restart is needed.」出處：`https://jrsoftware.org/ishelp/topic_setupcmdline.htm`。
- **事實（exit codes，逐字）**：0 = Setup 成功跑完（或用了 /HELP / /?）；1 = 初始化失敗；2 = 使用者在安裝開始前取消，或拒絕開頭的「This will install...」提示；3 = 進入下一階段時致命錯誤（如記憶體不足）；4 = 實際安裝過程中致命錯誤（Abort-Retry-Ignore 的錯誤不算致命；選 Abort 回 5）；5 = 安裝中使用者取消或在 Abort-Retry-Ignore 選 Abort；6 = 被除錯器強制終止；7 = 「Setup cannot proceed with installation」（在 Preparing to Install 階段判定）；**8 = 同 7，但「the system needs to be restarted in order to correct the problem」**。回傳 1／3／4／7／8 前通常會顯示錯誤訊息；「Any non-zero exit code indicates that Setup was not run to completion.」；文件提醒未來版本可能新增代碼。出處：`https://jrsoftware.org/ishelp/topic_setupexitcodes.htm`。

### 3.2 SmartScreen 與程式碼簽章

- **事實**：SmartScreen 是**基於信譽**（reputation）的雲端判斷層，**不是簽章有效性檢查**；簽章鏈完全有效也可能跳「Microsoft Defender SmartScreen prevented an unrecognized app from starting」。未簽章的檔案必須**每個新版本各自從零建立信譽**。出處：`https://knowledge.digicert.com/alerts/ev-signed-application-showing-microsoft-defender-smartscreen-warnings`、`https://www.cimco.com/support/guides/microsoft-defender-smartscreen-warning`。
- **事實**：EV 憑證自 2024 年起**不再**提供即時 SmartScreen 信譽（Microsoft 更新 Trusted Root Program 要求時移除）；新發行的 EV 簽章 app 與 OV 一樣需自然累積信譽。出處：`https://www.todesktop.com/blog/posts/windows-apps-psa-ev-certs-do-not-grant-immediate-reputation-anymore`。
- **事實**：受管理環境可把 SmartScreen 設為 Block 模式，此時連「Run anyway」都沒有。出處：`https://github.com/pnp/Microsoft365-Analytics-Insights/issues/175`。
- **事實（Azure Artifact Signing，原名 Azure Trusted Signing）**：
  - 官方介紹頁現行 canonical 路徑為 `/azure/artifact-signing/overview`（原 `/azure/trusted-signing/overview`）。服務為 fully managed，憑證生命週期在 **FIPS 140-3 Level 3** 認證的 HSM 內管理；account 有 **Basic SKU** 與 **Premium SKU** 兩種。出處：`https://learn.microsoft.com/en-us/azure/artifact-signing/overview`。
  - **不支援 free / trial / sponsored Azure subscription**，必須是付費訂閱（pay-as-you-go 或 enterprise agreement）。出處：`https://learn.microsoft.com/en-us/azure/artifact-signing/faq`。
  - **不發 EV 憑證**，且「There's no plan to issue EV certificates in the future.」。出處同上。
  - 簽章配額：**Basic 5,000 signatures/月**（含 public/private signing 與「1 of each Certificate Profile type」）；**Premium 100,000 signatures/月**（「10 of each Certificate Profile type」）。計費自建立 account 起算，**不按比例**。出處：`https://azure.microsoft.com/en-us/pricing/details/artifact-signing/`、FAQ 同上。**查不到**：實際月費金額 — 定價頁的 Basic / Premium 月費與超量單價皆顯示佔位符 `$-`（動態載入未渲染），官方 FAQ 只指向定價頁與 sales quote，未給數字。
  - **事實**：有 **Individual identity validation** 流程（FAQ 多處以 Individual 為題，需政府核發且帶地址的身分證件、Microsoft Authenticator + Verified ID、AU10TIX 驗證），即個人開發者可走 Public Trust；亦有 Organization identity validation。出處同上。
  - **事實**：SmartScreen 提示與簽章無關 —「SmartScreen reputation builds up automatically. The prompt stops appearing once the file hash has sufficient download history.」。出處同上。
- **事實（SignPath Foundation）**：為 open source 專案提供免費程式碼簽章 —「For OSS projects, our services are free of charge.」；「we verify that the binary was built from your open source repository」；私鑰產生/保存在 HSM。出處：`https://signpath.org/`。**查不到**：具體資格條件與簽章憑證類型的明文（頁面只說 OSS 與需申請，細節在 Apply／Terms）。

---

## 4. macOS

- **事實（Sparkle 2）**：簽章演算法為 **EdDSA（ed25519）**，對發布的更新封存檔（dmg/zip 等）、delta 更新與 installer package 簽章。`SUPublicEDKey` 是 `Info.plist` 中放公鑰的鍵；`generate_keys` 印出 base64 公鑰字串供貼入 plist。`generate_appcast` 掃描一包更新封存檔並產生 appcast（含簽章與 delta），金鑰自 Keychain 取得。建議以 HTTPS 提供更新並符合 App Transport Security；以 Developer ID 簽章並公證；簽章金鑰不要放在網頁伺服器。`SURequireSignedFeed`（Sparkle 2.9 起驗證）需搭配 `SUVerifyUpdateBeforeExtraction`。出處：`https://sparkle-project.org/documentation/`。**未逐字取得**：appcast 中簽章屬性的確切名稱（如 `sparkle:edSignature`）與 Sparkle 2 的最低 macOS 版本 — 該頁未寫；`auto_updater` 子代理讀其原始碼確認 appcast 用 `sparkle:edSignature`。
- **事實（Gatekeeper 與 Sequoia 變更）**：Apple 開發者公告 —「In macOS Sequoia, users will no longer be able to Control-click to override Gatekeeper when opening software that isn't signed correctly or notarized. They'll need to visit System Settings > Privacy & Security to review security information for software before allowing it to run.」同時建議「If you distribute software outside of the Mac App Store, we recommend that you submit your software to be notarized.」出處：`https://developer.apple.com/news?id=saqachfa`（2024-08-06）。
- **事實**：未簽章／未公證的軟體在現行 macOS 上「refuse to run」；Sequoia 的替代路徑是：先嘗試啟動並關掉對話框 → 開 System Settings → Privacy & Security → Security → 按該 app 的 **Open Anyway**（會再問一次並要求管理員密碼）。出處：`https://arstechnica.com/gadgets/2024/08/macos-15-sequoia-makes-you-jump-through-more-hoops-to-disable-gatekeeper-app-checks`、`https://mjtsai.com/blog/2024/07/05/sequoia-removes-gatekeeper-contextual-menu-override`。
- **事實**：Apple Developer Program 年費 **$99**，可讓簽章憑證有效期從 7 天變 1 年、解除 3-app 上限。出處：`https://docs.sidestore.io/docs/faq`（原文「you can pay for a $99/year Apple Developer account」）。**推測**：公證（notarization）需 Developer ID 因而需付費會員資格 — 由 Apple 開發者公告「submit your software to be notarized」+ Developer ID 計畫需會員推得，**未取得 Apple 官方定價頁逐字**。
- **事實（不能與 MAS 並存的一條）**：Mac App Store 的 Guideline 2.4.5 明文：「(vii) They must use the Mac App Store to distribute updates; other update mechanisms are not allowed.」「(iv) They may not download or install standalone apps, kexts, additional code, or resources to add functionality or significantly change the app from what we see during the review process.」「(ii) ... no third-party installers allowed.」出處：`https://developer.apple.com/app-store/review/guidelines/`。

---

## 5. Linux

- **事實（AppImage 更新資訊）**：update information 直接內嵌在 AppImage 內（存在 ISO 9660 Volume Descriptor #1 的 "Application Used" 欄位），可不必重打包整個 AppImage 就更改；由 `appimagetool -u` 內嵌並同時產生對應 `.zsync` 檔，或經 linuxdeploy 的 `$UPDATE_INFORMATION` / `$UPD_INFO`。出處：`https://docs.appimage.org/packaging-guide/optional/updates.html`、`https://github.com/AppImageCommunity/AppImageUpdate`。
- **事實（型別與語法，逐字取自 AppImageSpec draft）**：一個 AppImage 只能內嵌**恰好一種** transport 的 update info。型別：`zsync` 語法 `"zsync|https://server.domain/path/Application-latest-x86_64.AppImage.zsync"`；`gh-releases-zsync` 語法 `"gh-releases-zsync|probono|AppImages|latest|Subsurface-*x86_64.AppImage.zsync"`；`pling-v1-zsync` 語法 `"pling-v1-zsync|1623134|*-stable-x86_64.AppImage"`；`bintray-zsync`「It is deprecated.」。`gh-releases-zsync` 五個以 `|` 分隔的欄位依序為：型別字串、GitHub 使用者/組織、repo、release tag（特殊值 `latest` / `latest-pre` / `latest-all`；文件註明「pre-releases are not being considered when using `latest`」）、zsync 檔名（可用 `*` 萬用字元）。出處：`https://github.com/AppImage/AppImageSpec/blob/master/draft.md`（draft.md#update-information）。
- **事實（消費端工具）**：`AppImageUpdate`（GUI）、`appimageupdatetool`（CLI）、`validate`（檢查內嵌簽章完整性）；以 zsync 做 delta 更新，「Only the parts that have changed since the original version are downloaded」。可作為 CMake submodule 嵌入第三方 app 並連結 `libappimageupdate`。MIT 授權（樣本 GUI 部分基於 FLTK）。出處：`https://github.com/AppImageCommunity/AppImageUpdate`。
- **事實（AppImage 更新的副作用）**：以 zsync 更新時舊檔保留為 `.zs-old` 備份，且是在原檔旁產生新檔而非就地修改。用 `electron-builder` 建的 AppImage 使用它自己的更新機制，「cannot be updated using the usual tools」除非用 `appimagetool -u` 重新打包。出處：`https://docs.appimage.org/packaging-guide/optional/updates.html`。
- **事實（Flatpak 唯讀）**：sandboxed app「No access to any host files except the runtime, the app,」and its per-app data dirs，「Only the latter two being writable.」→ runtime 與 app 自身檔案（`/app`）在沙箱內是**唯讀**；預設可寫的只有 `~/.var/app/$FLATPAK_ID` 與 `$XDG_RUNTIME_DIR/app/$FLATPAK_ID`；`/app` 是保留路徑，用 `--filesystem` 要求寫入「will have no effect」。出處：`https://docs.flatpak.org/en/latest/sandbox-permissions.html`。
- **推測**：Flatpak 的更新由系統端執行（`flatpak update` / 軟體中心 / systemd timer），app 自身無法就地替換自己 — 依據是上條唯讀事實加上 `https://discussion.fedoraproject.org/t/flatpak-automatic-updates-where-how/106418` 描述的自動更新由系統 timer 驅動。**未取得 Flatpak 官方文件明文**。
- **查不到**：deb / rpm 的應用內自更新可行性 — 未找到發行版或 Debian/Fedora 官方文件明文說明 app 可否自行替換 `dpkg` / `rpm` 管理的檔案。**推測**：由套件管理器管理、app 不應自行覆寫（依據：套件管理器持有檔案清單與校驗）。**無逐字出處。**

---

## 6. iOS

- **事實（App Review Guidelines 逐字）**：
  - **2.5.2**：「Apps should be self-contained in their bundles, and may not read or write data outside the designated container area, nor may they **download, install, or execute code which introduces or changes features or functionality of the app, including other apps**. Educational apps designed to teach, develop, or allow students to test executable code may, in limited circumstances, download code provided that such code is not used for other purposes. Such apps must make the source code provided by the app completely viewable and editable by the user.」
  - **2.4.5 (ii)**（Mac App Store）：「They must be packaged and submitted using technologies provided in Xcode; no third-party installers allowed. They must also be self-contained, single app installation bundles and cannot install code or resources in shared locations.」
  - **2.4.5 (iv)**：「They may not download or install standalone apps, kexts, additional code, or resources to add functionality or significantly change the app from what we see during the review process.」
  - **2.4.5 (vii)**：「They must use the Mac App Store to distribute updates; other update mechanisms are not allowed.」
  出處：`https://developer.apple.com/app-store/review/guidelines/`。
- **事實（側載的技術限制）**：
  - 免費 Apple Account（personal team）簽出的 provisioning profile **7 天後到期**；一次最多 **3 個 app**；滾動一週內最多註冊約 **10 個 App ID**。付費 **$99/年** Apple Developer Program 後憑證改為最長 1 年、3-app 上限消失，但仍是 365 天到期。出處：`https://docs.sidestore.io/docs/faq`（原文「If using a free Apple Account, SideStore can only install 3 apps (including itself) at a time. Additionally, only 10 different apps may be installed in a week.」及「To remove this restriction (and also get a 365 day expiry), you can pay for a $99/year Apple Developer account.」）、`https://builds.io/blog/technologies/ios-technologies/stop-refreshing-sideloaded-apps-7-days`。
  - **事實**：SideStore 是 AltStore 的 fork，靠裝置上的 VPN 讓 iOS 接受安裝，並在背景週期性 refresh 以延長 7 天效期；「You only need a computer once during installation.」。出處：`https://docs.sidestore.io/docs/faq`、`https://github.com/SideStore/SideStore`。
- **查不到**：TestFlight 每個 beta build **90 天**到期的**官方**出處 — 只找到二手頁面（`https://www.facebook.com/fb-answers/apple-testflight-beta-builds-expire-90-days-official`），**未取得 Apple 官方文件逐字**。**推測**：90 天限制存在，數字未經官方來源確認。
- **推測**：Flutter app 在 iOS 上無法自我更新 — 依據為 Guideline 2.5.2 禁止下載/安裝/執行會改變功能的程式碼，加上 iOS 不允許 app 就地替換自己的 bundle。**未逐字取得「Flutter 不能」這種針對 Flutter 的官方敘述。**

---

## 7. GitHub Releases API 與供應鏈

### 7.1 速率限制

- **事實（逐字）**：未認證請求 —「60 requests per hour」，綁來源 IP。帶 PAT / OAuth 的認證請求為「personal rate limit of 5,000 requests per hour」（GitHub Enterprise Cloud 組織擁有的 app 代你操作時可到 15,000）。超限回「403 or 429 response」，且「the `x-ratelimit-remaining` header will be `0`」；不應在 `x-ratelimit-reset` 之前重試（secondary limit 看 `retry-after`）；文件警告「Continuing to make requests while you are rate limited may result in the banning of your integration.」。出處：`https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api`。

### 7.2 `releases/latest` 與 asset 物件

- **事實**：`GET /repos/{owner}/{repo}/releases/latest` 回傳的 latest release 定義為「the most recent non-prerelease, non-draft release, sorted by the `created_at` attribute」→ **不含 pre-release、不含 draft**。出處：`https://docs.github.com/en/rest/releases/releases`。
- **事實（asset 欄位）**：`assets[]` 含 `url`、`browser_download_url`（required；「The direct URL to download the asset in a browser」）、`id`、`node_id`、`name`、`label`、`state`（`uploaded` / `open`）、`content_type`、`size`、**`digest`（string or null）**、`download_count`、`created_at`、`updated_at`、`uploader`。API 文件本身**未**指定 `digest` 的雜湊演算法或格式。出處同上。
- **事實**：GitHub Changelog（2025-06-03）—「GitHub now automatically computes and displays **SHA256 checksums (digests)** for all uploaded release assets. These digests are generated at upload time, **immutable**, and let you verify that downloaded assets haven't been altered since publishing.」可在 Releases UI、Releases REST API、GraphQL API、`gh` CLI 取得。出處：`https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets`、GA 公告 `https://github.com/github/roadmap/issues/1136`。
- **事實（社群反證）**：功能上線前的既有 asset `digest` 為 `null`（例：`aquaproj/aqua` v2.51.2 於 2025-05-11 發布，asset `digest: null`）。另有社群回報**移除 asset 後以同名重新上傳，digest 會改變**，因此質疑 changelog 的「immutable」說法。出處：`https://github.com/orgs/community/discussions/161656`。另一討論指出 source-code 的 zip/tar asset 沒有 SHA256。出處：`https://github.com/orgs/community/discussions/23512`。
- **事實（FMP 自身，2026-09-28 以 `gh api repos/1morr/FMP/releases/latest` 實測）**：v1.11.0 共 11 個 asset，**每一個都帶 `digest`**，格式 `sha256:<64 hex>`。含 `fmp-latest-android-arm64-v8a.apk`、`fmp-latest-android-universal.apk`、`fmp-latest-windows-installer.exe`、`fmp-latest-windows.zip` 這組 `-latest-` 別名，以及 `fmp-v1.11.0-android-{arm64-v8a,armeabi-v7a,x86_64,universal}.apk`、`fmp-v1.11.0-windows-installer.exe`、`fmp-v1.11.0-windows.zip`、`fmp-v1.11.0-checksums.sha256`。同名的 `-latest-` 與 `-v1.11.0-` asset **digest 相同**（例：`fmp-latest-windows.zip` 與 `fmp-v1.11.0-windows.zip` 皆 `sha256:926f4bae122da377629826be3e2a2efa6fd1db9371524217d6dd77ca2f6c2923`）。`content_type` 分別為 `application/vnd.android.package-archive`、`application/x-msdos-program`、`application/zip`、`application/octet-stream`。

### 7.3 asset 下載的重導向（本次實測）

- **事實**：`https://github.com/1morr/FMP/releases/latest/download/<asset>` 回 **302** → `https://github.com/1morr/FMP/releases/download/v1.11.0/<asset>`（第二個 302）→ `https://release-assets.githubusercontent.com/github-production-release-asset/<...>?...`（簽章查詢參數，含 `se=` 到期時間與 `ske=` key 到期時間）→ 最終 **200**，回應來自 `Windows-Azure-Blob/1.0 Microsoft-HTTPAPI/2.0`，`x-ms-blob-type: BlockBlob`、`x-ms-server-encrypted: true`。`browser_download_url` 因此**不是**最終 URL。實測（2026-09-28 09:28 UTC）取得的簽章 `se=2026-09-28T10:18:47Z`，約 50 分鐘有效。出處：本次 `curl -L -o /dev/null -D -` 對 `fmp-v1.11.0-windows.zip` 的實測。
- **事實（最終回應標頭）**：`Content-Length: 25652422`、`Accept-Ranges: bytes`、`ETag: "0x8DF1A78B41500DB"`、`Last-Modified: Thu, 24 Sep 2026 20:16:22 GMT`、`Content-Disposition: attachment; filename=fmp-v1.11.0-windows.zip`、`Content-Type: application/octet-stream`、`x-ms-lease-status: unlocked`。→ **事實**：最終端點支援 Range 請求（可續傳／分塊下載）。出處同上。

### 7.4 構件證明（attestation）

- **事實**：`actions/attest-build-provenance` 為 workflow artifact 產生簽章的 SLSA build provenance 證明（in-toto 格式），以短效 Sigstore 憑證簽章（公開 repo 用公開 Sigstore instance，private/internal 用 GitHub 私有 instance），簽好的證明上傳到 GH attestations API，可用 `gh attestation` 驗證。**「As of version 4, `actions/attest-build-provenance` is simply a wrapper on top of `actions/attest`」**。出處：`https://github.com/actions/attest-build-provenance`。**未逐字取得**：該頁所示的 workflow permissions 片段（`id-token: write` / `attestations: write`）— README 只指向 `actions/attest` repo，**未取得可逐字引用的 YAML**。
- **事實（本地 CLI 實測）**：`gh version 2.97.0 (2026-07-31)`；`gh attestation verify --help` 顯示需 `--owner` 或 `--repo` 之一，會驗證 signer 身分（`SourceRepository`、`SourceRepositoryOwner`、`SubjectAlternativeName`），預設 predicate type 為 `https://slsa.dev/provenance/v1`。出處：本次 `gh --version`、`gh attestation verify --help`。

---

## 8. 交叉觀察（僅陳列已查得事實，不含設計建議）

1. **桌面三平台沒有一個成熟單一套件全包**：`auto_updater` 缺 Linux 且趨於停滯、macOS 需關 sandbox、Windows 綁 WinSparkle 0.8.1；`desktop_updater` 三平台齊、活躍、有簽章與 CLI，但 Linux 仍 candidate-only 且 3.x 破壞性變更頻繁。
2. **Android 自更新**：`ota_update` 分數與採用度最好（160/160、335 likes），但需自行處理 4 個 manifest 節點 + desugaring；Play 政策明文禁止把 `REQUEST_INSTALL_PACKAGES` 用於 self updates。
3. **`package_info_plus` 是唯一無替代品的必需品**（FMP 已在用，9.x → 10.x 為 major bump），且其 `installerStore` 可回報安裝來源。
4. **`upgrader` 無法承擔桌面更新**，只做「比對 + 提示」；下載與安裝要另找套件。
5. **`pub_semver` 的 build 排序語意與 FMP 的 `1.11.0+1011000` 版號習慣一致**（build 參與 `==` 與 `compareTo`）。
6. **GitHub 已原生提供 asset `digest`**（2025-06-03 起，FMP 全部 asset 都有），但官方 API 文件未載明演算法；另有社群對「同名重傳會改變 digest」與「舊 asset 為 null」的反證。
7. **驗證鏈選項並存**：Sparkle 2 用 EdDSA；`desktop_updater` 用 Ed25519 公鑰釘選；GitHub 有原生 digest + Sigstore build provenance（`gh attestation verify`）；Windows 另有 Authenticode（Artifact Signing 為 managed、FIPS 140-3 L3、不發 EV）與 SignPath Foundation（OSS 免費）。

## 9. 我認為最不確定的 3 個事實

1. **`Manifest.permission.INSTALL_PACKAGES` 的 protection level 是否為 `signature|privileged`** — `https://developer.android.com/reference/android/Manifest.permission` 抓取時在該行被截斷；「第三方 app 無法取得、只有系統 app 能靜默安裝」是**推測**（依據 `ota_update` README 敘述與 `PackageInstaller` 頁面「Requires INSTALL_PACKAGES or REQUEST_INSTALL_PACKAGES」的並列寫法）。
2. **GitHub asset `digest` 的「不可變」性質** — 官方 changelog 說 generated at upload time / immutable，但社群 discussion #161656 以實測指出「移除後同名重傳 digest 會變」，且舊 asset 為 `null`；兩者矛盾，我未自行重現。
3. **iOS／macOS 的兩個數字** — TestFlight beta build **90 天**到期只找到二手頁面（無 Apple 官方出處）；Apple Developer Program 的 **$99/年**取自 SideStore 文件與第三方 blog，**未取得 Apple 官方定價頁逐字**。另外 Sparkle 2 的最低 macOS 版本與 `sparkle:edSignature` 屬性名**未從 Sparkle 官網逐字取得**（後者由 `auto_updater` 原始碼側面確認）。
