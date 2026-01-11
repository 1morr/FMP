import '../../../data/models/track.dart';

/// 分组数据类
/// 用于将多P视频的各个分P组织在一起
class TrackGroup {
  /// 分组的唯一标识（通常是视频的bvid）
  final String groupKey;

  /// 该组下的所有歌曲/分P
  final List<Track> tracks;

  /// 父视频的标题
  final String parentTitle;

  TrackGroup({
    required this.groupKey,
    required this.tracks,
    required this.parentTitle,
  });

  /// 该组的第一首歌曲
  Track get firstTrack => tracks.first;

  /// 该组是否包含多个分P
  bool get hasMultipleParts => tracks.length > 1;

  /// 分P数量
  int get partCount => tracks.length;
}

/// 将 tracks 按 groupKey 分组
///
/// 返回按原始顺序排列的分组列表，每个分组内的 tracks 按 pageNum 排序
List<TrackGroup> groupTracks(List<Track> tracks) {
  final Map<String, List<Track>> grouped = {};
  final List<String> order = [];

  for (final track in tracks) {
    final key = track.groupKey;
    if (!grouped.containsKey(key)) {
      grouped[key] = [];
      order.add(key);
    }
    grouped[key]!.add(track);
  }

  return order.map((key) {
    final groupTracks = grouped[key]!;
    // 按 pageNum 排序
    groupTracks.sort((a, b) => (a.pageNum ?? 0).compareTo(b.pageNum ?? 0));
    return TrackGroup(
      groupKey: key,
      tracks: groupTracks,
      parentTitle: groupTracks.first.parentTitle ?? groupTracks.first.title,
    );
  }).toList();
}
