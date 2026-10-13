import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';

/// 插件為什麼不能用，給呈現層用（佇列、歷史、提示）。
///
/// 已安裝但被停用的是「音源已停用」，沒有安裝的是「音源未安裝」（ADR 0030 §決定 7、
/// ADR 0014 §決定 8：曲目保留、標示原因）。清單上（已安裝且啟用）的插件，以及清單
/// 還沒載入完時是 `null`：沒有要標示的。
final sourceUnavailableProvider = Provider.family<String?, String>((
  ref,
  pluginId,
) {
  final plugins = ref.watch(pluginRegistryProvider).value;
  if (plugins == null || plugins.containsKey(pluginId)) return null;
  final t = ref.watch(translationsProvider).sources;
  return ref.read(pluginRegistryProvider.notifier).isDisabled(pluginId)
      ? t.disabled
      : t.notInstalled;
});

/// 插件在介面上的名稱，給呈現層用（曲目、提示）。
///
/// 清單上的插件是 manifest 的 `name`；其餘是 [sourceUnavailableProvider] 的原因。
/// 清單還沒載入完時是 `null`，呼叫端自己決定怎麼顯示。
final pluginNameProvider = Provider.family<String?, String>((ref, pluginId) {
  final plugin = ref.watch(pluginRegistryProvider).value?[pluginId];
  return plugin?.manifest.name ??
      ref.watch(sourceUnavailableProvider(pluginId));
});
