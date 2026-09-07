/// 曲目識別鍵的唯一實作。
///
/// 這個字串**是持久化格式的一部分**，不只是個內部識別碼：
///
/// - `Track.sourcePageKey` 用它當 Isar 複合索引的鍵，而 Isar 只在 `put` 時重算
///   索引項 —— 改動字面輸出會讓既有列的索引項與新查詢對不上，而且不會有錯誤。
/// - `TrackBackup.uniqueKey` / `PlayHistoryBackup.trackKey` 用它當備份 JSON 裡的
///   外鍵，匯入時靠它把播放歷史接回曲目。改動它會讓既有備份檔匯不回來。
///
/// 所以 `test/data/models/track_key_test.dart` 用寫死的字面值把輸出釘住。
///
/// **它以 `cid` 區分分 P，不是 `pageNum`。** 需要用 pageNum 區分的地方
/// （串流解析的行程內快取）自己在後面接 pageNum，見
/// `stream_resolution_service.dart`。
class TrackKey {
  const TrackKey._();

  /// 完整識別鍵：有 cid 就是三段式，否則兩段式。
  static String format(String sourceTypeId, String sourceId, {int? cid}) =>
      cid != null ? '$sourceTypeId:$sourceId:$cid' : '$sourceTypeId:$sourceId';

  /// 分組鍵：同一支影片的所有分 P 共用它。
  static String formatGroup(String sourceTypeId, String sourceId) =>
      '$sourceTypeId:$sourceId';

  /// 把 [format] 產生的鍵拆回來；格式不符時回傳 null。
  ///
  /// 備份匯入是唯一需要反向解析的路徑，而它同時也是讓
  /// 「format/parse 來回一致」這件事可以被測試的原因。
  static TrackKeyParts? tryParse(String raw) {
    final parts = raw.split(':');
    if (parts.length == 2) {
      if (parts[0].isEmpty || parts[1].isEmpty) return null;
      return TrackKeyParts(sourceTypeId: parts[0], sourceId: parts[1]);
    }
    if (parts.length == 3) {
      final cid = int.tryParse(parts[2]);
      if (cid == null || parts[0].isEmpty || parts[1].isEmpty) return null;
      return TrackKeyParts(
        sourceTypeId: parts[0],
        sourceId: parts[1],
        cid: cid,
      );
    }
    return null;
  }
}

/// [TrackKey.tryParse] 的結果。
class TrackKeyParts {
  const TrackKeyParts({
    required this.sourceTypeId,
    required this.sourceId,
    this.cid,
  });

  final String sourceTypeId;
  final String sourceId;
  final int? cid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackKeyParts &&
          other.sourceTypeId == sourceTypeId &&
          other.sourceId == sourceId &&
          other.cid == cid;

  @override
  int get hashCode => Object.hash(sourceTypeId, sourceId, cid);

  @override
  String toString() => TrackKey.format(sourceTypeId, sourceId, cid: cid);
}
