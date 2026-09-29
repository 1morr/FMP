/// 曲目識別鍵的唯一實作（ADR 0005）。
///
/// 這個字串**是持久化格式的一部分**，不只是個內部識別碼：
///
/// - 新資料庫以它當曲目的唯一鍵（ADR 0010 §決定 2）。
/// - 舊版把同一個字串存在 Isar 的複合索引與備份 JSON 的外鍵裡；M5 匯入舊資料
///   （`lib/legacy_import/`）靠逐字相同的鍵把歌單、播放歷史接回曲目。
///
/// 格式與行為照舊版 `lib/data/models/track_key.dart` 原樣搬來（ADR 0008 檔頭
/// 補充：葉節點照搬），`test/domain/track_key_test.dart` 用寫死的字面值把輸出
/// 釘住。改動字面輸出等於改資料格式，要另立 ADR 並寫 migration。
///
/// **它以 `cid` 區分分 P，不是 `pageNum`。** 需要用 pageNum 區分的地方（例如
/// 串流解析的行程內快取）自己在後面接 pageNum。
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
  /// 匯入舊備份是需要反向解析的路徑，而它同時也讓「format/parse 來回一致」
  /// 這件事可以被測試。
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
