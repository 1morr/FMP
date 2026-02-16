import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/track.dart';
import '../../services/download/download_path_utils.dart';

/// 已下载分类（文件夹）数据模型
class DownloadedCategory {
  /// 原始文件夹名
  final String folderName;

  /// 显示名称（去掉 _id 后缀）
  final String displayName;

  /// 歌曲数量
  final int trackCount;

  /// 第一首歌的封面路径
  final String? coverPath;

  /// 完整文件夹路径
  final String folderPath;

  const DownloadedCategory({
    required this.folderName,
    required this.displayName,
    required this.trackCount,
    this.coverPath,
    required this.folderPath,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadedCategory && other.folderPath == folderPath;
  }

  @override
  int get hashCode => folderPath.hashCode;
}

/// 参数类（用于 Isolate.run()）
class ScanCategoriesParams {
  final String downloadPath;
  const ScanCategoriesParams(this.downloadPath);
}

/// 在单独的 isolate 中扫描已下载分类
/// 
/// 这是一个顶级函数，可以被 Isolate.run() 调用
Future<List<DownloadedCategory>> scanCategoriesInIsolate(ScanCategoriesParams params) async {
  final downloadDir = Directory(params.downloadPath);
  
  if (!await downloadDir.exists()) {
    return [];
  }

  final results = <DownloadedCategory>[];

  // 扫描所有子文件夹
  await for (final entity in downloadDir.list()) {
    if (entity is Directory) {
      final folderName = p.basename(entity.path);
      final trackCount = await _countAudioFilesInternal(entity);

      if (trackCount > 0) {
        final coverPath = await _findFirstCoverInternal(entity);
        results.add(DownloadedCategory(
          folderName: folderName,
          displayName: _extractDisplayNameInternal(folderName),
          trackCount: trackCount,
          coverPath: coverPath,
          folderPath: entity.path,
        ));
      }
    }
  }

  // 按名称排序，但"未分类"放最后
  results.sort((a, b) {
    if (a.folderName == '未分类') return 1;
    if (b.folderName == '未分类') return -1;
    return a.displayName.compareTo(b.displayName);
  });

  return results;
}

/// 内部函数：提取显示名称（用于 isolate）
String _extractDisplayNameInternal(String folderName) {
  final underscoreIndex = folderName.indexOf('_');
  if (underscoreIndex > 0) {
    return folderName.substring(underscoreIndex + 1);
  }
  return folderName;
}

/// 内部函数：查找封面（用于 isolate）
/// 
/// 按照与歌曲列表相同的排序逻辑（parentTitle/title 字母顺序），
/// 返回排序后第一首歌的封面，确保封面与歌曲列表第一首一致。
Future<String?> _findFirstCoverInternal(Directory folder) async {
  try {
    // 收集所有子文件夹及其排序信息
    final subFolders = <_FolderSortInfo>[];
    
    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final coverFile = File(p.join(entity.path, 'cover.jpg'));
        if (await coverFile.exists()) {
          // 读取 metadata.json 获取排序用的 title
          String sortKey = p.basename(entity.path);
          final metadataFile = File(p.join(entity.path, 'metadata.json'));
          if (await metadataFile.exists()) {
            try {
              final content = await metadataFile.readAsString();
              final metadata = jsonDecode(content) as Map<String, dynamic>;
              // 使用与 scanFolderForTracks 相同的排序逻辑
              sortKey = (metadata['parentTitle'] as String?) ?? 
                        (metadata['title'] as String?) ?? 
                        sortKey;
            } catch (_) {}
          }
          subFolders.add(_FolderSortInfo(
            coverPath: coverFile.path,
            sortKey: sortKey,
          ));
        }
      }
    }
    
    if (subFolders.isEmpty) return null;
    
    // 按 sortKey 排序（与歌曲列表排序逻辑一致）
    subFolders.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    
    return subFolders.first.coverPath;
  } catch (_) {}
  return null;
}

/// 用于封面排序的辅助类
class _FolderSortInfo {
  final String coverPath;
  final String sortKey;
  
  _FolderSortInfo({required this.coverPath, required this.sortKey});
}

/// 内部函数：统计音频文件数量（用于 isolate）
Future<int> _countAudioFilesInternal(Directory folder) async {
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
    return _extractDisplayNameInternal(folderName);
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
    return _findFirstCoverInternal(folder);
  }

  /// 统计文件夹中的音频文件数量
  static Future<int> countAudioFiles(Directory folder) async {
    return _countAudioFilesInternal(folder);
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
        ..pageCount = json['pageCount'] as int?
        ..parentTitle = json['parentTitle'] as String?
        ..playlistInfo = [PlaylistDownloadInfo()..playlistId = 0..downloadPath = audioPath]
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

        // 尝试从文件夹名提取 sourceId（新格式: sourceId_title）
        final sourceIdFromFolder = extractSourceId(folderName);

        // 扫描该视频文件夹下的所有 .m4a 文件
        await for (final audioEntity in entity.list()) {
          if (audioEntity is File && audioEntity.path.endsWith('.m4a')) {
            Track? track;

            // 从文件名判断是否是多P视频，并确定 metadata 文件名
            final fileName = p.basenameWithoutExtension(audioEntity.path);

            // 新格式: P01.m4a, P02.m4a
            final newPageMatch = RegExp(r'^P(\d+)$').firstMatch(fileName);
            // 旧格式: P01 - xxx.m4a
            final oldPageMatch = RegExp(r'^P(\d+)\s*-\s*(.+)$').firstMatch(fileName);

            // 确定要读取的 metadata 文件
            File? metadataFile;
            Map<String, dynamic>? metadata;

            if (newPageMatch != null) {
              // 多P新格式：优先读取 metadata_P{NN}.json，fallback 到 metadata.json
              final pageNumStr = newPageMatch.group(1)!;
              final pageMetadataFile = File(p.join(entity.path, 'metadata_P$pageNumStr.json'));
              final defaultMetadataFile = File(p.join(entity.path, 'metadata.json'));

              if (await pageMetadataFile.exists()) {
                metadataFile = pageMetadataFile;
              } else if (await defaultMetadataFile.exists()) {
                metadataFile = defaultMetadataFile;
              }
            } else if (oldPageMatch != null) {
              // 多P旧格式：读取 metadata.json（旧格式没有分P metadata）
              metadataFile = File(p.join(entity.path, 'metadata.json'));
            } else {
              // 单P视频：读取 metadata.json
              metadataFile = File(p.join(entity.path, 'metadata.json'));
            }

            // 读取 metadata
            if (metadataFile != null && await metadataFile.exists()) {
              try {
                final content = await metadataFile.readAsString();
                metadata = jsonDecode(content) as Map<String, dynamic>;
              } catch (_) {}
            }

            if (metadata != null) {
              if (newPageMatch != null) {
                // 新格式多P视频：P01.m4a
                final pageNum = int.tryParse(newPageMatch.group(1)!);
                track = trackFromMetadata(metadata, audioEntity.path);
                if (track != null) {
                  track.pageNum = pageNum;
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
                ..playlistInfo = [PlaylistDownloadInfo()..playlistId = 0..downloadPath = audioEntity.path]
                ..createdAt = DateTime.now();

            tracks.add(track);
          }
        }
      }
    }

    // 按 parentTitle + pageNum 排序（多P视频按分P顺序）
    tracks.sort((a, b) {
      final groupCompare = (a.parentTitle ?? a.title).compareTo(b.parentTitle ?? b.title);
      if (groupCompare != 0) return groupCompare;
      return (a.pageNum ?? 0).compareTo(b.pageNum ?? 0);
    });

    return tracks;
  }
}
