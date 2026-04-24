# FMP 应用内更新系统

核心文件结构见 `CLAUDE.md`。此文件记录更新流程细节。

## 核心文件

| 文件 | 说明 |
|------|------|
| `lib/services/update/update_service.dart` | GitHub Releases API、版本比较、下载、平台安装逻辑 |
| `lib/providers/update_provider.dart` | Riverpod 更新状态 |
| `lib/ui/widgets/update_dialog.dart` | 更新对话框、版本说明、下载进度 |

入口：设置页 → 关于 → 检查更新。

## Release 查询

- 请求 GitHub Releases latest API。
- `tag_name` 去掉 `v` 后与 `PackageInfo.fromPlatform()` 当前版本比较。
- 解析 assets：
  - Android 多 ABI：`fmp-<version>-android-<abi>.apk`
  - Android 旧格式：`fmp-<version>-android.apk` 当作 universal
  - Windows 安装版：`*-windows-installer.exe`
  - Windows 便携版：`*-windows.zip`

## Android

- 根据设备 ABI 选择 APK，fallback 到 universal。
- 下载到临时目录，并清理旧 `fmp-*.apk`。
- `downloadAndInstall()` 返回 APK 路径，不直接安装。
- `installApk()` 使用 `open_filex` 打开系统安装器。
- 需要 `REQUEST_INSTALL_PACKAGES` 权限。

## Windows

`UpdateInfo.isInstalledVersion` 通过当前应用目录下是否存在 `unins000.exe` 判断。

### 安装版

1. 下载 `*-windows-installer.exe` 到临时目录。
2. 使用参数启动：`/SILENT`, `/DIR=<current app dir>`, `/CLOSEAPPLICATIONS`, `/RESTARTAPPLICATIONS`。
3. 退出当前进程。

### 便携版

1. 下载 `*-windows.zip` 到临时目录。
2. 解压到临时 `fmp_update` 目录。
3. 生成 `fmp_updater.bat`，等待后 `xcopy` 覆盖当前目录并重启 exe。
4. 用 `fmp_updater.vbs` 隐藏 CMD 窗口运行 bat。
5. 退出当前进程。

启动时 `UpdateService.cleanupOldWindowsUpdateFiles()` 会清理旧更新残留。

## 版本来源

- 开发时：`pubspec.yaml` 的 `version`。
- CI 构建时：从 git tag 写入版本。
- 运行时：`package_info_plus`。

## 依赖

- `package_info_plus`
- `open_filex`
- `archive`
