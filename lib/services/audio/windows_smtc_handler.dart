import 'dart:async';
import 'dart:io';
import 'package:smtc_windows/smtc_windows.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';

/// Windows SMTC (System Media Transport Controls) 处理器
/// 提供 Windows 媒体键控制和系统媒体叠层显示
class WindowsSmtcHandler with Logging {
  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _buttonSubscription;

  // 回调函数，由 AudioController 设置
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function(Duration position)? onSeek;

  // 当前状态缓存
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  WindowsSmtcHandler() {
    logInfo('WindowsSmtcHandler created');
  }

  /// 初始化 SMTC
  Future<void> initialize() async {
    if (!Platform.isWindows) {
      logDebug('WindowsSmtcHandler: Not on Windows, skipping initialization');
      return;
    }

    try {
      _smtc = SMTCWindows(
        metadata: const MusicMetadata(
          title: 'FMP',
          album: '',
          albumArtist: '',
          artist: '',
          thumbnail: '',
        ),
        timeline: const PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: 0,
          positionMs: 0,
          minSeekTimeMs: 0,
          maxSeekTimeMs: 0,
        ),
        config: const SMTCConfig(
          fastForwardEnabled: false,
          nextEnabled: true,
          pauseEnabled: true,
          playEnabled: true,
          rewindEnabled: false,
          prevEnabled: true,
          stopEnabled: true,
        ),
      );

      _setupButtonListener();
      logInfo('WindowsSmtcHandler initialized successfully');
    } catch (e, stack) {
      logError('Failed to initialize WindowsSmtcHandler: $e', e, stack);
    }
  }

  /// 设置按钮事件监听
  void _setupButtonListener() {
    _buttonSubscription = _smtc?.buttonPressStream.listen((event) {
      logDebug('SMTC button pressed: $event');
      switch (event) {
        case PressedButton.play:
          onPlay?.call();
          break;
        case PressedButton.pause:
          onPause?.call();
          break;
        case PressedButton.next:
          onSkipToNext?.call();
          break;
        case PressedButton.previous:
          onSkipToPrevious?.call();
          break;
        case PressedButton.stop:
          onStop?.call();
          break;
        default:
          break;
      }
    });
  }

  /// 更新当前播放的媒体元数据
  void updateCurrentMediaItem(Track track) {
    if (_smtc == null) return;

    try {
      _smtc!.updateMetadata(MusicMetadata(
        title: track.title,
        album: '',
        albumArtist: '',
        artist: track.artist ?? '未知艺术家',
        thumbnail: track.thumbnailUrl ?? '',
      ));
      logDebug('SMTC updated media item: ${track.title}');
    } catch (e) {
      logError('Failed to update SMTC metadata: $e');
    }
  }

  /// 更新播放状态
  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    Duration? duration,
  }) {
    if (_smtc == null) return;

    _position = position;
    if (duration != null) {
      _duration = duration;
    }

    try {
      // 更新播放/暂停状态
      if (isPlaying) {
        _smtc!.setPlaybackStatus(PlaybackStatus.playing);
      } else {
        _smtc!.setPlaybackStatus(PlaybackStatus.paused);
      }

      // 更新时间线
      _updateTimeline();
    } catch (e) {
      logError('Failed to update SMTC playback state: $e');
    }
  }

  /// 更新时间线
  void _updateTimeline() {
    if (_smtc == null) return;

    try {
      final durationMs = _duration.inMilliseconds;
      final positionMs = _position.inMilliseconds.clamp(0, durationMs > 0 ? durationMs : 0);

      _smtc!.updateTimeline(PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: durationMs,
        positionMs: positionMs,
        minSeekTimeMs: 0,
        maxSeekTimeMs: durationMs,
      ));
    } catch (e) {
      logError('Failed to update SMTC timeline: $e');
    }
  }

  /// 设置停止状态
  void setStoppedState() {
    if (_smtc == null) return;

    try {
      _smtc!.setPlaybackStatus(PlaybackStatus.stopped);
    } catch (e) {
      logError('Failed to set SMTC stopped state: $e');
    }
  }

  /// 启用 SMTC
  void enable() {
    if (_smtc == null) return;

    try {
      _smtc!.enableSmtc();
      logDebug('SMTC enabled');
    } catch (e) {
      logError('Failed to enable SMTC: $e');
    }
  }

  /// 禁用 SMTC
  void disable() {
    if (_smtc == null) return;

    try {
      _smtc!.disableSmtc();
      logDebug('SMTC disabled');
    } catch (e) {
      logError('Failed to disable SMTC: $e');
    }
  }

  /// 清理资源
  void dispose() {
    _buttonSubscription?.cancel();
    _smtc?.dispose();
    _smtc = null;
    logInfo('WindowsSmtcHandler disposed');
  }
}
