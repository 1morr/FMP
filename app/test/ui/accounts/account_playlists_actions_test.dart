import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/accounts/account_playlists_page.dart';
import 'package:fmp/ui/accounts/account_playlists_state.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/memory_database.dart';
import '../support/shell_harness.dart';

// 帳號歌單頁的全選與底部動作鈕（U PR 13，ADR 0035，R7.10，舊版 L-23）。清單直接換掉
// `accountPlaylistsProvider`，不經插件腳本；匯入本身的測試在 `account_playlists_test.dart`。

const _pluginId = 'fmp-test';

List<LibraryPlaylist> _lists(int count) => [
  for (var i = 0; i < count; i++)
    LibraryPlaylist(
      playlistId: 'p$i',
      title: 'List $i',
      trackCount: i + 1,
      writable: false,
    ),
];

/// 開帳號歌單頁；[imported] 是已經在音樂庫的遠端 id。
Future<ShellHarness> _open(
  WidgetTester tester,
  List<LibraryPlaylist> playlists, {
  List<String> imported = const [],
  Size size = const Size(400, 800),
}) async {
  final database = memoryDatabase();
  final repository = PlaylistRepository(database);
  await tester.runAsync(() async {
    for (final id in imported) {
      await repository.createImported(
        pluginId: _pluginId,
        remoteId: id,
        info: RemotePlaylistInfo(name: 'Remote $id'),
      );
    }
  });
  final h = ShellHarness(
    database: database,
    extraOverrides: [
      accountPlaylistsProvider(_pluginId)
          .overrideWith((ref) async => playlists),
    ],
  );
  await h.pumpApp(
    tester,
    const AccountPlaylistsPage(pluginId: _pluginId),
    size: size,
  );
  await h.loadSettings(tester);
  await tester.pumpAndSettle();
  return h;
}

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<ButtonStyleButton>(),
);

void main() {
  testWidgets('the import button is at the bottom, not in the page bar', (
    tester,
  ) async {
    await _open(tester, _lists(3));

    final bar = find.byType(AppBar);
    expect(
      find.descendant(of: bar, matching: find.byType(FilledButton)),
      findsNothing,
    );
    final importButton = find.widgetWithText(
      FilledButton,
      'Import selected (0)',
    );
    expect(importButton, findsOneWidget);
    expect(
      tester.widget<FilledButton>(importButton).onPressed,
      isNull,
      reason: 'nothing ticked',
    );
    // 在清單的下面、視窗底部。
    expect(
      tester.getTopLeft(importButton).dy,
      greaterThan(tester.getBottomLeft(find.text('List 2')).dy),
    );
    expect(tester.getBottomLeft(importButton).dy, greaterThan(700));
  });

  testWidgets('Select all ticks every row that can be imported and then '
      'becomes Deselect all', (tester) async {
    await _open(tester, _lists(3), imported: ['p1']);

    await tester.tap(_button('Select all'));
    await tester.pump();

    // p1 已匯入、不能選：選到的是 p0 與 p2。
    expect(find.text('Import selected (2)'), findsOneWidget);
    expect(find.text('Deselect all'), findsOneWidget);
    expect(find.text('Select all'), findsNothing);

    await tester.tap(_button('Deselect all'));
    await tester.pump();

    expect(find.text('Import selected (0)'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets('ticking every row by hand also turns the button into '
      'Deselect all', (tester) async {
    await _open(tester, _lists(2));

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('Select all'), findsOneWidget, reason: 'one of two');
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();

    expect(find.text('Deselect all'), findsOneWidget);
    expect(find.text('Import selected (2)'), findsOneWidget);
  });

  testWidgets('when every playlist is already imported there is nothing to '
      'select and no bottom bar', (tester) async {
    await _open(tester, _lists(2), imported: ['p0', 'p1']);

    expect(find.text('Select all'), findsNothing);
    expect(find.textContaining('Import selected'), findsNothing);
  });

  testWidgets('an empty account has no bottom bar', (tester) async {
    await _open(tester, const []);

    expect(find.text('This account has no playlists yet'), findsOneWidget);
    expect(find.text('Select all'), findsNothing);
  });

  testWidgets('the bar wraps at a large text size instead of overflowing', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(tester, _lists(2), size: const Size(320, 700));

    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Import selected (0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
