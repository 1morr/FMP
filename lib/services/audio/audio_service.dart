import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';

/// 播放状态数据类
class PlaybackState {
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final Duration position;
  final Duration? duration;
  final Duration bufferedPosition;
  final double speed;
  final PlayMode playMode;
  final int? currentIndex;
  final Track? currentTrack;

  const PlaybackState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.position = Duration.zero,
    this.duration,
    this.bufferedPosition = Duration.zero,
    this.speed = 1.0,
    this.playMode = PlayMode.sequential,
    this.currentIndex,
    this.currentTrack,
  });

  PlaybackState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? speed,
    PlayMode? playMode,
    int? currentIndex,
    Track? currentTrack,
  }) {
    return PlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      speed: speed ?? this.speed,
      playMode: playMode ?? this.playMode,
      currentIndex: currentIndex ?? this.currentIndex,
      currentTrack: currentTrack ?? this.currentTrack,
    );
  }
}

/// 音频播放服务
/// 负责管理音频播放器的核心功能
class AudioService {
  final AudioPlayer _player = AudioPlayer();

  PlayMode _playMode = PlayMode.sequential;

  // 状态流
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<double> get speedStream => _player.speedStream;
  Stream<SequenceState?> get sequenceStateStream => _player.sequenceStateStream;

  // 当前状态
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  Duration get bufferedPosition => _player.bufferedPosition;
  double get speed => _player.speed;
  double get volume => _player.volume;
  int? get currentIndex => _player.currentIndex;
  PlayMode get playMode => _playMode;

  AudioPlayer get player => _player;

  /// 初始化音频服务
  Future<void> initialize() async {
    // 配置音频会话
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // 监听音频会话中断
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            // 降低音量
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
            // 恢复音量
            _player.setVolume(1.0);
            break;
          case AudioInterruptionType.pause:
            _player.play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // 监听音频设备变化（如耳机拔出）
    session.becomingNoisyEventStream.listen((_) {
      _player.pause();
    });
  }

  /// 释放资源
  Future<void> dispose() async {
    await _player.dispose();
  }

  // ========== 播放控制 ==========

  /// 播放
  Future<void> play() => _player.play();

  /// 暂停
  Future<void> pause() => _player.pause();

  /// 停止
  Future<void> stop() => _player.stop();

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

  /// 跳转到指定歌曲
  Future<void> seekToIndex(int index, [Duration position = Duration.zero]) =>
      _player.seek(position, index: index);

  /// 下一首
  Future<void> seekToNext() => _player.seekToNext();

  /// 上一首
  Future<void> seekToPrevious() => _player.seekToPrevious();

  /// 快进
  Future<void> seekForward([Duration duration = const Duration(seconds: 10)]) async {
    final newPosition = _player.position + duration;
    final maxPosition = _player.duration ?? Duration.zero;
    await _player.seek(newPosition > maxPosition ? maxPosition : newPosition);
  }

  /// 快退
  Future<void> seekBackward([Duration duration = const Duration(seconds: 10)]) async {
    final newPosition = _player.position - duration;
    await _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  // ========== 播放速度 ==========

  /// 设置播放速度 (0.5 - 2.0)
  Future<void> setSpeed(double speed) => _player.setSpeed(speed.clamp(0.5, 2.0));

  /// 重置播放速度
  Future<void> resetSpeed() => _player.setSpeed(1.0);

  // ========== 播放模式 ==========

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    _playMode = mode;
    switch (mode) {
      case PlayMode.sequential:
        await _player.setLoopMode(LoopMode.off);
        await _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.loop:
        await _player.setLoopMode(LoopMode.all);
        await _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.loopOne:
        await _player.setLoopMode(LoopMode.one);
        await _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.shuffle:
        await _player.setLoopMode(LoopMode.all);
        await _player.setShuffleModeEnabled(true);
        break;
    }
  }

  /// 切换到下一个播放模式
  Future<void> cyclePlayMode() async {
    final modes = PlayMode.values;
    final currentIndex = modes.indexOf(_playMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    await setPlayMode(modes[nextIndex]);
  }

  // ========== 音量控制 ==========

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  /// 静音切换
  Future<void> toggleMute() async {
    if (_player.volume > 0) {
      await _player.setVolume(0);
    } else {
      await _player.setVolume(1.0);
    }
  }

  // ========== 音频源设置 ==========

  /// 设置音频源
  Future<Duration?> setAudioSource(AudioSource source) async {
    return await _player.setAudioSource(source);
  }

  /// 设置单个URL
  Future<Duration?> setUrl(String url) async {
    return await _player.setUrl(url);
  }
}
