import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';

/// 系統媒體控制（brief〈播放〉）：Now Playing 顯示的資訊，與系統送來的播放、
/// 暫停、上一首、下一首、拖動進度。Android、iOS、macOS 的實作用
/// audio_service，Windows 接 runner 裡自己的 SMTC（事實 W7）；依平台挑在
/// `platform/media_controls.dart`。
///
/// 實作負責把 [show] 的資訊轉成平台的格式，失敗時自己寫 log、不丟錯；
/// 什麼時候送由 [MediaControlsBinding] 決定。
abstract interface class MediaControls {
  /// 系統送來的指令。
  Stream<MediaCommand> get commands;

  /// 顯示 [nowPlaying]；null 是沒有正在播的曲目，清掉 Now Playing。
  void show(NowPlaying? nowPlaying);
}

/// 系統送來的指令。
sealed class MediaCommand {
  const MediaCommand();
}

class PlayCommand extends MediaCommand {
  const PlayCommand();
}

class PauseCommand extends MediaCommand {
  const PauseCommand();
}

class NextCommand extends MediaCommand {
  const NextCommand();
}

class PreviousCommand extends MediaCommand {
  const PreviousCommand();
}

/// 拖動進度到 [position]。
class SeekCommand extends MediaCommand {
  const SeekCommand(this.position);

  final Duration position;

  @override
  bool operator ==(Object other) =>
      other is SeekCommand && other.position == position;

  @override
  int get hashCode => position.hashCode;
}

/// Now Playing 顯示的一份資訊。
class NowPlaying {
  const NowPlaying({
    required this.track,
    required this.status,
    required this.position,
    required this.duration,
    required this.canPrevious,
    required this.canNext,
  });

  /// 曲名、作者、封面網址都從它來。
  final Track track;

  final PlaybackStatus status;

  /// 送出這份資訊時的位置；播放中由系統自己往前推。
  final Duration position;

  /// 畫面顯示的長度（[PlaybackState.effectiveDuration]）；不知道是 null。
  final Duration? duration;

  /// 上一首、下一首有沒有作用（和 App 裡的鈕一樣，[skipAvailableProvider]）。
  final bool canPrevious;
  final bool canNext;

  /// 系統顯示暫停鈕：要播或正在播（[PlaybackStatus.wantsToPlay]）。
  bool get playing => status.wantsToPlay;

  /// 位置以外都一樣。
  bool sameApartFromPosition(NowPlaying other) =>
      other.track == track &&
      other.status == status &&
      other.duration == duration &&
      other.canPrevious == canPrevious &&
      other.canNext == canNext;

  @override
  bool operator ==(Object other) =>
      other is NowPlaying &&
      sameApartFromPosition(other) &&
      other.position == position;

  @override
  int get hashCode =>
      Object.hash(track, status, position, duration, canPrevious, canNext);

  @override
  String toString() =>
      'NowPlaying(${track.ref.logId}, ${status.name}, $position / $duration, '
      'previous: $canPrevious, next: $canNext)';
}

/// 這個平台的系統媒體控制；`main` 依平台建好再 override 進來。沒有（測試、
/// 平台不支援、初始化失敗）是 null。
final mediaControlsProvider = Provider<MediaControls?>((ref) => null);

/// 把播放接上 [mediaControlsProvider]；App 的根看著它，App 開著就一直接著。
final mediaControlsBindingProvider = Provider<MediaControlsBinding?>((ref) {
  final controls = ref.watch(mediaControlsProvider);
  if (controls == null) return null;
  final binding = MediaControlsBinding._(ref, controls);
  ref.onDispose(binding._dispose);
  return binding;
});

/// 播放狀態一變就更新 Now Playing，系統的指令轉給佇列與播放。
class MediaControlsBinding {
  MediaControlsBinding._(this._ref, this._controls) {
    _ref.listen(playbackProvider, (_, _) => _update(), fireImmediately: true);
    _ref.listen(skipAvailableProvider, (_, _) => _update());
    _commands = _controls.commands.listen(_onCommand);
  }

  late final StreamSubscription<MediaCommand> _commands;

  /// 和 App 裡的鈕做一樣的事：播放、暫停照播放鈕（播完或失敗的那首從頭
  /// 再播，解析與載入中不動），上一首、下一首照佇列（臨時播放時回到佇列）。
  void _onCommand(MediaCommand command) {
    final playback = _ref.read(playbackProvider.notifier);
    final queue = _ref.read(queueProvider.notifier);
    final state = _ref.read(playbackProvider);
    switch (command) {
      case PlayCommand():
        if (state != null && !state.playing) unawaited(playback.playPause());
      case PauseCommand():
        if (state?.status
            case PlaybackStatus.playing || PlaybackStatus.buffering) {
          unawaited(playback.pause());
        }
      case NextCommand():
        unawaited(queue.next());
      case PreviousCommand():
        unawaited(queue.previous());
      case SeekCommand(:final position):
        unawaited(playback.seek(position));
    }
  }

  final Ref _ref;
  final MediaControls _controls;

  /// 播放中位置照常往前走時，最久隔這麼久重送一次：SMTC 的時間軸不會自己
  /// 往前（事實 W6），audio_service 那邊多送無妨。
  static const resendEvery = Duration(seconds: 5);

  /// 最後送出的；送過 null 或還沒送過是 null。
  NowPlaying? _sent;

  /// 上一次看到的位置，認拖動進度用。
  Duration? _seenPosition;

  void _update() {
    final playback = _ref.read(playbackProvider);
    if (playback == null) {
      _seenPosition = null;
      if (_sent != null) _controls.show(null);
      _sent = null;
      return;
    }
    final skip = _ref.read(skipAvailableProvider);
    final next = NowPlaying(
      track: playback.track,
      status: playback.status,
      position: playback.position,
      duration: playback.effectiveDuration,
      canPrevious: skip.previous,
      canNext: skip.next,
    );
    final seen = _seenPosition;
    _seenPosition = next.position;
    if (_sent case final sent? when sent.sameApartFromPosition(next)) {
      if (next.position == sent.position) return;
      // 系統在播放中自己把位置往前推；照常往前走的位置隔一陣子才送，
      // 暫停中改了位置或拖了進度馬上送。
      final jumped =
          !next.playing || positionJumped(seen ?? next.position, next.position);
      if (!jumped && next.position - sent.position < resendEvery) return;
    }
    _sent = next;
    _controls.show(next);
  }

  void _dispose() => unawaited(_commands.cancel());
}
