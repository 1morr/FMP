import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';

/// 音频播放服务（单曲模式）
/// 只负责播放单首歌曲，队列逻辑由 QueueManager 管理
class AudioService with Logging {
  final AudioPlayer _player = AudioPlayer();

  // 完成事件控制器
  final _completedController = StreamController<void>.broadcast();

  // 流订阅列表（用于 dispose 时取消）
  final List<StreamSubscription> _subscriptions = [];

  // duck 前的音量（用于恢复）
  double _volumeBeforeDuck = 1.0;

  // ========== 状态流 ==========
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<double> get speedStream => _player.speedStream;

  /// 歌曲播放完成事件流
  Stream<void> get completedStream => _completedController.stream;

  // ========== 当前状态 ==========
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  Duration get bufferedPosition => _player.bufferedPosition;
  double get speed => _player.speed;
  double get volume => _player.volume;
  ProcessingState get processingState => _player.processingState;

  /// 初始化音频服务
  Future<void> initialize() async {
    logInfo('Initializing AudioService (single track mode)...');

    // 配置音频会话
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // 监听音频会话中断
    _subscriptions.add(
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 记住 duck 前的音量，以便正确恢复
              _volumeBeforeDuck = _player.volume;
              _player.setVolume(_player.volume * 0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              _player.pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 恢复到 duck 前的音量
              _player.setVolume(_volumeBeforeDuck);
              break;
            case AudioInterruptionType.pause:
              _player.play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      }),
    );

    // 监听音频设备变化（如耳机拔出）
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) {
        _player.pause();
      }),
    );

    // 监听播放状态，检测歌曲完成
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          logDebug('Track completed');
          _completedController.add(null);
        }
      }),
    );

    logInfo('AudioService initialized');
  }

  /// 释放资源
  Future<void> dispose() async {
    // 取消所有流订阅
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    await _completedController.close();
    await _player.dispose();
  }

  // ========== 播放控制 ==========

  /// 播放
  Future<void> play() => _player.play();

  /// 暂停
  Future<void> pause() {
    _cancelEnsurePlayback(); // 取消任何正在进行的播放确认
    return _player.pause();
  }

  /// 停止
  Future<void> stop() {
    _cancelEnsurePlayback(); // 取消任何正在进行的播放确认
    return _player.stop();
  }

  /// 切换播放/暂停
  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  // ========== 进度控制 ==========

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) => _player.seek(position);

  /// 快进
  Future<void> seekForward([Duration? duration]) async {
    final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
    final newPosition = _player.position + seekDuration;
    final maxPosition = _player.duration ?? Duration.zero;
    await _player.seek(newPosition > maxPosition ? maxPosition : newPosition);
  }

  /// 快退
  Future<void> seekBackward([Duration? duration]) async {
    final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
    final newPosition = _player.position - seekDuration;
    await _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  // ========== 播放速度 ==========

  /// 设置播放速度 (0.5 - 2.0)
  Future<void> setSpeed(double speed) => _player.setSpeed(speed.clamp(0.5, 2.0));

  /// 重置播放速度
  Future<void> resetSpeed() => _player.setSpeed(1.0);

  // ========== 音量控制 ==========

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  // ========== 音频源设置 ==========

  // 用于取消 _ensurePlayback 的重试逻辑
  bool _playbackCancelled = false;

  /// 确保播放开始
  /// 在 Android 上，setAudioSource 后可能需要等待播放器准备好
  Future<void> _ensurePlayback() async {
    _playbackCancelled = false;
    
    // 等待播放器进入 ready 状态（最多等待 2 秒）
    if (_player.processingState != ProcessingState.ready) {
      logDebug('Waiting for player to be ready, current state: ${_player.processingState}');
      try {
        await _player.playerStateStream
            .where((state) => state.processingState == ProcessingState.ready)
            .first
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        logWarning('Timeout waiting for ready state: ${_player.processingState}');
      }
    }

    // 检查是否被取消（用户可能已点击暂停）
    if (_playbackCancelled) {
      logDebug('Playback cancelled, not calling play()');
      return;
    }

    // 调用播放
    await _player.play();
    logDebug('_ensurePlayback completed, playing: ${_player.playing}, state: ${_player.processingState}');
  }

  /// 取消正在进行的 _ensurePlayback 重试
  void _cancelEnsurePlayback() {
    _playbackCancelled = true;
  }

  /// 创建带有 MediaItem 元数据的 AudioSource（用于后台播放通知）
  AudioSource _createAudioSource(String url, {
    Map<String, String>? headers,
    Track? track,
  }) {
    final mediaItem = track != null
        ? MediaItem(
            id: track.uniqueKey,
            title: track.title,
            artist: track.artist ?? '未知艺术家',
            artUri: track.thumbnailUrl != null ? Uri.parse(track.thumbnailUrl!) : null,
            duration: track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null,
          )
        : null;

    return AudioSource.uri(
      Uri.parse(url),
      headers: headers,
      tag: mediaItem,
    );
  }

  /// 播放指定 URL
  /// [headers] 可选的 HTTP 请求头，用于需要认证的音频源（如 Bilibili）
  /// [track] 可选的 Track 信息，用于后台播放通知显示
  Future<Duration?> playUrl(String url, {Map<String, String>? headers, Track? track}) async {
    logDebug('Playing URL: ${url.substring(0, url.length > 80 ? 80 : url.length)}...');
    if (headers != null) {
      logDebug('With headers: ${headers.keys.join(", ")}');
    }
    try {
      // 先停止当前播放
      await _player.stop();

      // 设置新的 URL（带 headers 和 MediaItem）
      final audioSource = _createAudioSource(url, headers: headers, track: track);
      final duration = await _player.setAudioSource(audioSource);
      logDebug('URL loaded successfully, duration: $duration');

      // 确保播放并等待状态确认
      await _ensurePlayback();

      logDebug('Playback started, duration: $duration, playing: ${_player.playing}');
      return duration;
    } on PlayerException catch (e) {
      logError('PlayerException playing URL: code=${e.code}, message=${e.message}');
      rethrow;
    } on PlayerInterruptedException catch (e) {
      logWarning('Playback interrupted (likely due to new track request): ${e.message}');
      rethrow;
    } catch (e, stack) {
      logError('Failed to play URL', e, stack);
      rethrow;
    }
  }

  /// 设置 URL（不自动播放）
  /// [headers] 可选的 HTTP 请求头
  /// [track] 可选的 Track 信息，用于后台播放通知显示
  Future<Duration?> setUrl(String url, {Map<String, String>? headers, Track? track}) async {
    logDebug('Setting URL: ${url.substring(0, url.length > 50 ? 50 : url.length)}...');
    try {
      final audioSource = _createAudioSource(url, headers: headers, track: track);
      final duration = await _player.setAudioSource(audioSource);
      logDebug('URL set, duration: $duration');
      return duration;
    } catch (e, stack) {
      logError('Failed to set URL', e, stack);
      rethrow;
    }
  }

  /// 播放本地文件
  /// [track] 可选的 Track 信息，用于后台播放通知显示
  Future<Duration?> playFile(String filePath, {Track? track}) async {
    logDebug('Playing file: $filePath');
    try {
      // 先停止当前播放
      await _player.stop();

      // 设置新的文件（带 MediaItem）
      final audioSource = _createFileAudioSource(filePath, track: track);
      final duration = await _player.setAudioSource(audioSource);

      // 确保播放并等待状态确认
      await _ensurePlayback();

      logDebug('File playback started, duration: $duration, playing: ${_player.playing}');
      return duration;
    } catch (e, stack) {
      logError('Failed to play file', e, stack);
      rethrow;
    }
  }

  /// 创建带有 MediaItem 元数据的本地文件 AudioSource
  AudioSource _createFileAudioSource(String filePath, {Track? track}) {
    final mediaItem = track != null
        ? MediaItem(
            id: track.uniqueKey,
            title: track.title,
            artist: track.artist ?? '未知艺术家',
            artUri: track.thumbnailUrl != null ? Uri.parse(track.thumbnailUrl!) : null,
            duration: track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null,
          )
        : null;

    return AudioSource.file(
      filePath,
      tag: mediaItem,
    );
  }

  /// 设置文件（不自动播放）
  /// [track] 可选的 Track 信息，用于后台播放通知显示
  Future<Duration?> setFile(String filePath, {Track? track}) async {
    logDebug('Setting file: $filePath');
    try {
      final audioSource = _createFileAudioSource(filePath, track: track);
      final duration = await _player.setAudioSource(audioSource);
      logDebug('File set, duration: $duration');
      return duration;
    } catch (e, stack) {
      logError('Failed to set file', e, stack);
      rethrow;
    }
  }
}
