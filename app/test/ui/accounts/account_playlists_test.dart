import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/ui/accounts/account_import_page.dart';
import 'package:fmp/ui/accounts/account_playlists_page.dart';
import 'package:fmp/ui/accounts/account_playlists_state.dart'
    show maxAccountPlaylistPages;
import 'package:fmp/ui/accounts/accounts_section.dart';
import 'package:material_ui/material_ui.dart';

import '../../plugins/plugin_harness.dart';
import '../support/plugin_page_harness.dart';

// 帳號頁的「歌單」（M4 PR 13，design §7.3）。插件是真的腳本（QuickJS），不連網：
// `libraryPlaylists`、`importPlaylist` 都是腳本裡的常數；匯入經真的 `PlaylistImporter` 寫進記憶體
// 資料庫。

const _id = 'plugin-l';

/// 四張歌單：`a` 可寫、`b` 唯讀、`old` 已在音樂庫（測試一開始就匯入）、`gone` 的 `importPlaylist`
/// 以 NotFound 失敗。
const _fourPlaylists = '''
export function libraryPlaylists(query) {
  return { playlists: [
    { playlistId: 'a', title: 'Road trip', trackCount: 3, writable: true },
    { playlistId: 'b', title: 'Study', trackCount: 5, writable: false },
    { playlistId: 'old', title: 'Already here', writable: false },
    { playlistId: 'gone', title: 'Vanished', trackCount: 1, writable: false },
  ], cursor: null };
}
''';

String _script(
  String library, {
  List<String> capabilities = const [
    'search',
    'resolveStream',
    'importPlaylist',
    'libraryRead',
    'login',
  ],
}) => pluginSource(
  '''
export function search() { return { items: [], hasMore: false }; }
export function resolveStream() { return { candidates: [] }; }
export function playlistFromUrl() { return null; }
export function importPlaylist(query) {
  if (query.playlistId === 'gone') throw { fmpError: 'NotFound' };
  return {
    playlist: { title: 'Remote ' + query.playlistId },
    items: [{ track: { sourceId: 's-' + query.playlistId, title: 'Song' } }],
    cursor: null,
    total: 1,
  };
}
export function loginVerify() { return { userId: 'u', displayName: 'Someone' }; }
$library
''',
  id: _id,
  capabilities: capabilities,
  login: '{"methods": ["cookie"]}',
);

Finder _button(String text) => find.ancestor(
  of: find.text(text),
  matching: find.bySubtype<ButtonStyleButton>(),
);

/// [row] 那一列的勾選框。
Finder _checkbox(String row) => find.descendant(
  of: find.ancestor(of: find.text(row), matching: find.byType(ListTile)),
  matching: find.byType(Checkbox),
);

/// [row] 那一列裡的 [text]。
Finder _inRow(String row, String text) => find.descendant(
  of: find.ancestor(of: find.text(row), matching: find.byType(ListTile)),
  matching: find.text(text),
);

/// 按「匯入所選 (n)」開匯入全頁，等它推上來的轉場走完。`settle` 只 `pump()`、假時鐘不前進，
/// 不等的話頁面停在轉場的第一格（在視窗右邊外面），點「完成」點不到。
Future<void> _startImport(WidgetTester tester, int count) async {
  await tester.tap(_button('Import selected ($count)'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// 匯入全頁跑完（插件在背景 isolate，要真的事件迴圈；最多等 20 輪，不用 `pumpAndSettle`：進行中的
/// 進度條一直在動），再按「完成」回到歌單頁。
Future<void> _finishImport(
  WidgetTester tester,
  PluginPageHarness h,
  String outcome,
) async {
  for (var i = 0; i < 20 && _button('Done').evaluate().isEmpty; i++) {
    await h.settle(tester);
  }
  // 結果寫在頁面頂端，不跳提示（提示會蓋住「完成」）。
  expect(find.text(outcome), findsOneWidget);
  await tester.tap(_button('Done'));
  await h.settle(tester);
  await tester.pump(const Duration(seconds: 1));
  await h.settle(tester);
}

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

/// 裝好插件（[library] 是 `libraryPlaylists` 的腳本）、登入、開到歌單頁。
Future<PluginPageHarness> _openPlaylists(
  WidgetTester tester,
  String library, {
  Iterable<String> alreadyImported = const [],
}) async {
  final h = await PluginPageHarness.create(tester);
  await tester.runAsync(() => h.install(_script(library)));
  await _signIn(tester, h);
  for (final remoteId in alreadyImported) {
    await tester.runAsync(
      () => PlaylistRepository(h.plugins.database).createImported(
        pluginId: _id,
        remoteId: remoteId,
        info: const RemotePlaylistInfo(name: 'Imported earlier'),
      ),
    );
  }
  await _openAccounts(tester, h);
  await tester.tap(_button('Playlists'));
  await h.settle(tester);
  await h.settle(tester);
  // 頁面推上來的轉場走完。
  await tester.pump(const Duration(seconds: 1));
  return h;
}

Future<List<String>> _playlistNames(
  WidgetTester tester,
  PluginPageHarness h,
) async => [
  for (final playlist in (await tester.runAsync(
    () => h.shell
        .container(tester)
        .read(playlistRepositoryProvider)
        .watchAll()
        .first,
  ))!)
    playlist.name,
];

void main() {
  // 點不到的 `tap` 直接失敗，不只印警告後在後面的斷言才紅。
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  group('the button on the account card', () {
    testWidgets('shows for an active account of a libraryRead plugin and '
        'opens the page in the settings navigation', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(() => h.install(_script(_fourPlaylists)));
      await _signIn(tester, h);
      await _openAccounts(tester, h);

      expect(_button('Playlists'), findsOneWidget);

      await tester.tap(_button('Playlists'));
      await h.settle(tester);
      await h.settle(tester);

      expect(find.byType(AccountPlaylistsPage), findsOneWidget);
      // 外殼的測試環境沒有插件名稱，標題退回插件 id。
      expect(find.text('$_id playlists'), findsOneWidget);
      // 導覽留著（在設定分頁自己的導覽裡，不是根導覽）。
      expect(find.text('Library'), findsWidgets);
    });

    testWidgets('is not there for an expired account', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(() => h.install(_script(_fourPlaylists)));
      await _signIn(tester, h, status: AccountStatus.invalidated);
      await _openAccounts(tester, h);

      expect(find.text('Expired'), findsOneWidget);
      expect(_button('Playlists'), findsNothing);
    });

    testWidgets('is not there when signed out', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(() => h.install(_script(_fourPlaylists)));
      await _openAccounts(tester, h);

      expect(find.text('Not signed in'), findsOneWidget);
      expect(_button('Playlists'), findsNothing);
    });

    testWidgets('is not there for a plugin that does not declare libraryRead', (
      tester,
    ) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(
        () => h.install(
          _script(
            '',
            capabilities: [
              'search',
              'resolveStream',
              'importPlaylist',
              'login',
            ],
          ),
        ),
      );
      await _signIn(tester, h);
      await _openAccounts(tester, h);

      expect(find.text('Active'), findsOneWidget);
      expect(_button('Playlists'), findsNothing);
    });
  });

  group('the page', () {
    testWidgets('lists the playlists; an imported one is marked and cannot be '
        'ticked', (tester) async {
      await _openPlaylists(tester, _fourPlaylists, alreadyImported: ['old']);

      expect(find.text('Road trip'), findsOneWidget);
      expect(find.text('Study'), findsOneWidget);
      expect(find.text('Already here'), findsOneWidget);
      expect(_inRow('Road trip', '3 songs'), findsOneWidget);
      // 英文的 1 首是單數（同音樂庫的首數）。
      expect(_inRow('Vanished', '1 song'), findsOneWidget);
      expect(_inRow('Road trip', 'Writable'), findsOneWidget);
      expect(_inRow('Study', 'Writable'), findsNothing);
      // 沒有 trackCount 的不寫首數。
      expect(_inRow('Already here', 'Imported'), findsOneWidget);
      expect(_inRow('Road trip', 'Imported'), findsNothing);
      expect(
        tester.widget<Checkbox>(_checkbox('Already here')).onChanged,
        isNull,
      );
      expect(
        tester.widget<Checkbox>(_checkbox('Road trip')).onChanged,
        isNotNull,
      );
      // 沒有勾選時不能匯入。
      expect(find.text('Import selected (0)'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(_button('Import selected (0)'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('ticking rows counts them; tapping an imported row does '
        'nothing', (tester) async {
      await _openPlaylists(tester, _fourPlaylists, alreadyImported: ['old']);

      await tester.tap(find.text('Road trip'));
      await tester.pump();
      await tester.tap(find.text('Already here'));
      await tester.pump();
      expect(find.text('Import selected (1)'), findsOneWidget);

      await tester.tap(_checkbox('Study'));
      await tester.pump();
      expect(find.text('Import selected (2)'), findsOneWidget);

      await tester.tap(_checkbox('Road trip'));
      await tester.pump();
      expect(find.text('Import selected (1)'), findsOneWidget);
    });

    testWidgets('imports the ticked rows one by one, flips them to '
        'imported and shows the count', (tester) async {
      final h = await _openPlaylists(
        tester,
        _fourPlaylists,
        alreadyImported: ['old'],
      );
      await tester.tap(find.text('Road trip'));
      await tester.tap(find.text('Study'));
      await tester.pump();

      await _startImport(tester, 2);
      await h.settle(tester);
      await h.settle(tester);
      await h.settle(tester);

      // 全頁進度跑完停在原地，按「完成」回到歌單頁。
      await _finishImport(tester, h, 'Playlists imported: 2');

      expect(_inRow('Road trip', 'Imported'), findsOneWidget);
      expect(_inRow('Study', 'Imported'), findsOneWidget);
      expect(tester.widget<Checkbox>(_checkbox('Road trip')).onChanged, isNull);
      expect(find.text('Import selected (0)'), findsOneWidget);
      expect(
        await _playlistNames(tester, h),
        containsAll(['Remote a', 'Remote b']),
      );
      // importPlaylist 沒給 writable：存的是帳號歌單清單給的權威值。
      final repository = PlaylistRepository(h.plugins.database);
      final a = await tester.runAsync(() => repository.findRemote(_id, 'a'));
      final b = await tester.runAsync(() => repository.findRemote(_id, 'b'));
      expect(a!.writable, isTrue);
      expect(b!.writable, isFalse);
    });

    testWidgets('a failed row shows its reason, the others still import', (
      tester,
    ) async {
      final h = await _openPlaylists(tester, _fourPlaylists);
      await tester.tap(find.text('Vanished'));
      await tester.tap(find.text('Study'));
      await tester.pump();

      await _startImport(tester, 2);
      await h.settle(tester);
      await h.settle(tester);
      await h.settle(tester);

      // 全頁進度跑完停在原地，按「完成」回到歌單頁。
      await _finishImport(tester, h, 'Playlists imported: 1, failed: 1');

      expect(_inRow('Study', 'Imported'), findsOneWidget);
      expect(_inRow('Vanished', 'Imported'), findsNothing);
      // 失敗的那列在名稱下寫原因，勾選留著可以再試。
      expect(find.textContaining('Import failed:'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Vanished'),
            matching: find.byType(ListTile),
          ),
          matching: find.textContaining('Import failed:'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Checkbox>(_checkbox('Vanished')).value, isTrue);
      expect(find.text('Import selected (1)'), findsOneWidget);
      expect(await _playlistNames(tester, h), ['Remote b']);
    });

    // 匯入進行中不能離開（返回鍵不作用），只能取消；跑完按「完成」才回到歌單頁。
    testWidgets('the import page cannot be left mid-import and finishes the '
        'batch', (tester) async {
      final h = await _openPlaylists(tester, _fourPlaylists);
      // 清單順序：a 先匯入，gone 後失敗。
      await tester.tap(find.text('Road trip'));
      await tester.tap(find.text('Vanished'));
      await tester.pump();

      await _startImport(tester, 2);
      expect(find.text('Playlist 0 of 2'), findsOneWidget);
      await Navigator.of(tester.element(find.byType(AccountImportPage)))
          .maybePop();
      await tester.pump();
      expect(find.byType(AccountImportPage), findsOneWidget);
      await h.settle(tester);
      await h.settle(tester);
      await h.settle(tester);

      expect(tester.takeException(), isNull);
      await _finishImport(tester, h, 'Playlists imported: 1, failed: 1');
      expect(find.byType(AccountImportPage), findsNothing);
      expect(await _playlistNames(tester, h), ['Remote a']);
    });

    testWidgets('an empty account shows the empty state', (tester) async {
      await _openPlaylists(
        tester,
        'export function libraryPlaylists() { return { playlists: [] }; }',
      );

      expect(find.text('This account has no playlists yet'), findsOneWidget);
    });

    testWidgets('reads every page and stops at the page limit, with a '
        'warning', (tester) async {
      // 每頁一張、cursor 永遠不結束。
      final h = await _openPlaylists(tester, '''
export function libraryPlaylists(query) {
  const n = query.cursor ? Number(query.cursor) : 1;
  return { playlists: [{ playlistId: 'p' + n, title: 'List ' + n, writable: false }], cursor: String(n + 1) };
}
''');

      expect(maxAccountPlaylistPages, 20);
      // 二十次插件呼叫要多等幾輪。
      for (var i = 0; i < 20 && find.text('List 1').evaluate().isEmpty; i++) {
        await h.settle(tester);
      }
      // 讀了 20 張，沒有第 21 張。
      expect(find.text('List 1'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('List 20'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      expect(find.text('List 20'), findsOneWidget);
      expect(find.text('List 21'), findsNothing);
      final warnings = [
        for (final record in h.shell.log.history)
          if (record.tag == 'library' && record.message.contains('page limit'))
            record,
      ];
      expect(warnings, hasLength(1));
      expect(warnings.single.fields, {'pluginId': _id, 'pages': 20});
      // 歌單名稱不進 log。
      expect(
        [for (final record in h.shell.log.history) record.toJsonLine()].join(),
        isNot(contains('List 1')),
      );
    });

    testWidgets('a short list of pages is read to the end', (tester) async {
      final h = await _openPlaylists(tester, '''
export function libraryPlaylists(query) {
  const n = query.cursor ? Number(query.cursor) : 1;
  return {
    playlists: [{ playlistId: 'p' + n, title: 'List ' + n, writable: false }],
    cursor: n < 3 ? String(n + 1) : null,
  };
}
''');

      expect(find.text('List 1'), findsOneWidget);
      expect(find.text('List 3'), findsOneWidget);
      expect(
        h.shell.log.history.where((record) => record.tag == 'library'),
        isEmpty,
      );
    });

    // 同一頁的重複由 DTO 驗證擋；跨頁的重複（插件分頁時清單變了）只留先出現的那張。
    testWidgets('a playlist repeated on a later page is listed once', (
      tester,
    ) async {
      await _openPlaylists(tester, '''
export function libraryPlaylists(query) {
  if (!query.cursor) {
    return { playlists: [{ playlistId: 'p1', title: 'List 1', writable: false }], cursor: '2' };
  }
  return { playlists: [
    { playlistId: 'p1', title: 'List 1 again', writable: true },
    { playlistId: 'p2', title: 'List 2', writable: false },
  ], cursor: null };
}
''');

      expect(tester.takeException(), isNull);
      expect(find.text('List 1'), findsOneWidget);
      expect(find.text('List 1 again'), findsNothing);
      expect(find.text('List 2'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
    });

    testWidgets('a failure can be retried', (tester) async {
      // 第一次呼叫失敗，之後成功。
      final h = await _openPlaylists(tester, '''
let calls = 0;
export function libraryPlaylists() {
  calls += 1;
  if (calls === 1) throw { fmpError: 'NetworkError' };
  return { playlists: [{ playlistId: 'a', title: 'Road trip', writable: false }] };
}
''');

      expect(find.text("Couldn't read the playlists"), findsOneWidget);
      expect(find.text('Road trip'), findsNothing);

      await tester.tap(_button('Retry'));
      await h.settle(tester);
      await h.settle(tester);

      expect(find.text('Road trip'), findsOneWidget);
    });

    testWidgets('a failure while offline uses the offline wording', (
      tester,
    ) async {
      final h = await PluginPageHarness.create(tester);
      await tester.runAsync(
        () => h.install(
          _script(
            "export function libraryPlaylists() { throw { fmpError: 'NetworkError' }; }",
          ),
        ),
      );
      await _signIn(tester, h);
      await _openAccounts(tester, h);
      await h.shell.setNetwork(tester, NetworkStatus.noInterface);
      await tester.tap(_button('Playlists'));
      await h.settle(tester);
      await h.settle(tester);

      expect(find.text('No network connection').hitTestable(), findsWidgets);
      expect(_button('Retry'), findsOneWidget);
      expect(find.text("Couldn't read the playlists"), findsNothing);
    });
  });
}
