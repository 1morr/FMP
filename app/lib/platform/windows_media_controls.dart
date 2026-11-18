import 'dart:async';

import 'package:flutter/services.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/media_controls.dart';
import 'package:fmp/playback/playback.dart';

/// Windows 的系統媒體控制（SMTC）：runner 裡自己接的
/// （`windows/runner/media_controls.cpp`，事實 W7），經 `fmp/media` 頻道。
///
/// 送給 runner：
///
/// - `metadata` `{title, artist, thumbnail?}`：換了曲目才送；runner 先清掉
///   舊的再設（事實 W6），沒有封面就不帶 `thumbnail`。
/// - `state` `{status, positionMs, durationMs?, canPrevious, canNext}`：
///   `status` 是 `playing`、`paused` 或 `changing`（解析、載入、緩衝中）；
///   長度不知道就不帶 `durationMs`，不能拖進度。
/// - `clear`：沒有正在播的曲目。
///
/// runner 送回 `command` `{name, positionMs?}`：`name` 是 `play`、`pause`、
/// `next`、`previous` 或 `seek`（帶 `positionMs`），其他按鈕不理。
///
/// runner 呼叫失敗時寫 warning，播放照常。
class WindowsMediaControls implements MediaControls {
  WindowsMediaControls(this._log) {
    _channel.setMethodCallHandler(_fromRunner);
  }

  static const _channel = MethodChannel('fmp/media');

  final Log _log;
  final _commands = StreamController<MediaCommand>.broadcast();

  /// 最後送過 `metadata` 的曲目；清掉後是 null。
  Track? _shownTrack;

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  void show(NowPlaying? nowPlaying) {
    if (nowPlaying == null) {
      if (_shownTrack == null) return;
      _shownTrack = null;
      _invoke('clear');
      return;
    }
    final track = nowPlaying.track;
    if (track != _shownTrack) {
      _shownTrack = track;
      _invoke('metadata', {
        'title': track.title,
        'artist': track.author,
        'thumbnail': ?track.coverUrl,
      });
    }
    _invoke('state', {
      'status': switch (nowPlaying.status) {
        PlaybackStatus.resolving ||
        PlaybackStatus.loading ||
        PlaybackStatus.buffering => 'changing',
        PlaybackStatus.playing => 'playing',
        PlaybackStatus.paused ||
        PlaybackStatus.completed ||
        PlaybackStatus.failed => 'paused',
      },
      'positionMs': nowPlaying.position.inMilliseconds,
      'durationMs': ?nowPlaying.duration?.inMilliseconds,
      'canPrevious': nowPlaying.canPrevious,
      'canNext': nowPlaying.canNext,
    });
  }

  void _invoke(String method, [Map<String, Object>? arguments]) => unawaited(
    _channel.invokeMethod<void>(method, arguments).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _log.warning(
        'Updating the Windows media controls failed: $method',
        error: error,
        stackTrace: stackTrace,
      );
    }),
  );

  Future<void> _fromRunner(MethodCall call) async {
    if (call.method != 'command') return;
    final arguments = (call.arguments as Map).cast<String, Object?>();
    final command = switch (arguments['name']) {
      'play' => const PlayCommand(),
      'pause' => const PauseCommand(),
      'next' => const NextCommand(),
      'previous' => const PreviousCommand(),
      'seek' => switch (arguments['positionMs']) {
        final int ms => SeekCommand(Duration(milliseconds: ms)),
        _ => null,
      },
      _ => null,
    };
    if (command != null) _commands.add(command);
  }

  /// 不再收 runner 的指令；測試用。
  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_commands.close());
  }
}
