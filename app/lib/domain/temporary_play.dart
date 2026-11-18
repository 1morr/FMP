import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';

/// 臨時播放（`GLOSSARY.md`）：在佇列之外播的那首，與離開佇列時停在哪裡。
///
/// 回到的是佇列的目前那首（`playback/` 決定什麼時候回去）：臨時播放時佇列
/// 照常能拖動、移除，目前那首換了就回到換上來的那首。離開時的位置只屬於
/// 離開的那個佇列位置（[QueueEntry.id]），回到別首就從頭播。
class TemporaryPlay {
  const TemporaryPlay._(this.track, this._leftEntryId, this.leftAt);

  /// 臨時播放 [track]。從佇列離開時記下目前那首 [leaving] 與它播到的
  /// [position]；已在臨時播放中（[previous] 不是 null）時只換曲目，保留最早
  /// 那個佇列位置。
  factory TemporaryPlay.start(
    Track track, {
    required TemporaryPlay? previous,
    required QueueEntry? leaving,
    required Duration position,
  }) => previous != null
      ? TemporaryPlay._(track, previous._leftEntryId, previous.leftAt)
      : TemporaryPlay._(
          track,
          leaving?.id,
          leaving == null ? Duration.zero : position,
        );

  /// 在佇列之外播的曲目。
  final Track track;

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
