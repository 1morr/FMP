# FMP 建置與發布指南

## 概述

FMP 使用 GitHub Actions 分離一般 CI 和正式 Release。`ci.yml` 會在 PR、`main` push 或手動觸發時執行分析、測試與建置煙霧測試；`release.yml` 只負責既有 `v*` tag 的 Android APK、Windows ZIP/Installer 打包與 GitHub Release 發布。應用程式內建檢查更新功能，使用者可在設定頁手動檢查並下載新版本。

本文件描述 CI 和發布流程。本機建置步驟見〈[建置指南](building.md)〉。

## 目錄

1. [Android 簽名配置](#1-android-簽名配置)
2. [GitHub Secrets 設定](#2-github-secrets-設定)
3. [Windows 安裝包 (InnoSetup)](#3-windows-安裝包-innosetup)
4. [發布新版本](#4-發布新版本)
5. [應用內更新機制](#5-應用內更新機制)
6. [常見問題](#6-常見問題)

---

## 1. Android 簽名配置

Android APK 必須使用固定的簽名金鑰。不同金鑰簽名的 APK 無法覆蓋安裝（系統顯示 "package conflicts"）。

本機建置預設使用 debug 簽名即可運作；只有在需要固定簽名（覆蓋安裝更新、或要準備上傳到 CI Secrets）時才需要以下步驟。

### 產生 Keystore（僅首次）

```bash
keytool -genkey -v \
  -keystore android/release.keystore \
  -alias fmp \
  -keyalg RSA -keysize 2048 \
  -validity 36500 \
  -dname "CN=FMP,OU=Personal,O=Personal,L=Unknown,ST=Unknown,C=US"
```

> `keytool` 是 Java JDK 自帶的命令列工具，安裝 JDK 後即可使用；Windows 上完整路徑通常在 `C:\Program Files\Java\jdk-17\bin\keytool.exe`。
> 讓 `keytool` 互動式提示輸入密碼。不要把 keystore 密碼寫在命令列、日誌、issue、螢幕截圖或 agent 對話中。

### 建立 key.properties（本機建置用）

在 `android/key.properties` 寫入：

```properties
storePassword=<你的密碼>
keyPassword=<你的密碼>
keyAlias=fmp
storeFile=../release.keystore
```

`build.gradle.kts` 會自動偵測該檔案：存在則使用你的 keystore 簽名，不存在則 fallback 到 debug 簽名。

> `key.properties` 和 `release.keystore` 均已在 `.gitignore` 中，不會被提交。仍需把它們當作簽名金鑰保管，不要複製到日誌、工單、agent 報告或暫時公開的目錄。

### 驗證 Keystore

```bash
keytool -list -keystore android/release.keystore
```

應輸出包含 `fmp` alias 和 `PrivateKeyEntry` 的資訊。

---

## 2. GitHub Secrets 設定

Release Android 簽名建置需要 4 個 Repository Secrets。**Secrets 只需設定一次**，設定後永久保存在 GitHub 儲存庫中。只有在重新產生 keystore 後才需要重新設定。

### 前置條件

```bash
# 確認已登入
gh auth status
```

### 一鍵設定所有 Secrets

```powershell
# 1. 上傳 Keystore（使用 certutil 編碼為 base64）
certutil -encode android/release.keystore "$env:TEMP\ks.txt"
Get-Content "$env:TEMP\ks.txt" |
  Where-Object { $_ -notmatch 'CERTIFICATE' } |
  gh secret set KEYSTORE_BASE64 --repo 1morr/FMP --body-file -
Remove-Item -LiteralPath "$env:TEMP\ks.txt" -Force

# 2. 設定密碼和別名（逐條輸入 secret 內容，不要把密碼放在命令列）
gh secret set KEYSTORE_PASSWORD --repo 1morr/FMP
gh secret set KEY_PASSWORD --repo 1morr/FMP
"fmp" | gh secret set KEY_ALIAS --repo 1morr/FMP --body-file -
```

> Linux/macOS 用 `base64 android/release.keystore | gh secret set KEYSTORE_BASE64 --body-file -`
> 暫存 base64 檔案、終端機 scrollback 和 agent transcript 都可能洩漏簽名金鑰。上傳後確認 `$env:TEMP\ks.txt` 已刪除，不要把 secret 值貼到報告中。

### 驗證 Secrets

```bash
gh secret list --repo 1morr/FMP
```

應顯示 4 個 Secrets：`KEYSTORE_BASE64`、`KEYSTORE_PASSWORD`、`KEY_PASSWORD`、`KEY_ALIAS`。

### 更換 Keystore 後

如果重新產生了 keystore，只需重新執行上面的指令即可。Secrets 會被覆蓋更新。

> 注意：更換簽名金鑰後，使用者需要先解除安裝舊 APK 再安裝新的。

---

## 3. Windows 安裝包 (InnoSetup)

Windows 版本使用 [Inno Setup](https://jrsoftware.org/isinfo.php) 產生 `.exe` 安裝包。安裝包會建立帶有 `AppUserModelID` 的開始功能表和桌面捷徑，讓 Windows SMTC（系統媒體傳輸控制項）能正確顯示應用程式圖示和名稱。

CI 不直接使用 inno_bundle 的預設輸出：`release.yml` 會以多組 regex 改寫產生的 `inno-script.iss`（注入 `DefaultGroupName=FMP` 與 `AppUserModelID: "com.personal.fmp"`），並在 ISCC 編譯前用一個 verify 步驟斷言兩者都存在。若上游 inno_bundle 輸出格式變動使替換失效，CI 會明確失敗，而不是產出靜默退回的安裝包（那會讓 SMTC 身分與開始功能表分組受損）。

本機安裝 Inno Setup 與建置安裝包的步驟見〈[建置指南 §建置安裝包](building.md#建置安裝包)〉；本節只說明 CI 特有的修補與驗證邏輯，以及 AppUserModelID 的完整原理。

### 設定

安裝包設定位於 `pubspec.yaml` 的 `inno_bundle` 區塊，完整欄位說明見〈[建置指南 §安裝包設定](building.md#安裝包設定)〉。

> **重要**：`id` 是 GUID 格式的 AppId，**發布後不可更改**。更改會導致使用者機器將更新視為不同的應用程式。

### SMTC AppUserModelID

Windows SMTC 透過 `AppUserModelID` 識別應用程式身分。本專案在兩個位置設定了該 ID：

1. **行程層級**（`windows/runner/main.cpp`）：

```cpp
#include <shobjidl.h>

// 在 wWinMain 開頭
::SetCurrentProcessExplicitAppUserModelID(L"com.personal.fmp");
```

2. **捷徑層級**（InnoSetup 安裝包）：

安裝包建立的開始功能表和桌面捷徑包含相符的 `AppUserModelID: "com.personal.fmp"`。`inno_bundle` 預設不會產生此屬性，CI 建置時會自動修補。

> 兩者必須一致，否則 SMTC 無法正確顯示應用程式資訊。

### 相關檔案

| 檔案 | 說明 |
|------|------|
| `pubspec.yaml` (`inno_bundle` 區塊) | 安裝包設定 |
| `windows/runner/main.cpp` | `SetCurrentProcessExplicitAppUserModelID` |
| `windows/runner/resources/app_icon.ico` | 安裝包和捷徑圖示 |

---

## 4. 發布新版本

### 發布流程

> **Release 建出來是草稿。** workflow 跑完之後要到 GitHub Releases 頁面按
> Publish 才會對外，README 的 `releases/latest/download/...` 連結在那之前看不到
> 它 —— 忘了按只會讓上一版繼續當最新版，不會發出半成品。這一步是給人看 body 與
> 產物的機會。

```bash
# 1. 確保程式碼已 commit 並 push
git add .
git commit -m "feat: ..."
git push

# 2. 打 tag 並 push（觸發 CI 建置和 Release）
git tag v1.2.0
git push origin v1.2.0
```

### CI 流程

一般驗證由 `.github/workflows/ci.yml` 負責。**沒有 path filter** —— 純文檔的
commit 一樣跑滿，因為 `AGENTS.md` 裡的規則是由測試強制的：

```text
pull_request / main push / workflow_dispatch
       │
       ▼
CI
       │
       ├─ validate (ubuntu)
       │   ├─ flutter pub get
       │   ├─ dart format --output=none --set-exit-if-changed lib test
       │   ├─ dart run build_runner build
       │   ├─ dart run slang
       │   ├─ flutter analyze
       │   └─ flutter test
       │
       ├─ build-android (ubuntu)
       │   └─ flutter build apk --release --target-platform android-arm64
       │
       └─ build-windows (windows-2022)
           └─ flutter build windows --release
```

`validate` 會執行程式碼產生、格式檢查、analyzer 與測試；兩個 build job 只作為跨平臺 release build 煙霧測試，不建立 GitHub Release。`*.g.dart` 等產生檔不進版本控制（見 `.gitignore`），所以本流程不對「產生檔已提交」做檢查——那類檢查在 git 從未追蹤這些檔案的情況下永遠會通過，無法真正偵測任何問題。圖示資產由維護者在本機執行 `dart run flutter_launcher_icons` 後提交，CI 不在每次驗證時重產圖示。

> Release 前（release checklist）：確認 `isar` / `isar_flutter_libs` 於目標平臺（Android `arm64-v8a` / `armeabi-v7a` / `x86_64`、Windows `x86_64`，必要時 Windows `arm64`）的 native libs 可用且對應 build job 通過。Isar 刻意凍結於 v3（見 `lib/data/AGENTS.md` 的 Dependency Note），不自行升級 v4。

### 發布自動化流程

```
git push origin v1.2.0
       │
       ▼
GitHub Actions (release.yml)
       │
       ├─ prepare
       │   ├─ 驗證 tag 格式為 v{major}.{minor}.{patch}
       │   └─ 確認 tag 已存在
       │
       ├─ validate (ubuntu)
       │   ├─ flutter analyze
       │   └─ flutter test
       │
       ├─ build-android (ubuntu)
       │   ├─ 按 ABI matrix 建置 arm64-v8a / armeabi-v7a / x86_64 / universal
       │   ├─ 從 tag 提取版本號寫入 pubspec.yaml
       │   ├─ 從 Secrets 解碼 keystore
       │   ├─ flutter build apk --release
       │   └─ 產物: fmp-v1.2.0-android-{abi}.apk
       │
       ├─ build-windows (windows)
       │   ├─ 從 tag 提取版本號寫入 pubspec.yaml
       │   ├─ flutter build windows --release
       │   ├─ 壓縮為 ZIP
       │   ├─ 安裝 InnoSetup + 產生安裝包
       │   ├─ 修補 ISS 指令碼（AppUserModelID + 語言修復）
       │   └─ 產物: fmp-v1.2.0-windows.zip
       │          fmp-v1.2.0-windows-installer.exe
       │
       └─ release
           ├─ 下載所有平臺的產物
           ├─ 組裝 Release Notes（手寫檔優先，否則自動產生）
           └─ 建立 GitHub Release（multi-ABI APK + ZIP + Installer + latest 穩定下載別名）
```

### Release Notes

body 一律由 `release` job 從 commit 範圍產生，沒有手寫檔這條路。做法是把
`<上一個 tag>..<本次 tag>` 之間的 commit 依 Conventional Commits 前綴分成
**Features / Fixes / Performance / Dependencies** 四段，其餘（`refactor`、
`docs`、`test`、`ci`、`style`）留給結尾的 compare 連結 —— 那些是使用者看不到的
改動，放進來只會把真正該讀的東西擠掉。四段都空的時候（例如整輪都是重構）才退回
列出全部 commit。

body 不只出現在 GitHub Release 頁面：`update_service.dart` 把它當成
`releaseNotes` 餵給 App 內的更新對話框。所以 markdown 要淺，長度要短。

> **一次性的歷史問題（已過去）**：2026-09-01 的歷史重寫讓 v1.2.0–v1.9.1 全部脫離
> `main` 的血緣，發 v1.10.0 時 `git describe` 只找得到 v1.1.4，任何候選 tag 都產出
> 同一份 1134 行清單，所以那一版的 body 是手寫的。v1.10.0 是在重寫後的歷史上打的
> tag，`git describe HEAD` 現在回它，之後的版本不再有這個問題。

> Release 頁面的 compare 連結預設是三點（`a...b`，走 merge-base）。因為上述重寫，
> v1.9.1 → v1.10.0 要用**兩點**（`a..b`）才會只顯示端點之間的實際差異。

### 版本號規則

- Tag 格式：`v{major}.{minor}.{patch}`，如 `v1.2.0`
- CI 建置時會把 tag 的版本寫進 `pubspec.yaml`：`version: 1.2.0+1002000`，但**不回寫
  repo** —— 所以**發完版要記得把 `pubspec.yaml` 的版本補上並 commit**
- `test/workflows/pubspec_version_test.dart` 守著這件事：committed 的版本不得低於
  HEAD 上最新的 tag。忘了補，下一次 CI 就會紅。之所以需要它，是因為開發建置讀的是
  committed 的值 —— 落後時 app 會自報舊版本，然後對自己跳出「有新版可用」
- `+{versionCode}` 由 tag 計算：`major * 1000000 + minor * 1000 + patch`
- Android 升級只接受更大的 `versionCode`；不要使用 `github.run_number`
  作為正式 APK build number，否則 workflow run number 重置或換 workflow
  可能導致新版 `versionName` 的 APK 被系統視為降級而拒絕安裝。

### Release 產物命名

| 平臺 | 產物命名 | 說明 |
|----------|---------------|-------|
| Android | `fmp-v1.2.0-android-arm64-v8a.apk` | ABI 專用 APK |
| Android | `fmp-v1.2.0-android-armeabi-v7a.apk` | ABI 專用 APK |
| Android | `fmp-v1.2.0-android-x86_64.apk` | 模擬器 / x86_64 APK |
| Android | `fmp-v1.2.0-android-universal.apk` | 應用內更新的 universal fallback |
| Android | `fmp-latest-android-universal.apk` | README 穩定下載連結 |
| Windows | `fmp-v1.2.0-windows.zip` | 免安裝版 |
| Windows | `fmp-v1.2.0-windows-installer.exe` | 安裝版 |
| Windows | `fmp-latest-windows.zip` | README 穩定下載連結 |
| Windows | `fmp-latest-windows-installer.exe` | README 穩定下載連結 |
| All | `fmp-v1.2.0-checksums.sha256` | 應用內更新校驗 manifest |

應用內更新支援 multi-ABI Android 命名格式，找不到符合裝置 ABI 的 asset 時會 fallback 到 `universal`。Release workflow 會為版本化 APK、ZIP、installer 產生 `sha256` manifest；App 下載時先寫入 `.part`，完成後驗證 GitHub asset size 和 manifest checksum，通過後才改名成正式檔。README 使用 `https://github.com/1morr/FMP/releases/latest/download/fmp-latest-*` 穩定下載連結，因此 Release workflow 不需要 commit 回 `main` 更新版本化下載 URL。

### 手動觸發

- `CI` workflow 可在任意 branch 手動觸發，用於非 Release 驗證。
- `Release` workflow 手動觸發時必須輸入已存在的 `vX.Y.Z` tag。它會 checkout 該 tag 並發布該 tag 對應的產物，不會從任意 branch 直接發版。

### Windows runner 版本

Windows CI 固定使用 `windows-2022`，避免 `windows-latest` 遷移到新版 Visual Studio/MSVC 後觸發原生外掛相容性問題。目前 `flutter_inappwebview_windows 0.6.0` 在 VS 2026 / MSVC 14.51 下會因 `<experimental/coroutine>` 棄用檢查而建置失敗；等該外掛升級或本專案完成 Windows 外掛修補並驗證後，再評估恢復 `windows-latest`。

---

## 5. 應用內更新機制

### 使用者操作

設定 → 關於 → 檢查更新

### 技術實作

```
檢查更新
  │
  ▼
GET https://api.github.com/repos/1morr/FMP/releases/latest
  │
  ├─ 比較 tag_name 與目前 app 版本
  │
  ├─ 無更新 → 提示「已是最新版本」
  │
  └─ 有更新 → 彈出對話方塊
       │
       ├─ 顯示版本號、Release Notes、檔案大小
       │
       └─ 使用者點選「立即更新」
            │
            ├─ Android: 下載 APK → 呼叫系統安裝器
            │
            └─ Windows:
                 ├─ 安裝版: 下載 installer → 靜默安裝到目前目錄 → 重啟
                 └─ 免安裝版: 下載 ZIP → 解壓 → VBS/BAT updater 等待舊行程結束 → 備份 → 替換 → 失敗回滾 → 重啟
```

下載與安裝安全邊界：
- 所有平臺下載都先落到 `.part`，驗證完成後才替換成正式檔案。
- 新 Release 附帶 `fmp-vX.Y.Z-checksums.sha256`；App 會優先使用 SHA-256 驗證，並保留 asset size 檢查作為相容舊版本的最低保護。
- Android 安裝前會檢查「允許此來源安裝應用程式」。未授權時，對話方塊會引導使用者開啟系統設定，回到 App 後可重新觸發安裝。
- Windows 免安裝版 updater 會等待原 FMP 行程結束，先備份目前目錄，再用 `robocopy` 替換；替換失敗會嘗試從備份回滾。

### 相關檔案

| 檔案 | 說明 |
|------|------|
| `lib/services/update/update_service.dart` | GitHub API 呼叫、下載、平臺安裝邏輯 |
| `lib/providers/system/update_provider.dart` | Riverpod 狀態管理 |
| `lib/ui/widgets/dialogs/update_dialog.dart` | 更新對話方塊 UI |
| `android/app/src/main/kotlin/com/personal/fmp/MainActivity.kt` | Android 安裝來源權限 MethodChannel |

---

## 6. 常見問題

### Q: APK 安裝時報 "package conflicts with an existing package"
**A:** 新舊 APK 簽名金鑰不同。需要先解除安裝舊版本再安裝。確保本機和 CI 使用同一個 `release.keystore`。

### Q: CI 建置失敗 "Keystore file not found"
**A:** 檢查 `key.properties` 中 `storeFile` 路徑是否為 `../release.keystore`（相對於 `android/app/` 目錄）。

### Q: CI 建置失敗 "Tag number over 30 is not supported"
**A:** `KEYSTORE_BASE64` Secret 損壞。重新執行 `certutil` 編碼指令上傳。

### Q: 版本號沒有更新
**A:** 確認使用 `v` 開頭的 tag（如 `v1.2.0`）。非 tag push 不會更新版本號。

### Q: Windows 更新時彈出 CMD 視窗
**A:** 已透過 VBScript 包裝解決。更新指令碼透過 `wscript` 隱藏啟動。
