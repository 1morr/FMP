import 'package:flutter/services.dart';
import 'package:fmp/plugins/src/plugin_host.dart';

/// 隨 App 打包的插件：資產裡每個 `plugins/<id>/manifest.json` 配同目錄的
/// `dist/plugin.js`（`pubspec.yaml` 的 `assets` 列出，`test/plugins/
/// plugin_assets_test.dart` 守著每個插件目錄都有列）。依 id 排序。
Future<List<PluginBundle>> loadBundledPlugins(AssetBundle assets) async {
  final manifest = await AssetManifest.loadFromAssetBundle(assets);
  final manifests = manifest.listAssets().where(_manifestPath.hasMatch).toList()
    ..sort();
  return [
    for (final path in manifests)
      PluginBundle(
        manifest: await assets.loadString(path),
        code: await assets.loadString(
          path.replaceFirst(_manifestFile, 'dist/plugin.js'),
        ),
      ),
  ];
}

final _manifestPath = RegExp(r'^plugins/[a-z0-9_-]+/manifest\.json$');
final _manifestFile = RegExp(r'manifest\.json$');
