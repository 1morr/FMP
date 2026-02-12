import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/logger.dart';

const _tag = 'UpdateService';
const _repoOwner = '1morr';
const _repoName = 'FMP';

/// 更新信息
class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String? apkDownloadUrl;
  final String? windowsInstallerDownloadUrl;
  final DateTime publishedAt;
  final int? assetSize; // bytes
  final String? htmlUrl; // GitHub release page URL

  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    this.apkDownloadUrl,
    this.windowsInstallerDownloadUrl,
    required this.publishedAt,
    this.assetSize,
    this.htmlUrl,
  });

  /// 当前平台的下载 URL
  String? get downloadUrl =>
      Platform.isAndroid ? apkDownloadUrl : windowsInstallerDownloadUrl;

  /// 当前平台的资源文件名
  String get assetFileName => Platform.isAndroid
      ? 'fmp-$version-android.apk'
      : 'fmp-$version-windows-installer.exe';
}

/// 应用更新服务
class UpdateService {
  final Dio _dio;

  UpdateService() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// 检查是否有新版本
  /// 返回 null 表示已是最新版本
  Future<UpdateInfo?> checkForUpdate() async {
    try {
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
      String? apkUrl;
      String? windowsInstallerUrl;
      int? assetSize;

      for (final asset in assets) {
        final name = asset['name'] as String;
        final url = asset['browser_download_url'] as String;
        final size = asset['size'] as int?;

        if (name.endsWith('.apk')) {
          apkUrl = url;
          if (Platform.isAndroid) assetSize = size;
        } else if (name.endsWith('-windows-installer.exe')) {
          windowsInstallerUrl = url;
          if (Platform.isWindows) assetSize = size;
        }
      }

      final releaseNotes = data['body'] as String? ?? '';
      final publishedAt = DateTime.parse(data['published_at'] as String);
      final htmlUrl = data['html_url'] as String?;

      AppLogger.info('Update available: $latestVersion', _tag);

      return UpdateInfo(
        version: tagName,
        releaseNotes: releaseNotes,
        apkDownloadUrl: apkUrl,
        windowsInstallerDownloadUrl: windowsInstallerUrl,
        publishedAt: publishedAt,
        assetSize: assetSize,
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
      await _downloadAndInstallWindows(url, info.assetFileName, onProgress);
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

  /// Windows: 下载 Installer 并运行
  Future<void> _downloadAndInstallWindows(
    String url,
    String fileName,
    void Function(int, int)? onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final installerPath = '${tempDir.path}/$fileName';

    AppLogger.info('Downloading installer to $installerPath', _tag);

    // 下载 Installer
    await _dio.download(
      url,
      installerPath,
      onReceiveProgress: onProgress,
    );

    AppLogger.info('Download complete, launching installer...', _tag);

    // 启动安装程序（静默更新模式，完成后自动重启应用）
    await Process.start(
      installerPath,
      ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );

    // 退出当前应用，让安装程序接管
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
