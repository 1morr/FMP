import 'package:flutter/foundation.dart';

import 'package:fmp/domain/track_key.dart';

/// 佇列的一份快照（ADR 0018 §決定 4）。與播放狀態沒有共同欄位：播到哪一首
/// 只在這裡。
@immutable
final class QueueState {
  const QueueState({required this.tracks, required this.currentIndex})
    : assert(
        currentIndex == null ||
            (currentIndex >= 0 && currentIndex < tracks.length),
      );

  static const empty = QueueState(tracks: [], currentIndex: null);

  /// 曲目，依播放順序。同一首可以出現兩次，以位置區分。
  final List<TrackKeyParts> tracks;

  /// 目前這首的位置；佇列是空的時為 `null`。
  final int? currentIndex;

  TrackKeyParts? get current => switch (currentIndex) {
    final index? => tracks[index],
    null => null,
  };

  bool get hasNext => currentIndex != null && currentIndex! + 1 < tracks.length;

  bool get hasPrevious => currentIndex != null && currentIndex! > 0;
}

/// 佇列的真相（ADR 0018 §決定 4）：M1 只在記憶體、只有依序播放的 `queue`
/// 模式、不持久化（M1 design 3.16）。其他模式、隨機、上限在 M2。
///
/// 只由 `PlaybackController` 呼叫。
final class QueueModel {
  QueueState _state = QueueState.empty;

  QueueState get state => _state;

  /// 以 [tracks] 取代佇列，從 [startIndex] 開始（播放某一首＝清單加起點）。
  void replace(List<TrackKeyParts> tracks, {int startIndex = 0}) {
    if (tracks.isEmpty) {
      _state = QueueState.empty;
      return;
    }
    RangeError.checkValidIndex(startIndex, tracks, 'startIndex');
    _state = QueueState(
      tracks: List.unmodifiable(tracks),
      currentIndex: startIndex,
    );
  }

  /// 下一首的位置與曲目；已經是最後一首（或佇列是空的）時為 `null`。
  ({int index, TrackKeyParts track})? get next {
    if (!_state.hasNext) return null;
    final index = _state.currentIndex! + 1;
    return (index: index, track: _state.tracks[index]);
  }

  /// 往下一首；已經是最後一首就不動並回傳 `false`。
  bool moveNext() => _moveTo((_state.currentIndex ?? -1) + 1);

  /// 往上一首；已經是第一首就不動並回傳 `false`。
  bool movePrevious() => _moveTo((_state.currentIndex ?? 0) - 1);

  bool _moveTo(int index) {
    if (_state.currentIndex == null ||
        index < 0 ||
        index >= _state.tracks.length) {
      return false;
    }
    _state = QueueState(tracks: _state.tracks, currentIndex: index);
    return true;
  }
}
