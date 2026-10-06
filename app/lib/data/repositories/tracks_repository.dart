import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/domain/track_info.dart';

/// `tracks` 表的存取（design §3.1）：佇列（與之後的播放歷史）參照的曲目顯示資料。
final class TracksRepository {
  TracksRepository(this._database);

  final AppDatabase _database;

  /// 寫入 [tracks]：同鍵以新值覆蓋（音源是權威，ADR 0019 §決定 2 同一方向）。
  /// 用 `ON CONFLICT DO UPDATE`，不用 REPLACE：REPLACE 會先刪列，被參照的列會
  /// 因為 `RESTRICT` 失敗。
  Future<void> upsert(Iterable<TrackInfo> tracks) {
    final now = clock.now().toUtc();
    final rows = [
      for (final track in tracks)
        TracksTableCompanion.insert(
          trackKey: '${track.key}',
          sourceTypeId: track.sourceTypeId,
          sourceId: track.sourceId,
          cid: Value(track.cid),
          title: track.title,
          uploader: Value(track.uploader),
          durationMs: Value(track.duration?.inMilliseconds),
          artworkJson: Value(encodeArtwork(track.artwork)),
          updatedAt: now,
        ),
    ];
    if (rows.isEmpty) return Future.value();
    return _database.batch(
      (batch) => batch.insertAllOnConflictUpdate(_database.tracksTable, rows),
    );
  }

  /// 刪掉沒有被任何東西參照的曲目，回傳刪了幾列（ADR 0019 §決定 1，啟動維護
  /// 清單呼叫）。目前的參照者只有 `queue_entries`；播放歷史（M2 PR 15）、歌單項目
  /// （M4）、下載紀錄（M6）各自在它們加表的 PR 加進這個查詢。
  Future<int> deleteOrphans() => _database.customUpdate(
    'DELETE FROM tracks WHERE track_key NOT IN '
    '(SELECT track_key FROM queue_entries)',
    updates: {_database.tracksTable},
    updateKind: UpdateKind.delete,
  );

  /// 曲目的封面存成 `[{url, width?}]`（ADR 0016 §決定 4 的 DTO 原樣）；沒有封面
  /// 存 `NULL`。
  static String? encodeArtwork(List<TrackArtwork> artwork) => artwork.isEmpty
      ? null
      : jsonEncode([
          for (final item in artwork)
            {'url': item.url.toString(), 'width': ?item.width},
        ]);

  static List<TrackArtwork> decodeArtwork(String? json) {
    if (json == null) return const [];
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      throw FormatException('Artwork is not a list in the database', json);
    }
    return [
      for (final item in decoded)
        if (item case {'url': final String url})
          TrackArtwork(
            url: Uri.parse(url),
            width: switch (item['width']) {
              final int width => width,
              _ => null,
            },
          )
        else
          throw FormatException('Unknown artwork in the database', json),
    ];
  }
}
