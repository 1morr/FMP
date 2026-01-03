import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../../core/logger.dart';

/// 音频播放服务（单曲模式）
/// 只负责播放单首歌曲，队列逻辑由 QueueManager 管理
class AudioService with Logging {
  final AudioPlayer _player = AudioPlayer();

  // 完成事件控制器
  final _completedController = StreamController<void>.broadcast();

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
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
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

    // 监听播放状态，检测歌曲完成
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        logDebug('Track completed');
        _completedController.add(null);
      }
    });

    logInfo('AudioService initialized');
  }

  /// 释放资源
  Future<void> dispose() async {
    await _completedController.close();
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

  /// 播放指定 URL
  Future<Duration?> playUrl(String url) async {
    logDebug('Playing URL: ${url.substring(0, url.length > 50 ? 50 : url.length)}...');
    try {
      // 先停止当前播放
      await _player.stop();

      // 设置新的 URL
      final duration = await _player.setUrl(url);

      // 确保播放
      await _player.play();

      // 再次确认播放状态
      if (!_player.playing) {
        logWarning('Player not playing after play() call, retrying...');
        await _player.play();
      }

      logDebug('Playback started, duration: $duration, playing: ${_player.playing}');
      return duration;
    } catch (e, stack) {
      logError('Failed to play URL', e, stack);
      rethrow;
    }
  }

  /// 设置 URL（不自动播放）
  Future<Duration?> setUrl(String url) async {
    logDebug('Setting URL: ${url.substring(0, url.length > 50 ? 50 : url.length)}...');
    try {
      final duration = await _player.setUrl(url);
      logDebug('URL set, duration: $duration');
      return duration;
    } catch (e, stack) {
      logError('Failed to set URL', e, stack);
      rethrow;
    }
  }

  /// 播放本地文件
  Future<Duration?> playFile(String filePath) async {
    logDebug('Playing file: $filePath');
    try {
      // 先停止当前播放
      await _player.stop();

      // 设置新的文件
      final duration = await _player.setFilePath(filePath);

      // 确保播放
      await _player.play();

      // 再次确认播放状态
      if (!_player.playing) {
        logWarning('Player not playing after play() call, retrying...');
        await _player.play();
      }

      logDebug('File playback started, duration: $duration, playing: ${_player.playing}');
      return duration;
    } catch (e, stack) {
      logError('Failed to play file', e, stack);
      rethrow;
    }
  }

  /// 设置文件（不自动播放）
  Future<Duration?> setFile(String filePath) async {
    logDebug('Setting file: $filePath');
    try {
      final duration = await _player.setFilePath(filePath);
      logDebug('File set, duration: $duration');
      return duration;
    } catch (e, stack) {
      logError('Failed to set file', e, stack);
      rethrow;
    }
  }
}
