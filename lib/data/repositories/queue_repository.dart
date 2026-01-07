import 'package:isar/isar.dart';
import '../models/play_queue.dart';
import '../../core/logger.dart';

/// PlayQueue 数据仓库
class QueueRepository with Logging {
  final Isar _isar;

  QueueRepository(this._isar);

  /// 获取或创建播放队列（单例）
  Future<PlayQueue> getOrCreate() async {
    logDebug('Getting or creating queue...');
    var queue = await _isar.playQueues.where().findFirst();
    if (queue == null) {
      logInfo('No existing queue found, creating new one');
      queue = PlayQueue();
      await _isar.writeTxn(() => _isar.playQueues.put(queue!));
      logDebug('Created new queue with id: ${queue.id}');
    } else {
      logDebug('Found existing queue with ${queue.trackIds.length} tracks, currentIndex: ${queue.currentIndex}');
    }
    return queue;
  }

  /// 保存播放队列
  Future<int> save(PlayQueue queue) async {
    logDebug('Saving queue: ${queue.trackIds.length} tracks, index: ${queue.currentIndex}');
    queue.lastUpdated = DateTime.now();
    return _isar.writeTxn(() => _isar.playQueues.put(queue));
  }

  /// 添加歌曲到队列末尾
  Future<void> addTrack(int trackId) async {
    final queue = await getOrCreate();
    if (!queue.trackIds.contains(trackId)) {
      queue.trackIds.add(trackId);
      await save(queue);
    }
  }

  /// 批量添加歌曲到队列
  Future<void> addTracks(List<int> trackIds) async {
    final queue = await getOrCreate();
    for (final trackId in trackIds) {
      if (!queue.trackIds.contains(trackId)) {
        queue.trackIds.add(trackId);
      }
    }
    await save(queue);
  }

  /// 插入歌曲到指定位置
  Future<void> insertTrack(int index, int trackId) async {
    final queue = await getOrCreate();
    queue.trackIds.insert(index.clamp(0, queue.trackIds.length), trackId);
    await save(queue);
  }

  /// 移除歌曲
  Future<void> removeTrack(int trackId) async {
    final queue = await getOrCreate();
    final index = queue.trackIds.indexOf(trackId);
    if (index != -1) {
      queue.trackIds.removeAt(index);
      // 调整当前索引
      if (index < queue.currentIndex) {
        queue.currentIndex--;
      } else if (index == queue.currentIndex && queue.currentIndex >= queue.trackIds.length) {
        queue.currentIndex = queue.trackIds.isEmpty ? 0 : queue.trackIds.length - 1;
      }
      await save(queue);
    }
  }

  /// 移除指定位置的歌曲
  Future<void> removeAt(int index) async {
    final queue = await getOrCreate();
    if (index >= 0 && index < queue.trackIds.length) {
      queue.trackIds.removeAt(index);
      // 调整当前索引
      if (index < queue.currentIndex) {
        queue.currentIndex--;
      } else if (index == queue.currentIndex && queue.currentIndex >= queue.trackIds.length) {
        queue.currentIndex = queue.trackIds.isEmpty ? 0 : queue.trackIds.length - 1;
      }
      await save(queue);
    }
  }

  /// 移动歌曲位置
  Future<void> moveTrack(int oldIndex, int newIndex) async {
    final queue = await getOrCreate();
    if (oldIndex >= 0 && oldIndex < queue.trackIds.length &&
        newIndex >= 0 && newIndex < queue.trackIds.length) {
      final trackId = queue.trackIds.removeAt(oldIndex);
      queue.trackIds.insert(newIndex, trackId);

      // 调整当前索引
      if (queue.currentIndex == oldIndex) {
        queue.currentIndex = newIndex;
      } else if (oldIndex < queue.currentIndex && newIndex >= queue.currentIndex) {
        queue.currentIndex--;
      } else if (oldIndex > queue.currentIndex && newIndex <= queue.currentIndex) {
        queue.currentIndex++;
      }

      await save(queue);
    }
  }

  /// 清空队列
  Future<void> clear() async {
    final queue = await getOrCreate();
    queue.trackIds.clear();
    queue.currentIndex = 0;
    queue.lastPositionMs = 0;
    queue.originalOrder = null;
    await save(queue);
  }

  /// 更新当前播放索引
  Future<void> updateCurrentIndex(int index) async {
    final queue = await getOrCreate();
    queue.currentIndex = index.clamp(0, queue.trackIds.isEmpty ? 0 : queue.trackIds.length - 1);
    await save(queue);
  }

  /// 更新播放位置
  Future<void> updatePosition(int positionMs) async {
    final queue = await getOrCreate();
    queue.lastPositionMs = positionMs;
    await save(queue);
  }

  /// 更新随机播放状态
  Future<void> updateShuffleEnabled(bool enabled) async {
    final queue = await getOrCreate();
    queue.isShuffleEnabled = enabled;
    await save(queue);
  }

  /// 更新循环模式
  Future<void> updateLoopMode(LoopMode mode) async {
    final queue = await getOrCreate();
    queue.loopMode = mode;
    await save(queue);
  }

  /// 随机打乱队列
  Future<void> shuffle() async {
    final queue = await getOrCreate();
    if (queue.trackIds.isEmpty) return;

    // 保存原始顺序
    queue.originalOrder = List.from(queue.trackIds);

    // 获取当前歌曲ID
    final currentTrackId = queue.currentTrackId;

    // 打乱
    queue.trackIds.shuffle();

    // 将当前播放的歌曲移到第一位
    if (currentTrackId != null) {
      queue.trackIds.remove(currentTrackId);
      queue.trackIds.insert(0, currentTrackId);
      queue.currentIndex = 0;
    }

    await save(queue);
  }

  /// 恢复原始顺序
  Future<void> unshuffle() async {
    final queue = await getOrCreate();
    if (queue.originalOrder != null) {
      final currentTrackId = queue.currentTrackId;
      queue.trackIds = List.from(queue.originalOrder!);
      queue.originalOrder = null;

      // 恢复当前索引
      if (currentTrackId != null) {
        final newIndex = queue.trackIds.indexOf(currentTrackId);
        if (newIndex != -1) {
          queue.currentIndex = newIndex;
        }
      }

      await save(queue);
    }
  }
}
