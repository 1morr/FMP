import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';

const _tag = 'UpdateService';
const _repoOwner = '1morr';
const _repoName = 'FMP';

/// 更新信息
class UpdateInfo {
  final String version;
  final String releaseNotes;

  /// APK download URLs keyed by ABI (arm64-v8a, armeabi-v7a, x86_64, universal)
  final Map<String, String> apkDownloadUrls;

  /// APK sizes keyed by ABI
  final Map<String, int> apkSizes;
  final String? windowsZipDownloadUrl;
  final String? windowsInstallerDownloadUrl;
  final DateTime publishedAt;
  final int? windowsAssetSize;
  final Map<String, String> assetSha256s;
  final String? htmlUrl; // GitHub release page URL

  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    this.apkDownloadUrls = const {},
    this.apkSizes = const {},
    this.windowsZipDownloadUrl,
    this.windowsInstallerDownloadUrl,
    required this.publishedAt,
    this.windowsAssetSize,
    this.assetSha256s = const {},
    this.htmlUrl,
  });

  /// 是否为安装版（检测 unins000.exe）
  static bool get isInstalledVersion {
    if (!Platform.isWindows) return false;
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return File('$appDir\\unins000.exe').existsSync();
  }

  /// 设备 ABI（仅 Android）
  static String? _deviceAbi;

  /// 获取设备主 ABI
  static Future<String> getDeviceAbi() async {
    if (_deviceAbi != null) return _deviceAbi!;
    if (!Platform.isAndroid) return 'universal';
    try {
      final result = await Process.run('getprop', ['ro.product.cpu.abi']);
      final abi = (result.stdout as String).trim();
      if (['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(abi)) {
        _deviceAbi = abi;
        return abi;
      }
    } catch (_) {}
    _deviceAbi = 'universal';
    return 'universal';
  }

  /// 当前平台的下载 URL
  String? get downloadUrl {
    if (Platform.isAndroid) {
      final abi = _deviceAbi ?? 'universal';
      return apkDownloadUrls[abi] ?? apkDownloadUrls['universal'];
    }
    if (Platform.isWindows) {
      return isInstalledVersion
          ? windowsInstallerDownloadUrl
          : windowsZipDownloadUrl;
    }
    return null;
  }

  /// 当前平台的资源大小
  int? get assetSize {
    if (Platform.isAndroid) {
      final abi = _deviceAbi ?? 'universal';
      return apkSizes[abi] ?? apkSizes['universal'];
    }
    return windowsAssetSize;
  }

  /// 当前设备的 ABI 标签（用于 UI 显示）
  String get deviceAbiLabel => _deviceAbi ?? 'universal';

  /// 当前平台的资源文件名
  String get assetFileName {
    if (Platform.isAndroid) {
      final abi = _deviceAbi ?? 'universal';
      return 'fmp-$version-android-$abi.apk';
    }
    if (isInstalledVersion) return 'fmp-$version-windows-installer.exe';
    return 'fmp-$version-windows.zip';
  }

  String? get assetSha256 => assetSha256s[assetFileName];
}

class UpdateIntegrityException implements Exception {
  final String message;

  const UpdateIntegrityException(this.message);

  @override
  String toString() => message;
}

/// 应用更新服务
class UpdateService {
  static const MethodChannel _platformChannel =
      MethodChannel('com.personal.fmp/platform');

  final Dio _dio;

  UpdateService()
      : _dio = Dio(BaseOptions(
          connectTimeout: AppConstants.updateConnectTimeout,
          receiveTimeout: AppConstants.networkReceiveTimeout,
        ));

  /// 检查已下载的更新文件是否存在且完整
  Future<String?> getExistingDownloadPath(UpdateInfo info) async {
    if (!Platform.isAndroid) return null;
    final cacheDir = await getTemporaryDirectory();
    final filePath = '${cacheDir.path}/${info.assetFileName}';
    final file = File(filePath);
    if (!file.existsSync()) return null;
    try {
      await _validateDownloadedAsset(
        filePath,
        expectedSize: info.assetSize,
        expectedSha256: info.assetSha256,
      );
    } on UpdateIntegrityException catch (e) {
      AppLogger.info('Existing APK failed integrity check, deleting: $e', _tag);
      await file.delete();
      return null;
    }
    AppLogger.info('Found existing APK: $filePath', _tag);
    return filePath;
  }

  /// 打开 APK 安装器（Android）
  Future<void> installApk(String filePath) async {
    AppLogger.info('Opening APK installer: $filePath', _tag);
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      throw Exception('Failed to open APK: ${result.message}');
    }
  }

  /// 清理临时目录中旧的 Windows 更新文件
  /// 包括：fmp-*.exe, fmp-*.zip, fmp_updater.bat, fmp_updater.vbs, fmp_update/
  /// 仅在 Windows 上调用，Android 由 _cleanupOldApks 在下载时处理
  static Future<void> cleanupOldWindowsUpdateFiles() async {
    if (!Platform.isWindows) return;
    try {
      final cacheDir = await getTemporaryDirectory();
      final dir = Directory(cacheDir.path);

      for (final entity in dir.listSync()) {
        final name = p.basename(entity.path);
        try {
          if (entity is File && _isWindowsUpdateFile(name)) {
            entity.deleteSync();
            AppLogger.info('Cleaned up old update file: $name', _tag);
          } else if (entity is Directory && name == 'fmp_update') {
            entity.deleteSync(recursive: true);
            AppLogger.info('Cleaned up old update directory: $name', _tag);
          }
        } catch (_) {}
      }
    } catch (e) {
      AppLogger.warning('Failed to cleanup old update files: $e', _tag);
    }
  }

  static bool _isWindowsUpdateFile(String name) {
    // fmp-v1.6.5-windows-installer.exe, fmp-v1.6.5-windows.zip
    if (name.startsWith('fmp-') &&
        (name.endsWith('.exe') || name.endsWith('.zip'))) {
      return true;
    }
    // fmp_updater.bat, fmp_updater.vbs（更新脚本残留）
    if (name == 'fmp_updater.bat' || name == 'fmp_updater.vbs') {
      return true;
    }
    return false;
  }

  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return true;
    final result =
        await _platformChannel.invokeMethod<bool>('canRequestPackageInstalls');
    return result ?? false;
  }

  Future<void> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) return;
    await _platformChannel.invokeMethod<bool>('openInstallPermissionSettings');
  }

  @visibleForTesting
  static Map<String, String> parseSha256ManifestForTest(String content) {
    return _parseSha256Manifest(content);
  }

  @visibleForTesting
  static Future<void> validateDownloadedAssetForTest(
    String filePath, {
    int? expectedSize,
    String? expectedSha256,
  }) {
    return _validateDownloadedAsset(
      filePath,
      expectedSize: expectedSize,
      expectedSha256: expectedSha256,
    );
  }

  @visibleForTesting
  static String buildPortableUpdaterBatchForTest({
    required String extractDir,
    required String appDir,
    required String exeName,
    required String vbsPath,
    required int appPid,
  }) {
    return _buildPortableUpdaterBatch(
      extractDir: extractDir,
      appDir: appDir,
      exeName: exeName,
      vbsPath: vbsPath,
      appPid: appPid,
    );
  }

  @visibleForTesting
  static String safeZipEntryDestinationForTest(
    String extractDir,
    String entryName,
  ) {
    return _safeZipEntryDestination(extractDir, entryName);
  }

  static String _safeZipEntryDestination(String extractDir, String entryName) {
    final normalizedName = entryName.replaceAll('\\', '/');
    final parts = p.posix.split(normalizedName);
    final hasDrivePrefix = RegExp(r'^[A-Za-z]:').hasMatch(entryName);

    if (normalizedName.startsWith('/') ||
        normalizedName.startsWith('\\') ||
        hasDrivePrefix ||
        parts.any((part) => part == '..')) {
      throw FormatException('Unsafe ZIP entry path: $entryName');
    }

    final normalizedExtractDir = p.normalize(extractDir);
    final destination =
        p.normalize(p.joinAll([normalizedExtractDir, ...parts]));
    final extractWithSeparator = normalizedExtractDir.endsWith(p.separator)
        ? normalizedExtractDir
        : '$normalizedExtractDir${p.separator}';

    if (destination != normalizedExtractDir &&
        !destination.startsWith(extractWithSeparator)) {
      throw FormatException('Unsafe ZIP entry path: $entryName');
    }

    return destination;
  }

  /// 检查是否有新版本
  /// 返回 null 表示已是最新版本
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      // Pre-fetch device ABI on Android (cached for later use)
      if (Platform.isAndroid) {
        await UpdateInfo.getDeviceAbi();
      }

      final response = await _dio.get(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
        options: Options(headers: {
          'Accept': 'application/vnd.github.v3+json',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('GitHub API returned ${response.statusCode}');
      }

      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'] as String; // e.g. "v1.2.0"
      final latestVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;

      // 获取当前版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      AppLogger.info('Current: $currentVersion, Latest: $latestVersion', _tag);

      // 比较版本号
      if (!_isNewerVersion(currentVersion, latestVersion)) {
        AppLogger.info('Already up to date', _tag);
        return null;
      }

      // 解析资源
      final assets = data['assets'] as List<dynamic>;
      final apkUrls = <String, String>{};
      final apkSizes = <String, int>{};
      String? windowsZipUrl;
      String? windowsInstallerUrl;
      int? windowsAssetSize;
      String? checksumUrl;

      // ABI pattern: fmp-v1.2.0-android-arm64-v8a.apk (greedy .+ backtracks to last -android-)
      final abiPattern = RegExp(r'fmp-.+-android-(.+)\.apk$');

      for (final asset in assets) {
        final name = asset['name'] as String;
        final url = asset['browser_download_url'] as String;
        final size = asset['size'] as int?;

        if (name.endsWith('.apk')) {
          final match = abiPattern.firstMatch(name);
          if (match != null) {
            // New multi-arch format: fmp-v1.2.0-android-{abi}.apk
            final abi = match.group(1)!;
            apkUrls[abi] = url;
            if (size != null) apkSizes[abi] = size;
          } else {
            // Legacy single APK format: fmp-v1.2.0-android.apk → treat as universal
            apkUrls['universal'] = url;
            if (size != null) apkSizes['universal'] = size;
          }
        } else if (name.endsWith('-windows-installer.exe')) {
          windowsInstallerUrl = url;
          if (Platform.isWindows && UpdateInfo.isInstalledVersion) {
            windowsAssetSize = size;
          }
        } else if (name.endsWith('-windows.zip')) {
          windowsZipUrl = url;
          if (Platform.isWindows && !UpdateInfo.isInstalledVersion) {
            windowsAssetSize = size;
          }
        } else if (name.endsWith('-checksums.sha256')) {
          checksumUrl = url;
        }
      }

      final assetSha256s = checksumUrl == null
          ? const <String, String>{}
          : await _fetchSha256Manifest(checksumUrl);

      final releaseNotes = data['body'] as String? ?? '';
      final publishedAt = DateTime.parse(data['published_at'] as String);
      final htmlUrl = data['html_url'] as String?;

      AppLogger.info(
          'Update available: $latestVersion, APK ABIs: ${apkUrls.keys.toList()}',
          _tag);

      return UpdateInfo(
        version: tagName,
        releaseNotes: releaseNotes,
        apkDownloadUrls: apkUrls,
        apkSizes: apkSizes,
        windowsZipDownloadUrl: windowsZipUrl,
        windowsInstallerDownloadUrl: windowsInstallerUrl,
        publishedAt: publishedAt,
        windowsAssetSize: windowsAssetSize,
        assetSha256s: assetSha256s,
        htmlUrl: htmlUrl,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        AppLogger.warning('No releases found', _tag);
        return null;
      }
      AppLogger.error('Failed to check for updates', e, null, _tag);
      rethrow;
    } catch (e, st) {
      AppLogger.error('Failed to check for updates', e, st, _tag);
      rethrow;
    }
  }

  /// 下载并安装更新
  /// Android: 返回下载的文件路径（不触发安装）
  /// Windows: 直接执行安装并退出应用
  Future<String> downloadAndInstall(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = info.downloadUrl;
    if (url == null) {
      throw Exception('No download URL for current platform');
    }

    if (Platform.isAndroid) {
      return _downloadAndroid(url, info, onProgress);
    } else if (Platform.isWindows) {
      if (UpdateInfo.isInstalledVersion) {
        await _downloadAndRunInstaller(url, info, onProgress);
      } else {
        await _downloadAndExtractZip(url, info, onProgress);
      }
      // Windows paths exit the app, this won't be reached
      return '';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// Android: 下载 APK，清理旧文件，返回文件路径
  Future<String> _downloadAndroid(
    String url,
    UpdateInfo info,
    void Function(int, int)? onProgress,
  ) async {
    final cacheDir = await getTemporaryDirectory();
    final fileName = info.assetFileName;
    final filePath = '${cacheDir.path}/$fileName';

    // 清理同目录下的旧 APK（保留当前目标文件名）
    await _cleanupOldApks(cacheDir.path, fileName);

    AppLogger.info('Downloading APK to $filePath', _tag);

    await _downloadVerifiedAsset(
      url,
      filePath,
      expectedSize: info.assetSize,
      expectedSha256: info.assetSha256,
      onReceiveProgress: onProgress,
    );

    AppLogger.info('Download complete: $filePath', _tag);
    return filePath;
  }

  /// 清理临时目录中同类型的旧 APK 文件
  Future<void> _cleanupOldApks(String dirPath, String keepFileName) async {
    try {
      final dir = Directory(dirPath);
      for (final entity in dir.listSync()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name != keepFileName &&
              name.startsWith('fmp-') &&
              name.endsWith('.apk')) {
            entity.deleteSync();
            AppLogger.info('Removed old APK: $name', _tag);
          }
        }
      }
    } catch (e) {
      AppLogger.warning('Failed to cleanup old APKs: $e', _tag);
    }
  }

  /// Windows 安装版: 下载 Installer 并运行（安装到当前目录）
  Future<void> _downloadAndRunInstaller(
    String url,
    UpdateInfo info,
    void Function(int, int)? onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = info.assetFileName;
    final installerPath = '${tempDir.path}/$fileName';
    final appDir = File(Platform.resolvedExecutable).parent.path;

    AppLogger.info(
        'Installed version detected, downloading installer to $installerPath',
        _tag);

    await _downloadVerifiedAsset(
      url,
      installerPath,
      expectedSize: info.assetSize,
      expectedSha256: info.assetSha256,
      onReceiveProgress: onProgress,
    );

    AppLogger.info('Download complete, launching installer to $appDir', _tag);

    // /DIR= 强制安装到当前应用目录，避免安装到默认 Program Files
    await Process.start(
      installerPath,
      ['/SILENT', '/DIR=$appDir', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }

  /// Windows 解压版: 下载 ZIP、解压覆盖到当前目录
  Future<void> _downloadAndExtractZip(
    String url,
    UpdateInfo info,
    void Function(int, int)? onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = info.assetFileName;
    final zipPath = '${tempDir.path}/$fileName';
    final extractDir = '${tempDir.path}/fmp_update';

    AppLogger.info(
        'Portable version detected, downloading ZIP to $zipPath', _tag);

    await _downloadVerifiedAsset(
      url,
      zipPath,
      expectedSize: info.assetSize,
      expectedSha256: info.assetSha256,
      onReceiveProgress: onProgress,
    );

    AppLogger.info('Download complete, extracting...', _tag);

    // 解压
    final extractDirObj = Directory(extractDir);
    if (extractDirObj.existsSync()) {
      extractDirObj.deleteSync(recursive: true);
    }
    extractDirObj.createSync(recursive: true);

    await Isolate.run(() => _extractZipToDirectorySync(zipPath, extractDir));

    // 获取当前应用目录
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final exeName = File(Platform.resolvedExecutable).uri.pathSegments.last;
    final appPid = pid;

    // 创建更新批处理脚本
    final batPath = '${tempDir.path}/fmp_updater.bat';
    final vbsPath = '${tempDir.path}/fmp_updater.vbs';
    final batScript = _buildPortableUpdaterBatch(
      extractDir: extractDir,
      appDir: appDir,
      exeName: exeName,
      vbsPath: vbsPath,
      appPid: appPid,
    );

    // 用 VBScript 隐藏 CMD 窗口启动 bat
    final vbsScript =
        'CreateObject("WScript.Shell").Run """${batPath.replaceAll('/', '\\')}""", 0, False';

    File(batPath).writeAsStringSync(batScript);
    File(vbsPath).writeAsStringSync(vbsScript);

    AppLogger.info('Starting updater script and exiting...', _tag);

    await Process.start(
      'wscript',
      [vbsPath],
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }

  /// 比较版本号，判断 latest 是否比 current 新
  bool _isNewerVersion(String current, String latest) {
    final currentParts =
        current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final latestParts =
        latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // 补齐长度
    while (currentParts.length < 3) {
      currentParts.add(0);
    }
    while (latestParts.length < 3) {
      latestParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  Future<void> _downloadVerifiedAsset(
    String url,
    String destinationPath, {
    int? expectedSize,
    String? expectedSha256,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final partialPath = '$destinationPath.part';
    final destination = File(destinationPath);
    final partial = File(partialPath);

    if (await partial.exists()) {
      await partial.delete();
    }

    try {
      await _dio.download(
        url,
        partialPath,
        onReceiveProgress: onReceiveProgress,
      );
      await _validateDownloadedAsset(
        partialPath,
        expectedSize: expectedSize,
        expectedSha256: expectedSha256,
      );
      if (await destination.exists()) {
        await destination.delete();
      }
      await partial.rename(destinationPath);
    } catch (_) {
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }
}

Future<Map<String, String>> _fetchSha256Manifest(String url) async {
  try {
    final dio = Dio(BaseOptions(
      connectTimeout: AppConstants.updateConnectTimeout,
      receiveTimeout: AppConstants.networkReceiveTimeout,
    ));
    final response = await dio.get<String>(url);
    final body = response.data;
    if (body == null) return const {};
    return _parseSha256Manifest(body);
  } catch (e) {
    AppLogger.warning('Failed to fetch update checksum manifest: $e', _tag);
    return const {};
  }
}

Map<String, String> _parseSha256Manifest(String content) {
  final checksums = <String, String>{};
  final linePattern = RegExp(
    r'^([a-fA-F0-9]{64})\s+\*?(.+)$',
  );
  for (final rawLine in content.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = linePattern.firstMatch(line);
    if (match == null) continue;
    checksums[p.basename(match.group(2)!.trim())] =
        match.group(1)!.toLowerCase();
  }
  return checksums;
}

Future<void> _validateDownloadedAsset(
  String filePath, {
  int? expectedSize,
  String? expectedSha256,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw const UpdateIntegrityException('Downloaded update file is missing');
  }

  if (expectedSize != null) {
    final actualSize = await file.length();
    if (actualSize != expectedSize) {
      throw UpdateIntegrityException(
        'Downloaded update size mismatch: expected $expectedSize, got $actualSize',
      );
    }
  }

  if (expectedSha256 != null && expectedSha256.isNotEmpty) {
    final digest = await sha256.bind(file.openRead()).first;
    final actualSha256 = digest.toString().toLowerCase();
    if (actualSha256 != expectedSha256.toLowerCase()) {
      throw UpdateIntegrityException(
        'Downloaded update checksum mismatch: expected $expectedSha256, got $actualSha256',
      );
    }
  }
}

String _buildPortableUpdaterBatch({
  required String extractDir,
  required String appDir,
  required String exeName,
  required String vbsPath,
  required int appPid,
}) {
  final backupDir = p.join(p.dirname(extractDir), 'fmp_update_backup');
  return '''@echo off
setlocal
chcp 65001 >nul
set "SRC=$extractDir"
set "DST=$appDir"
set "BACKUP=$backupDir"
set "APP_EXE=$exeName"

:wait_app
tasklist /FI "PID eq $appPid" 2>nul | find "$appPid" >nul
if not errorlevel 1 (
  timeout /t 1 /nobreak >nul
  goto wait_app
)

if exist "%BACKUP%" rmdir /s /q "%BACKUP%"
mkdir "%BACKUP%"
robocopy "%DST%" "%BACKUP%" /MIR /XD fmp_update_backup >nul
if errorlevel 8 goto rollback

robocopy "%SRC%" "%DST%" /MIR >nul
if errorlevel 8 goto rollback

start "" "%DST%\\%APP_EXE%"
goto cleanup

:rollback
if exist "%BACKUP%" robocopy "%BACKUP%" "%DST%" /MIR >nul
start "" "%DST%\\%APP_EXE%"

:cleanup
if exist "%SRC%" rmdir /s /q "%SRC%"
if exist "%BACKUP%" rmdir /s /q "%BACKUP%"
del "$vbsPath"
del "%~f0"
endlocal
''';
}

void _extractZipToDirectorySync(String zipPath, String extractDir) {
  final input = InputFileStream(zipPath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    for (final file in archive) {
      final filePath = UpdateService._safeZipEntryDestination(
        extractDir,
        file.name,
      );
      if (file.isFile) {
        File(filePath).parent.createSync(recursive: true);
        final output = OutputFileStream(filePath);
        try {
          file.writeContent(output);
        } finally {
          output.closeSync();
        }
      } else {
        Directory(filePath).createSync(recursive: true);
      }
    }
  } finally {
    input.closeSync();
  }
}
