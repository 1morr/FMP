import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/source_provider.dart';

/// 媒体项元数据（用于音频源标记）
class MediaItem {
  final String id;
  final String title;
  final String? artist;
  final Uri? artUri;

  const MediaItem({
    required this.id,
    required this.title,
    this.artist,
    this.artUri,
  });
}

/// 播放队列管理器
/// 负责管理播放列表、持久化和同步
class QueueManager with Logging {
  final AudioPlayer _player;
  final QueueRepository _queueRepository;
  final TrackRepository _trackRepository;
  final SourceManager _sourceManager;

  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  List<Track> _tracks = [];
  PlayQueue? _currentQueue;

  // 保存位置的定时器
  Timer? _savePositionTimer;
  
  // 索引变化订阅
  StreamSubscription<int?>? _indexSubscription;
  
  // 正在获取 URL 的 track id，防止重复获取
  final Set<int> _fetchingUrlTrackIds = {};

  /// 当前队列中的歌曲列表（不可修改）
  List<Track> get tracks => List.unmodifiable(_tracks);

  /// 队列长度
  int get length => _tracks.length;

  /// 是否为空
  bool get isEmpty => _tracks.isEmpty;

  /// 当前播放索引
  int? get currentIndex => _player.currentIndex;

  /// 当前播放的歌曲
  Track? get currentTrack {
    final index = currentIndex;
    if (index != null && index >= 0 && index < _tracks.length) {
      return _tracks[index];
    }
    return null;
  }

  /// 当前播放模式
  PlayMode get playMode => _currentQueue?.playMode ?? PlayMode.sequential;

  QueueManager({
    required AudioPlayer player,
    required QueueRepository queueRepository,
    required TrackRepository trackRepository,
    required SourceManager sourceManager,
  })  : _player = player,
        _queueRepository = queueRepository,
        _trackRepository = trackRepository,
        _sourceManager = sourceManager;

  /// 初始化队列（从持久化存储加载）
  Future<void> initialize() async {
    logInfo('Initializing QueueManager...');
    try {
      _currentQueue = await _queueRepository.getOrCreate();

      if (_currentQueue!.trackIds.isNotEmpty) {
        logDebug('Loading ${_currentQueue!.trackIds.length} saved tracks');
        // 加载保存的歌曲（不获取音频 URL）
        _tracks = await _trackRepository.getByIds(_currentQueue!.trackIds);

        if (_tracks.isNotEmpty) {
          await _rebuildPlaylist();

          // 恢复播放位置
          if (_currentQueue!.currentIndex < _tracks.length) {
            await _player.seek(
              Duration(milliseconds: _currentQueue!.lastPositionMs),
              index: _currentQueue!.currentIndex,
            );
          }
          logDebug('Restored ${_tracks.length} tracks, position: ${_currentQueue!.currentIndex}');
        } else {
          logDebug('No tracks found in database, setting empty audio source');
          await _player.setAudioSource(_playlist);
        }
      } else {
        logDebug('Empty queue, setting empty audio source');
        await _player.setAudioSource(_playlist);
      }

      // 启动定期保存位置
      _startPositionSaver();

      // 监听播放完成事件
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _savePosition();
        }
      });
      
      // 监听索引变化，用于延迟获取音频 URL
      _indexSubscription = _player.currentIndexStream.listen(_onIndexChanged);

      logInfo('QueueManager initialized with ${_tracks.length} tracks');
    } catch (e, stack) {
      logError('Failed to initialize QueueManager', e, stack);
      rethrow;
    }
  }

  /// 释放资源
  void dispose() {
    _savePositionTimer?.cancel();
    _indexSubscription?.cancel();
  }
  
  /// 当播放索引改变时，确保当前歌曲有有效的音频 URL，并预取下一首
  Future<void> _onIndexChanged(int? index) async {
    if (index == null || index < 0 || index >= _tracks.length) return;
    
    // 确保当前歌曲有有效的 URL
    await _ensureTrackUrlAt(index);
    
    // 预取下一首歌曲的 URL（后台执行，不阻塞）
    _prefetchNextTrack(index);
  }
  
  /// 确保指定索引的歌曲有有效的音频 URL
  Future<void> _ensureTrackUrlAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    
    final track = _tracks[index];
    
    // 如果有本地文件，不需要获取 URL
    if (track.downloadedPath != null || track.cachedPath != null) return;
    
    // 如果已经有有效的 URL，不需要获取
    if (track.hasValidAudioUrl) return;
    
    // 如果正在获取，不要重复获取
    if (_fetchingUrlTrackIds.contains(track.id)) return;
    
    logInfo('Track at index $index needs audio URL, fetching: ${track.title}');
    _fetchingUrlTrackIds.add(track.id);
    
    try {
      // 获取音频 URL
      final refreshedTrack = await _ensureAudioUrl(track);
      _tracks[index] = refreshedTrack;
      
      // 更新播放列表中的音频源
      await _updateAudioSourceAt(index, refreshedTrack);
      
      logDebug('Audio URL fetched and updated for: ${track.title}');
    } catch (e, stack) {
      logError('Failed to fetch audio URL for track at index $index', e, stack);
    } finally {
      _fetchingUrlTrackIds.remove(track.id);
    }
  }
  
  /// 预取下一首歌曲的 URL（后台执行）
  void _prefetchNextTrack(int currentIndex) {
    final nextIndex = currentIndex + 1;
    if (nextIndex >= _tracks.length) return;
    
    final nextTrack = _tracks[nextIndex];
    
    // 如果不需要获取 URL，跳过
    if (nextTrack.downloadedPath != null || 
        nextTrack.cachedPath != null || 
        nextTrack.hasValidAudioUrl ||
        _fetchingUrlTrackIds.contains(nextTrack.id)) {
      return;
    }
    
    logDebug('Prefetching audio URL for next track: ${nextTrack.title}');
    
    // 后台获取，不等待结果
    _ensureTrackUrlAt(nextIndex);
  }
  
  /// 更新指定索引的音频源
  Future<void> _updateAudioSourceAt(int index, Track track) async {
    if (index < 0 || index >= _playlist.length) return;
    
    final newSource = _createAudioSource(track);
    final currentIndex = _player.currentIndex;
    final currentPosition = _player.position;
    
    await _playlist.removeAt(index);
    await _playlist.insert(index, newSource);
    
    // 如果更新的是当前播放的歌曲，需要重新定位
    if (currentIndex == index) {
      await _player.seek(currentPosition, index: index);
    }
  }

  /// 启动位置保存定时器（每10秒保存一次）
  void _startPositionSaver() {
    _savePositionTimer?.cancel();
    _savePositionTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _savePosition();
    });
  }

  // ========== 播放操作 ==========

  /// 从队列中播放指定歌曲
  Future<void> playAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    
    logDebug('playAt called: index $index, track: ${_tracks[index].title}');
    
    // 确保该歌曲有有效的音频 URL
    final track = _tracks[index];
    if (track.downloadedPath == null && track.cachedPath == null && !track.hasValidAudioUrl) {
      logDebug('Track needs audio URL, fetching...');
      _tracks[index] = await _ensureAudioUrl(track);
      await _updateAudioSourceAt(index, _tracks[index]);
    }
    
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  /// 播放单首歌曲（替换队列）
  Future<void> playSingle(Track track) async {
    logInfo('playSingle called: ${track.title} (sourceId: ${track.sourceId})');
    try {
      // 清空队列
      _tracks.clear();
      logDebug('Queue cleared, preparing track...');
      
      // 保存并确保有音频 URL
      var savedTrack = await _trackRepository.save(track);
      logDebug('Track saved with id: ${savedTrack.id}');
      savedTrack = await _ensureAudioUrl(savedTrack);
      logDebug('Audio URL ensured');
      
      _tracks.add(savedTrack);
      
      // 重建播放列表并设置到播放器
      await _rebuildPlaylist();
      logDebug('Playlist rebuilt and set to player');
      
      // 开始播放
      await _player.play();
      await _persistQueue();
      logInfo('Playback started for: ${track.title}');
    } catch (e, stack) {
      logError('playSingle failed for: ${track.title}', e, stack);
      rethrow;
    }
  }

  /// 播放多首歌曲（替换队列）
  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    logInfo('playAll called: ${tracks.length} tracks, startIndex: $startIndex');
    if (tracks.isEmpty) {
      logWarning('playAll: tracks is empty, returning');
      return;
    }

    try {
      // 清空队列
      _tracks.clear();
      logDebug('Queue cleared, saving ${tracks.length} tracks...');
      
      // 批量保存到数据库（不获取音频 URL）
      final savedTracks = await _trackRepository.saveAll(tracks);
      logDebug('Saved ${savedTracks.length} tracks to database');
      
      _tracks.addAll(savedTracks);
      
      // 只获取起始歌曲的音频 URL
      final validStartIndex = startIndex.clamp(0, _tracks.length - 1);
      logDebug('Fetching audio URL for starting track: ${_tracks[validStartIndex].title}');
      _tracks[validStartIndex] = await _ensureAudioUrl(_tracks[validStartIndex]);
      logDebug('Starting track audio URL fetched');
      
      // 重建播放列表（其他歌曲使用占位符）
      await _rebuildPlaylist();
      logDebug('Playlist rebuilt with ${_tracks.length} tracks');
      
      // 跳转到指定索引
      await _player.seek(Duration.zero, index: validStartIndex);
      logDebug('Seeked to index $validStartIndex');
      
      // 开始播放
      await _player.play();
      await _persistQueue();
      logInfo('Playback started at index $validStartIndex');
    } catch (e, stack) {
      logError('playAll failed', e, stack);
      rethrow;
    }
  }

  // ========== 队列操作 ==========

  /// 确保 track 有有效的音频 URL
  Future<Track> _ensureAudioUrl(Track track) async {
    // 如果有下载或缓存路径，不需要获取 URL
    if (track.downloadedPath != null || track.cachedPath != null) {
      return track;
    }

    // 如果音频 URL 有效，直接返回
    if (track.hasValidAudioUrl) {
      return track;
    }

    // 获取音频 URL
    logDebug('Fetching audio URL for: ${track.title}');
    final source = _sourceManager.getSource(track.sourceType);
    if (source == null) {
      final error = 'No source available for ${track.sourceType}';
      logError(error);
      throw Exception(error);
    }

    try {
      final refreshedTrack = await source.refreshAudioUrl(track);
      // 保存更新后的 track
      await _trackRepository.save(refreshedTrack);
      logDebug('Audio URL fetched for: ${track.title}');
      return refreshedTrack;
    } catch (e, stack) {
      logError('Failed to fetch audio URL for: ${track.title}', e, stack);
      rethrow;
    }
  }

  /// 添加歌曲到队列末尾（不获取音频 URL，播放时再获取）
  Future<void> add(Track track) async {
    logDebug('add: ${track.title} (sourceId: ${track.sourceId})');
    try {
      // 保存到数据库（不获取音频 URL）
      final savedTrack = await _trackRepository.save(track);
      logDebug('Track saved with id: ${savedTrack.id}');
      
      _tracks.add(savedTrack);
      await _playlist.add(_createAudioSource(savedTrack));
      await _persistQueue();
      logDebug('Track added to queue, total: ${_tracks.length}');
    } catch (e, stack) {
      logError('Failed to add track: ${track.title}', e, stack);
      rethrow;
    }
  }

  /// 添加多首歌曲（不获取音频 URL，播放时再获取）
  Future<void> addAll(List<Track> tracks) async {
    logDebug('addAll: ${tracks.length} tracks');
    if (tracks.isEmpty) return;

    try {
      // 批量保存到数据库（不获取音频 URL）
      final savedTracks = await _trackRepository.saveAll(tracks);
      logDebug('Saved ${savedTracks.length} tracks to database');

      _tracks.addAll(savedTracks);
      await _playlist.addAll(savedTracks.map(_createAudioSource).toList());
      await _persistQueue();
      logDebug('All tracks added to queue, total: ${_tracks.length}');
    } catch (e, stack) {
      logError('Failed to add tracks', e, stack);
      rethrow;
    }
  }

  /// 插入歌曲到指定位置（不获取音频 URL，播放时再获取）
  Future<void> insert(int index, Track track) async {
    if (index < 0 || index > _tracks.length) return;

    final savedTrack = await _trackRepository.save(track);
    _tracks.insert(index, savedTrack);
    await _playlist.insert(index, _createAudioSource(savedTrack));
    await _persistQueue();
  }

  /// 添加到下一首播放
  Future<void> addNext(Track track) async {
    final insertIndex = (currentIndex ?? -1) + 1;
    await insert(insertIndex.clamp(0, _tracks.length), track);
  }

  /// 移除指定位置的歌曲
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;

    _tracks.removeAt(index);
    await _playlist.removeAt(index);
    await _persistQueue();
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
    await _playlist.move(oldIndex, newIndex);
    await _persistQueue();
  }

  /// 随机打乱队列
  Future<void> shuffle() async {
    if (_tracks.length <= 1) return;

    // 保存原始顺序用于恢复
    _currentQueue!.originalOrder = _tracks.map((t) => t.id).toList();

    // 保持当前播放的歌曲在第一位
    final current = currentTrack;
    _tracks.shuffle();

    if (current != null) {
      final index = _tracks.indexWhere((t) => t.id == current.id);
      if (index > 0) {
        _tracks.removeAt(index);
        _tracks.insert(0, current);
      }
    }

    await _rebuildPlaylist();
    if (current != null) {
      await _player.seek(Duration.zero, index: 0);
    }
    await _persistQueue();
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
    await _rebuildPlaylist();

    // 恢复到当前播放的歌曲
    if (current != null) {
      final newIndex = _tracks.indexWhere((t) => t.id == current.id);
      if (newIndex >= 0) {
        await _player.seek(_player.position, index: newIndex);
      }
    }
    await _persistQueue();
  }

  /// 清空队列
  Future<void> clear() async {
    logInfo('Clearing queue');
    try {
      _tracks.clear();
      await _playlist.clear();
      if (_currentQueue != null) {
        _currentQueue!.originalOrder = [];
        await _persistQueue();
      }
      logDebug('Queue cleared successfully');
    } catch (e, stack) {
      logError('Failed to clear queue', e, stack);
      rethrow;
    }
  }

  // ========== 持久化 ==========

  /// 持久化队列状态
  Future<void> _persistQueue() async {
    if (_currentQueue == null) return;

    _currentQueue!.trackIds = _tracks.map((t) => t.id).toList();
    _currentQueue!.currentIndex = _player.currentIndex ?? 0;
    _currentQueue!.lastPositionMs = _player.position.inMilliseconds;
    _currentQueue!.lastUpdated = DateTime.now();
    await _queueRepository.save(_currentQueue!);
  }

  /// 保存当前播放位置
  Future<void> _savePosition() async {
    if (_currentQueue == null) return;

    _currentQueue!.currentIndex = _player.currentIndex ?? 0;
    _currentQueue!.lastPositionMs = _player.position.inMilliseconds;
    await _queueRepository.save(_currentQueue!);
  }

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    if (_currentQueue == null) return;

    _currentQueue!.playMode = mode;
    await _queueRepository.save(_currentQueue!);
  }

  // ========== 私有方法 ==========

  /// 创建音频源
  AudioSource _createAudioSource(Track track) {
    Uri uri;
    
    if (track.downloadedPath != null) {
      uri = Uri.file(track.downloadedPath!);
    } else if (track.cachedPath != null) {
      uri = Uri.file(track.cachedPath!);
    } else if (track.audioUrl != null && track.audioUrl!.isNotEmpty) {
      uri = Uri.parse(track.audioUrl!);
    } else {
      // 使用一个占位符 URL（加载时会失败，但不会导致解析错误）
      uri = Uri.parse('https://placeholder.invalid/${track.id}.mp3');
    }

    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: track.id.toString(),
        title: track.title,
        artist: track.artist,
        artUri: track.thumbnailUrl != null ? Uri.parse(track.thumbnailUrl!) : null,
      ),
    );
  }

  /// 重建播放列表
  Future<void> _rebuildPlaylist() async {
    logDebug('Rebuilding playlist with ${_tracks.length} tracks');
    try {
      _playlist = ConcatenatingAudioSource(
        children: _tracks.map(_createAudioSource).toList(),
      );
      await _player.setAudioSource(_playlist);
      logDebug('Playlist rebuilt and set to player');
    } catch (e, stack) {
      logError('Failed to rebuild playlist', e, stack);
      rethrow;
    }
  }

  /// 更新歌曲的音频URL
  Future<void> updateTrackAudioUrl(Track track) async {
    final index = _tracks.indexWhere((t) => t.id == track.id);
    if (index < 0) return;

    _tracks[index] = track;
    await _trackRepository.save(track);

    // 更新播放列表中的音频源
    final newSource = _createAudioSource(track);
    await _playlist.removeAt(index);
    await _playlist.insert(index, newSource);
  }
}
