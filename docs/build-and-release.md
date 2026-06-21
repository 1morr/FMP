# FMP 构建与发布指南

## 概述

FMP 使用 GitHub Actions 分離一般 CI 和正式 Release。`ci.yml` 會在 PR、`main` push 或手動觸發時執行分析、測試與構建煙霧測試；`release.yml` 只負責既有 `v*` tag 的 Android APK、Windows ZIP/Installer 打包與 GitHub Release 發布。應用內建檢查更新功能，使用者可在設定頁手動檢查並下載新版本。

本文件描述 CI 和发布流程。本地构建步骤见 [构建指南](build-guide.md)。

## 目录

1. [Android 签名配置](#1-android-签名配置)
2. [GitHub Secrets 设置](#2-github-secrets-设置)
3. [Windows 安装包 (InnoSetup)](#3-windows-安装包-innosetup)
4. [发布新版本](#4-发布新版本)
5. [应用内更新机制](#5-应用内更新机制)
6. [常见问题](#6-常见问题)

---

## 1. Android 签名配置

Android APK 必须使用固定的签名密钥。不同密钥签名的 APK 无法覆盖安装（系统报 "package conflicts"）。

### 生成 Keystore（仅首次）

```bash
keytool -genkey -v \
  -keystore android/release.keystore \
  -alias fmp \
  -keyalg RSA -keysize 2048 \
  -validity 36500 \
  -dname "CN=FMP,OU=Personal,O=Personal,L=Unknown,ST=Unknown,C=US"
```

> Windows 上 `keytool` 路径通常在 `C:\Program Files\Java\jdk-17\bin\keytool.exe`
> 让 `keytool` 交互式提示输入密码。不要把 keystore 密码写在命令行、日志、issue、截图或 agent 对话中。

### 创建 key.properties（本地构建用）

在 `android/key.properties` 写入：

```properties
storePassword=<你的密码>
keyPassword=<你的密码>
keyAlias=fmp
storeFile=../release.keystore
```

> `key.properties` 和 `release.keystore` 均已在 `.gitignore` 中，不会被提交。仍需把它们当作签名密钥保管，不要复制到日志、工单、agent 报告或临时公开目录。

### 验证 Keystore

```bash
keytool -list -keystore android/release.keystore
```

应输出包含 `fmp` alias 和 `PrivateKeyEntry` 的信息。

---

## 2. GitHub Secrets 设置

Release Android 簽名構建需要 4 個 Repository Secrets。**Secrets 只需設定一次**，設定後永久保存在 GitHub 倉庫中。只有在重新生成 keystore 後才需要重新設定。

### 前置条件

```bash
# 确认已登录
gh auth status
```

### 一键设置所有 Secrets

```powershell
# 1. 上传 Keystore（使用 certutil 编码为 base64）
certutil -encode android/release.keystore "$env:TEMP\ks.txt"
Get-Content "$env:TEMP\ks.txt" |
  Where-Object { $_ -notmatch 'CERTIFICATE' } |
  gh secret set KEYSTORE_BASE64 --repo 1morr/FMP --body-file -
Remove-Item -LiteralPath "$env:TEMP\ks.txt" -Force

# 2. 设置密码和别名（逐条输入 secret 内容，不要把密码放在命令行）
gh secret set KEYSTORE_PASSWORD --repo 1morr/FMP
gh secret set KEY_PASSWORD --repo 1morr/FMP
"fmp" | gh secret set KEY_ALIAS --repo 1morr/FMP --body-file -
```

> Linux/macOS 用 `base64 android/release.keystore | gh secret set KEYSTORE_BASE64 --body-file -`
> 临时 base64 文件、终端 scrollback 和 agent transcript 都可能泄漏签名密钥。上传后确认 `$env:TEMP\ks.txt` 已删除，不要把 secret 值贴到报告中。

### 验证 Secrets

```bash
gh secret list --repo 1morr/FMP
```

应显示 4 个 Secrets：`KEYSTORE_BASE64`、`KEYSTORE_PASSWORD`、`KEY_PASSWORD`、`KEY_ALIAS`。

### 更换 Keystore 后

如果重新生成了 keystore，只需重新运行上面的命令即可。Secrets 会被覆盖更新。

> 注意：更换签名密钥后，用户需要先卸载旧 APK 再安装新的。

---

## 3. Windows 安装包 (InnoSetup)

Windows 版本使用 [Inno Setup](https://jrsoftware.org/isinfo.php) 生成 `.exe` 安装包。安装包会创建带有 `AppUserModelID` 的开始菜单和桌面快捷方式，使 Windows SMTC（系统媒体传输控件）能正确显示应用图标和名称。

### 前置条件

```bash
# 安装 Inno Setup
winget install -e --id JRSoftware.InnoSetup
```

### 配置

安装包配置位于 `pubspec.yaml` 的 `inno_bundle` 节：

```yaml
inno_bundle:
  id: BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA  # AppId，发布后不可更改
  name: FMP
  description: "Flutter Music Player - 跨平台音乐播放器"
  publisher: FMP
  installer_icon: windows/runner/resources/app_icon.ico
  admin: false  # 不需要管理员权限安装
```

> **重要**：`id` 是 GUID 格式的 AppId，**发布后不可更改**。更改会导致用户机器将更新视为不同应用。

### SMTC AppUserModelID

`windows/runner/main.cpp` 中设置了进程级 `AppUserModelID`：

```cpp
#include <shobjidl.h>

// 在 wWinMain 开头
::SetCurrentProcessExplicitAppUserModelID(L"com.personal.fmp");
```

安装包的快捷方式也需要匹配的 `AppUserModelID`。`inno_bundle` 生成的 ISS 脚本默认不包含此项，CI 构建时会自动补丁。

### 本地构建安装包

```bash
# 方法一：一键构建（构建 Flutter + 生成安装包）
dart run inno_bundle:build --release

# 方法二：分步构建（如果 inno_bundle 无法找到 ISCC.exe）
# 1. 构建 Flutter
flutter build windows --release

# 2. 生成 ISS 脚本（跳过 Flutter 构建和 ISCC 编译）
dart run inno_bundle:build --release --no-app --no-installer

# 3. 手动编译 ISS 脚本
& "C:\Users\<用户名>\AppData\Local\Programs\Inno Setup 6\ISCC.exe" build\windows\x64\installer\Release\inno-script.iss
```

产物路径：`build\windows\x64\installer\Release\FMP-x86_64-<版本>-Installer.exe`

### 相关文件

| 文件 | 说明 |
|------|------|
| `pubspec.yaml` (`inno_bundle` 节) | 安装包配置 |
| `windows/runner/main.cpp` | `SetCurrentProcessExplicitAppUserModelID` |
| `windows/runner/resources/app_icon.ico` | 安装包和快捷方式图标 |

---

## 4. 發布新版本

### 發布流程

```bash
# 1. 確保程式碼已 commit 並 push
git add .
git commit -m "feat: ..."
git push

# 2. 打 tag 並 push（觸發 CI 構建和 Release）
git tag v1.2.0
git push origin v1.2.0
```

### CI 流程

一般驗證由 `.github/workflows/ci.yml` 負責：

```text
pull_request / main push / workflow_dispatch
       │
       ▼
CI
       │
       ├─ validate (ubuntu)
       │   ├─ flutter pub get
       │   ├─ flutter pub run build_runner build --delete-conflicting-outputs
       │   ├─ dart run slang
       │   ├─ git diff --exit-code
       │   ├─ flutter analyze
       │   └─ flutter test
       │
       ├─ build-android (ubuntu)
       │   └─ flutter build apk --release --target-platform android-arm64
       │
       └─ build-windows (windows-2022)
           └─ flutter build windows --release
```

`validate` 會確認 Isar/slang 生成檔已提交，再執行 analyzer 與測試；兩個 build job 只作為跨平台 release build 煙霧測試，不建立 GitHub Release。圖示資產由維護者在本地執行 `dart run flutter_launcher_icons` 後提交，CI 不在每次驗證時重產圖示。

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
       │   ├─ 確認生成檔已提交
       │   ├─ flutter analyze
       │   └─ flutter test
       │
       ├─ build-android (ubuntu)
       │   ├─ 按 ABI matrix 構建 arm64-v8a / armeabi-v7a / x86_64 / universal
       │   ├─ 從 tag 提取版本號寫入 pubspec.yaml
       │   ├─ 從 Secrets 解碼 keystore
       │   ├─ flutter build apk --release
       │   └─ 產物: fmp-v1.2.0-android-{abi}.apk
       │
       ├─ build-windows (windows)
       │   ├─ 從 tag 提取版本號寫入 pubspec.yaml
       │   ├─ flutter build windows --release
       │   ├─ 壓縮為 ZIP
       │   ├─ 安裝 InnoSetup + 生成安裝包
       │   ├─ 補丁 ISS 腳本（AppUserModelID + 語言修復）
       │   └─ 產物: fmp-v1.2.0-windows.zip
       │          fmp-v1.2.0-windows-installer.exe
       │
       └─ release
           ├─ 下載所有平台的產物
           ├─ 自動生成 Release Notes
           └─ 建立 GitHub Release（multi-ABI APK + ZIP + Installer + latest 穩定下載別名）
```

### 版本號規則

- Tag 格式：`v{major}.{minor}.{patch}`，如 `v1.2.0`
- CI 自動將 tag 版本寫入 `pubspec.yaml`：`version: 1.2.0+{run_number}`
- `pubspec.yaml` 中的版本號無需手動修改，CI 會覆蓋
- `+{run_number}` 是 Android `versionCode`，自動遞增

### Release 產物命名

| 平台 | 產物命名 | 說明 |
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

Windows CI 固定使用 `windows-2022`，避免 `windows-latest` 迁移到新版 Visual Studio/MSVC 后触发原生插件兼容问题。当前 `flutter_inappwebview_windows 0.6.0` 在 VS 2026 / MSVC 14.51 下会因 `<experimental/coroutine>` 弃用检查构建失败；等该插件升级或本项目完成 Windows 插件补丁并验证后，再评估恢复 `windows-latest`。

---

## 5. 应用内更新机制

### 用户操作

设置 → 关于 → 检查更新

### 技术实现

```
检查更新
  │
  ▼
GET https://api.github.com/repos/1morr/FMP/releases/latest
  │
  ├─ 比较 tag_name 与当前 app 版本
  │
  ├─ 无更新 → 提示"已是最新版本"
  │
  └─ 有更新 → 弹出对话框
       │
       ├─ 显示版本号、Release Notes、文件大小
       │
       └─ 用户点击"立即更新"
            │
            ├─ Android: 下载 APK → 调用系统安装器
            │
            └─ Windows:
                 ├─ 安装版: 下载 installer → 静默安装到当前目录 → 重启
                 └─ 便携版: 下载 ZIP → 解压 → VBS/BAT updater 等待旧进程退出 → 备份 → 替换 → 失败回滚 → 重启
```

下载与安装安全边界：
- 所有平台下载都先落到 `.part`，验证完成后才替换成正式文件。
- 新 Release 附带 `fmp-vX.Y.Z-checksums.sha256`；App 会优先使用 SHA-256 验证，并保留 asset size 检查作为兼容旧版本的最低保护。
- Android 安装前会检查“允许此来源安装应用”。未授权时，对话框会引导用户打开系统设置，回到 App 后可重新触发安装。
- Windows 便携版 updater 会等待原 FMP 进程结束，先备份当前目录，再用 `robocopy` 替换；替换失败会尝试从备份回滚。

### 相关文件

| 文件 | 说明 |
|------|------|
| `lib/services/update/update_service.dart` | GitHub API 调用、下载、平台安装逻辑 |
| `lib/providers/system/update_provider.dart` | Riverpod 状态管理 |
| `lib/ui/widgets/dialogs/update_dialog.dart` | 更新对话框 UI |
| `android/app/src/main/kotlin/com/personal/fmp/MainActivity.kt` | Android 安装来源权限 MethodChannel |

---

## 6. 常见问题

### Q: APK 安装时报 "package conflicts with an existing package"
**A:** 新旧 APK 签名密钥不同。需要先卸载旧版本再安装。确保本地和 CI 使用同一个 `release.keystore`。

### Q: CI 构建失败 "Keystore file not found"
**A:** 检查 `key.properties` 中 `storeFile` 路径是否为 `../release.keystore`（相对于 `android/app/` 目录）。

### Q: CI 构建失败 "Tag number over 30 is not supported"
**A:** `KEYSTORE_BASE64` Secret 损坏。重新运行 `certutil` 编码命令上传。

### Q: 版本号没有更新
**A:** 确认使用 `v` 开头的 tag（如 `v1.2.0`）。非 tag push 不会更新版本号。

### Q: Windows 更新时弹出 CMD 窗口
**A:** 已通过 VBScript 包装解决。更新脚本通过 `wscript` 隐藏启动。
