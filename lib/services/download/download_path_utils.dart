import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../saf/saf_service.dart';

/// 下载路径计算工具类
///
/// 提供统一的路径计算逻辑，支持新的路径格式：
/// {baseDir}/{playlistName}/{sourceId}_{parentTitle}/P{n}.m4a
class DownloadPathUtils {
  DownloadPathUtils._();

  /// 计算下载路径
  ///
  /// 格式: {baseDir}/{playlistName}/{sourceId}_{parentTitle}/P{n}.m4a
  ///
  /// [baseDir] 下载根目录
  /// [playlistName] 歌单名称，null 时使用 "未分类"
  /// [track] 要下载的歌曲
  static String computeDownloadPath({
    required String baseDir,
    required String? playlistName,
    required Track track,
  }) {
    // 子目录：歌单名或"未分类"
    final subDir = playlistName != null
        ? sanitizeFileName(playlistName)
        : '未分类';

    // 视频文件夹名：sourceId_parentTitle
    final parentTitle = track.parentTitle ?? track.title;
    final videoFolder = '${track.sourceId}_${sanitizeFileName(parentTitle)}';

    // 音频文件名
    String fileName;
    if (track.isPartOfMultiPage && track.pageNum != null) {
      // 多P视频：P01.m4a, P02.m4a
      fileName = 'P${track.pageNum!.toString().padLeft(2, '0')}.m4a';
    } else {
      // 单P视频：audio.m4a
      fileName = 'audio.m4a';
    }

    return p.join(baseDir, subDir, videoFolder, fileName);
  }

  /// 从文件夹名提取 sourceId
  ///
  /// 文件夹格式: sourceId_title
  /// 返回 sourceId，如果格式不匹配返回 null
  static String? extractSourceIdFromFolderName(String folderName) {
    final underscoreIndex = folderName.indexOf('_');
    if (underscoreIndex > 0) {
      return folderName.substring(0, underscoreIndex);
    }
    return null;
  }

  /// 检查文件夹名是否匹配指定的 sourceId
  static bool folderMatchesSourceId(String folderName, String sourceId) {
    return folderName.startsWith('${sourceId}_');
  }

  /// 清理文件名中的特殊字符
  ///
  /// 将 Windows 不允许的字符转换为全角字符
  static String sanitizeFileName(String name) {
    // 将特殊字符转换为全角字符
    const replacements = {
      '/': '／', // U+FF0F
      '\\': '＼', // U+FF3C
      ':': '：', // U+FF1A
      '*': '＊', // U+FF0A
      '?': '？', // U+FF1F
      '"': '＂', // U+FF02
      '<': '＜', // U+FF1C
      '>': '＞', // U+FF1E
      '|': '｜', // U+FF5C
    };

    String result = name;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // 移除首尾空格和点
    result = result.trim();
    while (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }

    // 限制长度 (Windows 路径限制考虑)
    if (result.length > 200) {
      result = result.substring(0, 200);
    }

    return result.isEmpty ? 'untitled' : result;
  }

  /// 从完整路径提取歌单名
  ///
  /// 路径格式: {baseDir}/{playlistName}/{videoFolder}/{fileName}
  static String? extractPlaylistName(String fullPath, String baseDir) {
    if (!fullPath.startsWith(baseDir)) return null;

    final relativePath = fullPath.substring(baseDir.length);
    final parts = p.split(relativePath);

    // parts[0] 可能是空字符串（路径分隔符导致）
    // parts[1] 是歌单名
    for (final part in parts) {
      if (part.isNotEmpty) {
        return part;
      }
    }
    return null;
  }

  /// 获取下载基础目录
  ///
  /// 优先级：
  /// 1. 用户自定义目录（settings.customDownloadDir）
  /// 2. Android: 返回空字符串（强制用户通过 SAF 选择目录）
  /// 3. Windows/其他: Documents/FMP
  ///
  /// 返回空字符串表示未设置下载目录，调用方应提示用户先设置
  static Future<String> getDefaultBaseDir(SettingsRepository settingsRepo) async {
    final settings = await settingsRepo.get();

    // 1. 优先使用自定义目录
    if (settings.customDownloadDir != null && settings.customDownloadDir!.isNotEmpty) {
      return settings.customDownloadDir!;
    }

    // 2. Android: 返回空字符串，强制用户选择目录
    // 由于 Android Scoped Storage 限制，无法直接写入公共目录
    if (Platform.isAndroid) {
      return '';
    }

    // 3. Windows/其他: Documents 目录
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, 'FMP');
  }

  /// 检查下载目录是否已设置
  ///
  /// Android 必须通过 SAF 选择目录才能下载
  /// Windows 有默认目录，始终返回 true
  static Future<bool> isDownloadDirConfigured(SettingsRepository settingsRepo) async {
    final baseDir = await getDefaultBaseDir(settingsRepo);
    return baseDir.isNotEmpty;
  }

  /// 判断路径是否为 SAF content:// URI
  static bool isContentUri(String path) => SafService.isContentUri(path);

  /// 計算頭像的存儲路徑
  ///
  /// 格式: {baseDir}/avatars/{platform}/{creatorId}.jpg
  ///
  /// [baseDir] 下載根目錄
  /// [sourceType] 音源類型（bilibili 或 youtube）
  /// [creatorId] 創作者 ID（Bilibili ownerId 或 YouTube channelId）
  static String getAvatarPath({
    required String baseDir,
    required SourceType sourceType,
    required String creatorId,
  }) {
    final platform = sourceType == SourceType.bilibili ? 'bilibili' : 'youtube';
    return p.join(baseDir, 'avatars', platform, '$creatorId.jpg');
  }

  /// 確保頭像目錄存在
  static Future<void> ensureAvatarDirExists(String baseDir, SourceType sourceType) async {
    final platform = sourceType == SourceType.bilibili ? 'bilibili' : 'youtube';
    final dir = Directory(p.join(baseDir, 'avatars', platform));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}
