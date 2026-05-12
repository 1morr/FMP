# FMP 构建与发布指南

## 概述

FMP 使用 GitHub Actions 自动构建 Android APK 和 Windows EXE，通过 git tag 触发 Release 发布。也可以手动触发 workflow 做非 Release 构建验证。应用内置检查更新功能，用户可在设置页手动检查并下载新版本。

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
  -storepass <你的密码> \
  -keypass <你的密码> \
  -dname "CN=FMP,OU=Personal,O=Personal,L=Unknown,ST=Unknown,C=US"
```

> Windows 上 `keytool` 路径通常在 `C:\Program Files\Java\jdk-17\bin\keytool.exe`

### 创建 key.properties（本地构建用）

在 `android/key.properties` 写入：

```properties
storePassword=<你的密码>
keyPassword=<你的密码>
keyAlias=fmp
storeFile=../release.keystore
```

> `key.properties` 和 `release.keystore` 均已在 `.gitignore` 中，不会被提交。

### 验证 Keystore

```bash
keytool -list -keystore android/release.keystore -storepass <你的密码>
```

应输出包含 `fmp` alias 和 `PrivateKeyEntry` 的信息。

---

## 2. GitHub Secrets 设置

CI 构建需要 4 个 Repository Secrets。**Secrets 只需设置一次**，设置后永久保存在 GitHub 仓库中。只有在重新生成 keystore 后才需要重新设置。

### 前置条件

```bash
# 确认已登录
gh auth status
```

### 一键设置所有 Secrets

```powershell
# 1. 上传 Keystore（使用 certutil 编码为 base64）
certutil -encode android/release.keystore "$env:TEMP\ks.txt"
Get-Content "$env:TEMP\ks.txt" | Where-Object { $_ -notmatch 'CERTIFICATE' } | gh secret set KEYSTORE_BASE64 --repo 1morr/FMP

# 2. 设置密码和别名
gh secret set KEYSTORE_PASSWORD --repo 1morr/FMP --body "<你的密码>"
gh secret set KEY_PASSWORD --repo 1morr/FMP --body "<你的密码>"
gh secret set KEY_ALIAS --repo 1morr/FMP --body "fmp"
```

> Linux/macOS 用 `base64 android/release.keystore | gh secret set KEYSTORE_BASE64`

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

## 4. 发布新版本

### 发布流程

```bash
# 1. 确保代码已 commit 并 push
git add .
git commit -m "feat: ..."
git push

# 2. 打 tag 并 push（触发 CI 构建和 Release）
git tag v1.2.0
git push origin v1.2.0
```

### 自动化流程

```
git push origin v1.2.0
       │
       ▼
GitHub Actions (build.yml)
       │
       ├─ build-android (ubuntu)
       │   ├─ 按 ABI matrix 构建 arm64-v8a / armeabi-v7a / x86_64 / universal
       │   ├─ 从 tag 提取版本号写入 pubspec.yaml
       │   ├─ 从 Secrets 解码 keystore
       │   ├─ flutter build apk --release
       │   └─ 产物: fmp-v1.2.0-android-{abi}.apk
       │
       ├─ build-windows (windows)
       │   ├─ 从 tag 提取版本号写入 pubspec.yaml
       │   ├─ flutter build windows --release
       │   ├─ 压缩为 ZIP
       │   ├─ 安装 InnoSetup + 生成安装包
       │   ├─ 补丁 ISS 脚本（AppUserModelID + 语言修复）
       │   └─ 产物: fmp-v1.2.0-windows.zip
       │          fmp-v1.2.0-windows-installer.exe
       │
       └─ release
           ├─ 下载所有平台的产物
           ├─ 自动生成 Release Notes
           └─ 创建 GitHub Release（multi-ABI APK + ZIP + Installer）
```

### 版本号规则

- Tag 格式：`v{major}.{minor}.{patch}`，如 `v1.2.0`
- CI 自动将 tag 版本写入 `pubspec.yaml`：`version: 1.2.0+{run_number}`
- `pubspec.yaml` 中的版本号无需手动修改，CI 会覆盖
- `+{run_number}` 是 Android `versionCode`，自动递增

### Release 产物命名

| Platform | Asset pattern | Notes |
|----------|---------------|-------|
| Android | `fmp-v1.2.0-android-arm64-v8a.apk` | ABI-specific APK |
| Android | `fmp-v1.2.0-android-armeabi-v7a.apk` | ABI-specific APK |
| Android | `fmp-v1.2.0-android-x86_64.apk` | Emulator/x86_64 APK |
| Android | `fmp-v1.2.0-android-universal.apk` | Universal fallback and README download link |
| Windows | `fmp-v1.2.0-windows.zip` | Portable build |
| Windows | `fmp-v1.2.0-windows-installer.exe` | Installed build |

The in-app updater accepts the multi-ABI Android naming format and falls back to `universal` when no matching ABI asset is available.

### 非 Release 构建

当前 workflow 只监听 tag push 和手动 `workflow_dispatch`。手动在非 tag ref 上触发时会执行 `build-only` job，但不会创建 Release；如果以后重新加入普通 branch push 触发，非 tag push 也会走这条验证路径。

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
                 └─ 便携版: 下载 ZIP → 解压 → VBS 脚本静默替换文件 → 重启
```

### 相关文件

| 文件 | 说明 |
|------|------|
| `lib/services/update/update_service.dart` | GitHub API 调用、下载、平台安装逻辑 |
| `lib/providers/update_provider.dart` | Riverpod 状态管理 |
| `lib/ui/widgets/update_dialog.dart` | 更新对话框 UI |

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
