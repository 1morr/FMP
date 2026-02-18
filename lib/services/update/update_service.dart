import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:archive/archive.dart';

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
}

/// 应用更新服务
class UpdateService {
  final Dio _dio;

  UpdateService() : _dio = Dio(BaseOptions(
    connectTimeout: AppConstants.updateConnectTimeout,
    receiveTimeout: AppConstants.networkReceiveTimeout,
  ));

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
      final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;

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
        }
      }

      final releaseNotes = data['body'] as String? ?? '';
      final publishedAt = DateTime.parse(data['published_at'] as String);
      final htmlUrl = data['html_url'] as String?;

      AppLogger.info('Update available: $latestVersion, APK ABIs: ${apkUrls.keys.toList()}', _tag);

      return UpdateInfo(
        version: tagName,
        releaseNotes: releaseNotes,
        apkDownloadUrls: apkUrls,
        apkSizes: apkSizes,
        windowsZipDownloadUrl: windowsZipUrl,
        windowsInstallerDownloadUrl: windowsInstallerUrl,
        publishedAt: publishedAt,
        windowsAssetSize: windowsAssetSize,
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
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = info.downloadUrl;
    if (url == null) {
      throw Exception('No download URL for current platform');
    }

    if (Platform.isAndroid) {
      await _downloadAndInstallAndroid(url, info.assetFileName, onProgress);
    } else if (Platform.isWindows) {
      if (UpdateInfo.isInstalledVersion) {
        await _downloadAndRunInstaller(url, info.assetFileName, onProgress);
      } else {
        await _downloadAndExtractZip(url, info.assetFileName, onProgress);
      }
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// Android: 下载 APK 并触发系统安装
  Future<void> _downloadAndInstallAndroid(
    String url,
    String fileName,
    void Function(int, int)? onProgress,
  ) async {
    final cacheDir = await getTemporaryDirectory();
    final filePath = '${cacheDir.path}/$fileName';

    AppLogger.info('Downloading APK to $filePath', _tag);

    await _dio.download(
      url,
      filePath,
      onReceiveProgress: onProgress,
    );

    AppLogger.info('Download complete, opening APK installer', _tag);

    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      throw Exception('Failed to open APK: ${result.message}');
    }
  }

  /// Windows 安装版: 下载 Installer 并运行（安装到当前目录）
  Future<void> _downloadAndRunInstaller(
    String url,
    String fileName,
    void Function(int, int)? onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final installerPath = '${tempDir.path}/$fileName';
    final appDir = File(Platform.resolvedExecutable).parent.path;

    AppLogger.info('Installed version detected, downloading installer to $installerPath', _tag);

    await _dio.download(
      url,
      installerPath,
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
    String fileName,
    void Function(int, int)? onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final zipPath = '${tempDir.path}/$fileName';
    final extractDir = '${tempDir.path}/fmp_update';

    AppLogger.info('Portable version detected, downloading ZIP to $zipPath', _tag);

    await _dio.download(
      url,
      zipPath,
      onReceiveProgress: onProgress,
    );

    AppLogger.info('Download complete, extracting...', _tag);

    // 解压
    final extractDirObj = Directory(extractDir);
    if (extractDirObj.existsSync()) {
      extractDirObj.deleteSync(recursive: true);
    }
    extractDirObj.createSync(recursive: true);

    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final filePath = '$extractDir/${file.name}';
      if (file.isFile) {
        final outFile = File(filePath);
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory(filePath).createSync(recursive: true);
      }
    }

    // 获取当前应用目录
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final exeName = File(Platform.resolvedExecutable).uri.pathSegments.last;

    // 创建更新批处理脚本
    final batPath = '${tempDir.path}/fmp_updater.bat';
    final vbsPath = '${tempDir.path}/fmp_updater.vbs';
    final batScript = '''@echo off
chcp 65001 >nul
timeout /t 2 /nobreak > nul
xcopy /s /y /q "$extractDir\\*" "$appDir\\"
start "" "$appDir\\$exeName"
del "$vbsPath"
del "%~f0"
''';

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
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

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
}
