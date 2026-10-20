import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/library/remote_write_state.dart';

import '../../playback/fake_source_plugin.dart';
import '../../plugins/plugin_harness.dart';
import '../../support/pump_until.dart';

// 遠端寫入的入口條件（M4 design §7.1、§7.2、§10.6、§10.7）：插件在清單上、宣告
// `libraryWrite`、`CredentialState.active`；多選要同一個這樣的插件；移除要匯入歌單
// `writable`。每一條都有一個只差那一條件的對照。

FakeSourcePlugin _plugin(String id, {bool write = true}) =>
    FakeSourcePlugin((_) => [], id: id, libraryRead: true, libraryWrite: write);

Account _account(String pluginId, {AccountStatus? status}) => Account(
  pluginId: pluginId,
  userId: 'u',
  displayName: 'Someone',
  status: status ?? AccountStatus.active,
  loggedInAt: DateTime.utc(2026, 10, 20),
);

const _credentials = LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA'});

final class _Env {
  _Env(List<SourcePlugin> plugins) {
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(harness.database),
        credentialStoreProvider.overrideWithValue(harness.credentials),
        pluginRegistryProvider.overrideWithBuild(
          (ref, notifier) => {
            for (final plugin in plugins) plugin.manifest.id: plugin,
          },
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  final harness = PluginHarness();
  late final ProviderContainer container;

  /// 讓 autoDispose 的 provider 活著，並等到註冊表與帳號狀態讀進來。
  Future<Set<String>> writable() async {
    final subscription = container.listen(
      remoteWritablePluginsProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container.read(pluginRegistryProvider.future);
    await settle();
    await settle();
    return subscription.read();
  }

  Future<void> logIn(String pluginId, {AccountStatus? status}) async {
    await harness.credentials.ready;
    await harness.credentials.save(
      _account(pluginId, status: status),
      _credentials,
    );
  }
}

void main() {
  group('remoteWritablePluginsProvider', () {
    test('a logged in plugin that declares libraryWrite is in', () async {
      final env = _Env([_plugin('w')]);
      await env.logIn('w');

      expect(await env.writable(), {'w'});
    });

    // 對照：同一個插件，沒登入。
    test('the same plugin is out when signed out', () async {
      final env = _Env([_plugin('w')]);

      expect(await env.writable(), isEmpty);
    });

    test('logging in changes the set, and so does logging out', () async {
      final env = _Env([_plugin('w')]);
      expect(await env.writable(), isEmpty);

      await env.logIn('w');
      await settle();
      await settle();
      expect(env.container.read(remoteWritablePluginsProvider), {'w'});

      await env.harness.credentials.delete('w');
      await settle();
      await settle();
      expect(env.container.read(remoteWritablePluginsProvider), isEmpty);
    });

    test('an expired login is out', () async {
      final env = _Env([_plugin('w')]);
      await env.logIn('w');
      await env.harness.credentials.invalidate('w', of: _credentials);

      expect(await env.writable(), isEmpty);
    });

    test('a plugin without libraryWrite is out even when logged in', () async {
      final env = _Env([_plugin('r', write: false)]);
      await env.logIn('r');

      expect(await env.writable(), isEmpty);
    });

    test('only the logged in plugins are in', () async {
      final env = _Env([_plugin('a'), _plugin('b')]);
      await env.logIn('b');

      expect(await env.writable(), {'b'});
    });

    test('a plugin that is not on the list (disabled) is out', () async {
      final env = _Env([_plugin('a')]);
      await env.logIn('a');
      await env.logIn('gone');

      expect(await env.writable(), {'a'});
    });
  });

  group('remoteAddEntryFor', () {
    const writable = {'a', 'b'};

    test('one writable plugin is available', () {
      expect(remoteAddEntryFor(writable, ['a']), RemoteAddEntry.available);
      expect(remoteAddEntryFor(writable, ['a', 'a']), RemoteAddEntry.available);
    });

    test('a plugin that cannot write hides the item', () {
      expect(remoteAddEntryFor(writable, ['c']), RemoteAddEntry.hidden);
      expect(remoteAddEntryFor({}, ['a']), RemoteAddEntry.hidden);
      expect(remoteAddEntryFor(writable, const []), RemoteAddEntry.hidden);
    });

    test('songs of several plugins disable it, with a reason', () {
      expect(
        remoteAddEntryFor(writable, ['a', 'b']),
        RemoteAddEntry.mixedSources,
      );
      // 一個能寫、一個不能：仍然說明原因，而不是消失。
      expect(
        remoteAddEntryFor(writable, ['a', 'c']),
        RemoteAddEntry.mixedSources,
      );
      // 都不能寫就沒什麼好說明的。
      expect(remoteAddEntryFor(writable, ['c', 'd']), RemoteAddEntry.hidden);
    });
  });

  group('remoteRemoveEntryProvider', () {
    Future<(_Env, int)> imported({
      bool writable = true,
      bool login = true,
      bool pluginWrites = true,
    }) async {
      final env = _Env([_plugin('w', write: pluginWrites)]);
      final id = (await env.harness.database.transaction(() async {
        final repository = PlaylistRepository(env.harness.database);
        final id = (await repository.createImported(
          pluginId: 'w',
          remoteId: 'r1',
          info: const RemotePlaylistInfo(name: 'Road'),
        ))!;
        await repository.setWritable(id, writable: writable);
        return id;
      }));
      if (login) await env.logIn('w');
      return (env, id);
    }

    Future<bool> entry(_Env env, int id) async {
      final subscription = env.container.listen(
        remoteRemoveEntryProvider(id),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await env.container.read(pluginRegistryProvider.future);
      await settle();
      await settle();
      return subscription.read();
    }

    test('a writable imported playlist of a logged in plugin', () async {
      final (env, id) = await imported();

      expect(await entry(env, id), isTrue);
    });

    test('not when the playlist is not writable', () async {
      final (env, id) = await imported(writable: false);

      expect(await entry(env, id), isFalse);
    });

    test('not when signed out', () async {
      final (env, id) = await imported(login: false);

      expect(await entry(env, id), isFalse);
    });

    test('not when the plugin does not declare libraryWrite', () async {
      final (env, id) = await imported(pluginWrites: false);

      expect(await entry(env, id), isFalse);
    });

    test('not for a local playlist', () async {
      final (env, _) = await imported();
      final local = await PlaylistRepository(env.harness.database)
          .create(name: 'Local');

      expect(await entry(env, local), isFalse);
    });
  });
}
