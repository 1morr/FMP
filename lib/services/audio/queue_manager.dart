import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/track_repository.dart';

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
class QueueManager {
  final AudioPlayer _player;
  final QueueRepository _queueRepository;
  final TrackRepository _trackRepository;

  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  List<Track> _tracks = [];
  PlayQueue? _currentQueue;

  // 保存位置的定时器
  Timer? _savePositionTimer;

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
  })  : _player = player,
        _queueRepository = queueRepository,
        _trackRepository = trackRepository;

  /// 初始化队列（从持久化存储加载）
  Future<void> initialize() async {
    _currentQueue = await _queueRepository.getOrCreate();

    if (_currentQueue!.trackIds.isNotEmpty) {
      // 加载保存的歌曲
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
      }
    }

    // 启动定期保存位置
    _startPositionSaver();

    // 监听播放完成事件
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _savePosition();
      }
    });
  }

  /// 释放资源
  void dispose() {
    _savePositionTimer?.cancel();
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
    if (index >= 0 && index < _tracks.length) {
      await _player.seek(Duration.zero, index: index);
      await _player.play();
    }
  }

  /// 播放单首歌曲（替换队列）
  Future<void> playSingle(Track track) async {
    await clear();
    await add(track);
    await _player.play();
  }

  /// 播放多首歌曲（替换队列）
  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;

    await clear();
    await addAll(tracks);

    if (startIndex >= 0 && startIndex < tracks.length) {
      await _player.seek(Duration.zero, index: startIndex);
    }
    await _player.play();
  }

  // ========== 队列操作 ==========

  /// 添加歌曲到队列末尾
  Future<void> add(Track track) async {
    // 先保存 track 到数据库
    final savedTrack = await _trackRepository.save(track);
    _tracks.add(savedTrack);
    await _playlist.add(_createAudioSource(savedTrack));
    await _persistQueue();
  }

  /// 添加多首歌曲
  Future<void> addAll(List<Track> tracks) async {
    if (tracks.isEmpty) return;

    // 批量保存到数据库
    final savedTracks = await _trackRepository.saveAll(tracks);
    _tracks.addAll(savedTracks);
    await _playlist.addAll(savedTracks.map(_createAudioSource).toList());
    await _persistQueue();
  }

  /// 插入歌曲到指定位置
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
    _tracks.clear();
    await _playlist.clear();
    _currentQueue!.originalOrder = [];
    await _persistQueue();
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
    final uri = track.downloadedPath != null
        ? Uri.file(track.downloadedPath!)
        : track.cachedPath != null
            ? Uri.file(track.cachedPath!)
            : Uri.parse(track.audioUrl ?? '');

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
    _playlist = ConcatenatingAudioSource(
      children: _tracks.map(_createAudioSource).toList(),
    );
    await _player.setAudioSource(_playlist);
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
