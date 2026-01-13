import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/track.dart';
import '../../services/download/download_path_utils.dart';

/// 下载文件扫描工具类
///
/// 负责扫描本地文件系统，获取已下载的歌曲信息
class DownloadScanner {
  DownloadScanner._();

  /// 获取文件夹的显示名称
  ///
  /// 新格式: sourceId_title → 返回 title
  /// 旧格式: title → 直接返回
  static String extractDisplayName(String folderName) {
    // 尝试从新格式提取 (sourceId_title)
    final underscoreIndex = folderName.indexOf('_');
    if (underscoreIndex > 0) {
      return folderName.substring(underscoreIndex + 1);
    }
    // 旧格式或无下划线，直接返回
    return folderName;
  }

  /// 从文件夹名提取 sourceId
  ///
  /// 新格式: sourceId_title → 返回 sourceId
  /// 旧格式: title → 返回 null
  static String? extractSourceId(String folderName) {
    return DownloadPathUtils.extractSourceIdFromFolderName(folderName);
  }

  /// 查找文件夹中的封面（优先歌单封面，其次第一首歌的封面）
  static Future<String?> findFirstCover(Directory folder) async {
    try {
      // 1. 优先检查歌单封面
      final playlistCoverFile = File(p.join(folder.path, 'playlist_cover.jpg'));
      if (await playlistCoverFile.exists()) {
        return playlistCoverFile.path;
      }

      // 2. 遍历子文件夹（视频文件夹）查找第一首歌的封面
      await for (final entity in folder.list()) {
        if (entity is Directory) {
          final coverFile = File(p.join(entity.path, 'cover.jpg'));
          if (await coverFile.exists()) {
            return coverFile.path;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 统计文件夹中的音频文件数量
  static Future<int> countAudioFiles(Directory folder) async {
    int count = 0;
    try {
      await for (final entity in folder.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.m4a')) {
          count++;
        }
      }
    } catch (_) {}
    return count;
  }

  /// 从 metadata.json 创建 Track 对象
  static Track? trackFromMetadata(Map<String, dynamic> json, String audioPath) {
    try {
      final sourceTypeStr = json['sourceType'] as String?;
      if (sourceTypeStr == null) return null;

      final sourceType = SourceType.values.firstWhere(
        (e) => e.name == sourceTypeStr,
        orElse: () => SourceType.bilibili,
      );

      return Track()
        ..sourceId = json['sourceId'] as String? ?? ''
        ..sourceType = sourceType
        ..title = json['title'] as String? ?? p.basenameWithoutExtension(audioPath)
        ..artist = json['artist'] as String?
        ..durationMs = json['durationMs'] as int?
        ..thumbnailUrl = json['thumbnailUrl'] as String?
        ..cid = json['cid'] as int?
        ..pageNum = json['pageNum'] as int?
        ..parentTitle = json['parentTitle'] as String?
        ..playlistIds = [0]
        ..downloadPaths = [audioPath]
        ..order = json['order'] as int?
        ..createdAt = DateTime.tryParse(json['downloadedAt'] as String? ?? '') ?? DateTime.now();
    } catch (_) {
      return null;
    }
  }

  /// 扫描文件夹获取已下载的 Track 列表（基于本地文件）
  static Future<List<Track>> scanFolderForTracks(String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) return [];

    final tracks = <Track>[];

    // 遍历视频文件夹（每个视频一个子文件夹）
    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final folderName = p.basename(entity.path);
        final metadataFile = File(p.join(entity.path, 'metadata.json'));
        Map<String, dynamic>? metadata;

        // 读取 metadata.json
        if (await metadataFile.exists()) {
          try {
            final content = await metadataFile.readAsString();
            metadata = jsonDecode(content) as Map<String, dynamic>;
          } catch (_) {}
        }

        // 尝试从文件夹名提取 sourceId（新格式: sourceId_title）
        final sourceIdFromFolder = extractSourceId(folderName);

        // 扫描该视频文件夹下的所有 .m4a 文件
        await for (final audioEntity in entity.list()) {
          if (audioEntity is File && audioEntity.path.endsWith('.m4a')) {
            Track? track;

            if (metadata != null) {
              // 从文件名判断是否是多P视频
              final fileName = p.basenameWithoutExtension(audioEntity.path);

              // 新格式: P01.m4a, P02.m4a
              final newPageMatch = RegExp(r'^P(\d+)$').firstMatch(fileName);
              // 旧格式: P01 - xxx.m4a
              final oldPageMatch = RegExp(r'^P(\d+)\s*-\s*(.+)$').firstMatch(fileName);

              if (newPageMatch != null) {
                // 新格式多P视频：P01.m4a
                final pageNum = int.tryParse(newPageMatch.group(1)!);
                track = trackFromMetadata(metadata, audioEntity.path);
                if (track != null) {
                  track.pageNum = pageNum;
                  // 新格式没有文件名中的标题，使用 metadata 中的 title 或保持原样
                }
              } else if (oldPageMatch != null) {
                // 旧格式多P视频：P01 - xxx.m4a
                final pageNum = int.tryParse(oldPageMatch.group(1)!);
                track = trackFromMetadata(metadata, audioEntity.path);
                if (track != null) {
                  track.pageNum = pageNum;
                  // 旧格式的 title 使用文件名中的标题
                  track.title = oldPageMatch.group(2)!;
                }
              } else {
                // 单P视频 (audio.m4a)
                track = trackFromMetadata(metadata, audioEntity.path);
              }
            }

            // 如果没有 metadata 或解析失败，创建基本 Track
            if (track == null) {
              track = Track()
                ..sourceId = sourceIdFromFolder ?? p.basename(entity.path)
                ..sourceType = SourceType.bilibili
                ..title = extractDisplayName(p.basename(entity.path))
                ..playlistIds = [0]
                ..downloadPaths = [audioEntity.path]
                ..createdAt = DateTime.now();
            }

            tracks.add(track);
          }
        }
      }
    }

    // 按 order 排序，如果没有 order 则按 parentTitle + pageNum 排序（向后兼容）
    tracks.sort((a, b) {
      // 优先使用 order 排序
      if (a.order != null && b.order != null) {
        return a.order!.compareTo(b.order!);
      }
      // 如果只有一个有 order，有 order 的排前面
      if (a.order != null) return -1;
      if (b.order != null) return 1;
      // 都没有 order，按原来的方式排序（向后兼容）
      final groupCompare = (a.parentTitle ?? a.title).compareTo(b.parentTitle ?? b.title);
      if (groupCompare != 0) return groupCompare;
      return (a.pageNum ?? 0).compareTo(b.pageNum ?? 0);
    });

    return tracks;
  }
}
