import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/plugins/src/bundled_plugins.dart';
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
