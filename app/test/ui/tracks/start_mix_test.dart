import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/install/plugin_installer.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/tracks/start_mix.dart';

import '../../plugins/plugin_harness.dart';

// Mix 歌單「Mix 播放」停用的原因（M4 PR 11，design §5.4）：每種不能按的狀態各自的字樣。
// 測試插件宣告了 `mix`；另一個沒宣告 `mix` 的情況在 `mix_playlist_test.dart`（外殼）。

void main() {
  test('names why Mix play is unavailable: loading, not installed, '
      'disabled; null when the source can mix', () async {
    final harness = PluginHarness();
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
        networkInterfacesProvider.overrideWithValue(null),
        loginWebViewProvider.overrideWithValue(null),
        translationsProvider.overrideWithValue(AppLocale.en.buildSync()),
      ],
    );
    addTearDown(container.dispose);
    String? reason(String pluginId) =>
        container.read(mixUnavailableReasonProvider(pluginId));

    expect(reason('fmp-test'), 'Loading sources');

    await container
        .read(pluginInstallerProvider)
        .installBytes(testPluginFile.readAsBytesSync());
    await container.read(pluginRegistryProvider.future);

    expect(reason('fmp-test'), isNull);
    expect(reason('gone'), 'Source not installed');

    await container
        .read(pluginRegistryProvider.notifier)
        .setEnabled('fmp-test', enabled: false);

    expect(reason('fmp-test'), 'Source disabled');
  });
}
