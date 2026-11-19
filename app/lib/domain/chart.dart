import 'package:fmp/domain/track.dart';

/// 一份排行榜（`GLOSSARY.md`〈排行榜〉）：依名次的曲目，和抓到它的時間。
class Chart {
  const Chart({required this.tracks, required this.fetchedAt});

  /// 依名次，第一個是第 1 名。
  final List<Track> tracks;

  final DateTime fetchedAt;
}
