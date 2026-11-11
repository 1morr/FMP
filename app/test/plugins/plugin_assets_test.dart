import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/plugins/src/bundled_plugins.dart';

/// `app/plugins/` 底下每個插件（有 `manifest.json` 的目錄）都要打包進 App：
/// `pubspec.yaml` 的 `assets` 列出它的 manifest 與 `dist/plugin.js`。漏列時
/// App 裡就少一個插件，不會報錯，所以由這裡守。
void main() {
  List<String> pluginIds() => [
    for (final dir in Directory('plugins').listSync().whereType<Directory>())
      if (File('${dir.path}/manifest.json').existsSync())
        dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ]..sort();

  test('every plugin directory is bundled as an asset', () async {
    final ids = pluginIds();
    expect(ids, contains('bilibili'));
    final assets = (await AssetManifest.loadFromAssetBundle(rootBundle))
        .listAssets()
        .toSet();
    expect(missingPluginAssets(assets, ids), isEmpty);
  });

  test('loadBundledPlugins reads each manifest with its bundle', () async {
    final bundles = await loadBundledPlugins(rootBundle);
    expect(bundles, hasLength(pluginIds().length));
    for (final (i, id) in pluginIds().indexed) {
      expect(
        bundles[i].manifest,
        File('plugins/$id/manifest.json').readAsStringSync(),
      );
      expect(
        bundles[i].code,
        File('plugins/$id/dist/plugin.js').readAsStringSync(),
      );
    }
  });

  group('missingPluginAssets', () {
    const complete = {
      'plugins/a/manifest.json',
      'plugins/a/dist/plugin.js',
      'plugins/b/manifest.json',
      'plugins/b/dist/plugin.js',
    };

    test('turns red when a manifest or a bundle is not listed', () {
      expect(
        missingPluginAssets(complete.difference({'plugins/b/dist/plugin.js'}), [
          'a',
          'b',
        ]),
        ['plugins/b/dist/plugin.js'],
      );
      expect(
        missingPluginAssets(complete.difference({'plugins/a/manifest.json'}), [
          'a',
          'b',
        ]),
        ['plugins/a/manifest.json'],
      );
      expect(missingPluginAssets(complete, ['a', 'b', 'c']), hasLength(2));
    });

    test('stays green with other assets around', () {
      expect(
        missingPluginAssets(
          {...complete, 'packages/x/font.ttf', 'plugins/a/README.md'},
          ['b', 'a'],
        ),
        isEmpty,
      );
    });
  });
}

/// [pluginIds] 裡哪些插件的 manifest 或打包產物不在 [assets] 裡。
List<String> missingPluginAssets(Set<String> assets, List<String> pluginIds) =>
    [
      for (final id in pluginIds)
        for (final file in ['manifest.json', 'dist/plugin.js'])
          if (!assets.contains('plugins/$id/$file')) 'plugins/$id/$file',
    ];
