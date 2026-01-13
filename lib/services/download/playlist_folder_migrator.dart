import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;

import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/models/playlist.dart';
import '../../data/repositories/settings_repository.dart';
import 'download_path_utils.dart';

/// 歌单文件夹迁移服务
///
/// 当歌单重命名时，负责将下载文件夹迁移到新位置，
/// 并更新相关 Track 的下载路径记录
class PlaylistFolderMigrator with Logging {
  final Isar _isar;
  final SettingsRepository _settingsRepository;

  PlaylistFolderMigrator({
    required Isar isar,
    required SettingsRepository settingsRepository,
  })  : _isar = isar,
        _settingsRepository = settingsRepository;

  /// 迁移歌单文件夹
  ///
  /// 当歌单从 [oldName] 重命名为 [newName] 时调用
  /// 返回迁移的文件数量
  Future<int> migratePlaylistFolder({
    required Playlist playlist,
    required String oldName,
    required String newName,
  }) async {
    if (oldName == newName) return 0;

    final settings = await _settingsRepository.get();
    final baseDir = settings.customDownloadDir ?? await _getDefaultDownloadDir();

    // 清理文件名
    final oldFolderName = DownloadPathUtils.sanitizeFileName(oldName);
    final newFolderName = DownloadPathUtils.sanitizeFileName(newName);

    final oldFolder = Directory(p.join(baseDir, oldFolderName));
    final newFolder = Directory(p.join(baseDir, newFolderName));

    // 如果旧文件夹不存在，无需迁移
    if (!await oldFolder.exists()) {
      logDebug('Old playlist folder does not exist: ${oldFolder.path}');
      return 0;
    }

    // 如果新文件夹已存在，需要合并或跳过
    if (await newFolder.exists()) {
      logDebug('New playlist folder already exists, merging: ${newFolder.path}');
      return await _mergeAndMigrate(
        oldFolder: oldFolder,
        newFolder: newFolder,
        playlist: playlist,
      );
    }

    // 重命名文件夹
    try {
      await oldFolder.rename(newFolder.path);
      logDebug('Renamed folder: ${oldFolder.path} -> ${newFolder.path}');

      // 更新 Track 的下载路径
      return await _updateTrackPaths(
        playlist: playlist,
        oldBasePath: oldFolder.path,
        newBasePath: newFolder.path,
      );
    } catch (e, stack) {
      logError('Failed to rename playlist folder: $e', e, stack);
      return 0;
    }
  }

  /// 合并旧文件夹到已存在的新文件夹
  Future<int> _mergeAndMigrate({
    required Directory oldFolder,
    required Directory newFolder,
    required Playlist playlist,
  }) async {
    int migratedCount = 0;

    try {
      // 遍历旧文件夹中的视频子文件夹
      await for (final entity in oldFolder.list()) {
        if (entity is Directory) {
          final folderName = p.basename(entity.path);
          final targetPath = p.join(newFolder.path, folderName);
          final targetDir = Directory(targetPath);

          if (await targetDir.exists()) {
            // 目标已存在，跳过（或可以选择覆盖）
            logDebug('Target video folder already exists, skipping: $targetPath');
            continue;
          }

          // 移动视频文件夹到新位置
          try {
            await entity.rename(targetPath);
            migratedCount++;
            logDebug('Moved video folder: ${entity.path} -> $targetPath');
          } catch (e) {
            logDebug('Failed to move video folder: $e');
          }
        } else if (entity is File) {
          // 移动歌单封面等文件
          final fileName = p.basename(entity.path);
          final targetPath = p.join(newFolder.path, fileName);

          if (!await File(targetPath).exists()) {
            try {
              await entity.rename(targetPath);
              logDebug('Moved file: ${entity.path} -> $targetPath');
            } catch (e) {
              logDebug('Failed to move file: $e');
            }
          }
        }
      }

      // 删除空的旧文件夹
      if (await _isDirectoryEmpty(oldFolder)) {
        await oldFolder.delete();
        logDebug('Deleted empty old folder: ${oldFolder.path}');
      }

      // 更新 Track 的下载路径
      migratedCount += await _updateTrackPaths(
        playlist: playlist,
        oldBasePath: oldFolder.path,
        newBasePath: newFolder.path,
      );
    } catch (e, stack) {
      logError('Error during folder merge: $e', e, stack);
    }

    return migratedCount;
  }

  /// 更新 Track 的下载路径记录
  Future<int> _updateTrackPaths({
    required Playlist playlist,
    required String oldBasePath,
    required String newBasePath,
  }) async {
    int updatedCount = 0;

    // 获取歌单中的所有 Track
    final tracks = await _isar.tracks
        .filter()
        .anyOf(playlist.trackIds, (q, id) => q.idEqualTo(id))
        .findAll();

    await _isar.writeTxn(() async {
      for (final track in tracks) {
        bool updated = false;

        // 检查该歌单的下载路径是否需要更新
        final oldPath = track.getDownloadedPath(playlist.id);
        if (oldPath != null && oldPath.startsWith(oldBasePath)) {
          // 计算新路径
          final relativePath = oldPath.substring(oldBasePath.length);
          final newPath = '$newBasePath$relativePath';

          // 验证新路径的文件存在
          if (await File(newPath).exists()) {
            track.setDownloadedPath(playlist.id, newPath);
            updated = true;
          }
        }

        if (updated) {
          await _isar.tracks.put(track);
          updatedCount++;
        }
      }
    });

    logDebug('Updated $updatedCount track paths');
    return updatedCount;
  }

  /// 检查目录是否为空
  Future<bool> _isDirectoryEmpty(Directory dir) async {
    await for (final _ in dir.list()) {
      return false;
    }
    return true;
  }

  /// 获取默认下载目录
  Future<String> _getDefaultDownloadDir() async {
    if (Platform.isAndroid) {
      // Android: 使用应用文档目录
      return '/storage/emulated/0/Music/FMP';
    } else if (Platform.isWindows) {
      // Windows: 用户文档目录
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        return p.join(userProfile, 'Documents', 'FMP');
      }
    }
    // 回退
    return '/FMP';
  }
}
