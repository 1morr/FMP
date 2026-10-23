import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:fmp/legacy_import/legacy_source_ids.dart';
import 'package:fmp/legacy_import/skip_reason.dart';

/// 舊 B 站曲目是不是單 P（M5 design §5.1、§11 第 12 條）。
///
/// 新 B 站插件對單 P 影片只回兩段鍵（沒有 cid）；舊版播放時卻替每首補上 cid。規則照
/// bilibili 1.10.0 的 `itemsOfMedia`（`bilibili/src/plugin.js`，分 P 數 `pages <= 1` 時
/// 不帶 `cid`、`partIndex`、`parentTitle`；測試 `bilibili/test/import_playlist.test.js`
/// 的 `single part has no cid`）：
/// - `pageCount` ≤ 1；
/// - `pageCount` 空時：`pageNum` 空或 1，而且沒有 `parentTitle`。
bool isBilibiliSinglePart(LegacyTrack track) {
  final pageCount = track.pageCount;
  if (pageCount != null) return pageCount <= 1;
  final pageNum = track.pageNum;
  final parentTitle = track.parentTitle;
  return (pageNum == null || pageNum == 1) &&
      (parentTitle == null || parentTitle.isEmpty);
}

/// 轉換後的曲目鍵（B 站單 P 去 cid，其他照舊版的 `TrackKey.format`）。
TrackKeyParts normalizedKeyOf(LegacyTrack track) => TrackKeyParts(
  sourceTypeId: track.sourceType,
  sourceId: track.sourceId,
  cid: track.sourceType == legacyBilibili && isBilibiliSinglePart(track)
      ? null
      : track.cid,
);

/// 舊版的曲目鍵（歷史、舊歌詞配對的鍵都是這個）。
TrackKeyParts legacyKeyOf(LegacyTrack track) => TrackKeyParts(
  sourceTypeId: track.sourceType,
  sourceId: track.sourceId,
  cid: track.cid,
);

/// 舊 `Track` 表整理出來的對照：舊 `Track.id`、舊鍵 → 轉換後的鍵，以及每個鍵留下的那一列
/// （M5 design §5.1、§5.2）。歌單、佇列、歷史都經它找曲目。
final class LegacyTrackCatalog {
  LegacyTrackCatalog._(
    this._keyById,
    this._rowById,
    this._unknownSourceIds,
    this._keyByLegacyKey,
    this._bilibiliVideos,
    this._singlePartVideos,
    this.winners,
  );

  /// 整理 [tracks]；不認得的音源與同鍵的其他列計進 [tally]。
  factory LegacyTrackCatalog.build(List<LegacyTrack> tracks, Tally tally) {
    final keyById = <int, TrackKeyParts>{};
    final rowById = <int, LegacyTrack>{};
    final unknown = <int>{};
    final keyByLegacyKey = <TrackKeyParts, TrackKeyParts>{};
    final winners = <TrackKeyParts, LegacyTrack>{};
    final bilibiliVideos = <String>{};
    final singlePartVideos = <String>{};
    for (final track in tracks) {
      if (!legacySourceIds.contains(track.sourceType)) {
        unknown.add(track.id);
        tally.skip(SkipReason.unknownSource);
        continue;
      }
      final key = normalizedKeyOf(track);
      keyById[track.id] = key;
      rowById[track.id] = track;
      keyByLegacyKey.putIfAbsent(legacyKeyOf(track), () => key);
      if (track.sourceType == legacyBilibili) {
        bilibiliVideos.add(track.sourceId);
        if (isBilibiliSinglePart(track)) singlePartVideos.add(track.sourceId);
      }
      final current = winners[key];
      // 取最新的一列；時間相同時後面的列（id 較大）贏。
      if (current == null || !_updated(track).isBefore(_updated(current))) {
        winners[key] = track;
      }
      if (current != null) tally.skip(SkipReason.duplicateTrack);
    }
    return LegacyTrackCatalog._(
      keyById,
      rowById,
      unknown,
      keyByLegacyKey,
      bilibiliVideos,
      singlePartVideos,
      winners,
    );
  }

  static DateTime _updated(LegacyTrack track) =>
      track.updatedAt ?? track.createdAt;

  final Map<int, TrackKeyParts> _keyById;
  final Map<int, LegacyTrack> _rowById;
  final Set<int> _unknownSourceIds;
  final Map<TrackKeyParts, TrackKeyParts> _keyByLegacyKey;
  final Set<String> _bilibiliVideos;
  final Set<String> _singlePartVideos;

  /// 轉換後的鍵 → 留下的那一列，依第一次出現的順序。
  final Map<TrackKeyParts, LegacyTrack> winners;

  /// 舊 `Track.id` 對到的鍵；不存在或音源不認得時 `null`。
  TrackKeyParts? keyOfId(int id) => _keyById[id];

  /// 舊 `Track.id` 的那一列（不是同鍵留下的那一列）。
  LegacyTrack? rowOfId(int id) => _rowById[id];

  /// 這個 id 的列存在、但音源不認得。
  bool isUnknownSource(int id) => _unknownSourceIds.contains(id);

  /// 舊鍵（歷史裡的）→ 轉換後的鍵；`Track` 裡沒有時 `null`。
  TrackKeyParts? keyOfLegacyKey(TrackKeyParts legacyKey) =>
      _keyByLegacyKey[legacyKey];

  /// `Track` 裡有這支 B 站影片（任何一列）。
  bool knowsBilibiliVideo(String sourceId) =>
      _bilibiliVideos.contains(sourceId);

  /// `Track` 判定這支 B 站影片是單 P 時，它轉換後的（兩段）鍵；否則 `null`。
  TrackKeyParts? singlePartKeyOf(String sourceId) =>
      _singlePartVideos.contains(sourceId)
      ? TrackKeyParts(sourceTypeId: legacyBilibili, sourceId: sourceId)
      : null;

  bool containsKey(TrackKeyParts key) => winners.containsKey(key);
}

/// 一個 `Track` 列轉成匯入用的 [TrackInfo]。
///
/// `part_index`、`parent_title` 只給分 P 曲目（轉換後的鍵還帶 cid；新版只有分 P 曲目有這兩欄，
/// 單 P 照搬 `pageNum = 1` 會讓顯示標題多出「P1」）。
TrackInfo trackInfoOf(LegacyTrack track, TrackKeyParts key) {
  final isPart = key.cid != null;
  return TrackInfo(
    sourceTypeId: key.sourceTypeId,
    sourceId: key.sourceId,
    cid: key.cid,
    title: track.title,
    uploader: blankToNull(track.artist),
    duration: durationOf(track.durationMs),
    artwork: artworkOf(track.thumbnailUrl),
    partIndex: isPart ? track.pageNum : null,
    parentTitle: isPart ? blankToNull(track.parentTitle) : null,
  );
}

/// 空字串（或只有空白）當成沒有。
String? blankToNull(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

/// 毫秒 → [Duration]；空或負值（資料壞了）是 `null`。
Duration? durationOf(int? milliseconds) =>
    milliseconds == null || milliseconds < 0
    ? null
    : Duration(milliseconds: milliseconds);

/// 單一封面網址 → `[TrackArtwork(url)]`；空字串或不是 `http(s)` 的給空清單（M5 design §5.1）。
///
/// `http` 升級成 `https`：舊版存的 B 站封面多是 `http://i0.hdslb.com/...`，而媒體
/// client 只發 `https`（ADR 0012 §決定 1），不升級的話這些封面永遠是佔位圖。
List<TrackArtwork> artworkOf(String? url) {
  if (url == null) return const [];
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return const [];
  }
  return [
    TrackArtwork(
      url: uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri,
    ),
  ];
}
