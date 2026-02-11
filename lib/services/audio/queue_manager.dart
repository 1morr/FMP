import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../../core/constants/app_constants.dart';
import '../../core/extensions/track_extensions.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_provider.dart';

/// 播放队列管理器（纯队列逻辑）
/// 负责管理播放列表、索引、播放模式和持久化
/// 不直接操作音频播放器
class QueueManager with Logging {
  final QueueRepository _queueRepository;
  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;
  final SourceManager _sourceManager;

  // 队列数据
  List<Track> _tracks = [];
  int _currentIndex = 0;
  PlayQueue? _currentQueue;

  // 保存位置的定时器
  Timer? _savePositionTimer;

  // 当前播放位置（由外部更新）
  Duration _currentPosition = Duration.zero;

  // 正在获取 URL 的 track id，防止重复获取
  final Set<int> _fetchingUrlTrackIds = {};

  // ========== Shuffle 相关 ==========
  List<int> _shuffleOrder = [];
  int _shuffleIndex = 0;

  // ========== 状态变化通知 ==========
  final _stateController = StreamController<void>.broadcast();

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
    _shuffleIndex = index.clamp(0, _shuffleOrder.isEmpty ? 0 : _shuffleOrder.length - 1);
    logDebug('Restored shuffle state: order length=${_shuffleOrder.length}, index=$_shuffleIndex');
  }

  /// 获取接下来要播放的歌曲列表（考虑 shuffle 模式）
  List<Track> getUpcomingTracks({int count = 5}) {
    if (_tracks.isEmpty) return [];

    final List<Track> upcoming = [];
    int addedCount = 0;

    if (isShuffleEnabled && _shuffleOrder.isNotEmpty) {
      // 随机模式：按 shuffle order 获取后续歌曲
      for (var i = _shuffleIndex + 1; i < _shuffleOrder.length && addedCount < count; i++) {
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
      for (var i = _currentIndex + 1; i < _tracks.length && addedCount < count; i++) {
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
        for (var i = shuffleIdx; i < _shuffleOrder.length && addedCount < count; i++) {
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
    required SettingsRepository settingsRepository,
    required SourceManager sourceManager,
  })  : _queueRepository = queueRepository,
        _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _sourceManager = sourceManager;

  /// 初始化队列（从持久化存储加载）
  Future<void> initialize() async {
    logInfo('Initializing QueueManager...');
    try {
      _currentQueue = await _queueRepository.getOrCreate();

      // 检查是否启用记住播放位置
      final settings = await _settingsRepository.get();
      final shouldRestorePosition = settings.rememberPlaybackPosition;

      if (_currentQueue!.trackIds.isNotEmpty) {
        logDebug('Loading ${_currentQueue!.trackIds.length} saved tracks');
        _tracks = await _trackRepository.getByIds(_currentQueue!.trackIds);

        if (_tracks.isNotEmpty) {
          _currentIndex = _currentQueue!.currentIndex.clamp(0, _tracks.length - 1);
          
          // 只有启用了记住播放位置才恢复位置
          if (shouldRestorePosition) {
            _currentPosition = Duration(milliseconds: _currentQueue!.lastPositionMs);
            logDebug('Restored position: $_currentPosition');
          } else {
            _currentPosition = Duration.zero;
            logDebug('Remember position disabled, starting from beginning');
          }

          // 如果启用了随机播放，恢复 shuffle order
          if (isShuffleEnabled) {
            _generateShuffleOrder();
          }

          logDebug('Restored ${_tracks.length} tracks, index: $_currentIndex');
        }
      }

      // 启动定期保存
      _startPositionSaver();

      // 清理孤立的 Track 记录（不属于任何歌单且不在队列中的 tracks）
      // 使用 unawaited 避免阻塞初始化
      unawaited(_cleanupOrphanTracks());

      logInfo('QueueManager initialized with ${_tracks.length} tracks');
    } catch (e, stack) {
      logError('Failed to initialize QueueManager', e, stack);
      rethrow;
    }
  }

  /// 释放资源
  void dispose() {
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
    await _savePosition();
  }

  /// 获取恢复位置
  Duration get savedPosition => _currentPosition;

  /// 获取保存的音量
  double get savedVolume => _currentQueue?.lastVolume ?? 1.0;

  /// 是否启用记住播放位置（读取用户设置）
  Future<bool> get shouldRememberPosition async {
    final settings = await _settingsRepository.get();
    return settings.rememberPlaybackPosition;
  }

  /// 保存音量
  Future<void> saveVolume(double volume) async {
    if (_currentQueue == null) return;
    _currentQueue!.lastVolume = volume.clamp(0.0, 1.0);
    await _queueRepository.save(_currentQueue!);
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
    if (_currentQueue == null) return;
    
    _currentQueue!.isMixMode = enabled;
    _currentQueue!.mixPlaylistId = enabled ? playlistId : null;
    _currentQueue!.mixSeedVideoId = enabled ? seedVideoId : null;
    _currentQueue!.mixTitle = enabled ? title : null;
    
    await _queueRepository.save(_currentQueue!);
    logDebug('Mix mode ${enabled ? "enabled" : "disabled"}: playlistId=$playlistId, title=$title');
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
  Future<void> restoreQueue(List<Track> tracks, {required int startIndex}) async {
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
  Future<void> add(Track track) async {
    logDebug('add: ${track.title}');

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

  /// 确保歌曲有有效的音频 URL
  /// 
  /// 返回 (Track, String?) 元组：
  /// - Track: 更新后的歌曲对象
  /// - String?: 找到的本地文件路径，如果没有则为 null
  /// 
  /// 如果获取失败会重试一次
  /// 本地文件检查逻辑（B1）：检查所有路径，使用第一个存在的，仅清除不存在的
  /// [persist] 是否将 track 保存到数据库，临时播放时设为 false
  Future<(Track, String?)> ensureAudioUrl(Track track, {int retryCount = 0, bool persist = true}) async {
    // B1: 检查所有下载路径，找到第一个存在的文件
    String? localPath;
    final invalidPaths = <String>[];
    
    for (final path in track.allDownloadPaths) {
      if (File(path).existsSync()) {
        localPath = path;
        break;
      } else {
        invalidPaths.add(path);
      }
    }
    
    // 如果找到有效的本地文件
    if (localPath != null) {
      // B1: 清除无效路径（仅清除不存在的，不清除有效的）
      if (invalidPaths.isNotEmpty && persist) {
        final newInfos = <PlaylistDownloadInfo>[];
        for (final info in track.playlistInfo) {
          if (invalidPaths.contains(info.downloadPath)) {
            // 清除无效路径但保留歌单关联和名称
            newInfos.add(PlaylistDownloadInfo()
              ..playlistId = info.playlistId
              ..playlistName = info.playlistName
              ..downloadPath = '');
          } else {
            newInfos.add(PlaylistDownloadInfo()
              ..playlistId = info.playlistId
              ..playlistName = info.playlistName
              ..downloadPath = info.downloadPath);
          }
        }
        track.playlistInfo = newInfos;
        await _trackRepository.save(track);
        logDebug('Cleared ${invalidPaths.length} invalid paths for: ${track.title}');
      }
      
      logDebug('Using local file for: ${track.title}, path: $localPath');
      return (track, localPath);
    }

    // 本地文件都不存在，回退到在线播放
    // B1: 清除所有无效路径
    if (invalidPaths.isNotEmpty && persist) {
      final newInfos = <PlaylistDownloadInfo>[];
      for (final info in track.playlistInfo) {
        // 清除所有路径但保留歌单关联和名称
        newInfos.add(PlaylistDownloadInfo()
          ..playlistId = info.playlistId
          ..playlistName = info.playlistName
          ..downloadPath = '');
      }
      track.playlistInfo = newInfos;
      await _trackRepository.save(track);
      logDebug('Cleared all ${invalidPaths.length} invalid paths for: ${track.title}, falling back to online URL');
    } else if (track.hasAnyDownload) {
      logDebug('Local file not found for: ${track.title}, falling back to online URL');
    }

    // 如果音频 URL 有效，直接返回（无本地文件）
    if (track.hasValidAudioUrl) {
      logDebug('Audio URL still valid for: ${track.title}, expiry: ${track.audioUrlExpiry}');
      return (track, null);
    }

    // 获取音频 URL
    logDebug('Fetching audio URL for: ${track.title} (attempt ${retryCount + 1})');
    final source = _sourceManager.getSource(track.sourceType);
    if (source == null) {
      throw Exception('No source available for ${track.sourceType}');
    }

    try {
      final refreshedTrack = await source.refreshAudioUrl(track);
      if (persist) {
        // 【重要】从数据库获取最新的 track 数据，避免覆盖并发修改（如下载路径）
        // 这样做是因为 refreshAudioUrl 修改的是传入的 track 对象，
        // 但该对象可能是从内存队列中获取的旧版本，不包含最新的下载路径
        final freshTrack = await _trackRepository.getById(track.id);
        if (freshTrack != null) {
          // 只复制 URL 相关字段到最新的 track
          freshTrack.audioUrl = refreshedTrack.audioUrl;
          freshTrack.audioUrlExpiry = refreshedTrack.audioUrlExpiry;
          await _trackRepository.save(freshTrack);
          // 也更新 refreshedTrack 的 playlistInfo 以确保返回的数据是最新的
          refreshedTrack.playlistInfo = freshTrack.playlistInfo;
        } else {
          // track 被删除了？回退到保存刷新后的 track
          await _trackRepository.save(refreshedTrack);
        }
      }
      logDebug('Successfully fetched audio URL for: ${track.title}');

      // 更新队列中的 track
      final index = _tracks.indexWhere((t) => t.id == track.id);
      if (index >= 0) {
        _tracks[index] = refreshedTrack;
      }

      return (refreshedTrack, null);
    } catch (e) {
      // 如果是第一次尝试且失败，等待后重试一次
      if (retryCount < 1) {
        logWarning('Failed to fetch audio URL for ${track.title}, retrying in 1 second: $e');
        await Future.delayed(AppConstants.queueSaveRetryDelay);
        return ensureAudioUrl(track, retryCount: retryCount + 1, persist: persist);
      }
      logError('Failed to fetch audio URL for ${track.title} after ${retryCount + 1} attempts', e);
      rethrow;
    }
  }

  /// 确保歌曲有有效的音频流（返回流元信息）
  /// 
  /// 返回 (Track, String?, AudioStreamResult?) 元组：
  /// - Track: 更新后的歌曲对象
  /// - String?: 找到的本地文件路径，如果没有则为 null
  /// - AudioStreamResult?: 在线流信息（含码率/格式），如果使用本地文件则为 null
  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    // 检查本地文件
    String? localPath;
    final invalidPaths = <String>[];
    
    for (final path in track.allDownloadPaths) {
      if (File(path).existsSync()) {
        localPath = path;
        break;
      } else {
        invalidPaths.add(path);
      }
    }
    
    // 如果找到有效的本地文件
    if (localPath != null) {
      // 清除无效路径
      if (invalidPaths.isNotEmpty && persist) {
        final newInfos = <PlaylistDownloadInfo>[];
        for (final info in track.playlistInfo) {
          if (invalidPaths.contains(info.downloadPath)) {
            newInfos.add(PlaylistDownloadInfo()
              ..playlistId = info.playlistId
              ..playlistName = info.playlistName
              ..downloadPath = '');
          } else {
            newInfos.add(PlaylistDownloadInfo()
              ..playlistId = info.playlistId
              ..playlistName = info.playlistName
              ..downloadPath = info.downloadPath);
          }
        }
        track.playlistInfo = newInfos;
        await _trackRepository.save(track);
      }
      
      logDebug('Using local file for: ${track.title}');
      return (track, localPath, null);
    }

    // 清除所有无效路径（如果需要）
    if (invalidPaths.isNotEmpty && persist) {
      final newInfos = <PlaylistDownloadInfo>[];
      for (final info in track.playlistInfo) {
        newInfos.add(PlaylistDownloadInfo()
          ..playlistId = info.playlistId
          ..playlistName = info.playlistName
          ..downloadPath = '');
      }
      track.playlistInfo = newInfos;
      await _trackRepository.save(track);
    }

    // 获取在线音频流（使用用户设置的音频配置）
    logDebug('Fetching audio stream for: ${track.title} (attempt ${retryCount + 1})');
    final source = _sourceManager.getSource(track.sourceType);
    if (source == null) {
      throw Exception('No source available for ${track.sourceType}');
    }

    try {
      final config = await _buildAudioStreamConfig(track.sourceType);
      final streamResult = await source.getAudioStream(track.sourceId, config: config);
      
      // 更新 track 的 URL
      track.audioUrl = streamResult.url;
      track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));
      track.updatedAt = DateTime.now();
      
      if (persist) {
        final freshTrack = await _trackRepository.getById(track.id);
        if (freshTrack != null) {
          freshTrack.audioUrl = track.audioUrl;
          freshTrack.audioUrlExpiry = track.audioUrlExpiry;
          await _trackRepository.save(freshTrack);
          track.playlistInfo = freshTrack.playlistInfo;
        } else {
          await _trackRepository.save(track);
        }
      }
      
      logDebug('Got audio stream for ${track.title}: $streamResult');

      // 更新队列中的 track
      final index = _tracks.indexWhere((t) => t.id == track.id);
      if (index >= 0) {
        _tracks[index] = track;
      }

      return (track, null, streamResult);
    } catch (e) {
      if (retryCount < 1) {
        logWarning('Failed to fetch audio stream for ${track.title}, retrying: $e');
        await Future.delayed(AppConstants.queueSaveRetryDelay);
        return ensureAudioStream(track, retryCount: retryCount + 1, persist: persist);
      }
      logError('Failed to fetch audio stream for ${track.title} after ${retryCount + 1} attempts', e);
      rethrow;
    }
  }

  /// 获取备选音频流（当主 URL 播放失败时使用）
  Future<AudioStreamResult?> getAlternativeAudioStream(Track track, {String? failedUrl}) async {
    final source = _sourceManager.getSource(track.sourceType);
    if (source == null) return null;
    
    logDebug('Getting alternative audio stream for: ${track.title}');
    final config = await _buildAudioStreamConfig(track.sourceType);
    return await source.getAlternativeAudioStream(track.sourceId, failedUrl: failedUrl, config: config);
  }

  /// 获取备选音频 URL（简化版，向后兼容）
  Future<String?> getAlternativeAudioUrl(Track track, {String? failedUrl}) async {
    final result = await getAlternativeAudioStream(track, failedUrl: failedUrl);
    return result?.url;
  }

  /// 根据设置构建音频流配置
  Future<AudioStreamConfig> _buildAudioStreamConfig(SourceType sourceType) async {
    final settings = await _settingsRepository.get();
    
    // 根据源类型选择流优先级
    final streamPriority = sourceType == SourceType.youtube
        ? settings.youtubeStreamPriorityList
        : settings.bilibiliStreamPriorityList;

    return AudioStreamConfig(
      qualityLevel: settings.audioQualityLevel,
      formatPriority: settings.audioFormatPriorityList,
      streamPriority: streamPriority,
    );
  }

  /// 预取下一首歌曲的 URL
  Future<void> prefetchNext() async {
    final nextIdx = getNextIndex();
    if (nextIdx == null) return;

    var track = _tracks[nextIdx];
    
    // 使用扩展方法检查本地音频文件是否存在
    if (track.hasLocalAudio) {
      return; // 本地文件存在，无需预取
    }
    
    // 检查是否已有有效的在线 URL 或正在获取中
    if (track.hasValidAudioUrl || _fetchingUrlTrackIds.contains(track.id)) {
      return;
    }

    logDebug('Prefetching URL for next track: ${track.title}');
    _fetchingUrlTrackIds.add(track.id);

    try {
      await ensureAudioUrl(track);
    } catch (e) {
      logError('Failed to prefetch URL for: ${track.title}', e);
    } finally {
      _fetchingUrlTrackIds.remove(track.id);
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
    if (_currentQueue == null) return;

    _currentQueue!.trackIds = _tracks.map((t) => t.id).toList();
    _currentQueue!.currentIndex = _currentIndex;
    _currentQueue!.lastPositionMs = _currentPosition.inMilliseconds;
    _currentQueue!.lastUpdated = DateTime.now();
    await _queueRepository.save(_currentQueue!);
  }

  Future<void> _savePosition() async {
    if (_currentQueue == null) return;

    _currentQueue!.currentIndex = _currentIndex;
    _currentQueue!.lastPositionMs = _currentPosition.inMilliseconds;
    await _queueRepository.save(_currentQueue!);
  }

  void _notifyStateChanged() {
    _stateController.add(null);
  }
}
