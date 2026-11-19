import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/src/bundled_plugins.dart';
import 'package:fmp/plugins/src/manifest.dart';
import 'package:fmp/plugins/src/plugin_host.dart';

/// App 的插件宿主，載入隨 App 打包的插件（[loadBundledPlugins]）。第一次
/// 讀時才建；引擎在插件第一次被呼叫時才建。測試 override 成自己的宿主。
final pluginHostProvider = FutureProvider<PluginHost>((ref) async {
  final host = PluginHost(
    bundles: await loadBundledPlugins(rootBundle),
    log: ref.watch(logProvider),
  );
  ref.onDispose(host.close);
  return host;
});

/// id 是 `pluginId` 的插件的 manifest，畫面用它畫音源標識與音源名稱。宿主還沒
/// 載入完、或沒有這個插件時是 null。
final pluginManifestProvider = Provider.family<PluginManifest?, String>(
  (ref, pluginId) => ref
      .watch(pluginHostProvider)
      .value
      ?.plugins
      .where((p) => p.manifest.id == pluginId)
      .firstOrNull
      ?.manifest,
);

/// `track` 這首曲目的曲目資訊（插件能力 `trackInfo`，ADR 0039）。插件沒宣告
/// 這個能力（或沒載入）時是 null，不發請求；失敗時是插件丟的 `AppError`。
///
/// 只在記憶體（ARCHITECTURE〈快取〉）：同一首在這次開 App 期間只查一次，
/// 重試要 invalidate 它。
final trackInfoProvider = FutureProvider.family<TrackInfo?, TrackRef>((
  ref,
  track,
) async {
  final host = await ref.watch(pluginHostProvider.future);
  final plugin = host.pluginFor(track);
  if (plugin == null ||
      !plugin.manifest.capabilities.contains(PluginCapability.trackInfo)) {
    return null;
  }
  return plugin.trackInfo(track);
});
