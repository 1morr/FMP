import 'package:isar/isar.dart';
import '../models/download_task.dart';
import '../models/playlist_download_task.dart';
import '../../core/logger.dart';

/// 下载任务数据仓库
class DownloadRepository with Logging {
  final Isar _isar;

  DownloadRepository(this._isar);

  // ==================== DownloadTask CRUD ====================

  /// 获取所有下载任务
  Future<List<DownloadTask>> getAllTasks() async {
    return _isar.downloadTasks.where().sortByPriority().findAll();
  }

  /// 根据ID获取下载任务
  Future<DownloadTask?> getTaskById(int id) async {
    return _isar.downloadTasks.get(id);
  }

  /// 根据 trackId 获取下载任务
  Future<DownloadTask?> getTaskByTrackId(int trackId) async {
    return _isar.downloadTasks
        .where()
        .trackIdEqualTo(trackId)
        .findFirst();
  }

  /// 根据状态获取下载任务
  Future<List<DownloadTask>> getTasksByStatus(DownloadStatus status) async {
    return _isar.downloadTasks
        .filter()
        .statusEqualTo(status)
        .sortByPriority()
        .findAll();
  }

  /// 获取待下载的任务（pending + downloading）
  Future<List<DownloadTask>> getPendingTasks() async {
    return _isar.downloadTasks
        .filter()
        .statusEqualTo(DownloadStatus.pending)
        .or()
        .statusEqualTo(DownloadStatus.downloading)
        .sortByPriority()
        .findAll();
  }

  /// 获取正在下载的任务
  Future<List<DownloadTask>> getDownloadingTasks() async {
    return _isar.downloadTasks
        .filter()
        .statusEqualTo(DownloadStatus.downloading)
        .findAll();
  }

  /// 获取歌单下载任务相关的下载任务
  Future<List<DownloadTask>> getTasksByPlaylistTaskId(int playlistTaskId) async {
    return _isar.downloadTasks
        .where()
        .playlistDownloadTaskIdEqualTo(playlistTaskId)
        .sortByPriority()
        .findAll();
  }

  /// 保存下载任务
  Future<DownloadTask> saveTask(DownloadTask task) async {
    logDebug('Saving download task: trackId=${task.trackId}, status=${task.status}');
    final id = await _isar.writeTxn(() => _isar.downloadTasks.put(task));
    task.id = id;
    return task;
  }

  /// 批量保存下载任务
  Future<List<DownloadTask>> saveTasks(List<DownloadTask> tasks) async {
    logDebug('Saving ${tasks.length} download tasks');
    final ids = await _isar.writeTxn(() => _isar.downloadTasks.putAll(tasks));
    for (var i = 0; i < tasks.length; i++) {
      tasks[i].id = ids[i];
    }
    return tasks;
  }

  /// 删除下载任务
  Future<bool> deleteTask(int id) async {
    return _isar.writeTxn(() => _isar.downloadTasks.delete(id));
  }

  /// 批量删除下载任务
  Future<int> deleteTasks(List<int> ids) async {
    return _isar.writeTxn(() => _isar.downloadTasks.deleteAll(ids));
  }

  /// 删除所有已完成的任务
  Future<int> deleteCompletedTasks() async {
    return _isar.writeTxn(() async {
      final tasks = await _isar.downloadTasks
          .filter()
          .statusEqualTo(DownloadStatus.completed)
          .findAll();
      return _isar.downloadTasks.deleteAll(tasks.map((t) => t.id).toList());
    });
  }

  /// 更新任务状态
  Future<void> updateTaskStatus(int id, DownloadStatus status, {String? errorMessage}) async {
    await _isar.writeTxn(() async {
      final task = await _isar.downloadTasks.get(id);
      if (task != null) {
        task.status = status;
        if (status == DownloadStatus.completed) {
          task.completedAt = DateTime.now();
        }
        if (errorMessage != null) {
          task.errorMessage = errorMessage;
        }
        await _isar.downloadTasks.put(task);
      }
    });
  }

  /// 更新任务进度
  Future<void> updateTaskProgress(int id, double progress, int downloadedBytes, int? totalBytes) async {
    await _isar.writeTxn(() async {
      final task = await _isar.downloadTasks.get(id);
      if (task != null) {
        task.progress = progress;
        task.downloadedBytes = downloadedBytes;
        task.totalBytes = totalBytes;
        await _isar.downloadTasks.put(task);
      }
    });
  }

  /// 重置所有 downloading 状态的任务为 paused（用于程序重启）
  Future<void> resetDownloadingToPaused() async {
    logDebug('Reset all downloading tasks to paused status');
    await _isar.writeTxn(() async {
      final tasks = await _isar.downloadTasks
          .filter()
          .statusEqualTo(DownloadStatus.downloading)
          .findAll();
      for (final task in tasks) {
        task.status = DownloadStatus.paused;
        await _isar.downloadTasks.put(task);
      }
    });
  }

  /// 暂停所有任务
  Future<void> pauseAllTasks() async {
    await _isar.writeTxn(() async {
      final tasks = await _isar.downloadTasks
          .filter()
          .statusEqualTo(DownloadStatus.downloading)
          .or()
          .statusEqualTo(DownloadStatus.pending)
          .findAll();
      for (final task in tasks) {
        task.status = DownloadStatus.paused;
        await _isar.downloadTasks.put(task);
      }
    });
  }

  /// 恢复所有暂停的任务
  Future<void> resumeAllTasks() async {
    await _isar.writeTxn(() async {
      final tasks = await _isar.downloadTasks
          .filter()
          .statusEqualTo(DownloadStatus.paused)
          .findAll();
      for (final task in tasks) {
        task.status = DownloadStatus.pending;
        await _isar.downloadTasks.put(task);
      }
    });
  }

  /// 清空所有未完成的任务
  Future<int> clearQueue() async {
    return _isar.writeTxn(() async {
      final tasks = await _isar.downloadTasks
          .filter()
          .not()
          .statusEqualTo(DownloadStatus.completed)
          .findAll();
      return _isar.downloadTasks.deleteAll(tasks.map((t) => t.id).toList());
    });
  }

  // ==================== PlaylistDownloadTask CRUD ====================

  /// 获取所有歌单下载任务
  Future<List<PlaylistDownloadTask>> getAllPlaylistTasks() async {
    return _isar.playlistDownloadTasks.where().sortByPriority().findAll();
  }

  /// 根据ID获取歌单下载任务
  Future<PlaylistDownloadTask?> getPlaylistTaskById(int id) async {
    return _isar.playlistDownloadTasks.get(id);
  }

  /// 根据 playlistId 获取歌单下载任务
  Future<PlaylistDownloadTask?> getPlaylistTaskByPlaylistId(int playlistId) async {
    return _isar.playlistDownloadTasks
        .where()
        .playlistIdEqualTo(playlistId)
        .filter()
        .not()
        .statusEqualTo(DownloadStatus.completed)
        .findFirst();
  }

  /// 获取当前正在执行的歌单下载任务
  Future<PlaylistDownloadTask?> getActivePlaylistTask() async {
    return _isar.playlistDownloadTasks
        .filter()
        .statusEqualTo(DownloadStatus.downloading)
        .findFirst();
  }

  /// 获取下一个待执行的歌单下载任务
  Future<PlaylistDownloadTask?> getNextPendingPlaylistTask() async {
    return _isar.playlistDownloadTasks
        .filter()
        .statusEqualTo(DownloadStatus.pending)
        .sortByPriority()
        .findFirst();
  }

  /// 保存歌单下载任务
  Future<PlaylistDownloadTask> savePlaylistTask(PlaylistDownloadTask task) async {
    logDebug('Saving playlist download task: playlistId=${task.playlistId}, name=${task.playlistName}');
    final id = await _isar.writeTxn(() => _isar.playlistDownloadTasks.put(task));
    task.id = id;
    return task;
  }

  /// 删除歌单下载任务
  Future<bool> deletePlaylistTask(int id) async {
    // 同时删除关联的下载任务
    await _isar.writeTxn(() async {
      final tasks = await _isar.downloadTasks
          .where()
          .playlistDownloadTaskIdEqualTo(id)
          .findAll();
      await _isar.downloadTasks.deleteAll(tasks.map((t) => t.id).toList());
    });
    return _isar.writeTxn(() => _isar.playlistDownloadTasks.delete(id));
  }

  /// 更新歌单下载任务状态
  Future<void> updatePlaylistTaskStatus(int id, DownloadStatus status) async {
    await _isar.writeTxn(() async {
      final task = await _isar.playlistDownloadTasks.get(id);
      if (task != null) {
        task.status = status;
        if (status == DownloadStatus.completed) {
          task.completedAt = DateTime.now();
        }
        await _isar.playlistDownloadTasks.put(task);
      }
    });
  }

  // ==================== 监听流 ====================

  /// 监听所有下载任务变化
  Stream<List<DownloadTask>> watchAllTasks() {
    return _isar.downloadTasks
        .where()
        .sortByPriority()
        .watch(fireImmediately: true);
  }

  /// 监听歌单下载任务变化
  Stream<List<PlaylistDownloadTask>> watchPlaylistTasks() {
    return _isar.playlistDownloadTasks
        .where()
        .sortByPriority()
        .watch(fireImmediately: true);
  }

  /// 获取下一个优先级值（用于新任务）
  Future<int> getNextPriority() async {
    final tasks = await _isar.downloadTasks.where().sortByPriorityDesc().findFirst();
    final playlistTasks = await _isar.playlistDownloadTasks.where().sortByPriorityDesc().findFirst();
    
    final taskPriority = tasks?.priority ?? 0;
    final playlistTaskPriority = playlistTasks?.priority ?? 0;
    
    return (taskPriority > playlistTaskPriority ? taskPriority : playlistTaskPriority) + 1;
  }
}
