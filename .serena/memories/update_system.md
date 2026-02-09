# 应用内更新系统

## 概述

FMP 支持应用内检查更新，通过 GitHub Releases API 获取最新版本信息，支持 Android APK 和 Windows EXE 的下载与安装。

## 核心文件

| 文件 | 说明 |
|------|------|
| `lib/services/update/update_service.dart` | 核心服务：GitHub API 调用、版本比较、下载、平台安装逻辑 |
| `lib/providers/update_provider.dart` | Riverpod 状态管理（StateNotifier + StateNotifierProvider） |
| `lib/ui/widgets/update_dialog.dart` | 更新对话框 UI，显示版本、Release Notes、下载进度 |

## 入口

设置页 → 关于 → 检查更新（`_CheckUpdateListTile` in `settings_page.dart`）

## 状态流转

```
UpdateState:
  - checking: 正在检查
  - upToDate: 已是最新
  - updateAvailable: 有新版本可用
  - downloading: 下载中（含进度）
  - error: 出错
```

## 更新流程

### 检查更新
1. 调用 `GET https://api.github.com/repos/1morr/FMP/releases/latest`
2. 解析 `tag_name`（如 `v1.2.0`）与当前 app 版本比较
3. 有更新则弹出 `UpdateDialog`

### Android 安装
1. 下载 APK 到外部存储 `getExternalStorageDirectory()`
2. 使用 `open_filex` 包调用系统安装器
3. 需要 `REQUEST_INSTALL_PACKAGES` 权限（已在 AndroidManifest.xml 配置）

### Windows 安装
1. 下载 ZIP 到临时目录
2. 使用 `archive` 包解压
3. 创建 `fmp_updater.bat` 批处理脚本（等待 2 秒 → 复制文件 → 重启应用 → 自删除）
4. 创建 `fmp_updater.vbs` 包装脚本，使用 `WScript.Shell` 隐藏 CMD 窗口
5. 通过 `wscript` 启动 VBS，实现静默更新

## 依赖

```yaml
# pubspec.yaml
dependencies:
  package_info_plus: ^8.0.0  # 获取当前 app 版本
  open_filex: ^4.5.0         # Android APK 安装
  archive: ^4.0.2            # Windows ZIP 解压
```

## 版本号来源

- 开发时：`pubspec.yaml` 中的 `version` 字段
- CI 构建时：从 git tag 自动提取并写入 `pubspec.yaml`
- 运行时：通过 `PackageInfo.fromPlatform()` 读取编译后的版本

## 签名配置

Android APK 必须使用固定签名密钥，否则无法覆盖安装。

- 本地：`android/key.properties` + `android/release.keystore`
- CI：从 GitHub Secrets 解码 keystore

详见 `docs/build-and-release.md`

## 相关 Secrets

| Secret | 说明 |
|--------|------|
| `KEYSTORE_BASE64` | release.keystore 的 base64 编码 |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_PASSWORD` | key 密码 |
| `KEY_ALIAS` | key 别名（fmp） |
