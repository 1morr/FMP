import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/playback/playback_controller.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';

/// 系統媒體控制的唯一出口（ADR 0018 §決定 1、8，design §8.2）：把控制器的
/// 狀態、佇列與進度整理成 [NowPlaying] 推給平台，並把系統按鍵送回控制器。
///
/// 照 `QueueStore`、`PlayHistoryRecorder` 的分工：只聽控制器的輸出，不改它的
/// 狀態；系統指令一律呼叫控制器（唯一入口）。
///
/// 推送規則（Harmonoid 的慣例）：
/// - 只在值改變時推，推送一個接一個、不重疊；
/// - 位置只在狀態改變與 seek 時推：系統依速度自己外推，高頻的進度 stream
///   只用來取得時長；
/// - 還沒按過播放的 [Idle] 是 [MediaPhase.idle]：系統不顯示通知、不搶前景。
final class NowPlayingPublisher {
  /// [artworkFile] 取得曲目封面的本機檔（經統一快取庫）；拿不到回 `null` 或
  /// 丟出都當作沒有封面，不影響其他欄位。
  NowPlayingPublisher({
    required this._controls,
    required this._artworkFile,
    required this._log,
  });

  static const _tag = 'media-controls';

  final SystemMediaControls _controls;
  final Future<Uri?> Function(TrackInfo track) _artworkFile;
  final Log _log;

  late PlaybackController _controller;
  final _subscriptions = <StreamSubscription<Object?>>[];

  NowPlaying? _last;
  Future<void> _pushing = Future.value();
  bool _disposed = false;

  /// 目前這首的時長（進度 stream 回報的）；換曲目時清掉。
  Duration? _duration;
  TrackKeyParts? _artworkOf;
  Uri? _artwork;

  /// 開始聽 [controller]，並先推一次現況。
  void attach(PlaybackController controller) {
    _controller = controller;
    _subscriptions
      ..add(controller.states.listen((_) => _refresh()))
      ..add(controller.queueStates.listen((_) => _refresh()))
      ..add(
        controller.seeks.listen(
          (position) => _refresh(position: position, force: true),
        ),
      )
      ..add(
        controller.progress.listen((progress) {
          if (progress.duration == _duration) return;
          _duration = progress.duration;
          _refresh();
        }),
      )
      ..add(_controls.commands.listen(_onCommand));
    _refresh();
  }

  void _onCommand(MediaCommand command) {
    switch (command) {
      case MediaPlay():
        _run('play', _controller.play);
      case MediaPause():
        _run('pause', _controller.pause);
      case MediaPrevious():
        _run('previous', _controller.previous);
      case MediaNext():
        _run('next', _controller.next);
      case MediaSeek(:final position):
        _run('seek', () => _controller.seek(position));
      // 停止當作暫停：位置與佇列都保留，之後按播放從原處繼續。
      case MediaStop():
        _run('stop', _controller.pause);
    }
  }

  void _run(String command, Future<void> Function() action) {
    unawaited(
      action().catchError((Object error, StackTrace stackTrace) {
        _log.report(
          'System media command failed: $command',
          AppError.wrap(error, stackTrace),
          tag: _tag,
        );
      }),
    );
  }

  /// 重算並在值改變時推送。[position] 是這次推送的位置（預設取控制器的）；
  /// 只有位置不同時，除非 [force]（seek）否則不推。
  void _refresh({Duration? position, bool force = false}) {
    if (_disposed) return;
    final queue = _controller.queue;
    final track = queue.current;
    if (track == null) {
      _artworkOf = null;
      _artwork = null;
      _duration = null;
    } else if (track.key != _artworkOf) {
      _artworkOf = track.key;
      _artwork = null;
      _duration = null;
      unawaited(_loadArtwork(track));
    }
    final next = _build(
      queue,
      _controller.state,
      position ?? _controller.position,
    );
    final last = _last;
    if (last != null) {
      if (next == last) return;
      if (!force && next.copyWith(position: last.position) == last) return;
    }
    _last = next;
    _pushing = _pushing.then((_) => _push(next));
  }

  Future<void> _push(NowPlaying nowPlaying) async {
    if (_disposed) return;
    try {
      await _controls.publish(nowPlaying);
    } on Object catch (error, stackTrace) {
      // 系統那一側的問題不影響播放；下一次改變時再推。
      _log.report(
        'Failed to publish now playing',
        AppError.wrap(error, stackTrace),
        tag: _tag,
      );
    }
  }

  Future<void> _loadArtwork(TrackInfo track) async {
    final Uri? file;
    try {
      file = await _artworkFile(track);
    } on Object catch (error, stackTrace) {
      _log.debug(
        'Artwork for the system media controls is not available',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (file == null || _disposed || track.key != _artworkOf) return;
    _artwork = file;
    _refresh();
  }

  NowPlaying _build(QueueState queue, PlaybackState state, Duration position) {
    final track = queue.current;
    if (track == null) return NowPlaying.nothing;
    final playing = switch (state) {
      Playing() || Loading() || Buffering() || Retrying() => true,
      Paused() || Idle() || Failed() => false,
    };
    return NowPlaying(
      id: track.key.toString(),
      title: track.title,
      uploader: track.uploader,
      duration: _duration ?? track.duration,
      artworkFile: _artwork,
      phase: switch (state) {
        Idle() => MediaPhase.idle,
        Loading() => MediaPhase.loading,
        Buffering() || Retrying() => MediaPhase.buffering,
        Playing() || Paused() || Failed() => MediaPhase.ready,
      },
      playing: playing,
      position: position,
      controls: [
        MediaControl.previous,
        if (playing) MediaControl.pause else MediaControl.play,
        if (queue.hasNext) MediaControl.next,
      ],
    );
  }

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
