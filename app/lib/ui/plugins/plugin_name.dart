import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';

/// 插件在介面上的名稱，給呈現層用（曲目、提示）。
///
/// 清單上的插件是 manifest 的 `name`；已安裝但被停用的是「音源已停用」，沒有安裝
/// 的是「音源未安裝」（ADR 0030 §決定 7、ADR 0014 §決定 8：曲目保留、標示原因）。
/// 清單還沒載入完時是 `null`，呼叫端自己決定怎麼顯示。
final pluginNameProvider = Provider.family<String?, String>((ref, pluginId) {
  final plugins = ref.watch(pluginRegistryProvider).value;
  if (plugins == null) return null;
  final plugin = plugins[pluginId];
  if (plugin != null) return plugin.manifest.name;
  final t = ref.watch(translationsProvider).sources;
  return ref.read(pluginRegistryProvider.notifier).isDisabled(pluginId)
      ? t.disabled
      : t.notInstalled;
});
