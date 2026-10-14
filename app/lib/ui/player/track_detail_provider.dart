import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/domain/track_key.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 曲目詳細的記憶體快取筆數（M3 design §11.2）。
const trackDetailCacheSize = 32;

/// 曲目詳細的記憶體 LRU：最近用到的 [capacity] 筆，不持久化。
final class TrackDetailCache {
  TrackDetailCache({this.capacity = trackDetailCacheSize});

  final int capacity;

  // LinkedHashMap：迭代順序是插入順序，最舊的在最前面。
  final _entries = <String, TrackDetail>{};

  /// 命中時把它標成最近用過。
  TrackDetail? get(String key) {
    final detail = _entries.remove(key);
    if (detail != null) _entries[key] = detail;
    return detail;
  }

  void put(String key, TrackDetail detail) {
    _entries.remove(key);
    _entries[key] = detail;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }
}

final trackDetailCacheProvider = Provider<TrackDetailCache>(
  (ref) => TrackDetailCache(),
);

/// [plugin] 宣告了 `trackDetail`（詳細區先看這個）。
bool declaresTrackDetail(SourcePlugin? plugin) =>
    plugin?.manifest.capabilities.contains(PluginCapability.trackDetail) ??
    false;

/// [track] 的詳細資料：每首第一次顯示時呼叫一次插件，之後讀 [TrackDetailCache]。
/// 插件沒宣告 `trackDetail`（或還沒載入）是 `null`；失敗是 `AsyncError`，重試是
/// `ref.invalidate`。
///
/// - 快取命中時同步回傳（不經 `async`），第一格就是資料，不閃一下佔位。
/// - 請求進行中時 `keepAlive`：使用者在回應之前切走分頁、收起面板再回來，接上同一個
///   請求，不再呼叫一次；結束後放開，autoDispose 照常（失敗不留，下次顯示再取）。
final trackDetailProvider = FutureProvider.autoDispose
    .family<TrackDetail?, TrackKeyParts>((ref, track) {
      final plugin = ref.watch(
        pluginRegistryProvider.select(
          (plugins) => plugins.value?[track.sourceTypeId],
        ),
      );
      if (plugin == null || !declaresTrackDetail(plugin)) return null;
      final cache = ref.watch(trackDetailCacheProvider);
      final key = track.toString();
      final cached = cache.get(key);
      if (cached != null) return cached;
      final link = ref.keepAlive();
      return plugin
          .trackDetail(
            TrackDetailQuery(sourceId: track.sourceId, cid: track.cid),
          )
          .then((detail) {
            cache.put(key, detail);
            return detail;
          })
          .whenComplete(link.close);
    });
