import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/accounts/accounts_state.dart';
import 'package:fmp/ui/library/library_state.dart';

// 遠端寫入的入口條件（M4 design §7.1、§7.2、§10.6、§10.7；ADR 0019 §決定 4）。

/// 現在能寫遠端歌單的插件 id：在插件清單上（已啟用）、宣告 `libraryWrite`、`CredentialState`
/// 是 `active`（登入過而且憑證沒被拒絕）。插件清單或憑證變動就重算。
final remoteWritablePluginsProvider = Provider.autoDispose<Set<String>>((ref) {
  final plugins = ref.watch(pluginRegistryProvider).value ?? const {};
  return {
    for (final plugin in plugins.values)
      if (plugin.manifest.capabilities.contains(PluginCapability.libraryWrite))
        if (ref.watch(accountViewProvider(plugin.manifest.id)).value?.state ==
            CredentialState.active)
          plugin.manifest.id,
  };
});

/// 「加入遠端歌單…」這一項的狀態。
enum RemoteAddEntry {
  /// 不出現：曲目所屬的插件不能寫遠端（沒宣告、停用、沒登入）。
  hidden,

  /// 出現但停用，並說明：選了不同音源的曲目（一次只能加進一個音源的帳號）。
  mixedSources,

  /// 可以按。
  available,
}

/// [trackPluginIds] 是要加入的曲目所屬的插件 id（單首就一個），[writable] 是
/// [remoteWritablePluginsProvider]。全部屬於同一個能寫的插件才是 [RemoteAddEntry.available]；
/// 屬於好幾個插件而且至少一個能寫是 [RemoteAddEntry.mixedSources]（停用並說明）；一個都不能寫
/// 就不出現。
RemoteAddEntry remoteAddEntryFor(
  Set<String> writable,
  Iterable<String> trackPluginIds,
) {
  final ids = trackPluginIds.toSet();
  if (ids.isEmpty || ids.intersection(writable).isEmpty) {
    return RemoteAddEntry.hidden;
  }
  if (ids.length > 1) return RemoteAddEntry.mixedSources;
  return RemoteAddEntry.available;
}

/// 匯入歌單 [playlistId]（本地 id）詳情裡「從遠端歌單移除」能不能出現：這張是匯入歌單、
/// `playlist_remote.writable`、它的插件現在能寫（[remoteWritablePluginsProvider]）。
final remoteRemoveEntryProvider = Provider.autoDispose.family<bool, int>((
  ref,
  playlistId,
) {
  final remote = ref.watch(playlistDetailProvider(playlistId)).value?.remote;
  if (remote == null || !remote.writable) return false;
  return ref.watch(remoteWritablePluginsProvider).contains(remote.pluginId);
});
