import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/accounts/accounts_section.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../../plugins/plugin_harness.dart';
import '../support/plugin_page_harness.dart';

// 帳號頁卡片「⋯」的「從帳號匯入電台」（M4 PR 15，design §7.4）。插件是真的腳本（QuickJS），
// 不連網；忙碌與離開頁面的案例換成假插件，才能停在呼叫中途。

const _id = 'plugin-l';
const _name = 'Plugin plugin-l';

const _live = '''
export function liveSearch() { return { items: [], hasMore: false }; }
export function liveRoomFromUrl() { return null; }
export function liveStatus() { throw { fmpError: 'NotFound' }; }
export function resolveLive() { return { candidates: [] }; }
''';

const _all = ['search', 'live', 'libraryRead', 'login'];

/// [rooms]（JS 表達式）給了就匯出 `libraryLiveRooms`。
String _script({String? rooms, List<String> capabilities = _all}) =>
    pluginSource(
      '''
export function search() { return { items: [], hasMore: false }; }
export function loginVerify() { return { userId: 'u', displayName: 'Someone' }; }
${capabilities.contains('live') ? _live : ''}
${capabilities.contains('libraryRead') ? 'export function libraryPlaylists() { return { playlists: [], cursor: null }; }' : ''}
${rooms == null ? '' : 'export function libraryLiveRooms() { return $rooms; }'}
''',
      id: _id,
      capabilities: capabilities,
      login: '{"methods": ["cookie"]}',
    );

String _rooms(Iterable<String> ids) =>
    '{ rooms: [${[for (final id in ids) "{ roomId: '$id', title: 'Room $id', hostName: 'Host', status: 'live' }"].join(', ')}] }';

Future<void> _signIn(
  WidgetTester tester,
  PluginPageHarness h, {
  AccountStatus status = AccountStatus.active,
}) async {
  var saved = false;
  unawaited(
    h.plugins.credentials
        .save(
          Account(
            pluginId: _id,
            userId: 'u',
            displayName: 'Someone',
            status: status,
            loggedInAt: DateTime.utc(2026, 10, 20),
          ),
          const LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA_123'}),
        )
        .then((_) => saved = true),
  );
  await tester.pump();
  expect(saved, isTrue);
}

Future<void> _openAccounts(WidgetTester tester, PluginPageHarness h) async {
  await h.shell.pumpShell(
    tester,
    size: const Size(1000, 800),
    collapsePanel: true,
  );
  await tester.tap(find.text('Settings').first);
  await h.settle(tester);
  expect(find.byType(AccountsSection), findsOneWidget);
}

/// 裝好 [source]、登入（[signIn]）、開到帳號頁。
Future<PluginPageHarness> _open(
  WidgetTester tester,
  String source, {
  bool signIn = true,
  AccountStatus status = AccountStatus.active,
  List<Override> overrides = const [],
}) async {
  final h = await PluginPageHarness.create(tester, overrides: overrides);
  await tester.runAsync(() => h.install(source));
  if (signIn) await _signIn(tester, h, status: status);
  await _openAccounts(tester, h);
  return h;
}

final _menuButton = find.descendant(
  of: find.ancestor(of: find.text(_name), matching: find.byType(Card)),
  matching: find.byTooltip('More options'),
);

/// 任何型別參數的 PopupMenuButton（`byType` 只認 `PopupMenuButton<dynamic>`）。
final _anyMenu = find.byWidgetPredicate((w) => w is PopupMenuButton);
final _menuItem = find.text('Import live rooms from account');

/// 開「⋯」選單、按「從帳號匯入電台」，等匯入跑完。
Future<void> _import(WidgetTester tester, PluginPageHarness h) async {
  await tester.tap(_menuButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(_menuItem);
  for (var i = 0; i < 3; i++) {
    await h.settle(tester);
  }
}

Future<List<String>> _stations(
  WidgetTester tester,
  PluginPageHarness h,
) async =>
    (await tester.runAsync(() => RadioRepository(h.plugins.database).list()))!
        .map((s) => s.roomId)
        .toList();

List<String> _listen(PluginPageHarness h) {
  final toasts = <String>[];
  final subscription = h.shell.toaster.toasts.listen(
    (toast) => toasts.add(toast.message),
  );
  addTearDown(subscription.cancel);
  return toasts;
}

void main() {
  group('the menu item only shows when every condition holds', () {
    testWidgets('exported, declares live, signed in: shown', (tester) async {
      await _open(tester, _script(rooms: _rooms(['1'])));

      await tester.tap(_menuButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(_menuItem, findsOneWidget);
    });

    testWidgets('declared but not exported: no menu', (tester) async {
      await _open(tester, _script());

      expect(_menuButton, findsNothing);
      expect(_anyMenu, findsNothing);
    });

    testWidgets('exported but live is not declared: not even loadable, '
        'so no menu', (tester) async {
      // 匯出了 libraryLiveRooms 卻沒宣告 live，載入就被拒（library_read_capability_test）；
      // 卡片依 manifest 的 live 再擋一次。
      await _open(
        tester,
        _script(
          rooms: _rooms(['1']),
          capabilities: ['search', 'libraryRead', 'login'],
        ),
      );

      expect(_menuButton, findsNothing);
    });

    testWidgets('a plugin that does not declare live: no menu, even if '
        'the registry says it exports', (tester) async {
      final fake = FakeSourcePlugin((_) => const [], id: _id, libraryRead: true)
        ..onLibraryLiveRooms = () => const LibraryLiveRooms(rooms: []);
      await _open(
        tester,
        _script(capabilities: ['search', 'libraryRead', 'login']),
        overrides: [
          pluginRegistryProvider.overrideWithBuild(
            (ref, notifier) => {_id: fake},
          ),
        ],
      );

      expect(_menuButton, findsNothing);
    });

    testWidgets('no libraryRead: no menu', (tester) async {
      await _open(tester, _script(capabilities: ['search', 'live', 'login']));

      expect(_menuButton, findsNothing);
    });

    testWidgets('not signed in: no menu', (tester) async {
      await _open(tester, _script(rooms: _rooms(['1'])), signIn: false);

      expect(find.text('Not signed in'), findsOneWidget);
      expect(_menuButton, findsNothing);
    });

    testWidgets('signed in but the credential expired: no menu', (
      tester,
    ) async {
      await _open(
        tester,
        _script(rooms: _rooms(['1'])),
        status: AccountStatus.invalidated,
      );

      expect(find.text('Expired'), findsOneWidget);
      expect(_menuButton, findsNothing);
    });
  });

  group('the result toast', () {
    testWidgets('added and already there: both counts, and the rooms are in '
        'the radio list', (tester) async {
      final h = await _open(tester, _script(rooms: _rooms(['1', '2', '3'])));
      await tester.runAsync(
        () => RadioRepository(h.plugins.database).add(
          pluginId: _id,
          roomId: '2',
          title: 'Mine',
          addedAt: DateTime.utc(2026, 10, 1),
        ),
      );
      final toasts = _listen(h);

      await _import(tester, h);

      expect(toasts, ['Added to Radio: 2, already in your stations: 1']);
      expect(await _stations(tester, h), ['2', '1', '3']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('all new: only the added count; a second time: only the '
        'existing count', (tester) async {
      final h = await _open(tester, _script(rooms: _rooms(['1', '2'])));
      final toasts = _listen(h);

      await _import(tester, h);
      // 同一句提示在去重時間內不會再出現，換掉時間之前的那則。
      await tester.pump(const Duration(seconds: 10));
      await _import(tester, h);

      expect(toasts, ['Added to Radio: 2', 'Already in your stations: 2']);
      expect(await _stations(tester, h), ['1', '2']);
    });

    testWidgets('an account that follows nothing says so', (tester) async {
      final h = await _open(tester, _script(rooms: '{ rooms: [] }'));
      final toasts = _listen(h);

      await _import(tester, h);

      expect(toasts, ["This account doesn't follow any live rooms"]);
      expect(await _stations(tester, h), isEmpty);
    });

    testWidgets('a failure is explained, and nothing is added', (tester) async {
      final h = await _open(
        tester,
        _script(rooms: '(() => { throw { fmpError: "RateLimited" }; })()'),
      );
      final toasts = _listen(h);

      await _import(tester, h);

      expect(toasts, hasLength(1));
      expect(toasts.single, startsWith("Couldn't import live rooms: "));
      expect(toasts.single, isNot(contains('No network connection')));
      expect(await _stations(tester, h), isEmpty);
    });

    testWidgets('a failure while offline says offline', (tester) async {
      final h = await _open(
        tester,
        _script(rooms: '(() => { throw { fmpError: "NetworkError" }; })()'),
      );
      await h.shell.setNetwork(tester, NetworkStatus.noInterface);
      final toasts = _listen(h);

      await _import(tester, h);

      expect(toasts, ["Couldn't import live rooms: No network connection"]);
    });
  });

  group('while the import runs', () {
    /// 匯入停在 [gate]：插件清單換成一個 `libraryLiveRooms` 等 [gate] 的假插件。
    Future<PluginPageHarness> openPending(
      WidgetTester tester,
      Completer<LibraryLiveRooms> gate,
    ) {
      final fake = FakeSourcePlugin(
        (_) => const [],
        id: _id,
        live: true,
        libraryRead: true,
      )..onLibraryLiveRooms = () => gate.future;
      return _open(
        tester,
        _script(rooms: '{ rooms: [] }'),
        overrides: [
          pluginRegistryProvider.overrideWithBuild(
            (ref, notifier) => {_id: fake},
          ),
        ],
      );
    }

    Future<void> startImport(WidgetTester tester) async {
      await tester.tap(_menuButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_menuItem);
      await tester.pump();
    }

    double progress(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(LinearProgressIndicator),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    bool menuEnabled(WidgetTester tester) =>
        tester.widget<PopupMenuButton>(_anyMenu).enabled;

    FilledButton playlistsButton(WidgetTester tester) => tester.widget(
      find.ancestor(
        of: find.text('Playlists'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );

    testWidgets('the card is busy: progress shows, actions are disabled, and '
        'they come back afterwards', (tester) async {
      final gate = Completer<LibraryLiveRooms>();
      final h = await openPending(tester, gate);
      expect(progress(tester), 0);
      expect(menuEnabled(tester), isTrue);
      expect(playlistsButton(tester).onPressed, isNotNull);

      await startImport(tester);

      expect(progress(tester), 1);
      expect(menuEnabled(tester), isFalse);
      expect(playlistsButton(tester).onPressed, isNull);

      gate.complete(const LibraryLiveRooms(rooms: []));
      await h.settle(tester);

      expect(progress(tester), 0);
      expect(menuEnabled(tester), isTrue);
      expect(playlistsButton(tester).onPressed, isNotNull);
    });

    testWidgets('leaving the page mid-import: a failure afterwards does not '
        'throw and shows nothing', (tester) async {
      final gate = Completer<LibraryLiveRooms>();
      final h = await openPending(tester, gate);
      final toasts = _listen(h);
      await startImport(tester);

      // 換到設定的另一組：帳號區塊（和它的 State）被丟掉。
      await tester.tap(find.text('About').first);
      await h.settle(tester);
      expect(find.byType(AccountsSection), findsNothing);

      gate.completeError(StateError('late failure'));
      await h.settle(tester);

      expect(tester.takeException(), isNull);
      expect(toasts, isEmpty);
    });

    testWidgets('leaving the page mid-import: the import still finishes '
        'without throwing', (tester) async {
      final gate = Completer<LibraryLiveRooms>();
      final h = await openPending(tester, gate);
      final toasts = _listen(h);
      await startImport(tester);
      await tester.tap(find.text('About').first);
      await h.settle(tester);

      gate.complete(
        const LibraryLiveRooms(
          rooms: [
            LiveRoom(roomId: 'z', title: 'Z', status: LiveRoomStatus.live),
          ],
        ),
      );
      await h.settle(tester);
      await h.settle(tester);

      expect(tester.takeException(), isNull);
      expect(await _stations(tester, h), ['z']);
      expect(toasts, ['Added to Radio: 1']);
    });
  });
}
