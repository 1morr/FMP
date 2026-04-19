import 'dart:async';
import 'dart:math';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/play_queue.dart';
import '../../data/models/track.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/track_repository.dart';
import 'audio_stream_manager.dart';
import 'queue_persistence_manager.dart';

/// 播放队列管理器（纯队列逻辑）
/// 负责管理播放列表、索引、播放模式和持久化
/// 不直接操作音频播放器
class QueueManager with Logging {
  final QueueRepository _queueRepository;
  final TrackRepository _trackRepository;
  final QueuePersistenceManager _queuePersistenceManager;
  final AudioStreamManager _audioStreamManager;

  // 队列数据
  List<Track> _tracks = [];
  int _currentIndex = 0;
  PlayQueue? _currentQueue;

  // 保存位置的定时器
  Timer? _savePositionTimer;

  // 当前播放位置（由外部更新）
  Duration _currentPosition = Duration.zero;

  // ========== Shuffle 相关 ==========
  List<int> _shuffleOrder = [];
  int _shuffleIndex = 0;

  // ========== 状态变化通知 ==========
  final _stateController = StreamController<void>.broadcast();
  bool _isDisposed = false;

  /// 状态变化流（当队列、索引、播放模式变化时触发）
  Stream<void> get stateStream => _stateController.stream;

  // ========== 公开属性 ==========

  /// 当前队列中的歌曲列表（不可修改）
  List<Track> get tracks => List.unmodifiable(_tracks);

  /// 队列长度
  int get length => _tracks.length;

  /// 是否为空
  bool get isEmpty => _tracks.isEmpty;

  /// 当前播放索引
  int get currentIndex => _currentIndex;

  /// 当前播放的歌曲
  Track? get currentTrack {
    if (_currentIndex >= 0 && _currentIndex < _tracks.length) {
      return _tracks[_currentIndex];
    }
    return null;
  }

  /// 是否启用随机播放
  bool get isShuffleEnabled => _currentQueue?.isShuffleEnabled ?? false;

  /// 当前循环模式
  LoopMode get loopMode => _currentQueue?.loopMode ?? LoopMode.none;

  /// 是否有下一首
  bool get hasNext => getNextIndex() != null;

  /// 是否有上一首
  bool get hasPrevious => getPreviousIndex() != null;

  /// 获取当前 shuffle order（用于临时播放保存/恢复）
  List<int> get shuffleOrder => List.unmodifiable(_shuffleOrder);

  /// 获取当前 shuffle index（用于临时播放保存/恢复）
  int get shuffleIndex => _shuffleIndex;

  /// 设置 shuffle 状态（用于临时播放恢复）
  void setShuffleState(List<int> order, int index) {
    _shuffleOrder = List.from(order);
    _shuffleIndex =
        index.clamp(0, _shuffleOrder.isEmpty ? 0 : _shuffleOrder.length - 1);
    logDebug(
        'Restored shuffle state: order length=${_shuffleOrder.length}, index=$_shuffleIndex');
  }

  /// 获取接下来要播放的歌曲列表（考虑 shuffle 模式）
  List<Track> getUpcomingTracks({int count = 5}) {
    if (_tracks.isEmpty) return [];

    final List<Track> upcoming = [];
    int addedCount = 0;

    if (isShuffleEnabled && _shuffleOrder.isNotEmpty) {
      // 随机模式：按 shuffle order 获取后续歌曲
      for (var i = _shuffleIndex + 1;
          i < _shuffleOrder.length && addedCount < count;
          i++) {
        final trackIndex = _shuffleOrder[i];
        if (trackIndex >= 0 && trackIndex < _tracks.length) {
          upcoming.add(_tracks[trackIndex]);
          addedCount++;
        }
      }
      // 如果列表循环且还没填满，从头开始
      if (loopMode == LoopMode.all && addedCount < count) {
        for (var i = 0; i < _shuffleIndex && addedCount < count; i++) {
          final trackIndex = _shuffleOrder[i];
          if (trackIndex >= 0 && trackIndex < _tracks.length) {
            upcoming.add(_tracks[trackIndex]);
            addedCount++;
          }
        }
      }
    } else {
      // 顺序模式：按原始顺序获取后续歌曲
      for (var i = _currentIndex + 1;
          i < _tracks.length && addedCount < count;
          i++) {
        upcoming.add(_tracks[i]);
        addedCount++;
      }
      // 如果列表循环且还没填满，从头开始
      if (loopMode == LoopMode.all && addedCount < count) {
        for (var i = 0; i < _currentIndex && addedCount < count; i++) {
          upcoming.add(_tracks[i]);
          addedCount++;
        }
      }
    }

    return upcoming;
  }

  /// 从指定索引获取接下来要播放的歌曲列表（考虑 shuffle 模式）
  /// 用于临时播放模式下显示恢复后将要播放的歌曲
  List<Track> getUpcomingTracksFromIndex(int fromIndex, {int count = 5}) {
    if (_tracks.isEmpty) return [];

    final safeIndex = fromIndex.clamp(0, _tracks.length - 1);
    final List<Track> upcoming = [];
    int addedCount = 0;

    if (isShuffleEnabled && _shuffleOrder.isNotEmpty) {
      // 随机模式：找到对应的 shuffle 索引，然后获取后续歌曲
      // 注意：这里从 safeIndex 对应的 shuffle 位置开始
      final shuffleIdx = _shuffleOrder.indexOf(safeIndex);
      if (shuffleIdx >= 0) {
        for (var i = shuffleIdx;
            i < _shuffleOrder.length && addedCount < count;
            i++) {
          final trackIndex = _shuffleOrder[i];
          if (trackIndex >= 0 && trackIndex < _tracks.length) {
            upcoming.add(_tracks[trackIndex]);
            addedCount++;
          }
        }
      }
    } else {
      // 顺序模式：从指定索引开始获取歌曲
      for (var i = safeIndex; i < _tracks.length && addedCount < count; i++) {
        upcoming.add(_tracks[i]);
        addedCount++;
      }
    }

    return upcoming;
  }

  QueueManager({
    required QueueRepository queueRepository,
    required TrackRepository trackRepository,
    required QueuePersistenceManager queuePersistenceManager,
    required AudioStreamManager audioStreamManager,
  })  : _queueRepository = queueRepository,
        _trackRepository = trackRepository,
        _queuePersistenceManager = queuePersistenceManager,
        _audioStreamManager = audioStreamManager {
    _audioStreamManager.attachQueueTrackUpdater(replaceTrack);
  }

  /// 初始化队列（从持久化存储加载）
  Future<void> initialize() async {
    logInfo('Initializing QueueManager...');
    try {
      final restoredState = await _queuePersistenceManager.restoreState();
      _currentQueue = restoredState.queue;
      _tracks = restoredState.tracks;
      _currentPosition = restoredState.savedPosition;

      if (_tracks.isNotEmpty) {
        _currentIndex = restoredState.currentIndex.clamp(0, _tracks.length - 1);

        if (_currentPosition > Duration.zero) {
          logDebug('Restored position: $_currentPosition');
        } else {
          logDebug('Remember position disabled, starting from beginning');
        }

        if (isShuffleEnabled) {
          _generateShuffleOrder();
        }

        logDebug('Restored ${_tracks.length} tracks, index: $_currentIndex');
      }

      // 启动定期保存
      _startPositionSaver();

      // 清理孤立的 Track 记录（不属于任何歌单且不在队列中的 tracks）
      // 延迟 10 秒执行，避免与启动初始化竞争 I/O 和 CPU
      Future.delayed(const Duration(seconds: 10), () {
        _cleanupOrphanTracks();
      });

      logInfo('QueueManager initialized with ${_tracks.length} tracks');
    } catch (e, stack) {
      logError('Failed to initialize QueueManager', e, stack);
      rethrow;
    }
  }

  /// 释放资源
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _savePositionTimer?.cancel();
    _stateController.close();
  }

  // ========== 播放控制 ==========

  /// 设置当前索引（由 AudioController 调用）
  void setCurrentIndex(int index) {
    if (index < 0 || index >= _tracks.length) return;
    _currentIndex = index;

    // 更新 shuffle index
    if (isShuffleEnabled && _shuffleOrder.isNotEmpty) {
      _shuffleIndex = _shuffleOrder.indexOf(index);
      if (_shuffleIndex < 0) _shuffleIndex = 0;
    }

    _notifyStateChanged();
    _persistQueue();
  }

  /// 更新当前播放位置（由 AudioController 调用）
  void updatePosition(Duration position) {
    _currentPosition = position;
  }

  /// 立即保存当前位置（用于 seek 后立即保存）
  Future<void> savePositionNow() async {
    await _queuePersistenceManager.savePositionNow(
      queue: _currentQueue,
      currentIndex: _currentIndex,
      currentPosition: _currentPosition,
    );
  }

  /// 获取恢复位置
  Duration get savedPosition => _currentPosition;

  /// 获取保存的音量
  double get savedVolume => _currentQueue?.lastVolume ?? 1.0;

  /// 获取播放位置恢复设置
  Future<({bool enabled, int restartRewindSeconds, int tempPlayRewindSeconds})>
      getPositionRestoreSettings() async {
    return _queuePersistenceManager.getPositionRestoreSettings();
  }

  /// 保存音量
  Future<void> saveVolume(double volume) async {
    await _queuePersistenceManager.saveVolume(
      queue: _currentQueue,
      volume: volume,
    );
  }

  // ========== Mix 播放列表狀態 ==========

  /// 是否為 Mix 播放模式
  bool get isMixMode => _currentQueue?.isMixMode ?? false;

  /// Mix 播放列表 ID
  String? get mixPlaylistId => _currentQueue?.mixPlaylistId;

  /// Mix 種子視頻 ID
  String? get mixSeedVideoId => _currentQueue?.mixSeedVideoId;

  /// Mix 播放列表標題
  String? get mixTitle => _currentQueue?.mixTitle;

  /// 設置 Mix 播放模式
  Future<void> setMixMode({
    required bool enabled,
    String? playlistId,
    String? seedVideoId,
    String? title,
  }) async {
    await _queuePersistenceManager.setMixMode(
      queue: _currentQueue,
      enabled: enabled,
      playlistId: playlistId,
      seedVideoId: seedVideoId,
      title: title,
    );
    logDebug(
        'Mix mode ${enabled ? "enabled" : "disabled"}: playlistId=$playlistId, title=$title');
  }

  /// 清除 Mix 模式
  Future<void> clearMixMode() async {
    await setMixMode(enabled: false);
  }

  /// 获取下一首歌曲的索引
  int? getNextIndex() {
    if (_tracks.isEmpty) return null;

    if (isShuffleEnabled && _shuffleOrder.isNotEmpty) {
      // 随机模式
      if (_shuffleIndex < _shuffleOrder.length - 1) {
        return _shuffleOrder[_shuffleIndex + 1];
      }
      // 列表循环时回到开头
      if (loopMode == LoopMode.all) {
        return _shuffleOrder[0];
      }
      return null;
    } else {
      // 顺序模式
      if (_currentIndex < _tracks.length - 1) {
        return _currentIndex + 1;
      }
      // 列表循环时回到开头
      if (loopMode == LoopMode.all) {
        return 0;
      }
      return null;
    }
  }

  /// 获取上一首歌曲的索引
  int? getPreviousIndex() {
    if (_tracks.isEmpty) return null;

    if (isShuffleEnabled && _shuffleOrder.isNotEmpty) {
      // 随机模式
      if (_shuffleIndex > 0) {
        return _shuffleOrder[_shuffleIndex - 1];
      }
      // 列表循环时回到结尾
      if (loopMode == LoopMode.all) {
        return _shuffleOrder[_shuffleOrder.length - 1];
      }
      return null;
    } else {
      // 顺序模式
      if (_currentIndex > 0) {
        return _currentIndex - 1;
      }
      // 列表循环时回到结尾
      if (loopMode == LoopMode.all) {
        return _tracks.length - 1;
      }
      return null;
    }
  }

  /// 移动到下一首
  int? moveToNext() {
    final nextIdx = getNextIndex();
    if (nextIdx != null) {
      _currentIndex = nextIdx;
      if (isShuffleEnabled && _shuffleOrder.isNotEmpty) {
        _shuffleIndex = _shuffleOrder.indexOf(nextIdx);
      }
      _notifyStateChanged();
      _persistQueue();
    }
    return nextIdx;
  }

  /// 移动到上一首
  int? moveToPrevious() {
    final prevIdx = getPreviousIndex();
    if (prevIdx != null) {
      _currentIndex = prevIdx;
      if (isShuffleEnabled && _shuffleOrder.isNotEmpty) {
        _shuffleIndex = _shuffleOrder.indexOf(prevIdx);
      }
      _notifyStateChanged();
      _persistQueue();
    }
    return prevIdx;
  }

  // ========== 队列操作 ==========

  /// 播放单首歌曲（替换队列）
  Future<Track> playSingle(Track track) async {
    logInfo('playSingle: ${track.title}');

    _tracks.clear();
    _shuffleOrder.clear();

    // 使用 getOrCreate 避免重复创建 Track
    final savedTrack = await _trackRepository.getOrCreate(track);
    _tracks.add(savedTrack);
    _currentIndex = 0;

    await _persistQueue();
    _notifyStateChanged();

    return savedTrack;
  }

  /// 播放多首歌曲（替换队列）
  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    logInfo('playAll: ${tracks.length} tracks, startIndex: $startIndex');
    if (tracks.isEmpty) return;

    _tracks.clear();
    _shuffleOrder.clear();

    // 使用 getOrCreateAll 避免重复创建 Track
    final savedTracks = await _trackRepository.getOrCreateAll(tracks);
    _tracks.addAll(savedTracks);
    _currentIndex = startIndex.clamp(0, _tracks.length - 1);

    // 如果是 shuffle 模式，生成 shuffle order
    if (isShuffleEnabled) {
      _generateShuffleOrder();
    }

    await _persistQueue();
    _notifyStateChanged();
  }

  /// 恢复队列状态（不重新生成 shuffle order，用于临时播放恢复）
  Future<void> restoreQueue(List<Track> tracks,
      {required int startIndex}) async {
    logInfo('restoreQueue: ${tracks.length} tracks, startIndex: $startIndex');
    if (tracks.isEmpty) return;

    _tracks.clear();
    // 不清空 shuffle order，由外部通过 setShuffleState 设置

    // 使用 getOrCreateAll 避免重复创建 Track
    final savedTracks = await _trackRepository.getOrCreateAll(tracks);
    _tracks.addAll(savedTracks);
    _currentIndex = startIndex.clamp(0, _tracks.length - 1);

    await _persistQueue();
    _notifyStateChanged();
  }

  /// 添加歌曲到队列末尾
  /// 返回 true 表示添加成功，false 表示队列已满
  Future<bool> add(Track track) async {
    logDebug('add: ${track.title}');

    // 检查队列是否超过最大容量
    if (_tracks.length >= AppConstants.maxQueueSize) {
      logWarning(
          'Queue size exceeds maximum ${AppConstants.maxQueueSize}, skipping add');
      return false;
    }

    // 使用 getOrCreate 避免重复创建 Track
    final savedTrack = await _trackRepository.getOrCreate(track);
    _tracks.add(savedTrack);

    // 更新 shuffle order
    if (isShuffleEnabled) {
      // 如果 shuffle order 为空但有歌曲，需要重新生成
      if (_shuffleOrder.isEmpty && _tracks.length > 1) {
        _generateShuffleOrder();
      } else {
        _addToShuffleOrder(_tracks.length - 1);
      }
    }

    await _persistQueue();
    _notifyStateChanged();
    return true;
  }

  /// 添加多首歌曲
  Future<void> addAll(List<Track> tracks) async {
    logDebug('addAll: ${tracks.length} tracks');
    if (tracks.isEmpty) return;

    // 使用 getOrCreateAll 避免重复创建 Track
    final savedTracks = await _trackRepository.getOrCreateAll(tracks);
    final startIndex = _tracks.length;
    _tracks.addAll(savedTracks);

    // 更新 shuffle order
    if (isShuffleEnabled) {
      // 如果 shuffle order 为空但有歌曲，需要重新生成
      if (_shuffleOrder.isEmpty && _tracks.isNotEmpty) {
        _generateShuffleOrder();
      } else {
        for (var i = 0; i < savedTracks.length; i++) {
          _addToShuffleOrder(startIndex + i);
        }
      }
    }

    await _persistQueue();
    _notifyStateChanged();
  }

  /// 插入歌曲到指定位置
  Future<void> insert(int index, Track track) async {
    if (index < 0 || index > _tracks.length) return;

    // 调整 shuffle order
    if (isShuffleEnabled && _shuffleOrder.isNotEmpty) {
      _adjustShuffleOrderForInsert(index);
    }

    // 使用 getOrCreate 避免重复创建 Track
    final savedTrack = await _trackRepository.getOrCreate(track);
    _tracks.insert(index, savedTrack);

    // 调整当前索引
    if (index <= _currentIndex) {
      _currentIndex++;
    }

    // 添加到 shuffle order
    if (isShuffleEnabled) {
      // 如果 shuffle order 为空但有歌曲，需要重新生成
      if (_shuffleOrder.isEmpty && _tracks.length > 1) {
        _generateShuffleOrder();
      } else {
        _addToShuffleOrder(index);
      }
    }

    await _persistQueue();
    _notifyStateChanged();
  }

  /// 添加到下一首播放
  Future<void> addNext(Track track) async {
    final insertIndex = _currentIndex + 1;
    await insert(insertIndex.clamp(0, _tracks.length), track);
  }

  /// 移除指定位置的歌曲
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;

    // 从 shuffle order 中移除
    if (isShuffleEnabled) {
      _removeFromShuffleOrder(index);
    }

    _tracks.removeAt(index);

    // 调整当前索引
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex && _currentIndex >= _tracks.length) {
      _currentIndex = _tracks.length - 1;
    }

    await _persistQueue();
    _notifyStateChanged();
  }

  /// 移除指定歌曲
  Future<void> remove(Track track) async {
    final index = _tracks.indexWhere((t) => t.id == track.id);
    if (index >= 0) {
      await removeAt(index);
    }
  }

  /// 移动歌曲位置
  Future<void> move(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _tracks.length) return;
    if (newIndex < 0 || newIndex >= _tracks.length) return;
    if (oldIndex == newIndex) return;

    final track = _tracks.removeAt(oldIndex);
    _tracks.insert(newIndex, track);

    // 调整当前索引
    if (oldIndex == _currentIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    await _persistQueue();
    _notifyStateChanged();
  }

  /// 随机打乱队列（破坏性）
  Future<void> shuffle() async {
    if (_tracks.length <= 1) return;

    // 保存原始顺序
    _currentQueue!.originalOrder = _tracks.map((t) => t.id).toList();

    // 保持当前歌曲在第一位
    final current = currentTrack;
    _tracks.shuffle();

    if (current != null) {
      final index = _tracks.indexWhere((t) => t.id == current.id);
      if (index > 0) {
        _tracks.removeAt(index);
        _tracks.insert(0, current);
      }
    }

    _currentIndex = 0;

    await _persistQueue();
    _notifyStateChanged();
  }

  /// 恢复原始顺序
  Future<void> restoreOrder() async {
    final originalOrder = _currentQueue?.originalOrder;
    if (originalOrder == null || originalOrder.isEmpty) return;

    final current = currentTrack;
    final Map<int, Track> trackMap = {
      for (var t in _tracks) t.id: t,
    };

    _tracks = originalOrder
        .where((id) => trackMap.containsKey(id))
        .map((id) => trackMap[id]!)
        .toList();

    _currentQueue!.originalOrder = [];

    // 恢复当前歌曲的索引
    if (current != null) {
      _currentIndex = _tracks.indexWhere((t) => t.id == current.id);
      if (_currentIndex < 0) _currentIndex = 0;
    }

    await _persistQueue();
    _notifyStateChanged();
  }

  /// 清空队列
  Future<void> clear() async {
    logInfo('Clearing queue');

    _tracks.clear();
    _currentIndex = 0;
    _shuffleOrder.clear();
    _shuffleIndex = 0;

    if (_currentQueue != null) {
      _currentQueue!.originalOrder = [];
      _currentQueue!.isMixMode = false;
      _currentQueue!.mixPlaylistId = null;
      _currentQueue!.mixSeedVideoId = null;
      _currentQueue!.mixTitle = null;
      await _persistQueue();
    }

    _notifyStateChanged();
  }

  // ========== 播放模式 ==========

  /// 切换随机播放
  Future<void> toggleShuffle() async {
    if (_currentQueue == null) return;

    final wasEnabled = _currentQueue!.isShuffleEnabled;
    _currentQueue!.isShuffleEnabled = !wasEnabled;
    await _queueRepository.save(_currentQueue!);

    if (!wasEnabled) {
      // 开启随机：生成 shuffle order
      _generateShuffleOrder();
    } else {
      // 关闭随机：清空 shuffle order
      _clearShuffleOrder();
    }

    _notifyStateChanged();
  }

  /// 直接設置隨機播放狀態
  Future<void> setShuffle(bool enabled) async {
    if (_currentQueue == null) return;
    if (_currentQueue!.isShuffleEnabled == enabled) return;

    _currentQueue!.isShuffleEnabled = enabled;
    await _queueRepository.save(_currentQueue!);

    if (enabled) {
      _generateShuffleOrder();
    } else {
      _clearShuffleOrder();
    }

    _notifyStateChanged();
  }

  /// 设置循环模式
  Future<void> setLoopMode(LoopMode mode) async {
    if (_currentQueue == null) return;

    _currentQueue!.loopMode = mode;
    await _queueRepository.save(_currentQueue!);

    _notifyStateChanged();
  }

  /// 循环切换循环模式：none -> all -> one -> none
  Future<void> cycleLoopMode() async {
    final nextMode = switch (loopMode) {
      LoopMode.none => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.none,
    };
    await setLoopMode(nextMode);
  }

  // ========== URL 获取 ==========

  void replaceTrack(Track updatedTrack) {
    final index = _tracks.indexWhere((t) => t.id == updatedTrack.id);
    if (index >= 0) {
      _tracks[index] = updatedTrack;
    }
  }

  // ========== Shuffle 内部方法 ==========

  void _generateShuffleOrder() {
    if (_tracks.isEmpty) return;

    final random = Random();

    // 创建索引列表（排除当前歌曲）
    _shuffleOrder = List.generate(_tracks.length, (i) => i)
      ..remove(_currentIndex)
      ..shuffle(random);

    // 将当前歌曲放在开头
    _shuffleOrder.insert(0, _currentIndex);
    _shuffleIndex = 0;

    logDebug('Generated shuffle order, length: ${_shuffleOrder.length}');
  }

  void _clearShuffleOrder() {
    _shuffleOrder.clear();
    _shuffleIndex = 0;
  }

  void _addToShuffleOrder(int trackIndex) {
    if (!isShuffleEnabled || _shuffleOrder.isEmpty) return;

    final random = Random();
    final remainingSlots = _shuffleOrder.length - _shuffleIndex - 1;
    if (remainingSlots > 0) {
      final insertPos = _shuffleIndex + 1 + random.nextInt(remainingSlots + 1);
      _shuffleOrder.insert(insertPos, trackIndex);
    } else {
      _shuffleOrder.add(trackIndex);
    }
  }

  void _removeFromShuffleOrder(int trackIndex) {
    if (!isShuffleEnabled || _shuffleOrder.isEmpty) return;

    final shuffleIdx = _shuffleOrder.indexOf(trackIndex);
    if (shuffleIdx >= 0) {
      _shuffleOrder.removeAt(shuffleIdx);
      if (shuffleIdx < _shuffleIndex) {
        _shuffleIndex--;
      }
    }

    // 调整所有大于 trackIndex 的索引
    for (var i = 0; i < _shuffleOrder.length; i++) {
      if (_shuffleOrder[i] > trackIndex) {
        _shuffleOrder[i]--;
      }
    }
  }

  void _adjustShuffleOrderForInsert(int insertIndex) {
    if (!isShuffleEnabled || _shuffleOrder.isEmpty) return;

    for (var i = 0; i < _shuffleOrder.length; i++) {
      if (_shuffleOrder[i] >= insertIndex) {
        _shuffleOrder[i]++;
      }
    }
  }

  // ========== 持久化 ==========

  void _startPositionSaver() {
    _savePositionTimer?.cancel();
    _savePositionTimer = Timer.periodic(AppConstants.positionSaveInterval, (_) {
      _savePosition();
    });
  }

  /// 清理孤立的 Track 记录
  ///
  /// 在应用启动时调用，删除不属于任何歌单且不在当前队列中的 tracks。
  /// 这些 tracks 通常来自临时播放或 Mix 播放列表。
  Future<void> _cleanupOrphanTracks() async {
    try {
      final currentTrackIds = _tracks.map((t) => t.id).toList();
      final deleted = await _trackRepository.deleteOrphanTracks(
        excludeTrackIds: currentTrackIds,
      );
      if (deleted > 0) {
        logInfo('Cleaned up $deleted orphan tracks on startup');
      }
    } catch (e) {
      // 清理失败不影响正常使用，只记录警告
      logWarning('Failed to cleanup orphan tracks: $e');
    }
  }

  Future<void> _persistQueue() async {
    await _queuePersistenceManager.persistQueue(
      queue: _currentQueue,
      tracks: _tracks,
      currentIndex: _currentIndex,
      currentPosition: _currentPosition,
    );
  }

  Future<void> _savePosition() async {
    await _queuePersistenceManager.savePositionNow(
      queue: _currentQueue,
      currentIndex: _currentIndex,
      currentPosition: _currentPosition,
    );
  }

  void _notifyStateChanged() {
    if (_isDisposed || _stateController.isClosed) return;
    _stateController.add(null);
  }
}
