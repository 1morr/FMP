import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/track.dart';
import '../../services/download/download_path_utils.dart';
import '../../services/saf/saf_service.dart';

/// 下载文件扫描工具类
///
/// 负责扫描本地文件系统和 SAF 目录，获取已下载的歌曲信息
class DownloadScanner {
  final SafService _safService;
  
  DownloadScanner(this._safService);

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
            track ??= Track()
                ..sourceId = sourceIdFromFolder ?? p.basename(entity.path)
                ..sourceType = SourceType.bilibili
                ..title = extractDisplayName(p.basename(entity.path))
                ..playlistIds = [0]
                ..downloadPaths = [audioEntity.path]
                ..createdAt = DateTime.now();

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

  /// 扫描 SAF 目录获取已下载的 Track 列表
  ///
  /// SAF 目录结构: {baseDir}/{playlistName}/{sourceId_title}/P01.m4a
  /// 注意：SAF 不支持 metadata.json，只能从文件名推断信息
  Future<List<Track>> scanSafFolderForTracks(String folderUri) async {
    final tracks = <Track>[];

    try {
      // 遍历视频文件夹
      final videoFolders = await _safService.listDirectory(folderUri);

      for (final videoFolder in videoFolders.where((f) => f.isDirectory)) {
        final folderName = videoFolder.name;
        final sourceId = extractSourceId(folderName);
        final displayName = extractDisplayName(folderName);

        // 扫描视频文件夹中的音频文件
        final files = await _safService.listDirectory(videoFolder.uri);

        for (final file in files.where((f) => !f.isDirectory && f.name.endsWith('.m4a'))) {
          final fileName = p.basenameWithoutExtension(file.name);

          // 解析文件名确定页码
          int? pageNum;
          String title = displayName;

          // 新格式: P01.m4a, P02.m4a
          final newPageMatch = RegExp(r'^P(\d+)$').firstMatch(fileName);
          // 旧格式: P01 - xxx.m4a
          final oldPageMatch = RegExp(r'^P(\d+)\s*-\s*(.+)$').firstMatch(fileName);

          if (newPageMatch != null) {
            pageNum = int.tryParse(newPageMatch.group(1)!);
          } else if (oldPageMatch != null) {
            pageNum = int.tryParse(oldPageMatch.group(1)!);
            title = oldPageMatch.group(2)!;
          }

          final track = Track()
            ..sourceId = sourceId ?? folderName
            ..sourceType = SourceType.bilibili // 默认，无法从 SAF 确定
            ..title = title
            ..parentTitle = displayName
            ..pageNum = pageNum
            ..playlistIds = [0]
            ..downloadPaths = [file.uri]
            ..createdAt = DateTime.now();

          tracks.add(track);
        }
      }
    } catch (e) {
      // 扫描失败，返回空列表
    }

    // 排序
    tracks.sort((a, b) {
      final groupCompare = (a.parentTitle ?? a.title).compareTo(b.parentTitle ?? b.title);
      if (groupCompare != 0) return groupCompare;
      return (a.pageNum ?? 0).compareTo(b.pageNum ?? 0);
    });

    return tracks;
  }

  /// 统一扫描方法，自动检测路径类型
  Future<List<Track>> scanForTracks(String path) async {
    if (SafService.isContentUri(path)) {
      return scanSafFolderForTracks(path);
    } else {
      return scanFolderForTracks(path);
    }
  }

  /// 扫描 SAF 目录获取封面
  Future<String?> findFirstCoverSaf(String folderUri) async {
    try {
      // 1. 检查歌单封面
      final files = await _safService.listDirectory(folderUri);
      final playlistCover = files.where((f) => !f.isDirectory && f.name == 'playlist_cover.jpg').firstOrNull;
      if (playlistCover != null) {
        return playlistCover.uri;
      }

      // 2. 遍历子文件夹查找第一首歌的封面
      for (final folder in files.where((f) => f.isDirectory)) {
        final subFiles = await _safService.listDirectory(folder.uri);
        final cover = subFiles.where((f) => !f.isDirectory && f.name == 'cover.jpg').firstOrNull;
        if (cover != null) {
          return cover.uri;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 统计 SAF 目录中的音频文件数量
  Future<int> countAudioFilesSaf(String folderUri) async {
    int count = 0;
    try {
      final folders = await _safService.listDirectory(folderUri);
      for (final folder in folders.where((f) => f.isDirectory)) {
        final files = await _safService.listDirectory(folder.uri);
        count += files.where((f) => !f.isDirectory && f.name.endsWith('.m4a')).length;
      }
    } catch (_) {}
    return count;
  }
}
