import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/tracks/now_playing_overlay.dart';

// 曲目清單共用的「正在播放」標示與固定欄寬的時長（ADR 0035 §決定 1，B-01、B-26、B-34）。

/// 正在播的曲目的鍵：完整鍵與分組鍵（同一支影片的分 P 共用，`TrackKey.formatGroup`）。
@immutable
final class PlayingKey {
  const PlayingKey({required this.key, required this.group});

  factory PlayingKey.of(TrackInfo track) => PlayingKey(
    key: track.key,
    group: TrackKey.formatGroup(track.sourceTypeId, track.sourceId),
  );

  final TrackKeyParts key;
  final String group;

  /// [track] 是不是正在播的那一首；[group] 時同一支影片的任何分 P 在播都算
  /// （分 P 群組的標題列、搜尋結果的影片列）。
  bool matches(TrackInfo track, {bool group = false}) => group
      ? this.group == TrackKey.formatGroup(track.sourceTypeId, track.sourceId)
      : key == track.key;

  @override
  bool operator ==(Object other) =>
      other is PlayingKey && other.key == key && other.group == group;

  @override
  int get hashCode => Object.hash(key, group);
}

/// 正在播的曲目（臨時播放中是臨時的那首）；沒有曲目時是 `null`。直播間不是曲目，也是
/// `null`。
final currentTrackKeyProvider = Provider<PlayingKey?>((ref) {
  final track = ref.watch(
    playbackQueueProvider.select((queue) => queue.value?.current),
  );
  return track == null ? null : PlayingKey.of(track);
});

/// [track] 現在是不是正在播；只在這個答案改變時重建。
bool watchIsPlaying(WidgetRef ref, TrackInfo track, {bool group = false}) =>
    ref.watch(
      currentTrackKeyProvider.select(
        (playing) => playing?.matches(track, group: group) ?? false,
      ),
    );

/// 正在播的那一列的曲名樣式：主色、粗體。
TextStyle? playingTitleStyle(BuildContext context, {required bool playing}) =>
    playing
    ? TextStyle(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      )
    : null;

/// 列首的封面；[playing] 時疊 [NowPlayingOverlay]。
class TrackCover extends StatelessWidget {
  const TrackCover({super.key, required this.track, required this.playing});

  final TrackInfo track;
  final bool playing;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ArtworkImage(
        pluginId: track.sourceTypeId,
        artwork: track.artwork,
        size: AppLayout.artworkThumbnail,
      ),
      if (playing) const NowPlayingOverlay(size: AppLayout.artworkThumbnail),
    ],
  );
}

/// 列尾的時長：固定寬度、右對齊，所以後面的「⋯」不隨時長的位數移動。沒有時長是空欄。
class TrackDuration extends StatelessWidget {
  const TrackDuration({super.key, required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AppLayout.trackDurationColumn,
    child: Text(
      duration == null ? '' : formatDuration(duration!),
      textAlign: TextAlign.end,
    ),
  );
}
