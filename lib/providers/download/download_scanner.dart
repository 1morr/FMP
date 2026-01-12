import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/track.dart';

/// 下载文件扫描工具类
///
/// 负责扫描本地文件系统，获取已下载的歌曲信息
class DownloadScanner {
  DownloadScanner._();

  /// 从文件夹名中提取显示名称（移除 _playlistId 后缀）
  ///
  /// 格式: "歌单名_123456" -> "歌单名"
  static String extractDisplayName(String folderName) {
    final lastUnderscoreIndex = folderName.lastIndexOf('_');
    if (lastUnderscoreIndex > 0) {
      final suffix = folderName.substring(lastUnderscoreIndex + 1);
      // 检查后缀是否为纯数字
      if (RegExp(r'^\d+$').hasMatch(suffix)) {
        return folderName.substring(0, lastUnderscoreIndex);
      }
    }
    return folderName;
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
        ..downloadedPath = audioPath
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
        final metadataFile = File(p.join(entity.path, 'metadata.json'));
        Map<String, dynamic>? metadata;

        // 读取 metadata.json
        if (await metadataFile.exists()) {
          try {
            final content = await metadataFile.readAsString();
            metadata = jsonDecode(content) as Map<String, dynamic>;
          } catch (_) {}
        }

        // 扫描该视频文件夹下的所有 .m4a 文件
        await for (final audioEntity in entity.list()) {
          if (audioEntity is File && audioEntity.path.endsWith('.m4a')) {
            Track? track;

            if (metadata != null) {
              // 检查是否是多P视频（有多个 .m4a 文件）
              // 多P视频的文件名格式: P01 - xxx.m4a, P02 - yyy.m4a
              final fileName = p.basenameWithoutExtension(audioEntity.path);
              final pageMatch = RegExp(r'^P(\d+)').firstMatch(fileName);

              if (pageMatch != null) {
                // 多P视频：从文件名提取 pageNum，使用 metadata 的基础信息
                final pageNum = int.tryParse(pageMatch.group(1)!);
                track = trackFromMetadata(metadata, audioEntity.path);
                if (track != null) {
                  track.pageNum = pageNum;
                  // 多P视频的 title 使用文件名（去掉 P01 - 前缀）
                  final titleMatch = RegExp(r'^P\d+\s*-\s*(.+)$').firstMatch(fileName);
                  if (titleMatch != null) {
                    track.title = titleMatch.group(1)!;
                  }
                }
              } else {
                // 单P视频
                track = trackFromMetadata(metadata, audioEntity.path);
              }
            }

            // 如果没有 metadata 或解析失败，创建基本 Track
            if (track == null) {
              track = Track()
                ..sourceId = p.basename(entity.path)
                ..sourceType = SourceType.bilibili
                ..title = p.basenameWithoutExtension(audioEntity.path)
                ..downloadedPath = audioEntity.path
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
