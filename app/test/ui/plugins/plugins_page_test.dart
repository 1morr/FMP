import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/endpoints.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/plugins/plugin_dialogs.dart';
import 'package:material_ui/material_ui.dart';

import '../support/plugin_page_harness.dart';

const _custom = 'https://custom.test/index.json';

final _a = pluginScript(
  'plugin-a',
  name: 'Alpha',
  capabilities: ['search', 'resolveStream'],
  hosts: ['a.example.test'],
  description: 'Plays Alpha songs',
);
final _b = pluginScript('plugin-b', name: 'Beta');

Finder _button(String text) => find.ancestor(
  of: find.text(text),
  matching: find.bySubtype<ButtonStyleButton>(),
);

Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Card));

/// [name] 那張卡裡的 [finder]。
Finder _inCard(String name, Finder finder) =>
    find.descendant(of: _card(name), matching: finder);

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

Future<void> _openAvailable(WidgetTester tester, PluginPageHarness h) async {
  await tester.tap(find.text('Available'));
  await tester.pumpAndSettle();
  await h.settle(tester);
}

void main() {
  group('the installed tab', () {
    testWidgets('lists installed plugins with version, author and '
        'description, enabled ones switched on', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(() async {
        await h.install(_a, indexUrl: officialPluginIndexUrl);
        await h.install(_b, enabled: false);
      });
      await h.open(tester);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('1.0.0 · FMP tests'), findsNWidgets(2));
      expect(find.text('Plays Alpha songs'), findsOneWidget);
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect([for (final s in switches) s.value], [true, false]);
      expect(_inCard('Beta', find.text('Disabled')), findsOneWidget);
      expect(_inCard('Alpha', find.text('Disabled')), findsNothing);
    });

    testWidgets('details show the translated capabilities, the hosts and '
        'the source', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(() async {
        await h.install(_a, indexUrl: officialPluginIndexUrl);
        await h.install(_b);
      });
      await h.open(tester);

      expect(find.text('a.example.test'), findsNothing);
      await tester.tap(_inCard('Alpha', find.text('Details')));
      await tester.pump();

      expect(find.text('Search, Playback'), findsOneWidget);
      expect(find.text('a.example.test'), findsOneWidget);
      expect(find.text('Official repository'), findsOneWidget);
      // 另一張沒展開；從檔案或網址裝的來源另有說法。
      await tester.tap(_inCard('Beta', find.text('Details')));
      await tester.pump();
      expect(find.text('Installed from a file or URL'), findsOneWidget);
      await tester.tap(_inCard('Alpha', find.text('Hide details')));
      await tester.pump();
      expect(find.text('a.example.test'), findsNothing);
    });

    testWidgets('a plugin that stopped responding is tagged', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(() => h.install(_b));
      await h.open(tester);
      expect(find.text('Not responding'), findsNothing);

      await tester.runAsync(
        () => h
            .container(tester)
            .read(pluginRegistryProvider.notifier)
            .register(UnresponsivePlugin(_b)),
      );
      await h.settle(tester);

      expect(_inCard('Beta', find.text('Not responding')), findsOne);
    });

    testWidgets('the switch disables and enables a plugin and writes it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(() => h.install(_b));
      await h.open(tester);
      expect(h.registered(tester), {'plugin-b'});

      // 開關的名稱是插件名（只有開關、沒有字）。
      expect(
        tester.getSemantics(find.byType(Switch)),
        matchesSemantics(
          label: 'Enable Beta',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Enable Beta'));
      await h.settle(tester);

      expect((await h.stored(tester)).single.enabled, isFalse);
      expect(h.registered(tester), isEmpty);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('Disabled'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await h.settle(tester);

      expect((await h.stored(tester)).single.enabled, isTrue);
      expect(h.registered(tester), {'plugin-b'});
      expect(find.text('Disabled'), findsNothing);
      semantics.dispose();
    });

    testWidgets('removing asks first; cancelling keeps the plugin', (
      tester,
    ) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(() async {
        await h.install(_a);
        await h.install(_b);
      });
      // 憑證的存取排在 CredentialStore 在假時間 zone 建好的鏈上：在這個 zone 呼叫、
      // pump 讓它跑完（在 runAsync 裡等它永遠等不到，見 PluginPageHarness.create）。
      var saved = false;
      unawaited(
        h.plugins.credentials
            .save(
              Account(
                pluginId: 'plugin-a',
                userId: 'u',
                displayName: 'Someone',
                status: AccountStatus.active,
                loggedInAt: DateTime.utc(2026, 10, 9),
              ),
              const LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA'}),
            )
            .then((_) => saved = true),
      );
      await tester.pump();
      expect(saved, isTrue);
      await h.open(tester);
      Iterable<String> stored() => h.plugins.secureStorage.values.keys;
      expect(stored(), ['credentials.plugin-a']);

      await tester.tap(_inCard('Alpha', _button('Remove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove Alpha?'), findsOneWidget);
      expect(
        find.textContaining('Songs stay and show "Source not installed"'),
        findsOneWidget,
      );
      await tester.tap(_button('Cancel'));
      await h.settle(tester);
      expect((await h.stored(tester)).map((p) => p.id), [
        'plugin-a',
        'plugin-b',
      ]);
      expect(stored(), ['credentials.plugin-a']);

      await tester.tap(_inCard('Alpha', _button('Remove')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: _button('Remove'),
        ),
      );
      await h.settle(tester);

      expect((await h.stored(tester)).map((p) => p.id), ['plugin-b']);
      expect(h.registered(tester), {'plugin-b'});
      // 經 PluginInstaller.remove：憑證與帳號列一起刪（PR 7 的步驟）。
      expect(stored(), isEmpty);
      expect(
        await tester.runAsync(AccountRepository(h.plugins.database).list),
        isEmpty,
      );
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Removed Alpha'), findsOneWidget);
    });

    testWidgets('nothing installed is an empty state', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await h.open(tester);

      expect(find.text('No plugins installed'), findsOneWidget);
    });
  });

  group('the available tab', () {
    testWidgets('lists the official and custom repositories, marking '
        'installed plugins', (tester) async {
      final h = await PluginPageHarness.create(tester);
      h
        ..publish([_a, _b])
        ..publish([pluginScript('plugin-c', name: 'Gamma')], url: _custom);
      await tester.runAsync(() async {
        await h.install(_b, indexUrl: officialPluginIndexUrl);
        await h.addIndex(_custom);
      });
      await h.open(tester);
      await _openAvailable(tester, h);

      expect(find.text('Official repository'), findsOneWidget);
      expect(find.text('Custom repository: $_custom'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
      expect(_inCard('Alpha', _button('Install')), findsOneWidget);
      expect(_inCard('Beta', find.text('Installed')), findsOne);
      expect(_inCard('Beta', _button('Install')), findsNothing);
      // 讀 index 不下載插件檔。
      expect(h.fetched, unorderedEquals([officialPluginIndexUrl, _custom]));
    });

    testWidgets('an entry for a newer FMP cannot be installed', (tester) async {
      final h = (await PluginPageHarness.create(tester))
        ..publish([_a], apiVersions: {'plugin-a': 2});
      await h.open(tester);
      await _openAvailable(tester, h);

      final button = _inCard('Alpha', _button('Requires a newer FMP'));
      expect(button, findsOneWidget);
      expect(_enabled(tester, button), isFalse);
    });

    testWidgets('installing asks with the downloaded manifest; cancelling '
        'installs nothing', (tester) async {
      final h = (await PluginPageHarness.create(tester))..publish([_a]);
      await h.open(tester);
      await _openAvailable(tester, h);

      await tester.tap(_inCard('Alpha', _button('Install')));
      await h.settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('Install Alpha?'), findsOneWidget);
      expect(find.text('By FMP tests · version 1.0.0'), findsOneWidget);
      expect(find.text('Search, Playback'), findsOneWidget);
      expect(find.text('a.example.test'), findsOneWidget);
      expect(
        find.text(
          'This script will access these sites as you, with your sign-in.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Unofficial source'), findsNothing);
      await tester.tap(_button('Cancel'));
      await h.settle(tester);
      expect(await h.stored(tester), isEmpty);

      await tester.tap(_inCard('Alpha', _button('Install')));
      await h.settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: _button('Install'),
        ),
      );
      await h.settle(tester);

      final stored = (await h.stored(tester)).single;
      expect(stored.id, 'plugin-a');
      expect(stored.sourceIndexUrl, officialPluginIndexUrl);
      expect(h.registered(tester), {'plugin-a'});
      expect(find.text('Installed Alpha'), findsOneWidget);
      expect(_inCard('Alpha', find.text('Installed')), findsOne);
    });

    testWidgets('the confirmation shows the downloaded file, not what the '
        'repository says about it', (tester) async {
      // 名稱、作者、說明不在比對之列：index 可以寫別的，對話框照 `.js` 的標頭。
      final h = (await PluginPageHarness.create(tester))
        ..publish(
          [_a],
          entryOverrides: {
            'plugin-a': {
              'name': 'Trusted',
              'author': 'Someone else',
              'description': 'Harmless',
            },
          },
        );
      await h.open(tester);
      await _openAvailable(tester, h);

      await tester.tap(_inCard('Trusted', _button('Install')));
      await h.settle(tester);
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
      expect(inDialog(find.text('Install Alpha?')), findsOneWidget);
      expect(inDialog(find.text('By FMP tests · version 1.0.0')), findsOne);
      expect(inDialog(find.text('Plays Alpha songs')), findsOneWidget);
      expect(inDialog(find.textContaining('Trusted')), findsNothing);
      expect(inDialog(find.textContaining('Someone else')), findsNothing);
      expect(inDialog(find.textContaining('Harmless')), findsNothing);
    });

    for (final (field, value) in [
      ('id', 'plugin-z'),
      ('version', '1.0.1'),
      ('capabilities', ['search']),
      ('allowedHosts', ['a.example.test', 'more.example.test']),
    ]) {
      testWidgets('a repository whose $field differs from the file is '
          'refused before asking', (tester) async {
        final h = (await PluginPageHarness.create(tester))
          ..publish(
            [_a],
            entryOverrides: {
              'plugin-a': {field: value},
            },
          );
        await h.open(tester);
        await _openAvailable(tester, h);

        await tester.tap(_inCard('Alpha', _button('Install')));
        await h.settle(tester);

        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.text(
            "The plugin file doesn't match the repository; nothing was "
            'installed',
          ),
          findsOneWidget,
        );
        expect(await h.stored(tester), isEmpty);
        expect(h.registered(tester), isEmpty);
      });
    }

    testWidgets('a custom repository plugin is marked unofficial', (
      tester,
    ) async {
      final h = (await PluginPageHarness.create(tester))
        ..publish([_a], url: _custom);
      await tester.runAsync(() => h.addIndex(_custom));
      await h.open(tester);
      await _openAvailable(tester, h);

      await tester.tap(_inCard('Alpha', _button('Install')));
      await h.settle(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Unofficial source: FMP hasn\'t reviewed this plugin.'),
        findsOneWidget,
      );
    });

    testWidgets('a file that does not match the repository is refused with '
        'a hint', (tester) async {
      final h = (await PluginPageHarness.create(tester))
        ..publish([_a], sha256Overrides: {'plugin-a': 'a' * 64});
      await h.open(tester);
      await _openAvailable(tester, h);

      await tester.tap(_inCard('Alpha', _button('Install')));
      await h.settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('The repository was just updated. Try again later.'),
        findsOneWidget,
      );
      expect(await h.stored(tester), isEmpty);
    });

    for (final status in [
      NetworkStatus.noInterface,
      NetworkStatus.unreachable,
    ]) {
      testWidgets('offline (${status.name}): the shared offline state; the '
          'installed tab still works', (tester) async {
        final h = await PluginPageHarness.create(tester);
        await tester.runAsync(() => h.install(_b));
        await h.open(tester);
        await h.shell.setNetwork(tester, status);

        await _openAvailable(tester, h);

        expect(
          find.text(switch (status) {
            NetworkStatus.noInterface => 'No network connection',
            _ => "Can't reach the network",
          }),
          findsOneWidget,
        );
        expect(_button('Retry'), findsOneWidget);

        h.publish([_a]);
        await h.shell.setNetwork(tester, NetworkStatus.online);
        await tester.tap(_button('Retry'));
        await h.settle(tester);
        expect(find.text('Alpha'), findsOneWidget);

        await tester.tap(find.text('Installed').first);
        await tester.pumpAndSettle();
        expect(find.text('Beta'), findsOneWidget);
      });
    }

    testWidgets('one unreadable repository is a notice in its section; the '
        'others are listed', (tester) async {
      // 自訂的那份沒有放上去：讀它是 NetworkError。
      final h = (await PluginPageHarness.create(tester))..publish([_a]);
      await tester.runAsync(() => h.addIndex(_custom));
      await h.open(tester);
      await _openAvailable(tester, h);

      expect(_inCard('Alpha', _button('Install')), findsOneWidget);
      expect(find.text("Couldn't read this repository"), findsOneWidget);
      expect(find.text('No network connection'), findsNothing);

      h.publish([pluginScript('plugin-c', name: 'Gamma')], url: _custom);
      await tester.tap(_button('Retry'));
      await h.settle(tester);
      expect(find.text('Gamma'), findsOneWidget);
      expect(find.text("Couldn't read this repository"), findsNothing);
    });

    testWidgets('online but unreadable is a failure, not the offline state', (
      tester,
    ) async {
      final h = await PluginPageHarness.create(tester);
      await h.open(tester);
      await _openAvailable(tester, h);

      expect(
        find.text("Couldn't read the plugin repositories"),
        findsOneWidget,
      );
      expect(find.text('No network connection'), findsNothing);
    });
  });

  group('updates', () {
    final a11 = pluginScript(
      'plugin-a',
      name: 'Alpha',
      version: '1.1.0',
      capabilities: ['search', 'resolveStream'],
      hosts: ['a.example.test'],
    );
    // 1.1.0 多一個網域與一個能力。
    final b11 = pluginScript(
      'plugin-b',
      name: 'Beta',
      version: '1.1.0',
      capabilities: ['search', 'lyrics'],
      hosts: ['example.test', 'new.example.test'],
    );

    Future<PluginPageHarness> open(WidgetTester tester) async {
      final h = (await PluginPageHarness.create(tester))..publish([a11, b11]);
      await tester.runAsync(() async {
        await h.install(_a, indexUrl: officialPluginIndexUrl);
        await h.install(_b, indexUrl: officialPluginIndexUrl);
      });
      await h.open(tester);
      return h;
    }

    testWidgets('opening the page shows updates from the source repository', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Update available'), findsNWidgets(2));
      expect(_inCard('Alpha', _button('Update to 1.1.0')), findsOneWidget);
      expect(_enabled(tester, _button('Update all')), isTrue);
    });

    testWidgets('an update without added access does not ask', (tester) async {
      final h = await open(tester);

      await tester.tap(_inCard('Alpha', _button('Update to 1.1.0')));
      await h.settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await h.stored(tester)).firstWhere((p) => p.id == 'plugin-a').version,
        '1.1.0',
      );
      expect(find.text('Updated Alpha to 1.1.0'), findsOneWidget);
    });

    testWidgets('an update that adds a capability and a host lists only '
        'those and waits for the confirmation', (tester) async {
      final h = await open(tester);

      await tester.tap(_inCard('Beta', _button('Update to 1.1.0')));
      await h.settle(tester);
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(find.text('Update Beta?'), findsOneWidget);
      Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
      expect(inDialog(find.text('New capabilities')), findsOneWidget);
      expect(inDialog(find.text('Lyrics')), findsOneWidget);
      expect(inDialog(find.text('New sites')), findsOneWidget);
      expect(inDialog(find.text('new.example.test')), findsOneWidget);
      expect(inDialog(find.text('example.test')), findsNothing);
      expect(inDialog(find.textContaining('Search')), findsNothing);

      await tester.tap(_button('Cancel'));
      await h.settle(tester);
      expect(
        (await h.stored(tester)).firstWhere((p) => p.id == 'plugin-b').version,
        '1.0.0',
      );

      await tester.tap(_inCard('Beta', _button('Update to 1.1.0')));
      await h.settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(inDialog(_button('Update')));
      await h.settle(tester);
      expect(
        (await h.stored(tester)).firstWhere((p) => p.id == 'plugin-b').version,
        '1.1.0',
      );
    });

    testWidgets('update all asks only for the plugin whose access grows', (
      tester,
    ) async {
      final h = await open(tester);

      await tester.tap(_button('Update all'));
      await h.settle(tester);
      await tester.pumpAndSettle();

      // Alpha 已經更新，Beta 在等確認。
      expect(find.text('Update Beta?'), findsOneWidget);
      expect(
        (await h.stored(tester)).firstWhere((p) => p.id == 'plugin-a').version,
        '1.1.0',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: _button('Update'),
        ),
      );
      await h.settle(tester);

      expect((await h.stored(tester)).map((p) => p.version), [
        '1.1.0',
        '1.1.0',
      ]);
      expect(find.text('Plugins updated: 2'), findsOneWidget);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('a newer version for a newer FMP cannot be updated', (
      tester,
    ) async {
      final h = (await PluginPageHarness.create(tester))
        ..publish([a11], apiVersions: {'plugin-a': 2});
      await tester.runAsync(
        () => h.install(_a, indexUrl: officialPluginIndexUrl),
      );
      await h.open(tester);

      final button = _inCard('Alpha', _button('Requires a newer FMP'));
      expect(button, findsOneWidget);
      expect(_enabled(tester, button), isFalse);
      expect(_enabled(tester, _button('Update all')), isFalse);
    });

    testWidgets('an older version in the repository is never offered', (
      tester,
    ) async {
      final h = (await PluginPageHarness.create(tester))..publish([_a]);
      await tester.runAsync(
        () => h.install(a11, indexUrl: officialPluginIndexUrl),
      );
      await h.open(tester);

      expect(find.text('Update available'), findsNothing);
      expect(find.textContaining('Update to'), findsNothing);
      expect(_enabled(tester, _button('Update all')), isFalse);
    });

    testWidgets('a plugin is not updated from another repository', (
      tester,
    ) async {
      final h = (await PluginPageHarness.create(tester))..publish([a11]);
      await tester.runAsync(() => h.install(_a, indexUrl: _custom));
      await h.open(tester);

      expect(find.text('Update available'), findsNothing);
      expect(_enabled(tester, _button('Update all')), isFalse);
    });

    testWidgets('check for updates reads the repositories again', (
      tester,
    ) async {
      final h = (await PluginPageHarness.create(tester))..publish([_a]);
      await tester.runAsync(
        () => h.install(_a, indexUrl: officialPluginIndexUrl),
      );
      await h.open(tester);
      expect(find.text('Update available'), findsNothing);

      h.publish([a11]);
      await tester.tap(_button('Check for updates'));
      await h.settle(tester);

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Updates available: 1'), findsOneWidget);
      expect(
        h.fetched.where((url) => url == officialPluginIndexUrl),
        hasLength(2),
      );
    });
  });

  group('installing from a file or a URL', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
    }

    testWidgets('from a file: unofficial, every capability and host', (
      tester,
    ) async {
      final dialogs = FakeFileDialogs(
        PickedFile(
          name: 'alpha.js',
          bytes: Uint8List.fromList(utf8.encode(_a)),
        ),
      );
      final h = await PluginPageHarness.create(tester, dialogs: dialogs);
      await h.open(tester);

      await openMenu(tester);
      await tester.tap(find.text('Install from file'));
      await h.settle(tester);
      await tester.pumpAndSettle();

      expect(dialogs.extensions, ['js']);
      expect(find.text('Install Alpha?'), findsOneWidget);
      expect(find.text('Search, Playback'), findsOneWidget);
      expect(find.text('a.example.test'), findsOneWidget);
      expect(find.textContaining('Unofficial source'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: _button('Install'),
        ),
      );
      await h.settle(tester);

      final stored = (await h.stored(tester)).single;
      expect(stored.id, 'plugin-a');
      expect(stored.sourceIndexUrl, isNull);
      expect(h.registered(tester), {'plugin-a'});
    });

    testWidgets('a file that is not a plugin installs nothing', (tester) async {
      final h = await PluginPageHarness.create(
        tester,
        dialogs: FakeFileDialogs(
          PickedFile(
            name: 'x.js',
            bytes: Uint8List.fromList(utf8.encode('export {};')),
          ),
        ),
      );
      await h.open(tester);

      await openMenu(tester);
      await tester.tap(find.text('Install from file'));
      await h.settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining("Couldn't install the plugin"), findsOne);
      expect(await h.stored(tester), isEmpty);
    });

    testWidgets('without file dialogs there is no file entry', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await h.open(tester);

      await openMenu(tester);

      expect(find.text('Install from file'), findsNothing);
      expect(find.text('Install from URL'), findsOneWidget);
    });

    testWidgets('from a URL: only https, then unofficial and the replaced '
        'version', (tester) async {
      final h = await PluginPageHarness.create(tester);
      h.remote['https://files.test/alpha.js'] = pluginScript(
        'plugin-a',
        name: 'Alpha',
        version: '2.0.0',
      );
      await tester.runAsync(() => h.install(_a));
      await h.open(tester);
      h.fetched.clear();

      await openMenu(tester);
      await tester.tap(find.text('Install from URL'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'http://files.test/a.js');
      await tester.tap(_button('Download'));
      await tester.pump();
      expect(find.text('Enter a URL that starts with https'), findsOneWidget);
      expect(h.fetched, isEmpty);

      await tester.enterText(
        find.byType(TextField),
        'https://files.test/alpha.js',
      );
      await tester.tap(_button('Download'));
      await h.settle(tester);
      await tester.pumpAndSettle();

      expect(h.fetched, ['https://files.test/alpha.js']);
      expect(find.text('Install Alpha?'), findsOneWidget);
      expect(find.textContaining('Unofficial source'), findsOneWidget);
      expect(
        find.text('It replaces the installed version 1.0.0.'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: _button('Install'),
        ),
      );
      await h.settle(tester);

      expect((await h.stored(tester)).single.version, '2.0.0');
    });
  });

  group('repositories', () {
    testWidgets('adding warns that it is unofficial; removing deletes it', (
      tester,
    ) async {
      final h = await PluginPageHarness.create(tester);
      await h.open(tester);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage repositories'));
      await tester.pumpAndSettle();
      expect(find.text(officialPluginIndexUrl), findsOneWidget);

      await tester.tap(_button('Add repository'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Unofficial source: FMP hasn't reviewed the plugins in this list.",
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), _custom);
      await tester.tap(_button('Add'));
      await h.settle(tester);
      await tester.pumpAndSettle();

      final repository = h
          .container(tester)
          .read(pluginIndexRepositoryProvider);
      expect((await tester.runAsync(repository.list))!.map((r) => r.url), [
        _custom,
      ]);
      expect(find.text(_custom), findsOneWidget);

      await tester.tap(find.byTooltip('Remove this repository'));
      await h.settle(tester);

      expect(await tester.runAsync(repository.list), isEmpty);
      expect(find.text(_custom), findsNothing);
    });
  });

  group('repositories already listed', () {
    for (final (name, url) in [
      ('the official one', officialPluginIndexUrl),
      ('a custom one', _custom),
    ]) {
      testWidgets('adding $name again is refused', (tester) async {
        final h = await PluginPageHarness.create(tester);
        await tester.runAsync(() => h.addIndex(_custom));
        await h.open(tester);
        final repository = h
            .container(tester)
            .read(pluginIndexRepositoryProvider);

        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manage repositories'));
        await tester.pumpAndSettle();
        await tester.tap(_button('Add repository'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), url);
        await tester.tap(_button('Add'));
        await h.settle(tester);
        await tester.pumpAndSettle();

        expect(find.text('This repository is already listed'), findsOneWidget);
        expect((await tester.runAsync(repository.list))!.map((r) => r.url), [
          _custom,
        ]);
      });
    }
  });

  test('only https URLs with a host and no user info are accepted', () {
    expect(
      parseHttpsUrl(' https://a.test/x.js '),
      Uri.parse('https://a.test/x.js'),
    );
    for (final bad in [
      'http://a.test/x.js',
      'https:///x.js',
      'https://user:pass@a.test/x.js',
      'a.test/x.js',
      '',
    ]) {
      expect(parseHttpsUrl(bad), isNull, reason: bad);
    }
  });
}
