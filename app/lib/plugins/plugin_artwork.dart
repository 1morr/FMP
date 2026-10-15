import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// [pluginId] 的封面 cache manager（ADR 0016 §決定 4、design §4.3）：統一快取庫
/// 加上那個插件的媒體 client，下載時每跳以那個插件的允許網域檢查，索引記在它
/// 名下。
///
/// 快取庫還沒開好或開不起來、插件不在清單上時是 `null`（封面顯示佔位圖）。插件
/// 更新後清單裡換成新的插件實例，這裡跟著重建、拿到新的媒體 client；其他插件的
/// 變動不會重建它。
final artworkCacheManagerProvider = Provider.family<BaseCacheManager?, String>((
  ref,
  pluginId,
) {
  final store = ref.watch(cacheStoreProvider).value;
  if (store == null) return null;
  // 媒體 client 在插件加入清單時（發出新清單之前）就換好了。
  ref.watch(
    pluginRegistryProvider.select((plugins) => plugins.value?[pluginId]),
  );
  final media = ref.read(pluginRegistryProvider.notifier).mediaClient(pluginId);
  if (media == null) return null;
  final manager = FmpImageCacheManager(
    store: store,
    pluginId: pluginId,
    media: media,
  );
  ref.onDispose(() => unawaited(manager.dispose()));
  return manager;
});

/// 不屬於某個曲目的封面網址（歌單的自訂封面，M4 design §10.5）該經哪個插件的媒體 client
/// 讀：清單上（已安裝且啟用）第一個允許網域包含它的插件（[pluginForArtwork]）；沒有就是
/// `null`，封面顯示佔位圖。宿主沒有任意網址的讀取路徑（ADR 0012 §決定 1）。沒人看就放開：
/// 以網址為鍵，對話框的預覽每打出一個新網址就是一份。
final artworkPluginProvider = Provider.autoDispose.family<String?, Uri>(
  (ref, url) => switch (ref.watch(pluginRegistryProvider).value) {
    final plugins? => pluginForArtwork(plugins.values, url),
    null => null,
  },
);

/// [plugins] 裡第一個允許網域包含 [url] 的插件 id（只收 `https`，規則同媒體 client 的每跳
/// 檢查，`AllowedHosts.allows`）；都不包含是 `null`。帶 user info 的網址也是 `null`：媒體
/// client 一律不發（會變成 `Authorization` header），收下的話封面永遠是佔位圖。
String? pluginForArtwork(Iterable<SourcePlugin> plugins, Uri url) {
  if (url.userInfo.isNotEmpty) return null;
  for (final plugin in plugins) {
    if (AllowedHosts(plugin.manifest.allowedHosts).allows(url)) {
      return plugin.manifest.id;
    }
  }
  return null;
}
