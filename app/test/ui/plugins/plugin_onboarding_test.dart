import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:material_ui/material_ui.dart';

import '../support/plugin_page_harness.dart';

// 首次啟動引導（M3 PR 6，ADR 0030 §決定 12，design §7.6）：沒有可搜尋的插件時，搜尋頁就地
// 列出官方插件、一次確認後依序安裝。

final _a = pluginScript('plugin-a', name: 'Alpha', hosts: ['a.example.test']);
final _b = pluginScript(
  'plugin-b',
  name: 'Beta',
  capabilities: ['search', 'resolveStream'],
  hosts: ['b.example.test'],
);

Finder _button(String text) => find.ancestor(
  of: find.text(text),
  matching: find.bySubtype<ButtonStyleButton>(),
);

/// 以搜尋為音源的真插件清單開外殼，官方插件庫放 [published]。
Future<PluginPageHarness> _open(
  WidgetTester tester, {
  List<String> published = const [],
  Size size = const Size(1000, 800),
  Future<void> Function(PluginPageHarness h)? before,
}) async {
  final h = await PluginPageHarness.create(tester, registrySources: true);
  if (published.isNotEmpty) h.publish(published);
  if (before != null) await tester.runAsync(() => before(h));
  await h.shell.pumpShell(tester, size: size);
  await h.settle(tester);
  return h;
}

Finder get _title => find.text('Install plugins to start searching');

bool? _checked(WidgetTester tester, String name) => tester
    .widget<CheckboxListTile>(
      find.ancestor(
        of: find.text(name),
        matching: find.byType(CheckboxListTile),
      ),
    )
    .value;

Future<void> _confirm(WidgetTester tester, PluginPageHarness h) async {
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: _button('Install')),
  );
  await h.settle(tester);
}

void main() {
  testWidgets('with no plugin the search page lists the official ones, all '
      'checked', (tester) async {
    final h = await _open(tester, published: [_a, _b]);

    expect(_title, findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(_checked(tester, 'Alpha'), isTrue);
    expect(_checked(tester, 'Beta'), isTrue);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(h.fetched, hasLength(1), reason: 'only the index is read');
  });

  testWidgets('one confirmation lists every selected plugin, then they are '
      'installed and the onboarding goes away', (tester) async {
    final h = await _open(tester, published: [_a, _b]);

    await tester.tap(_button('Install'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Install these plugins?'), findsOneWidget);
    expect(find.text('Search, Playback'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Capabilities: Search, Playback'),
      ),
      findsOneWidget,
      reason: "Beta's capabilities",
    );
    expect(find.text('Sites it connects to: a.example.test'), findsOneWidget);
    expect(
      find.text(
        'This script will access these sites as you, with your sign-in.',
      ),
      findsOneWidget,
      reason: 'one shared warning',
    );
    await _confirm(tester, h);
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      {for (final p in await h.stored(tester)) p.id},
      {'plugin-a', 'plugin-b'},
    );
    expect(_title, findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.text('Plugins installed: 2'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation installs nothing; an unchecked '
      'plugin is left out', (tester) async {
    final h = await _open(tester, published: [_a, _b]);

    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(_checked(tester, 'Beta'), isFalse);
    await tester.tap(_button('Install'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Capabilities: Search, Playback'), findsNothing);
    await tester.tap(_button('Cancel'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(await h.stored(tester), isEmpty);
    expect(_title, findsOneWidget);

    await tester.tap(_button('Install'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await _confirm(tester, h);
    expect({for (final p in await h.stored(tester)) p.id}, {'plugin-a'});
  });

  testWidgets('a plugin that is installed but disabled is listed as '
      'installed, and the onboarding is back once every search plugin is '
      'disabled', (tester) async {
    final h = await _open(
      tester,
      published: [_a, _b],
      before: (h) => h.install(_a),
    );
    expect(_title, findsNothing, reason: 'Alpha can search');
    expect(find.byType(ChoiceChip), findsOneWidget);

    unawaited(
      h
          .container(tester)
          .read(pluginRegistryProvider.notifier)
          .setEnabled('plugin-a', enabled: false),
    );
    await h.settle(tester);

    expect(_title, findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(_checked(tester, 'Alpha'), isFalse);
    expect(_checked(tester, 'Beta'), isTrue);
  });

  testWidgets('offline: the shared offline state with Retry, which reads the '
      'index again', (tester) async {
    final h = await _open(tester);
    await h.shell.setNetwork(tester, NetworkStatus.noInterface);
    await h.settle(tester);

    expect(find.text('No network connection'), findsWidgets);
    expect(_title, findsNothing);
    final fetches = h.fetched.length;

    h.publish([_a]);
    await h.shell.setNetwork(tester, NetworkStatus.online);
    await tester.tap(_button('Retry'));
    await h.settle(tester);

    expect(h.fetched.length, greaterThan(fetches));
    expect(_title, findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('online but the index cannot be read: a plain failure with '
      'Retry', (tester) async {
    final h = await _open(tester);

    expect(find.text("Couldn't read the plugin repositories"), findsOneWidget);
    h.publish([_a]);
    await tester.tap(_button('Retry'));
    await h.settle(tester);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('Install reads the index again; when that fails nothing is '
      'installed and Retry is offered', (tester) async {
    final h = await _open(tester, published: [_a]);
    h.remote.clear();

    await tester.tap(_button('Install'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AlertDialog), findsNothing);
    expect(await h.stored(tester), isEmpty);
    expect(find.text("Couldn't read the plugin repositories"), findsOneWidget);
    expect(_button('Retry'), findsOneWidget);
  });

  testWidgets('a plugin that fails is listed, the others are still '
      'installed', (tester) async {
    final h = await PluginPageHarness.create(tester, registrySources: true);
    h.publish([_a, _b], sha256Overrides: {'plugin-b': 'f' * 64});
    await h.shell.pumpShell(tester);
    await h.settle(tester);

    await tester.tap(_button('Install'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Beta'),
      ),
      findsNothing,
      reason: 'only the verified plugin is confirmed',
    );
    await _confirm(tester, h);
    await tester.pump(const Duration(milliseconds: 500));

    expect({for (final p in await h.stored(tester)) p.id}, {'plugin-a'});
    expect(find.text("Some plugins weren't installed"), findsOneWidget);
    expect(
      find.text(
        "Couldn't install Beta: The repository was just updated. Try again "
        'later.',
      ),
      findsOneWidget,
    );
    // 引導還在、Alpha 標著「已安裝」：頁面本身就是結果，不另跳提示蓋住底部的按鈕。
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Plugins installed: 1'), findsNothing);

    await tester.ensureVisible(_button('Close'));
    await tester.tap(_button('Close'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_title, findsNothing);
    expect(find.byType(ChoiceChip), findsOneWidget);
  });

  testWidgets('when everything fails the list stays and can be tried again', (
    tester,
  ) async {
    final h = await PluginPageHarness.create(tester, registrySources: true);
    h.publish([_a], sha256Overrides: {'plugin-a': 'f' * 64});
    await h.shell.pumpShell(tester);
    await h.settle(tester);

    await tester.tap(_button('Install'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'nothing to confirm',
    );
    expect(_title, findsOneWidget);
    expect(find.text("Some plugins weren't installed"), findsOneWidget);
    expect(await h.stored(tester), isEmpty);
    expect(_button('Install'), findsOneWidget);

    // 「插件庫剛更新，請稍後再試」：再按一次要讀新的 index，不是拿舊的那一份再比一次。
    h.publish([_a]);
    await tester.tap(_button('Install'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await _confirm(tester, h);
    await tester.pump(const Duration(milliseconds: 500));

    expect({for (final p in await h.stored(tester)) p.id}, {'plugin-a'});
    expect(_title, findsNothing);
  });

  testWidgets('Later after everything failed puts the onboarding away', (
    tester,
  ) async {
    final h = await PluginPageHarness.create(tester, registrySources: true);
    h.publish([_a], sha256Overrides: {'plugin-a': 'f' * 64});
    await h.shell.pumpShell(tester);
    await h.settle(tester);
    await tester.tap(_button('Install'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Some plugins weren't installed"), findsOneWidget);

    await tester.tap(_button('Later'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(_title, findsNothing);
    expect(find.text("Some plugins weren't installed"), findsNothing);
    expect(find.text('No sources to search'), findsOneWidget);
  });

  testWidgets('Later shows the plain empty state, whose button opens the '
      'plugin page', (tester) async {
    final h = await _open(tester, published: [_a]);

    await tester.tap(_button('Later'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(_title, findsNothing);
    expect(find.text('No sources to search'), findsOneWidget);
    await tester.tap(_button('Go to plugins'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('No plugins installed'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('Go to plugins opens the plugin section on a narrow window '
      'too', (tester) async {
    final h = await _open(tester, published: [_a], size: const Size(400, 800));

    await tester.tap(_button('Later'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(_button('Go to plugins'));
    await h.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('No plugins installed'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });
}
