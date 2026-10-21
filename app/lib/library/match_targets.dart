import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 一個可以當匹配目標的音源（M4 design §8.3）：已啟用、同時宣告 `search` 與 `resolveStream`。
/// [enabled] 是設定（`source_settings.match_target`，空＝是目標）。
@immutable
final class MatchTargetOption {
  const MatchTargetOption({required this.plugin, required this.enabled});

  final SourcePlugin plugin;
  final bool enabled;

  String get pluginId => plugin.manifest.id;

  @override
  bool operator ==(Object other) =>
      other is MatchTargetOption &&
      identical(other.plugin, plugin) &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(plugin, enabled);
}

/// [plugin] 能不能當匹配目標：搜得到、也播得了。
bool canBeMatchTarget(SourcePlugin plugin) {
  final capabilities = plugin.manifest.capabilities;
  return capabilities.contains(PluginCapability.search) &&
      capabilities.contains(PluginCapability.resolveStream);
}

/// 可以當匹配目標的音源（[plugins] 是插件清單，依它的順序），照設定排好：`match_rank` 由小到大，
/// 沒有的排在後面、依插件清單（ADR 0014 §決定 9）。停用的（`match_target = false`）也在裡面，
/// [MatchTargetOption.enabled] 為假。
List<MatchTargetOption> matchTargetOptions(
  Iterable<SourcePlugin> plugins,
  Iterable<MatchTargetSetting> settings,
) {
  final byId = {for (final setting in settings) setting.pluginId: setting};
  final eligible = [
    for (final (index, plugin) in plugins.where(canBeMatchTarget).indexed)
      (index: index, plugin: plugin, setting: byId[plugin.manifest.id]),
  ];
  eligible.sort((a, b) {
    final rankA = a.setting?.rank;
    final rankB = b.setting?.rank;
    if (rankA != null && rankB != null && rankA != rankB) {
      return rankA.compareTo(rankB);
    }
    if (rankA != null && rankB == null) return -1;
    if (rankA == null && rankB != null) return 1;
    return a.index.compareTo(b.index);
  });
  return [
    for (final entry in eligible)
      MatchTargetOption(
        plugin: entry.plugin,
        enabled: entry.setting?.target ?? true,
      ),
  ];
}

/// `source_settings` 的匹配兩欄，跟著寫入更新。
final matchTargetSettingsProvider = StreamProvider<List<MatchTargetSetting>>(
  (ref) => ref.watch(sourceSettingsRepositoryProvider).watchMatchTargets(),
);

/// 設定頁「匹配目標音源」的清單：[matchTargetOptions] 跟著插件清單與設定；插件清單或設定還在讀
/// 時是 `null`。只在使用者打開那一區時才被讀：它會把插件清單拉起來，一直掛在外殼裡的頁面不要
/// watch 它（理由見 `app/AGENTS.md` § 排行的「給畫面的榜單清單」）。
final matchTargetOptionsProvider = Provider<List<MatchTargetOption>?>((ref) {
  final plugins = ref.watch(pluginRegistryProvider).value;
  final settings = ref.watch(matchTargetSettingsProvider).value;
  if (plugins == null || settings == null) return null;
  return matchTargetOptions(plugins.values, settings);
});
