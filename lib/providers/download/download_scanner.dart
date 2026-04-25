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

/// 参数类（用于 Isolate.run() 扫描单个下载分类详情）
class ScanFolderTracksParams {
  final String folderPath;
  const ScanFolderTracksParams(this.folderPath);
}

class DownloadedTrackDto {
  const DownloadedTrackDto({
    required this.sourceId,
    required this.sourceTypeName,
    required this.title,
    required this.audioPath,
    this.artist,
    this.durationMs,
    this.thumbnailUrl,
    this.cid,
    this.pageNum,
    this.pageCount,
    this.parentTitle,
    required this.createdAtIso,
  });

  final String sourceId;
  final String sourceTypeName;
  final String title;
  final String? artist;
  final int? durationMs;
  final String? thumbnailUrl;
  final int? cid;
  final int? pageNum;
  final int? pageCount;
  final String? parentTitle;
  final String audioPath;
  final String createdAtIso;

  Track toTrack() {
    final sourceType = SourceType.values.firstWhere(
      (e) => e.name == sourceTypeName,
      orElse: () => SourceType.bilibili,
    );
    return Track()
      ..sourceId = sourceId
      ..sourceType = sourceType
      ..title = title
      ..artist = artist
      ..durationMs = durationMs
      ..thumbnailUrl = thumbnailUrl
      ..cid = cid
      ..pageNum = pageNum
      ..pageCount = pageCount
      ..parentTitle = parentTitle
      ..playlistInfo = [
        PlaylistDownloadInfo()
          ..playlistId = 0
          ..downloadPath = audioPath,
      ]
      ..createdAt = DateTime.tryParse(createdAtIso) ?? DateTime.now();
  }
}

/// 在单独的 isolate 中扫描已下载分类
///
/// 这是一个顶级函数，可以被 Isolate.run() 调用
Future<List<DownloadedCategory>> scanCategoriesInIsolate(
    ScanCategoriesParams params) async {
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

Future<List<DownloadedTrackDto>> scanFolderTrackDtosInIsolate(
  ScanFolderTracksParams params,
) {
  return DownloadScanner.scanFolderForTrackDtos(params.folderPath);
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

  /// 从 metadata.json 创建可跨 isolate 传输的 DTO
  static DownloadedTrackDto? trackDtoFromMetadata(
    Map<String, dynamic> json,
    String audioPath,
  ) {
    try {
      final sourceTypeStr = json['sourceType'] as String?;
      if (sourceTypeStr == null) return null;

      return DownloadedTrackDto(
        sourceId: json['sourceId'] as String? ?? '',
        sourceTypeName: sourceTypeStr,
        title:
            json['title'] as String? ?? p.basenameWithoutExtension(audioPath),
        artist: json['artist'] as String?,
        durationMs: json['durationMs'] as int?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        cid: json['cid'] as int?,
        pageNum: json['pageNum'] as int?,
        pageCount: json['pageCount'] as int?,
        parentTitle: json['parentTitle'] as String?,
        audioPath: audioPath,
        createdAtIso: json['downloadedAt'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// 扫描文件夹获取已下载歌曲 DTO 列表（基于本地文件）
  static Future<List<DownloadedTrackDto>> scanFolderForTrackDtos(
    String folderPath,
  ) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) return [];

    final tracks = <DownloadedTrackDto>[];

    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final folderName = p.basename(entity.path);
        final sourceIdFromFolder = extractSourceId(folderName);

        await for (final audioEntity in entity.list()) {
          if (audioEntity is! File || !audioEntity.path.endsWith('.m4a')) {
            continue;
          }

          DownloadedTrackDto? track;
          final audioPath =
              '$folderPath/${p.basename(entity.path)}/${p.basename(audioEntity.path)}';
          final fileName = p.basenameWithoutExtension(audioEntity.path);
          final newPageMatch = RegExp(r'^P(\d+)$').firstMatch(fileName);
          final oldPageMatch =
              RegExp(r'^P(\d+)\s*-\s*(.+)$').firstMatch(fileName);

          File? metadataFile;
          Map<String, dynamic>? metadata;

          if (newPageMatch != null) {
            final pageNumStr = newPageMatch.group(1)!;
            final pageMetadataFile =
                File(p.join(entity.path, 'metadata_P$pageNumStr.json'));
            final defaultMetadataFile =
                File(p.join(entity.path, 'metadata.json'));

            if (await pageMetadataFile.exists()) {
              metadataFile = pageMetadataFile;
            } else if (await defaultMetadataFile.exists()) {
              metadataFile = defaultMetadataFile;
            }
          } else {
            metadataFile = File(p.join(entity.path, 'metadata.json'));
          }

          if (metadataFile != null && await metadataFile.exists()) {
            try {
              final content = await metadataFile.readAsString();
              metadata = jsonDecode(content) as Map<String, dynamic>;
            } catch (_) {}
          }

          if (metadata != null) {
            track = trackDtoFromMetadata(metadata, audioPath);
            if (track != null && newPageMatch != null) {
              track = DownloadedTrackDto(
                sourceId: track.sourceId,
                sourceTypeName: track.sourceTypeName,
                title: track.title,
                artist: track.artist,
                durationMs: track.durationMs,
                thumbnailUrl: track.thumbnailUrl,
                cid: track.cid,
                pageNum: int.tryParse(newPageMatch.group(1)!),
                pageCount: track.pageCount,
                parentTitle: track.parentTitle,
                audioPath: track.audioPath,
                createdAtIso: track.createdAtIso,
              );
            } else if (track != null && oldPageMatch != null) {
              track = DownloadedTrackDto(
                sourceId: track.sourceId,
                sourceTypeName: track.sourceTypeName,
                title: oldPageMatch.group(2)!,
                artist: track.artist,
                durationMs: track.durationMs,
                thumbnailUrl: track.thumbnailUrl,
                cid: track.cid,
                pageNum: int.tryParse(oldPageMatch.group(1)!),
                pageCount: track.pageCount,
                parentTitle: track.parentTitle,
                audioPath: track.audioPath,
                createdAtIso: track.createdAtIso,
              );
            }
          }

          track ??= DownloadedTrackDto(
            sourceId: sourceIdFromFolder ?? p.basename(entity.path),
            sourceTypeName: SourceType.bilibili.name,
            title: extractDisplayName(p.basename(entity.path)),
            audioPath: audioPath,
            createdAtIso: DateTime.now().toIso8601String(),
          );

          tracks.add(track);
        }
      }
    }

    tracks.sort((a, b) {
      final groupCompare =
          (a.parentTitle ?? a.title).compareTo(b.parentTitle ?? b.title);
      if (groupCompare != 0) return groupCompare;
      return (a.pageNum ?? 0).compareTo(b.pageNum ?? 0);
    });

    return tracks;
  }

  /// 扫描文件夹获取已下载的 Track 列表（基于本地文件）
  static Future<List<Track>> scanFolderForTracks(String folderPath) async {
    final dtos = await scanFolderForTrackDtos(folderPath);
    return dtos.map((dto) => dto.toTrack()).toList();
  }
}
