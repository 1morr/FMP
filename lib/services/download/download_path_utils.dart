import 'package:path/path.dart' as p;

import '../../data/models/track.dart';

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
}
