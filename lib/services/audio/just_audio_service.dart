import 'dart:async';

import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import 'audio_service.dart';
import 'audio_types.dart';

/// Android 音频播放服务（使用 just_audio / ExoPlayer）
/// 比 media_kit 更轻量，节省 ~10-15MB 内存
class JustAudioService extends FmpAudioService with Logging {
  late final ja.AudioPlayer _player;
  late final AudioSession _session;

  // 完成事件控制器
  final _completedController = StreamController<void>.broadcast();

  // 流订阅列表
  final List<StreamSubscription> _subscriptions = [];

  // duck 前的音量
  double _volumeBeforeDuck = 1.0;

  // 中断前是否正在播放
  bool _wasPlayingBeforeInterruption = false;

  // 是否已触发过 completion 事件（防止重复触发）
  bool _hasCompletionFired = false;

  // 缓存的状态
  double _volume = 1.0;
  double _speed = 1.0;

  // 状态流控制器
  final _playerStateController = BehaviorSubject<FmpPlayerState>.seeded(
    const FmpPlayerState(
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

  // 音频设备（Android 不支持设备切换）
  final _audioDevicesController = BehaviorSubject<List<FmpAudioDevice>>.seeded([]);
  final _audioDeviceController = BehaviorSubject<FmpAudioDevice?>.seeded(null);

  // ========== 状态流 ==========
  @override
  Stream<FmpPlayerState> get playerStateStream => _playerStateController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration?> get durationStream => _durationController.stream;
  @override
  Stream<Duration> get bufferedPositionStream => _bufferedPositionController.stream;
  @override
  Stream<double> get speedStream => _speedController.stream;
  @override
  Stream<FmpAudioProcessingState> get processingStateStream => _processingStateController.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<void> get completedStream => _completedController.stream;
  @override
  Stream<List<FmpAudioDevice>> get audioDevicesStream => _audioDevicesController.stream;
  @override
  Stream<FmpAudioDevice?> get audioDeviceStream => _audioDeviceController.stream;

  // ========== 当前状态 ==========
  @override
  bool get isPlaying => _player.playing;
  @override
  Duration get position => _player.position;
  @override
  Duration? get duration => _player.duration;
  @override
  Duration get bufferedPosition => _player.bufferedPosition;
  @override
  double get speed => _speed;
  @override
  double get volume => _volume;
  @override
  FmpAudioProcessingState get processingState => _processingStateController.value;
  @override
  List<FmpAudioDevice> get audioDevices => [];
  @override
  FmpAudioDevice? get audioDevice => null;

  /// 将 just_audio ProcessingState 映射为 FmpAudioProcessingState
  FmpAudioProcessingState _mapProcessingState(ja.ProcessingState state) {
    switch (state) {
      case ja.ProcessingState.idle:
        return FmpAudioProcessingState.idle;
      case ja.ProcessingState.loading:
        return FmpAudioProcessingState.loading;
      case ja.ProcessingState.buffering:
        return FmpAudioProcessingState.buffering;
      case ja.ProcessingState.ready:
        return FmpAudioProcessingState.ready;
      case ja.ProcessingState.completed:
        return FmpAudioProcessingState.completed;
    }
  }

  @override
  Future<void> initialize() async {
    logInfo('Initializing JustAudioService...');

    _player = ja.AudioPlayer();

    // 配置音频会话（just_audio 自动管理 audio_session，但我们仍需监听中断）
    _session = await AudioSession.instance;
    await _session.configure(const AudioSessionConfiguration.music());

    // 监听音频会话中断
    _subscriptions.add(
      _session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _volumeBeforeDuck = _volume;
              setVolume(_volume * 0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              _wasPlayingBeforeInterruption = _player.playing;
              if (_wasPlayingBeforeInterruption) {
                logDebug('Audio interrupted while playing, will resume after interruption ends');
                pause();
              }
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              setVolume(_volumeBeforeDuck);
              break;
            case AudioInterruptionType.pause:
              if (_wasPlayingBeforeInterruption) {
                logDebug('Interruption ended, resuming playback');
                play();
              }
              _wasPlayingBeforeInterruption = false;
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      }),
    );

    // 监听耳机拔出
    _subscriptions.add(
      _session.becomingNoisyEventStream.listen((_) {
        pause();
      }),
    );

    // 设置 just_audio 流监听
    _setupListeners();

    logInfo('JustAudioService initialized');
  }

  /// 设置 just_audio 播放器的流监听
  void _setupListeners() {
    // 监听播放器状态（合成 playing + processingState）
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        final playing = state.playing;
        final processingState = _mapProcessingState(state.processingState);

        _playingController.add(playing);
        _processingStateController.add(processingState);
        _playerStateController.add(FmpPlayerState(
          playing: playing,
          processingState: processingState,
        ));

        // 处理完成事件
        if (state.processingState == ja.ProcessingState.completed &&
            !_hasCompletionFired) {
          _hasCompletionFired = true;
          logDebug('Track completed');
          _completedController.add(null);
        } else if (state.processingState != ja.ProcessingState.completed) {
          _hasCompletionFired = false;
        }
      }),
    );

    // 监听位置
    _subscriptions.add(
      _player.positionStream.listen((pos) {
        _positionController.add(pos);
      }),
    );

    // 监听时长
    _subscriptions.add(
      _player.durationStream.listen((dur) {
        _durationController.add(dur);
      }),
    );

    // 监听缓冲位置
    _subscriptions.add(
      _player.bufferedPositionStream.listen((pos) {
        _bufferedPositionController.add(pos);
      }),
    );

    // 监听速度
    _subscriptions.add(
      _player.speedStream.listen((rate) {
        _speed = rate;
        _speedController.add(rate);
      }),
    );
  }

  @override
  Future<void> dispose() async {
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
    await _audioDevicesController.close();
    await _audioDeviceController.close();

    await _player.dispose();
  }

  // ========== 播放控制 ==========

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    // 释放音频焦点
    await _session.setActive(false);
    _hasCompletionFired = false;
  }

  @override
  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  // ========== 进度控制 ==========

  @override
  Future<void> seekTo(Duration position) async {
    _hasCompletionFired = false;
    await _player.seek(position);
  }

  @override
  Future<void> seekForward([Duration? duration]) async {
    final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
    final newPosition = _player.position + seekDuration;
    final maxPosition = _player.duration ?? Duration.zero;
    await _player.seek(newPosition > maxPosition ? maxPosition : newPosition);
  }

  @override
  Future<void> seekBackward([Duration? duration]) async {
    final seekDuration = duration ?? const Duration(seconds: AppConstants.seekDurationSeconds);
    final newPosition = _player.position - seekDuration;
    await _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  @override
  Future<bool> seekToLive() async {
    // 策略 1：用 duration（有些流会提供）
    final currentDuration = _player.duration;
    if (currentDuration != null && currentDuration.inSeconds >= 5) {
      final targetPosition = currentDuration - const Duration(seconds: 1);
      logInfo('seekToLive: seeking to $targetPosition (duration: $currentDuration)');
      await _player.seek(targetPosition);
      return true;
    }

    // 策略 2：用 bufferedPosition（直播流通常 duration 为 null，但 bufferedPosition 可用）
    final buffered = _player.bufferedPosition;
    if (buffered.inSeconds >= 5) {
      final targetPosition = buffered - const Duration(seconds: 1);
      logInfo('seekToLive: seeking to buffered edge $targetPosition (buffered: $buffered)');
      await _player.seek(targetPosition);
      return true;
    }

    logInfo('seekToLive: no seekable range (duration: $currentDuration, buffered: $buffered)');
    return false;
  }

  // ========== 播放速度 ==========

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.5, 2.0));
  }

  @override
  Future<void> resetSpeed() async {
    await _player.setSpeed(1.0);
  }

  // ========== 音量控制 ==========

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
  }

  // ========== 音频设备控制（Android 不支持） ==========

  @override
  Future<void> setAudioDevice(FmpAudioDevice device) async {
    // Android 不支持音频设备切换
  }

  @override
  Future<void> setAudioDeviceAuto() async {
    // Android 不支持音频设备切换
  }

  // ========== 音频源设置 ==========

  /// 等待播放器进入 idle 状态
  Future<void> _waitForIdle() async {
    if (_player.processingState == ja.ProcessingState.idle) return;

    logDebug('Waiting for player to be idle, current state: ${_player.processingState}');
    try {
      await _player.playerStateStream
          .where((s) => s.processingState == ja.ProcessingState.idle)
          .first
          .timeout(const Duration(milliseconds: 500));
      logDebug('Player is now idle');
    } catch (_) {
      logWarning('Timeout waiting for idle state, proceeding anyway');
    }
  }



  @override
  Future<Duration?> playUrl(String url, {Map<String, String>? headers, Track? track}) async {
    logDebug('Playing URL: ${url.substring(0, url.length > 80 ? 80 : url.length)}...');
    if (headers != null) {
      logDebug('With headers: ${headers.keys.join(", ")}');
    }
    try {
      _hasCompletionFired = false;
      await _player.stop();
      await _waitForIdle();

      // 设置加载状态
      _processingStateController.add(FmpAudioProcessingState.loading);
      _playerStateController.add(const FmpPlayerState(
        playing: false,
        processingState: FmpAudioProcessingState.loading,
      ));

      // 激活音频会话
      await _session.setActive(true);

      // 使用 just_audio 的 AudioSource.uri（支持 headers）
      final source = ja.AudioSource.uri(
        Uri.parse(url),
        headers: headers,
      );
      final duration = await _player.setAudioSource(source);

      logDebug('URL loaded successfully, duration: $duration');

      // 使用 unawaited play() — just_audio 的 play() 会等待平台播放请求完成才返回，
      // 这可能阻塞数秒（特别是首次播放）。不 await 让 playUrl() 尽快返回，
      // 使 AudioController._exitLoadingState() 及时被调用，避免 UI 卡在加载状态。
      // play() 内部会立即通过 _playingSubject.add(true) 广播播放状态。
      unawaited(_player.play());

      logDebug('Play requested, duration: $duration');
      return duration;
    } catch (e, stack) {
      logError('Failed to play URL', e, stack);
      rethrow;
    }
  }

  @override
  Future<Duration?> setUrl(String url, {Map<String, String>? headers, Track? track}) async {
    logDebug('Setting URL: ${url.substring(0, url.length > 50 ? 50 : url.length)}...');
    try {
      _processingStateController.add(FmpAudioProcessingState.loading);
      await _session.setActive(true);

      final source = ja.AudioSource.uri(
        Uri.parse(url),
        headers: headers,
      );
      final duration = await _player.setAudioSource(source);

      logDebug('URL set, duration: $duration');
      return duration;
    } catch (e, stack) {
      logError('Failed to set URL', e, stack);
      rethrow;
    }
  }

  @override
  Future<Duration?> playFile(String filePath, {Track? track}) async {
    logDebug('Playing file: $filePath');
    try {
      _hasCompletionFired = false;
      await _player.stop();
      await _waitForIdle();

      _processingStateController.add(FmpAudioProcessingState.loading);
      _playerStateController.add(const FmpPlayerState(
        playing: false,
        processingState: FmpAudioProcessingState.loading,
      ));

      await _session.setActive(true);

      final source = ja.AudioSource.file(filePath);
      final duration = await _player.setAudioSource(source);

      // 与 playUrl() 同理，不 await play()
      unawaited(_player.play());

      logDebug('File play requested, duration: $duration');
      return duration;
    } catch (e, stack) {
      logError('Failed to play file', e, stack);
      rethrow;
    }
  }

  @override
  Future<Duration?> setFile(String filePath, {Track? track}) async {
    logDebug('Setting file: $filePath');
    try {
      _processingStateController.add(FmpAudioProcessingState.loading);
      await _session.setActive(true);

      final source = ja.AudioSource.file(filePath);
      final duration = await _player.setAudioSource(source);

      logDebug('File set, duration: $duration');
      return duration;
    } catch (e, stack) {
      logError('Failed to set file', e, stack);
      rethrow;
    }
  }
}
