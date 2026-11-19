/// 曲目資訊（`GLOSSARY.md`）：插件能力 `trackInfo` 給的一首曲目的詳細資料
/// （ADR 0039）。每個欄位都選填，插件給不了是 null，畫面就不顯示那一列。
/// 時長、網址、作者、封面在 `Track` 上，不在這裡。
class TrackInfo {
  const TrackInfo({
    this.album,
    this.publishedAt,
    this.playCount,
    this.likeCount,
    this.commentCount,
    this.description,
  });

  /// 專輯名稱。
  final String? album;

  /// 發佈時間（UTC）。
  final DateTime? publishedAt;

  /// 播放數。
  final int? playCount;

  /// 點讚數。
  final int? likeCount;

  /// 評論數。
  final int? commentCount;

  /// 簡介；可以有多行。
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is TrackInfo &&
      other.album == album &&
      other.publishedAt == publishedAt &&
      other.playCount == playCount &&
      other.likeCount == likeCount &&
      other.commentCount == commentCount &&
      other.description == description;

  @override
  int get hashCode => Object.hash(
    album,
    publishedAt,
    playCount,
    likeCount,
    commentCount,
    description,
  );

  @override
  String toString() =>
      'TrackInfo($album, $publishedAt, $playCount, $likeCount, $commentCount, '
      '${description?.length} chars)';
}
