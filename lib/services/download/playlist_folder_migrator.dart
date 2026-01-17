import 'package:isar/isar.dart';

import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/models/playlist.dart';
import '../../data/repositories/settings_repository.dart';
import 'download_path_utils.dart';

/// 歌单下载路径更新服务
///
/// 当歌单重命名时，负责更新所有 Track 的预计算下载路径。
/// 注意：不再自动移动已下载的文件，需要用户手动移动。
class PlaylistFolderMigrator with Logging {
  final Isar _isar;
  final SettingsRepository _settingsRepository;

  PlaylistFolderMigrator({
    required Isar isar,
    required SettingsRepository settingsRepository,
  })  : _isar = isar,
        _settingsRepository = settingsRepository;

  /// 更新所有 Track 的预计算下载路径（无论文件是否已下载）
  ///
  /// 当歌单重命名时调用，确保未下载的歌曲也能使用新路径
  /// 返回更新的 Track 数量
  Future<int> updateAllTrackDownloadPaths({
    required Playlist playlist,
    required String newName,
  }) async {
    int updatedCount = 0;

    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);

    // 获取歌单中的所有 Track
    final tracks = await _isar.tracks
        .filter()
        .anyOf(playlist.trackIds, (q, id) => q.idEqualTo(id))
        .findAll();

    await _isar.writeTxn(() async {
      for (final track in tracks) {
        // 重新计算下载路径
        final newPath = DownloadPathUtils.computeDownloadPath(
          baseDir: baseDir,
          playlistName: newName,
          track: track,
        );

        // 更新路径
        track.setDownloadPath(playlist.id, newPath);
        await _isar.tracks.put(track);
        updatedCount++;
      }
    });

    logDebug('Updated download paths for $updatedCount tracks');
    return updatedCount;
  }
}
