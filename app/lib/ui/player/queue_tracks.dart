import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/plugins/source_dto.dart';

/// 佇列裡每首曲目的顯示資料（曲名、上傳者、封面），鍵是 [trackKeyOf]。
///
/// 開始播放的畫面把手上的 [TrackSummary] 放在這裡，播放列以鍵查。佇列的項目
/// 已經帶著顯示資料（`QueueEntry`），播放列改讀它之後這裡就刪掉（M2）。
/// 每次播放一份新的清單就整份換掉，不會一直長大。
final queueTracksProvider =
    NotifierProvider<QueueTracks, Map<String, TrackSummary>>(QueueTracks.new);

final class QueueTracks extends Notifier<Map<String, TrackSummary>> {
  @override
  Map<String, TrackSummary> build() => const {};

  void replace(List<TrackSummary> tracks) => state = Map.unmodifiable({
    for (final track in tracks) trackKeyOf(track): track,
  });
}

/// [track] 的曲目鍵（`TrackKey.format`）。
String trackKeyOf(TrackSummary track) =>
    TrackKey.format(track.sourceTypeId, track.sourceId, cid: track.cid);

/// 把整份 [tracks] 交給 `PlaybackController`（UI 唯一的播放入口），從第
/// [index] 首開始依序播放。
Future<void> playTracks(WidgetRef ref, List<TrackSummary> tracks, int index) {
  ref.read(queueTracksProvider.notifier).replace(tracks);
  return ref.read(playbackControllerProvider).playQueue([
    for (final track in tracks) track.toTrackInfo(),
  ], startIndex: index);
}
