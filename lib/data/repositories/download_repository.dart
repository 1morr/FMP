import 'package:isar/isar.dart';
import '../models/download_task.dart';
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

  /// 根据 trackId 和 playlistId 获取下载任务
  Future<DownloadTask?> getTaskByTrackIdAndPlaylist(int trackId, int playlistId) async {
    return _isar.downloadTasks
        .filter()
        .trackIdEqualTo(trackId)
        .and()
        .playlistIdEqualTo(playlistId)
        .findFirst();
  }

  /// 根据 savePath 获取下载任务（用于任务去重）
  Future<DownloadTask?> getTaskBySavePath(String savePath) async {
    return _isar.downloadTasks
        .filter()
        .savePathEqualTo(savePath)
        .findFirst();
  }

  /// 清除已完成和失败的任务（用于启动时清理）
  Future<int> clearCompletedAndErrorTasks() async {
    return _isar.writeTxn(() async {
      final tasks = await _isar.downloadTasks
          .filter()
          .statusEqualTo(DownloadStatus.completed)
          .or()
          .statusEqualTo(DownloadStatus.failed)
          .findAll();
      return _isar.downloadTasks.deleteAll(tasks.map((t) => t.id).toList());
    });
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

  /// 重置所有 downloading 和 pending 状态的任务为 paused（用于程序重启）
  Future<void> resetDownloadingToPaused() async {
    logDebug('Reset all downloading and pending tasks to paused status');
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

  /// 清除所有已完成的任务
  Future<int> clearCompleted() async {
    return _isar.writeTxn(() async {
      final tasks = await _isar.downloadTasks
          .filter()
          .statusEqualTo(DownloadStatus.completed)
          .findAll();
      return _isar.downloadTasks.deleteAll(tasks.map((t) => t.id).toList());
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

  /// 获取下一个优先级值（用于新任务）
  Future<int> getNextPriority() async {
    final task = await _isar.downloadTasks.where().sortByPriorityDesc().findFirst();
    return (task?.priority ?? 0) + 1;
  }
}
