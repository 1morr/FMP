import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// App 根元件。目前只顯示 App 名稱、flavor、資料目錄與載入的插件，供實機確認
/// 身分與插件的開發入口；正式的外殼在 M1 PR 12。
class FmpApp extends StatelessWidget {
  const FmpApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: flavor.displayName,
      home: _IdentityPage(flavor: flavor),
    );
  }
}

class _IdentityPage extends ConsumerWidget {
  const _IdentityPage({required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              flavor.displayName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(flavor.name),
            SelectableText(ref.watch(dataDirectoryProvider).path),
            const _PluginList(),
          ],
        ),
      ),
    );
  }
}

/// 載入的插件（`id version`，沒有回應的加註），以及開發入口安裝失敗時的錯誤類別。
class _PluginList extends ConsumerWidget {
  const _PluginList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final install = ref.watch(devPluginInstallProvider);
    final plugins = ref.watch(pluginRegistryProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (install case AsyncError(error: final AppError error))
          Text('Dev plugin: ${error.typeName}'),
        ...switch (plugins) {
          AsyncData(:final value) => [
            for (final plugin in value.values)
              Text(
                '${plugin.manifest.id} ${plugin.manifest.version}'
                '${plugin.health == PluginHealth.unresponsive ? ' (unresponsive)' : ''}',
              ),
          ],
          AsyncError(:final error) => [Text('Plugins: $error')],
          _ => const <Widget>[],
        },
      ],
    );
  }
}
