import 'package:fmp/data/import/import_summary.dart';

/// 轉換時一筆資料沒有（照原樣）寫進匯入包的理由，或值得在結果裡提一下的註記
/// （M5 design §5）。
///
/// 序列化成 [name]（英文識別字，結果對話框依它查翻譯；改名等於改 `summary_json` 的
/// 內容）。
enum SkipReason {
  /// 舊 `sourceType`／`platform` 不是 `bilibili`、`youtube`、`netease`。
  unknownSource,

  /// 曲目沒有被任何歌單、佇列、播放歷史參照（寫了會被當孤兒）。
  unreferenced,

  /// 同一個曲目鍵（B 站單 P 去 cid 之後）的另一列，只留最新的。
  duplicateTrack,

  /// 歌單、佇列的項目指到不存在的 `Track.id`。
  danglingTrackId,

  /// Mix 歌單沒有種子影片。
  mixWithoutSeed,

  /// 播放歷史超過換算後的保留筆數。
  overHistoryLimit,

  /// （插件, 房間）與先前一筆電台重複。
  duplicateStation,

  /// `originalSource` 是 `spotify`，或 `originalSongId` 的格式與新插件的 `sourceId` 不同。
  originIdFormat,

  /// 舊帳號列與憑證裡都找不到使用者 id（`accounts.user_id` 不可空），不匯入該平台。
  accountWithoutId,

  // 以下是註記：該筆資料有寫進匯入包，只是值得提一下，不計入「略過」。

  /// 歌單有網址卻認不出來，轉成本機歌單。
  remoteNotRecognized,

  /// 歌單的（插件, 遠端 id）與先前一張重複，轉成本機歌單。
  duplicateRemote,

  /// 歌單的 `importSourceType` 與網址辨識出的插件不同，以網址為準。
  importSourceMismatch,

  /// 播放歷史裡的 B 站分 P 鍵在 `Track` 裡找不到，沒辦法判斷是不是單 P，照原樣。
  unverifiedPart;

  /// 這個理由是不是「略過」：真正略過的進 `CollectionSummary.skipped`，註記進 `notes`。
  bool get isSkip => switch (this) {
    remoteNotRecognized ||
    duplicateRemote ||
    importSourceMismatch ||
    unverifiedPart => false,
    _ => true,
  };
}

/// 一個 collection 的計數，轉成 [CollectionSummary]。
final class Tally {
  int read = 0;
  int written = 0;
  final Map<SkipReason, int> _skipped = {};
  final Map<SkipReason, int> _notes = {};

  void skip(SkipReason reason, [int count = 1]) {
    assert(reason.isSkip, '$reason is a note, not a skip');
    _skipped.update(reason, (n) => n + count, ifAbsent: () => count);
  }

  void note(SkipReason reason, [int count = 1]) {
    assert(!reason.isSkip, '$reason is a skip, not a note');
    _notes.update(reason, (n) => n + count, ifAbsent: () => count);
  }

  CollectionSummary toSummary() => CollectionSummary(
    read: read,
    written: written,
    skipped: {for (final e in _skipped.entries) e.key.name: e.value},
    notes: {for (final e in _notes.entries) e.key.name: e.value},
  );
}
