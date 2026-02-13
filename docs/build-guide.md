# FMP 构建指南

本文档介绍如何在本地构建 FMP（Flutter Music Player）的 Android APK 和 Windows 安装包。

## 前置条件

| 工具 | 版本要求 | 用途 |
|------|---------|------|
| [Flutter SDK](https://flutter.dev/docs/get-started/install) | >= 3.5.0 | 跨平台框架 |
| [Java JDK](https://adoptium.net/) | 17 | Android 构建（同时提供 `keytool` 命令） |

## 初始化项目

```bash
git clone <repo-url>
cd FMP

# 安装依赖
flutter pub get

# 代码生成（Isar models、i18n 等）
flutter pub run build_runner build --delete-conflicting-outputs

# 生成应用图标
dart run flutter_launcher_icons
```

## 构建 Android APK

```bash
flutter build apk --release
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`

### 签名密钥（可选）

不配置签名密钥也能构建，APK 会使用 debug 签名。唯一的影响是：**不同签名的 APK 无法覆盖安装**（系统会报 "package conflicts"），需要先卸载旧版本。

如果需要固定签名（使安装更新时无需卸载），按以下步骤配置：

**1. 生成 Keystore：**

`keytool` 是 Java JDK 自带的命令行工具，安装 JDK 后即可使用。

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

> 如果 `keytool` 不在 PATH 中，完整路径通常在 `C:\Program Files\Java\jdk-17\bin\keytool.exe`

**2. 创建 `android/key.properties`：**

```properties
storePassword=<你的密码>
keyPassword=<你的密码>
keyAlias=fmp
storeFile=../release.keystore
```

`build.gradle.kts` 会自动检测该文件：存在则使用你的 keystore 签名，不存在则 fallback 到 debug 签名。

> `key.properties` 和 `release.keystore` 均已在 `.gitignore` 中，不会被提交。

## 构建 Windows

### 仅构建 EXE（免安装版）

```bash
flutter build windows --release
```

产物目录：`build\windows\x64\runner\Release\`

可以直接运行 `fmp.exe`，但 Windows SMTC（系统媒体传输控件）不会正确显示应用图标和名称。需要通过安装包安装才能完整支持 SMTC。

### 构建安装包

安装包使用 [Inno Setup](https://jrsoftware.org/isinfo.php) 生成 `.exe` 安装程序。安装后会创建带有 `AppUserModelID` 的开始菜单和桌面快捷方式，使 SMTC 能正确识别应用。

#### 前置条件

安装 Inno Setup（仅构建安装包时需要）：

```bash
winget install -e --id JRSoftware.InnoSetup
```

#### 工作原理

项目使用 [`inno_bundle`](https://pub.dev/packages/inno_bundle) Dart 包（已配置在 `dev_dependencies` 中）来自动生成 Inno Setup 脚本。它读取 `pubspec.yaml` 中的 `inno_bundle` 配置节，扫描 Flutter 构建产物目录，生成一个 `.iss` 脚本文件，然后调用 Inno Setup 的命令行编译器 `ISCC.exe` 将其编译为安装包。

流程：`pubspec.yaml 配置` → `inno_bundle 生成 .iss 脚本` → `ISCC.exe 编译为 .exe 安装包`

#### 方法一：一键构建

```bash
dart run inno_bundle:build --release
```

这个命令会依次执行：构建 Flutter → 生成 ISS 脚本 → 调用 ISCC.exe 编译安装包。

#### 方法二：分步构建

`inno_bundle` 调用 `ISCC.exe` 时可能因路径含空格而失败，此时可以分步操作：

```bash
# 1. 构建 Flutter（如果已构建可跳过）
flutter build windows --release

# 2. 仅生成 ISS 脚本（--no-app 跳过 Flutter 构建，--no-installer 跳过 ISCC 编译）
dart run inno_bundle:build --release --no-app --no-installer

# 3. 手动调用 ISCC.exe 编译 ISS 脚本
& "C:\Users\<用户名>\AppData\Local\Programs\Inno Setup 6\ISCC.exe" build\windows\x64\installer\Release\inno-script.iss
```

产物路径：`build\windows\x64\installer\Release\FMP-x86_64-<版本>-Installer.exe`

### SMTC 与 AppUserModelID

Windows SMTC 通过 `AppUserModelID` 识别应用身份。本项目在两个位置设置了该 ID：

1. **进程级**（`windows/runner/main.cpp`）：

```cpp
#include <shobjidl.h>

// 在 wWinMain 开头
::SetCurrentProcessExplicitAppUserModelID(L"com.personal.fmp");
```

2. **快捷方式级**（InnoSetup 安装包）：

安装包创建的开始菜单和桌面快捷方式包含匹配的 `AppUserModelID: "com.personal.fmp"`。`inno_bundle` 默认不生成此属性，CI 构建时会自动补丁。

> 两者必须一致，否则 SMTC 无法正确显示应用信息。

### 安装包配置

配置位于 `pubspec.yaml` 的 `inno_bundle` 节：

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

## 常用命令

```bash
# 运行（调试模式）
flutter run

# 静态分析
flutter analyze

# 运行测试
flutter test

# 重新生成代码（修改 Isar model 后必须执行）
flutter pub run build_runner build --delete-conflicting-outputs
```

## 相关文件

| 文件 | 说明 |
|------|------|
| `pubspec.yaml` | 依赖和安装包配置 |
| `windows/runner/main.cpp` | Windows 入口，`SetCurrentProcessExplicitAppUserModelID` |
| `windows/runner/resources/app_icon.ico` | 应用和安装包图标 |
| `android/app/build.gradle.kts` | Android 签名和构建配置 |

---

## 更多资源

- [返回 README](../README.md)
- [开发文档](development.md) - 项目架构、技术栈、开发规范
