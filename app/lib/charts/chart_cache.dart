import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/domain/track_info.dart';

/// 一個榜單：（插件 id, 榜單 id）。
typedef ChartKey = ({String pluginId, String chartId});

/// 一個榜單上次抓到的內容（M4 design §9.1）。
@immutable
final class ChartCacheEntry {
  const ChartCacheEntry({required this.fetchedAt, required this.tracks});

  /// 抓到的時間（UTC），畫面標「更新於 …」。
  final DateTime fetchedAt;

  /// 榜單的曲目，順序是插件給的；可以是空的。
  final List<TrackInfo> tracks;

  @override
  bool operator ==(Object other) =>
      other is ChartCacheEntry &&
      other.fetchedAt == fetchedAt &&
      listEquals(other.tracks, tracks);

  @override
  int get hashCode => Object.hash(fetchedAt, Object.hashAll(tracks));
}

/// 榜單的快取（M4 design §9.1、ADR 0016 §決定 4）：只經 [CacheStore] 讀寫，不碰 `cache.db`
/// 的表（`fmp_layer_imports`）。鍵是 `chart:<pluginId>:<chartId>`，內容是
/// `{fetchedAt, tracks}` 的 JSON，所屬插件記在索引（移除插件時 `CacheStore.removePlugin`
/// 一起刪）。被淘汰或檔案不見了視為沒有快取。
class ChartCache {
  ChartCache(this._store);

  final CacheStore _store;

  static String _key(ChartKey key) => 'chart:${key.pluginId}:${key.chartId}';

  /// 存 [key] 的內容，取代舊的。
  Future<void> write(ChartKey key, ChartCacheEntry entry) => _store.put(
    CacheCategory.chart,
    key.pluginId,
    _key(key),
    Uint8List.fromList(utf8.encode(jsonEncode(_encode(entry)))),
  );

  /// [key] 的內容；沒有、被淘汰、或內容讀不懂都是 `null`。
  Future<ChartCacheEntry?> read(ChartKey key) async {
    final bytes = await _store.get(
      CacheCategory.chart,
      key.pluginId,
      _key(key),
    );
    if (bytes == null) return null;
    try {
      return _decode(jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      // 寫到一半的檔或別的版本的格式：快取可以丟，當成沒有。
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 刪 [key] 的內容（榜單在設定頁停用時，ADR 0016 §決定 4）。
  Future<void> remove(ChartKey key) =>
      _store.remove(CacheCategory.chart, key.pluginId, key: _key(key));

  /// 刪 [pluginId] 的全部榜單內容（插件停用時）。
  Future<void> removePlugin(String pluginId) =>
      _store.remove(CacheCategory.chart, pluginId);

  static Map<String, Object?> _encode(ChartCacheEntry entry) => {
    'fetchedAt': entry.fetchedAt.millisecondsSinceEpoch,
    'tracks': [for (final track in entry.tracks) _encodeTrack(track)],
  };

  static Map<String, Object?> _encodeTrack(TrackInfo track) => {
    'sourceTypeId': track.sourceTypeId,
    'sourceId': track.sourceId,
    'cid': track.cid,
    'title': track.title,
    'uploader': track.uploader,
    'durationMs': track.duration?.inMilliseconds,
    'artwork': [
      for (final image in track.artwork)
        {'url': image.url.toString(), 'width': image.width},
    ],
    'partIndex': track.partIndex,
    'parentTitle': track.parentTitle,
  };

  static ChartCacheEntry _decode(Object? json) {
    final map = json! as Map<String, Object?>;
    return ChartCacheEntry(
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        map['fetchedAt']! as int,
        isUtc: true,
      ),
      tracks: List.unmodifiable([
        for (final track in map['tracks']! as List<Object?>)
          _decodeTrack(track! as Map<String, Object?>),
      ]),
    );
  }

  static TrackInfo _decodeTrack(Map<String, Object?> map) => TrackInfo(
    sourceTypeId: map['sourceTypeId']! as String,
    sourceId: map['sourceId']! as String,
    cid: map['cid'] as int?,
    title: map['title']! as String,
    uploader: map['uploader'] as String?,
    duration: switch (map['durationMs']) {
      final int milliseconds => Duration(milliseconds: milliseconds),
      _ => null,
    },
    artwork: List.unmodifiable([
      for (final image in map['artwork']! as List<Object?>)
        TrackArtwork(
          url: Uri.parse((image! as Map<String, Object?>)['url']! as String),
          width: (image as Map<String, Object?>)['width'] as int?,
        ),
    ]),
    partIndex: map['partIndex'] as int?,
    parentTitle: map['parentTitle'] as String?,
  );
}

/// 榜單快取。快取庫開不起來是 `AsyncError`（`cacheStoreProvider` 已記過 error）。
final chartCacheProvider = FutureProvider<ChartCache>(
  (ref) async => ChartCache(await ref.watch(cacheStoreProvider.future)),
);

/// 榜單快取每寫入或刪除一次加一：讀快取的 provider 監看它，工作寫了之後跟著重讀。
final chartCacheRevisionProvider = NotifierProvider<ChartCacheRevision, int>(
  ChartCacheRevision.new,
);

final class ChartCacheRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// 一個榜單的快取內容（沒有或被淘汰是 `null`），給首頁與探索頁用（M4 PR 21）。
final chartContentProvider = FutureProvider.autoDispose
    .family<ChartCacheEntry?, ChartKey>((ref, key) async {
      ref.watch(chartCacheRevisionProvider);
      return (await ref.watch(chartCacheProvider.future)).read(key);
    });
