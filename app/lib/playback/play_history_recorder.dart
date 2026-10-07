import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/playback/playback_controller.dart';

/// 把控制器報的「這一首算一次播放」（[PlaybackController.plays]）寫進播放歷史
/// （design §7.8）。
///
/// 照 `QueueStore` 的分工：它只聽控制器的輸出、不改控制器，控制器也不碰資料層。
/// 寫入一個接一個（歷史的先後就是播放的先後）；寫失敗只經 `Log.report` 記下，不提示、
/// 不影響播放，那一筆就沒有了。
final class PlayHistoryRecorder {
  /// [limit] 在每次寫入時讀「播放歷史保留筆數」（等資料庫的設定讀出來）。
  PlayHistoryRecorder({
    required this._repository,
    required this._limit,
    required this._log,
  });

  static const _tag = 'play-history';

  final PlayHistoryRepository _repository;
  final Future<int> Function() _limit;
  final Log _log;

  StreamSubscription<CountedPlay>? _subscription;
  Future<void> _writing = Future.value();
  bool _disposed = false;

  /// 開始聽 [plays]（接 [PlaybackController.plays]）。
  void listen(Stream<CountedPlay> plays) {
    _subscription = plays.listen(_onPlay);
  }

  void _onPlay(CountedPlay play) {
    _writing = _writing.then((_) => _write(play));
  }

  Future<void> _write(CountedPlay play) async {
    // dispose 之後不再寫（同 `QueueStore`）：組裝點的 ref 已經不能讀設定，資料庫可能
    // 也正要關。排在 dispose 之前、還沒寫的那幾筆就沒有了。
    if (_disposed) return;
    try {
      final limit = await _limit();
      if (_disposed) return;
      await _repository.record(play.track, playedAt: play.at, limit: limit);
    } on Object catch (error, stackTrace) {
      _log.report(
        'Failed to record play history',
        AppError.wrap(error, stackTrace),
        tag: _tag,
      );
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
