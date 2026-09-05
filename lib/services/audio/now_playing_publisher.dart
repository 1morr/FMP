import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../data/models/play_queue.dart';
import '../../data/models/radio_station.dart';
import '../../data/models/track.dart';
import '../../main.dart' show audioHandler, windowsSmtcHandler;
import 'audio_handler.dart';
import 'audio_runtime_platform.dart';
import 'audio_types.dart';
import 'playback_capabilities.dart';
import 'windows_smtc_handler.dart';

/// 誰正在擁有系統媒體控制。
///
/// 只有兩個：音樂（`AudioController`）與電台（`RadioController`）。電台是
/// `lib/services/audio/AGENTS.md` 記載的刻意例外 —— 它繞過 `AudioController`
/// 直接用共用後端，但系統媒體控制只有一組，必須有人仲裁。
enum NowPlayingOwner { music, radio }

/// 系統媒體鍵按下去會呼到的東西。
///
/// 沒有給的就是這個模式沒有這個命令。實際綁不綁還要看
/// [PlaybackCapabilities] —— 能力是唯一的真相來源，命令只是它的實作。
class MediaControlCommands {
  const MediaControlCommands({
    required this.play,
    required this.pause,
    required this.stop,
    this.skipToNext,
    this.skipToPrevious,
    this.seek,
    this.setLoopMode,
    this.setShuffleEnabled,
  });

  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function() stop;
  final Future<void> Function()? skipToNext;
  final Future<void> Function()? skipToPrevious;
  final Future<void> Function(Duration position)? seek;
  final Future<void> Function(LoopMode mode)? setLoopMode;
  final Future<void> Function(bool enabled)? setShuffleEnabled;
}

/// 「現在在播什麼、現在能做什麼」的唯一對外出口。
///
/// 收下過去散在 `AudioController`（7 處 `_usesMobileAudioHandler` ＋ 5 處
/// `Platform.isWindows`）與 `RadioController`（10 處 `Platform.isAndroid` /
/// `Platform.isWindows`）的平台分支，把「上層用 `Platform.isX` 判斷」換成
/// 「上層宣告能力、由這裡決定送到哪個表面」。
///
/// 平台判斷只靠可注入的 [AudioRuntimePlatform]，這個檔案**不 import
/// `dart:io`**。`desktop` 涵蓋 Linux / macOS 而不只是 Windows，這是安全的，
/// 因為 [WindowsSmtcHandler] 的每個方法在 `_smtc == null` 時都自己早退，而
/// `_smtc` 只在 `Platform.isWindows` 的 `initialize()` 裡才會非 null
/// （`main.dart` 在其他平台只建構、不初始化）。**這是平台收斂能成立的唯一
/// 理由** —— 不是漏了檢查。
///
/// 它刻意**不擁有**：`PlayerState` 與任何狀態投影、位置節流（那需要 `Timer`，
/// 留在 `AudioController`）、`FmpAudioService` 本身（速度與緩衝位置由呼叫端
/// 讀好傳進來，維持成純 sink）、「電台在不在播」的判斷、以及原生控制代碼的
/// 生命週期（見 [release]）。
class NowPlayingPublisher with Logging {
  NowPlayingPublisher({
    required FmpAudioHandler audioHandler,
    required WindowsSmtcHandler smtcHandler,
    required AudioRuntimePlatform platform,
  })  : _audioHandler = audioHandler,
        _smtcHandler = smtcHandler,
        _platform = platform;

  final FmpAudioHandler _audioHandler;
  final WindowsSmtcHandler _smtcHandler;
  final AudioRuntimePlatform _platform;

  NowPlayingOwner _owner = NowPlayingOwner.music;

  /// 音樂的綁定要記住，[release] 才能在不回頭找 `AudioController` 的情況下
  /// 自己還原。過去這條路是電台去呼
  /// `AudioController.restoreMediaControlOwnership()`，外面包著一個吞掉一切
  /// 的 try/catch —— 一旦它拋了，能力會永遠停在電台的全關狀態，離開電台後
  /// 上下一首**再也回不來**。
  MediaControlCommands? _musicCommands;
  PlaybackCapabilities _musicCapabilities = PlaybackCapabilities.music;

  PlaybackCapabilities _publishedCapabilities = PlaybackCapabilities.none;

  /// 目前對外宣告的能力。測試與 log 用。
  PlaybackCapabilities get capabilities => _publishedCapabilities;

  /// 目前的擁有者。
  NowPlayingOwner get owner => _owner;

  /// 接管系統媒體控制。
  ///
  /// 回呼與能力宣告在這裡是**同一次原子操作** —— 這正是 issue #40 症狀一
  /// 不可能再發生的原因：過去電台只能把回呼設成 null，卻沒有辦法收回已經
  /// 宣告出去的按鈕。
  ///
  /// 交接採 last-writer-wins，不做優先權：交接點只有兩個（電台開始播、
  /// 電台停止），兩邊都在主 isolate 上同步執行，而且這裡一次換掉全部狀態，
  /// 不存在「換了一半」的中間態。
  void claim(
    NowPlayingOwner owner, {
    required MediaControlCommands commands,
    required PlaybackCapabilities capabilities,
  }) {
    if (owner == NowPlayingOwner.music) {
      _musicCommands = commands;
      _musicCapabilities = capabilities;
    }
    _owner = owner;
    logInfo('Media control owner -> ${owner.name} ($capabilities)');
    _apply(commands, capabilities);
  }

  /// 交還系統媒體控制。
  ///
  /// 電台交還時直接套用這裡記住的音樂綁定，**不需要 `AudioController` 在場
  /// 或可達**。音樂交還（controller dispose）時把記憶一併忘掉，否則電台之後
  /// 停止會還原到一個已經釋放的 controller。
  ///
  /// 刻意沒有 `dispose()`：兩個 handler 都是行程級單例
  /// （`FmpAudioHandler` 由 `AudioService.init()` 在 `runApp` 之前建立，
  /// `WindowsSmtcHandler` 的原生 session 只在 `main.dart` 建立一次且**沒有
  /// 任何程式碼會重建它**）。真正不能活過 controller 的是回呼綁定，不是原生
  /// 控制代碼 —— 過去 `AudioController.dispose()` 直接 dispose 掉 SMTC，
  /// 只要 provider 重建過一次，SMTC 就在這個 session 裡永久死掉。
  void release(NowPlayingOwner owner) {
    if (owner == NowPlayingOwner.music) {
      _musicCommands = null;
    }
    if (_owner != owner) {
      // 已經被別人接管了，這次釋放不該動到現任擁有者。
      return;
    }
    _owner = NowPlayingOwner.music;
    final commands = _musicCommands;
    if (commands == null) {
      logInfo('Media control released with no music owner; unbinding');
      _apply(null, PlaybackCapabilities.none);
      return;
    }
    logInfo('Media control owner -> music (restored)');
    _apply(commands, _musicCapabilities);
  }

  /// 發佈正在播放的歌曲。
  void publishTrack(NowPlayingOwner owner, Track track) {
    if (!_isOwner(owner, 'publishTrack')) return;
    switch (_platform) {
      case AudioRuntimePlatform.mobile:
        _audioHandler.updateCurrentMediaItem(track);
      case AudioRuntimePlatform.desktop:
        _smtcHandler.updateCurrentMediaItem(track);
    }
  }

  /// 發佈正在播放的電台。
  void publishRadioStation(NowPlayingOwner owner, RadioStation station) {
    if (!_isOwner(owner, 'publishRadioStation')) return;
    switch (_platform) {
      case AudioRuntimePlatform.mobile:
        _audioHandler.updateCurrentRadioStation(station);
      case AudioRuntimePlatform.desktop:
        _smtcHandler.updateCurrentRadioStation(station);
    }
  }

  /// 發佈播放狀態。
  ///
  /// 節流是呼叫端的責任 —— 位置每秒更新多次，但狀態轉換（載入、重置）一次
  /// 都不能丟，兩者不能共用同一個節流器。
  void publishPlaybackState(
    NowPlayingOwner owner, {
    required bool isPlaying,
    required Duration position,
    required Duration bufferedPosition,
    required FmpAudioProcessingState processingState,
    Duration? duration,
    double speed = 1.0,
  }) {
    if (!_isOwner(owner, 'publishPlaybackState')) return;
    switch (_platform) {
      case AudioRuntimePlatform.mobile:
        _audioHandler.updatePlaybackState(
          isPlaying: isPlaying,
          position: position,
          bufferedPosition: bufferedPosition,
          processingState: processingState,
          speed: speed,
        );
      case AudioRuntimePlatform.desktop:
        _smtcHandler.updatePlaybackState(
          isPlaying: isPlaying,
          position: position,
          duration: duration,
        );
    }
  }

  /// 發佈循環／隨機模式。
  ///
  /// 兩個模式一起送：它們在 Android 上共用同一則 `PlaybackState`，分開送等於
  /// 白發一次。Windows 端不接受這兩個模式（`SMTCConfig` 沒有對應旗標）。
  void publishPlayModes(
    NowPlayingOwner owner, {
    required LoopMode loopMode,
    required bool shuffleEnabled,
  }) {
    if (!_isOwner(owner, 'publishPlayModes')) return;
    switch (_platform) {
      case AudioRuntimePlatform.mobile:
        _audioHandler.updatePlayModes(
          loopMode: loopMode,
          shuffleEnabled: shuffleEnabled,
        );
      case AudioRuntimePlatform.desktop:
        break;
    }
  }

  /// 發佈「已停止」。
  void publishStopped(NowPlayingOwner owner) {
    if (!_isOwner(owner, 'publishStopped')) return;
    switch (_platform) {
      case AudioRuntimePlatform.mobile:
        _audioHandler.updatePlaybackState(
          isPlaying: false,
          position: Duration.zero,
          bufferedPosition: Duration.zero,
          processingState: FmpAudioProcessingState.idle,
        );
      case AudioRuntimePlatform.desktop:
        _smtcHandler.setStoppedState();
    }
  }

  /// 非現任擁有者的發佈一律丟棄。
  ///
  /// 這不是潔癖，是擋一個今天就會發生的 bug：點一首歌（串流解析進行中）後
  /// 立刻點電台，`RadioController` 只會 `pause()` 音樂、**不取消進行中的
  /// 請求**，那個請求完成後會把歌名蓋到電台的通知欄／SMTC 上。加上能力之後
  /// 不擋的話，它還會把電台的全關能力蓋回音樂的全開能力 —— 變成間歇性的
  /// #40 回歸。
  bool _isOwner(NowPlayingOwner owner, String what) {
    if (owner == _owner) return true;
    logDebug('Ignored $what from ${owner.name}; owner is ${_owner.name}');
    return false;
  }

  void _apply(
    MediaControlCommands? commands,
    PlaybackCapabilities capabilities,
  ) {
    _publishedCapabilities = capabilities;
    switch (_platform) {
      case AudioRuntimePlatform.mobile:
        _audioHandler
          ..onPlay = commands?.play
          ..onPause = commands?.pause
          ..onStop = commands?.stop
          ..onSkipToNext =
              capabilities.canSkipNext ? commands?.skipToNext : null
          ..onSkipToPrevious =
              capabilities.canSkipPrevious ? commands?.skipToPrevious : null
          ..onSeek = capabilities.canSeek ? commands?.seek : null
          ..onSetLoopMode = capabilities.canRepeat ? commands?.setLoopMode : null
          ..onSetShuffleEnabled =
              capabilities.canShuffle ? commands?.setShuffleEnabled : null
          ..updateCapabilities(capabilities);
      case AudioRuntimePlatform.desktop:
        _smtcHandler
          ..onPlay = commands?.play
          ..onPause = commands?.pause
          ..onStop = commands?.stop
          ..onSkipToNext =
              capabilities.canSkipNext ? commands?.skipToNext : null
          ..onSkipToPrevious =
              capabilities.canSkipPrevious ? commands?.skipToPrevious : null
          ..onSeek = capabilities.canSeek ? commands?.seek : null
          ..updateCapabilities(capabilities);
    }
  }
}

/// `main.dart` 的兩個全域 `late` 單例，全 repo 只在這裡被引用。
///
/// 它們的生命週期屬於 `AudioService.init()` 與 SMTC 的啟動流程，不在這一層
/// 管理；這裡只是把散在兩個 controller 裡的直接引用收成一處。
final fmpAudioHandlerProvider = Provider<FmpAudioHandler>((ref) => audioHandler);

final windowsSmtcHandlerProvider =
    Provider<WindowsSmtcHandler>((ref) => windowsSmtcHandler);

final nowPlayingPublisherProvider = Provider<NowPlayingPublisher>((ref) {
  return NowPlayingPublisher(
    audioHandler: ref.watch(fmpAudioHandlerProvider),
    smtcHandler: ref.watch(windowsSmtcHandlerProvider),
    platform: ref.watch(audioRuntimePlatformProvider),
  );
});
