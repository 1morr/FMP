import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/plugins/plugin_registry.dart';

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
