import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/install/plugin_installer.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';

import '../../plugins/plugin_harness.dart';

ProviderContainer _container(PluginHarness harness, AppLocale locale) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(harness.database),
      logProvider.overrideWithValue(harness.log),
      redactorProvider.overrideWithValue(harness.redactor),
      credentialStoreProvider.overrideWithValue(harness.credentials),
      sourceHttpClientFactoryProvider.overrideWithValue(harness.httpClients),
      mediaHttpClientFactoryProvider.overrideWithValue(
        harness.mediaHttpClients,
      ),
      scriptPluginLoaderProvider.overrideWithValue(harness.loader),
      translationsProvider.overrideWithValue(locale.buildSync()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('gives the manifest name of a loaded plugin, "not installed" for an '
      'unknown one and "disabled" for a disabled one', () async {
    final harness = PluginHarness();
    final container = _container(harness, AppLocale.en);
    expect(container.read(pluginNameProvider('fmp-test')), isNull);

    await container
        .read(pluginInstallerProvider)
        .installBytes(testPluginFile.readAsBytesSync());
    await container.read(pluginRegistryProvider.future);

    expect(container.read(pluginNameProvider('fmp-test')), 'FMP Test Plugin');
    expect(
      container.read(pluginNameProvider('not-installed')),
      'Source not installed',
    );

    await container
        .read(pluginRegistryProvider.notifier)
        .setEnabled('fmp-test', enabled: false);

    expect(container.read(pluginNameProvider('fmp-test')), 'Source disabled');
  });

  test('the texts follow the interface language', () async {
    for (final (locale, notInstalled) in [
      (AppLocale.zhTw, '音源未安裝'),
      (AppLocale.zhCn, '音源未安装'),
      (AppLocale.en, 'Source not installed'),
    ]) {
      final container = _container(PluginHarness(), locale);
      await container.read(pluginRegistryProvider.future);

      expect(container.read(pluginNameProvider('gone')), notInstalled);
    }
  });
}
