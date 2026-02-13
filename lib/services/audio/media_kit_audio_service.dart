import 'dart:async';

import 'package:audio_session/audio_session.dart' hide AudioDevice;
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:rxdart/rxdart.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import 'audio_types.dart';

/// 音频播放服务（使用 media_kit 直接实现）
/// 替代原来的 just_audio + just_audio_media_kit 方案
/// 解决了 just_audio_media_kit 代理对 audio-only 流的兼容性问题
class MediaKitAudioService with Logging {
  late final Player _player;
  late final AudioSession _session;

  // 完成事件控制器
  final _completedController = StreamController<void>.broadcast();

  // 流订阅列表（用于 dispose 时取消）
  final List<StreamSubscription> _subscriptions = [];

  // duck 前的音量（用于恢复）
  double _volumeBeforeDuck = 1.0;

  // 中断前是否正在播放（用于判断中断结束后是否恢复播放）
  bool _wasPlayingBeforeInterruption = false;

  // 是否已触发过 completion 事件（防止重复触发）
  bool _hasCompletionFired = false;

  // 缓存的状态（用于合成 PlayerState）
  bool _isBuffering = false;
  bool _isCompleted = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _volume = 1.0; // 存储为 0-1 范围
  double _speed = 1.0;

  // 状态流控制器
  final _playerStateController = BehaviorSubject<MediaKitPlayerState>.seeded(
    const MediaKitPlayerState(
      playing: false,
      processingState: FmpAudioProcessingState.idle,
    ),
  );

  final _processingStateController = BehaviorSubject<FmpAudioProcessingState>.seeded(
    FmpAudioProcessingState.idle,
  );

  final _positionController = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _durationController = BehaviorSubject<Duration?>.seeded(null);
  final _bufferedPositionController = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _speedController = BehaviorSubject<double>.seeded(1.0);
  final _playingController = BehaviorSubject<bool>.seeded(false);
  final _volumeController = BehaviorSubject<double>.seeded(1.0);

  // 音频设备相关
  final _audioDevicesController = BehaviorSubject<List<AudioDevice>>.seeded([]);
  final _audioDeviceController = BehaviorSubject<AudioDevice?>.seeded(null);

  // ========== 状态流 ==========
  Stream<MediaKitPlayerState> get playerStateStream => _playerStateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<Duration> get bufferedPositionStream => _bufferedPositionController.stream;
  Stream<double> get speedStream => _speedController.stream;
  Stream<FmpAudioProcessingState> get processingStateStream => _processingStateController.stream;
  Stream<bool> get playingStream => _playingController.stream;

  /// 歌曲播放完成事件流
  Stream<void> get completedStream => _completedController.stream;

  /// 可用音频设备列表流
  Stream<List<AudioDevice>> get audioDevicesStream => _audioDevicesController.stream;

  /// 当前音频设备流
  Stream<AudioDevice?> get audioDeviceStream => _audioDeviceController.stream;

  // ========== 当前状态 ==========
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration? get duration => _duration;
  Duration get bufferedPosition => _bufferedPositionController.value;
  double get speed => _speed;
  double get volume => _volume;
  FmpAudioProcessingState get processingState => _processingStateController.value;

  /// 可用音频设备列表
  List<AudioDevice> get audioDevices => _audioDevicesController.value;

  /// 当前音频设备
  AudioDevice? get audioDevice => _audioDeviceController.value;

  /// 初始化音频服务
  Future<void> initialize() async {
    logInfo('Initializing MediaKitAudioService...');

    // 创建 media_kit 播放器
    // 优化内存：将 demuxer 缓存从默认的 32 MB 降低到 8 MB
    // 对于纯音频播放，8 MB 缓冲足够（约 4-5 分钟的 256kbps 音频）
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 8 * 1024 * 1024, // 8 MB（默认 32 MB）
      ),
    );

    // 配置音频会话
    _session = await AudioSession.instance;
    await _session.configure(const AudioSessionConfiguration.music());

    // 监听音频会话中断
    _subscriptions.add(
      _session.interruptionEventStream.listen((event) {
        if (event.begin) {
          // 中断开始
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 记住 duck 前的音量，以便正确恢复
              _volumeBeforeDuck = _volume;
              setVolume(_volume * 0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              // 记住中断前是否正在播放，只有正在播放时才在中断结束后恢复
              _wasPlayingBeforeInterruption = _isPlaying;
              if (_wasPlayingBeforeInterruption) {
                logDebug('Audio interrupted while playing, will resume after interruption ends');
                pause();
              }
              break;
          }
        } else {
          // 中断结束
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 恢复到 duck 前的音量
              setVolume(_volumeBeforeDuck);
              break;
            case AudioInterruptionType.pause:
              // 只有中断前正在播放时才恢复播放
              if (_wasPlayingBeforeInterruption) {
                logDebug('Interruption ended, resuming playback');
                play();
              } else {
                logDebug('Interruption ended, but was not playing before, staying paused');
              }
              _wasPlayingBeforeInterruption = false;
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      }),
    );

    // 监听音频设备变化（如耳机拔出）
    _subscriptions.add(
      _session.becomingNoisyEventStream.listen((_) {
        pause();
      }),
    );

    // 设置 media_kit 流监听
    _setupMediaKitListeners();

    logInfo('MediaKitAudioService initialized');
  }

  /// 设置 media_kit 播放器的流监听
  void _setupMediaKitListeners() {
    // 监听播放状态
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        _isPlaying = playing;
        _playingController.add(playing);
        _updatePlayerState();
      }),
    );

    // 监听位置
    _subscriptions.add(
      _player.stream.position.listen((pos) {
        _position = pos;
        _positionController.add(pos);
      }),
    );

    // 监听时长
    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        _duration = dur;
        _durationController.add(dur);
      }),
    );

    // 监听缓冲
    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        _isBuffering = buffering;
        _updatePlayerState();
      }),
    );

    // 监听完成
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        _isCompleted = completed;
        if (completed && !_hasCompletionFired) {
          _hasCompletionFired = true;
          logDebug('Track completed');
          _completedController.add(null);
        } else if (!completed) {
          _hasCompletionFired = false;
        }
        _updatePlayerState();
      }),
    );

    // 监听缓冲位置
    _subscriptions.add(
      _player.stream.buffer.listen((buffer) {
        _bufferedPositionController.add(buffer);
      }),
    );

    // 监听速度
    _subscriptions.add(
      _player.stream.rate.listen((rate) {
        _speed = rate;
        _speedController.add(rate);
      }),
    );

    // 监听音量
    _subscriptions.add(
      _player.stream.volume.listen((vol) {
        // media_kit 音量范围是 0-100，转换为 0-1
        _volume = vol / 100.0;
        _volumeController.add(_volume);
      }),
    );

    // 监听错误
    _subscriptions.add(
      _player.stream.error.listen((error) {
        logError('media_kit error: $error');
      }),
    );

    // 监听可用音频设备列表变化
    _subscriptions.add(
      _player.stream.audioDevices.listen((devices) {
        logDebug('Audio devices changed: ${devices.length} devices');
        _audioDevicesController.add(devices);
      }),
    );

    // 监听当前音频设备变化
    _subscriptions.add(
      _player.stream.audioDevice.listen((device) {
        logDebug('Audio device changed: ${device.name}');
        _audioDeviceController.add(device);
      }),
    );

    // 初始化时获取当前设备列表（stream 只在变化时触发）
    final initialDevices = _player.state.audioDevices;
    logDebug('Initial audio devices: ${initialDevices.length} devices');
    _audioDevicesController.add(initialDevices);

    final initialDevice = _player.state.audioDevice;
    logDebug('Initial audio device: ${initialDevice.name}');
    _audioDeviceController.add(initialDevice);
  }

  /// 更新合成的播放器状态
  void _updatePlayerState() {
    final state = _synthesizeProcessingState();
    _processingStateController.add(state);
    _playerStateController.add(MediaKitPlayerState(
      playing: _isPlaying,
      processingState: state,
    ));
  }

  /// 合成处理状态
  FmpAudioProcessingState _synthesizeProcessingState() {
    if (_isCompleted) {
      return FmpAudioProcessingState.completed;
    }
    // 如果正在播放，即使在缓冲也视为 ready（音频实际在播放）
    if (_isPlaying) {
      return FmpAudioProcessingState.ready;
    }
    if (_isBuffering) {
      return FmpAudioProcessingState.buffering;
    }
    if (_duration != null && _duration!.inMilliseconds > 0) {
      return FmpAudioProcessingState.ready;
    }
    return FmpAudioProcessingState.idle;
  }

  /// 释放资源
  Future<void> dispose() async {
    // 取消所有流订阅
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    await _completedController.close();
    await _playerStateController.close();
    await _processingStateController.close();
    await _positionController.close();
    await _durationController.close();
    await _bufferedPositionController.close();
    await _speedController.close();
    await _playingController.close();
    await _volumeController.close();
    await _audioDevicesController.close();
    await _audioDeviceController.close();

    await _player.dispose();
  }

  // ========== 播放控制 ==========

  /// 播放
  Future<void> play() async {
    await _player.play();
  }

  /// 暂停
  Future<void> pause() async {
    _cancelEnsurePlayback();
    await _player.pause();
  }

  /// 停止
  Future<void> stop() async {
    _cancelEnsurePlayback();
    await _player.stop();
    // 释放音频焦点
    await _session.setActive(false);
    // 重置状态，确保 _synthesizeProcessingState 返回 idle
    _isCompleted = false;
    _isBuffering = false;
    _isPlaying = false;
    _hasCompletionFired = false;
    _duration = null;
    _position = Duration.zero;
    _durationController.add(null);
    _positionController.add(Duration.zero);
    _updatePlayerState();
  }

  /// 切换播放/暂停
  Future<void> togglePlayPause() async {
    await _player.playOrPause();
  }

  // ========== 进度控制 ==========

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    // 重置 completion 标志，允许再次触发 completion 事件
    _hasCompletionFired = false;
    _isCompleted = false;
    await _player.seek(position);
  }

  /// 快进
  Future<void> seekForward([Duration? duration]) async {
    final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
    final newPosition = _position + seekDuration;
    final maxPosition = _duration ?? Duration.zero;
    await _player.seek(newPosition > maxPosition ? maxPosition : newPosition);
  }

  /// 快退
  Future<void> seekBackward([Duration? duration]) async {
    final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
    final newPosition = _position - seekDuration;
    await _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  /// 嘗試跳到直播流的最新位置
  /// 返回 true 表示成功 seek，false 表示無法 seek（需要重新連接）
  Future<bool> seekToLive() async {
    // 獲取當前 duration
    final currentDuration = _duration ?? Duration.zero;
    
    // 如果 duration 為 0 或太短，無法 seek
    if (currentDuration.inSeconds < 5) {
      logDebug('seekToLive: duration too short (${currentDuration.inSeconds}s), cannot seek');
      return false;
    }
    
    // 嘗試 seek 到接近末尾（留 1 秒緩衝）
    final targetPosition = currentDuration - const Duration(seconds: 1);
    logDebug('seekToLive: seeking to $targetPosition (duration: $currentDuration)');
    
    await _player.seek(targetPosition);
    return true;
  }

  // ========== 播放速度 ==========

  /// 设置播放速度 (0.5 - 2.0)
  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed.clamp(0.5, 2.0));
  }

  /// 重置播放速度
  Future<void> resetSpeed() async {
    await _player.setRate(1.0);
  }

  // ========== 音量控制 ==========

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    // 转换为 media_kit 的 0-100 范围
    await _player.setVolume((volume.clamp(0.0, 1.0) * 100).toDouble());
  }

  // ========== 音频设备控制 ==========

  /// 设置音频输出设备
  Future<void> setAudioDevice(AudioDevice device) async {
    logInfo('Setting audio device: ${device.name} (${device.description})');
    await _player.setAudioDevice(device);
  }

  /// 设置为自动选择音频设备（跟随系统默认）
  Future<void> setAudioDeviceAuto() async {
    logInfo('Setting audio device to auto');
    await _player.setAudioDevice(AudioDevice.auto());
  }

  // ========== 音频源设置 ==========

  // 用于取消 _ensurePlayback 的重试逻辑
  bool _playbackCancelled = false;

  /// 取消正在进行的 _ensurePlayback 重试
  void _cancelEnsurePlayback() {
    _playbackCancelled = true;
  }

  /// 确保播放开始
  Future<void> _ensurePlayback() async {
    _playbackCancelled = false;

    logDebug('_ensurePlayback called, current state: ${_synthesizeProcessingState()}');

    // 等待播放器准备好或检测失败
    // media_kit 通常在 open() 返回后就准备好了
    // 但我们仍然等待一小段时间确保状态稳定
    int attempts = 0;
    const maxAttempts = 50; // 5 seconds total

    while (attempts < maxAttempts) {
      if (_playbackCancelled) {
        logDebug('Playback cancelled, not calling play()');
        return;
      }

      final state = _synthesizeProcessingState();
      if (state == FmpAudioProcessingState.ready) {
        break;
      }
      if (state == FmpAudioProcessingState.idle && attempts > 5) {
        // 如果在尝试5次后仍然是 idle，可能加载失败
        logError('Stream failed to open: player in idle state after open()');
        throw Exception('Stream failed to open');
      }

      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    if (_playbackCancelled) {
      logDebug('Playback cancelled, not calling play()');
      return;
    }

    // 开始播放（如果还没有在播放）
    if (!_isPlaying) {
      await _player.play();
    }
    logDebug('_ensurePlayback completed, playing: $_isPlaying');
  }

  /// 播放指定 URL
  /// [headers] 可选的 HTTP 请求头，用于需要认证的音频源（如 Bilibili, YouTube）
  /// [track] 可选的 Track 信息，用于后台播放通知显示
  Future<Duration?> playUrl(String url, {Map<String, String>? headers, Track? track}) async {
    logDebug('Playing URL: ${url.substring(0, url.length > 80 ? 80 : url.length)}...');
    if (headers != null) {
      logDebug('With headers: ${headers.keys.join(", ")}');
    }
    try {
      // 先停止当前播放
      _hasCompletionFired = false;
      _isCompleted = false;
      await _player.stop();

      // 等待播放器进入 idle 状态
      await _waitForIdle();

      // 设置加载状态
      _processingStateController.add(FmpAudioProcessingState.loading);
      _playerStateController.add(MediaKitPlayerState(
        playing: false,
        processingState: FmpAudioProcessingState.loading,
      ));

      // 激活音频会话（请求音频焦点）
      await _session.setActive(true);

      // 使用 media_kit 直接打开 URL，原生支持 httpHeaders（不需要代理）
      final media = Media(url, httpHeaders: headers);
      await _player.open(media, play: false);

      // 短暂等待时长信息（流媒体可能需要播放后才能获取）
      Duration? resultDuration;
      for (int i = 0; i < 10; i++) {
        if (_duration != null && _duration!.inMilliseconds > 0) {
          resultDuration = _duration;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      logDebug('URL loaded successfully, duration: $resultDuration (may update later)');

      // 确保播放并等待状态确认
      await _ensurePlayback();

      logDebug('Playback started, duration: $resultDuration, playing: $_isPlaying');
      return resultDuration;
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
      // 设置加载状态
      _processingStateController.add(FmpAudioProcessingState.loading);

      // 激活音频会话（请求音频焦点）
      await _session.setActive(true);

      final media = Media(url, httpHeaders: headers);
      await _player.open(media, play: false);

      // 短暂等待时长信息
      Duration? resultDuration;
      for (int i = 0; i < 10; i++) {
        if (_duration != null && _duration!.inMilliseconds > 0) {
          resultDuration = _duration;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      logDebug('URL set, duration: $resultDuration');
      return resultDuration;
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
      _hasCompletionFired = false;
      _isCompleted = false;
      await _player.stop();

      // 等待播放器进入 idle 状态
      await _waitForIdle();

      // 设置加载状态
      _processingStateController.add(FmpAudioProcessingState.loading);
      _playerStateController.add(MediaKitPlayerState(
        playing: false,
        processingState: FmpAudioProcessingState.loading,
      ));

      // 激活音频会话（请求音频焦点）
      await _session.setActive(true);

      // 使用 media_kit 打开本地文件
      final media = Media(filePath);
      await _player.open(media, play: false);

      // 短暂等待时长信息
      Duration? resultDuration;
      for (int i = 0; i < 10; i++) {
        if (_duration != null && _duration!.inMilliseconds > 0) {
          resultDuration = _duration;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 确保播放并等待状态确认
      await _ensurePlayback();

      logDebug('File playback started, duration: $resultDuration, playing: $_isPlaying');
      return resultDuration;
    } catch (e, stack) {
      logError('Failed to play file', e, stack);
      rethrow;
    }
  }

  /// 设置文件（不自动播放）
  /// [track] 可选的 Track 信息，用于后台播放通知显示
  Future<Duration?> setFile(String filePath, {Track? track}) async {
    logDebug('Setting file: $filePath');
    try {
      // 设置加载状态
      _processingStateController.add(FmpAudioProcessingState.loading);

      // 激活音频会话（请求音频焦点）
      await _session.setActive(true);

      final media = Media(filePath);
      await _player.open(media, play: false);

      // 短暂等待时长信息
      Duration? resultDuration;
      for (int i = 0; i < 10; i++) {
        if (_duration != null && _duration!.inMilliseconds > 0) {
          resultDuration = _duration;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      logDebug('File set, duration: $resultDuration');
      return resultDuration;
    } catch (e, stack) {
      logError('Failed to set file', e, stack);
      rethrow;
    }
  }

  /// 等待播放器进入 idle 状态
  Future<void> _waitForIdle() async {
    final currentState = _synthesizeProcessingState();
    if (currentState == FmpAudioProcessingState.idle) {
      return;
    }

    logDebug('Waiting for player to be idle, current state: $currentState');
    int attempts = 0;
    const maxAttempts = 10;

    while (attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (_synthesizeProcessingState() == FmpAudioProcessingState.idle) {
        logDebug('Player is now idle');
        return;
      }
      attempts++;
    }

    logWarning('Timeout waiting for idle state, proceeding anyway');
  }
}
