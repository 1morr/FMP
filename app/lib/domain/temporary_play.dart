import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';

/// 臨時播放（`GLOSSARY.md`）：在佇列之外播的那首（或一組分 P），與離開佇列
/// 時停在哪裡。
///
/// 一組分 P 整組當成一首（brief〈播放〉）：組內播完一個接下一個、上一首與
/// 下一首在組內移動，整組播完或走出兩端才回佇列。單獨一首是只有一個的組。
///
/// 回到的是佇列的目前那首（`playback/` 決定什麼時候回去）：臨時播放時佇列
/// 照常能拖動、移除，目前那首換了就回到換上來的那首。離開時的位置只屬於
/// 離開的那個佇列位置（[QueueEntry.id]），回到別首就從頭播。
class TemporaryPlay {
  const TemporaryPlay._(this.group, this.index, this._leftEntryId, this.leftAt);

  /// 臨時播放 [group]，從第 [start] 個開始。從佇列離開時記下目前那首
  /// [leaving] 與它播到的 [position]；已在臨時播放中（[previous] 不是 null）
  /// 時只換曲目，保留最早那個佇列位置。[group] 不能是空的。
  factory TemporaryPlay.start(
    List<Track> group, {
    int start = 0,
    required TemporaryPlay? previous,
    required QueueEntry? leaving,
    required Duration position,
  }) {
    RangeError.checkValidIndex(start, group, 'start');
    final tracks = List<Track>.unmodifiable(group);
    return previous != null
        ? TemporaryPlay._(tracks, start, previous._leftEntryId, previous.leftAt)
        : TemporaryPlay._(
            tracks,
            start,
            leaving?.id,
            leaving == null ? Duration.zero : position,
          );
  }

  /// 這次臨時播放的整組曲目；單獨一首時只有一個。
  final List<Track> group;

  /// 正在播 [group] 的第幾個。
  final int index;

  /// 在佇列之外播的曲目。
  Track get track => group[index];

  /// 組內的下一個；已是最後一個時是 null（該回佇列了）。
  TemporaryPlay? get next => index + 1 < group.length
      ? TemporaryPlay._(group, index + 1, _leftEntryId, leftAt)
      : null;

  /// 組內的上一個；已是第一個時是 null（該回佇列了）。
  TemporaryPlay? get previous => index > 0
      ? TemporaryPlay._(group, index - 1, _leftEntryId, leftAt)
      : null;

  /// 離開時佇列的目前那首；那時沒有目前那首是 null。
  final int? _leftEntryId;

  /// 離開時那首播到哪裡。
  final Duration leftAt;

  /// 回到 [target] 時從哪裡播：是離開的那個佇列位置，就從離開的地方倒退
  /// [rewind]，不早於開頭；是別的位置（離開的那首被移除了）就從頭。
  Duration resumeAt(QueueEntry target, Duration rewind) {
    if (target.id != _leftEntryId) return Duration.zero;
    final at = leftAt - rewind;
    return at.isNegative ? Duration.zero : at;
  }
}
