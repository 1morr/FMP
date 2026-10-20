import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/library/remote_write_state.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 「加入遠端歌單…」（M4 PR 14，ADR 0019 §決定 4，design §7.1、§10.6、§10.7）：入口只在曲目所屬的
// 插件現在能寫遠端時出現；對話框讀完帳號的歌單、只列可寫的、可建新的並已勾上；直接送出，結果提示
// 三種形狀與「詳細」。入口條件本身（插件、登入、同一個插件）的對照在 remote_write_state_test.dart，
// 這裡以 override 直接決定哪些插件能寫。

const _more = 'More options';
const _item = 'Add to remote playlist…';

/// 外殼（假插件 `fmp-test` 有 libraryRead 與 libraryWrite），[writable] 是現在能寫的插件。
ShellHarness _harness({Set<String> writable = const {'fmp-test'}}) {
  return ShellHarness(
    libraryRead: true,
    libraryWrite: true,
    registryOfSources: true,
    extraOverrides: [remoteWritablePluginsProvider.overrideWithValue(writable)],
  );
}

LibraryPlaylist _playlist(
  String id,
  String title, {
  bool writable = true,
  int? count,
}) => LibraryPlaylist(
  playlistId: id,
  title: title,
  writable: writable,
  trackCount: count,
);

LibraryPlaylistPage _page(List<LibraryPlaylist> playlists, {String? cursor}) =>
    LibraryPlaylistPage(playlists: playlists, cursor: cursor);

AddToPlaylistResponse _results(List<LibraryWriteStatus> statuses) =>
    AddToPlaylistResponse(
      results: [
        for (final status in statuses)
          LibraryWriteResult(
            status: status,
            error: status == LibraryWriteStatus.failed
                ? RateLimited(pluginId: 'fmp-test')
                : null,
          ),
      ],
    );

const _added = LibraryWriteStatus.added;
const _present = LibraryWriteStatus.alreadyPresent;
const _failed = LibraryWriteStatus.failed;

/// 兩張可寫的與一張唯讀的。
void _serveThree(ShellHarness h) {
  h.plugin.onLibraryPlaylists = (query) => _page([
    _playlist('p1', 'Road trip', count: 3),
    _playlist('p2', 'Study', count: 1),
    _playlist('ro', 'Followed', writable: false, count: 9),
  ]);
}

Future<void> _search(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'song');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump();
}

Future<void> _openMenu(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(ListTile, title),
      matching: find.byTooltip(_more),
    ),
  );
  await tester.pumpAndSettle();
}

/// 搜尋結果 [title] 那一列的「⋯」→「加入遠端歌單…」。
Future<void> _openDialog(WidgetTester tester, String title) async {
  await _openMenu(tester, title);
  await tester.tap(find.widgetWithText(MenuItemButton, _item));
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

/// 「新增遠端歌單」對話框的名稱欄（搜尋頁的搜尋框也在畫面上）。
final _nameField = find.descendant(
  of: find.byType(AlertDialog).last,
  matching: find.byType(TextField),
);

Finder _check(String name) => find.widgetWithText(CheckboxListTile, name);

bool _checked(WidgetTester tester, String name) =>
    tester.widget<CheckboxListTile>(_check(name)).value ?? false;

FilledButton _addButton(WidgetTester tester) =>
    tester.widget(find.widgetWithText(FilledButton, 'Add'));

List<Toast> _listenToasts(ShellHarness h) {
  final toasts = <Toast>[];
  final subscription = h.toaster.toasts.listen(toasts.add);
  addTearDown(subscription.cancel);
  return toasts;
}

void main() {
  group('the menu item', () {
    testWidgets('is in the song menu when the plugin can write', (
      tester,
    ) async {
      final h = _harness();
      await h.pumpShell(tester);
      await _search(tester);

      await _openMenu(tester, 'Song a');

      expect(find.widgetWithText(MenuItemButton, _item), findsOneWidget);
      expect(
        tester
            .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, _item))
            .onPressed,
        isNotNull,
      );
    });

    // 對照：同一個畫面，插件現在不能寫（沒登入）。
    testWidgets('is not there when the plugin cannot write', (tester) async {
      final h = _harness(writable: const {});
      await h.pumpShell(tester);
      await _search(tester);

      await _openMenu(tester, 'Song a');

      expect(find.widgetWithText(MenuItemButton, 'Add to playlist…'), findsOne);
      expect(find.text(_item), findsNothing);
    });
  });

  group('the dialog', () {
    testWidgets('lists only the writable playlists, with counts', (
      tester,
    ) async {
      final h = _harness();
      _serveThree(h);
      await h.pumpShell(tester);
      await _search(tester);

      await _openDialog(tester, 'Song a');

      expect(find.text('Add to remote playlist'), findsOneWidget);
      expect(_check('Road trip'), findsOneWidget);
      expect(_check('Study'), findsOneWidget);
      expect(find.text('Followed'), findsNothing, reason: 'read-only');
      expect(find.text('3 songs'), findsOneWidget);
      expect(find.text('1 song'), findsOneWidget);
      expect(_checked(tester, 'Road trip'), isFalse);
      expect(_addButton(tester).onPressed, isNull, reason: 'nothing checked');
    });

    testWidgets('reads every page before showing', (tester) async {
      final h = _harness();
      h.plugin.onLibraryPlaylists = (query) => query.cursor == null
          ? _page([_playlist('p1', 'Page one')], cursor: 'next')
          : _page([_playlist('p2', 'Page two')]);
      await h.pumpShell(tester);
      await _search(tester);

      await _openDialog(tester, 'Song a');

      expect(_check('Page one'), findsOneWidget);
      expect(_check('Page two'), findsOneWidget);
      expect(h.plugin.libraryPlaylistQueries.map((q) => q.cursor), [
        null,
        'next',
      ]);
    });

    testWidgets('shows a progress indicator while reading', (tester) async {
      final h = _harness();
      final gate = Completer<LibraryPlaylistPage>();
      h.plugin.onLibraryPlaylists = (query) => gate.future;
      await h.pumpShell(tester);
      await _search(tester);

      await _openMenu(tester, 'Song a');
      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('New playlist on the remote'), findsNothing);

      gate.complete(_page([_playlist('p1', 'Late')]));
      await tester.pumpAndSettle();
      expect(_check('Late'), findsOneWidget);
    });

    testWidgets('a failed read can be retried', (tester) async {
      final h = _harness();
      var fail = true;
      h.plugin.onLibraryPlaylists = (query) => fail
          ? throw NetworkError(pluginId: 'fmp-test')
          : _page([_playlist('p1', 'Back again')]);
      await h.pumpShell(tester);
      await _search(tester);

      await _openDialog(tester, 'Song a');

      expect(find.text("Couldn't load your playlists"), findsOneWidget);
      expect(find.textContaining('Network connection failed'), findsOneWidget);
      expect(_addButton(tester).onPressed, isNull);

      fail = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(_check('Back again'), findsOneWidget);
      expect(find.text("Couldn't load your playlists"), findsNothing);
    });

    testWidgets('a failed read while offline says so', (tester) async {
      final h = _harness();
      h.plugin.onLibraryPlaylists = (query) =>
          throw NetworkError(pluginId: 'fmp-test');
      await h.pumpShell(tester);
      await h.setNetwork(tester, NetworkStatus.noInterface);
      await _search(tester);

      await _openDialog(tester, 'Song a');

      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('No network connection'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Network connection failed'),
        ),
        findsNothing,
      );
    });

    testWidgets('says so when there is nothing to add to, and still offers '
        'a new playlist', (tester) async {
      final h = _harness();
      h.plugin.onLibraryPlaylists = (query) =>
          _page([_playlist('ro', 'Followed', writable: false)]);
      await h.pumpShell(tester);
      await _search(tester);

      await _openDialog(tester, 'Song a');

      expect(find.text('No playlists you can add to yet'), findsOneWidget);
      expect(find.text('New playlist on the remote'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('Cancel closes it without a call', (tester) async {
      final h = _harness();
      _serveThree(h);
      await h.pumpShell(tester);
      await _search(tester);
      await _openDialog(tester, 'Song a');
      await tester.tap(_check('Road trip'));
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(h.plugin.addToPlaylistQueries, isEmpty);
    });
  });

  group('a new remote playlist', () {
    testWidgets('is created from the typed name, appears checked and has no '
        'track count', (tester) async {
      final h = _harness();
      _serveThree(h);
      h.plugin.onCreatePlaylist = (query) =>
          const CreatePlaylistResult(playlistId: 'new-1');
      await h.pumpShell(tester);
      await _search(tester);
      await _openDialog(tester, 'Song a');

      await tester.tap(find.text('New playlist on the remote'));
      await tester.pumpAndSettle();
      expect(find.text('New remote playlist'), findsOneWidget);
      // 空白不能建。
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
            .onPressed,
        isNull,
      );
      await tester.enterText(_nameField, '  Fresh list  ');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(h.plugin.createPlaylistQueries.single.title, 'Fresh list');
      expect(_check('Fresh list'), findsOneWidget);
      expect(_checked(tester, 'Fresh list'), isTrue);
      expect(_checked(tester, 'Road trip'), isFalse);
      expect(
        find.descendant(
          of: _check('Fresh list'),
          matching: find.textContaining('song'),
        ),
        findsNothing,
      );
      expect(_addButton(tester).onPressed, isNotNull);
    });

    testWidgets('a failed creation is toasted and adds nothing', (
      tester,
    ) async {
      final h = _harness();
      _serveThree(h);
      h.plugin.onCreatePlaylist = (query) =>
          throw AuthRequired(pluginId: 'fmp-test');
      final toasts = _listenToasts(h);
      await h.pumpShell(tester);
      await _search(tester);
      await _openDialog(tester, 'Song a');

      await tester.tap(find.text('New playlist on the remote'));
      await tester.pumpAndSettle();
      await tester.enterText(_nameField, 'Nope');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(toasts.single.kind, ToastKind.error);
      expect(toasts.single.message, startsWith("Couldn't create the playlist"));
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
    });
  });

  group('adding', () {
    testWidgets('sends one call per checked playlist at once and toasts the '
        'count', (tester) async {
      final h = _harness();
      _serveThree(h);
      h.plugin.onAddToPlaylist = (query) =>
          _results([for (final _ in query.tracks) _added]);
      final toasts = _listenToasts(h);
      await h.pumpShell(tester);
      await _search(tester);
      await _openDialog(tester, 'Song a');

      await tester.tap(_check('Road trip'));
      await tester.tap(_check('Study'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(
        [for (final q in h.plugin.addToPlaylistQueries) q.playlistId],
        ['p1', 'p2'],
      );
      expect(h.plugin.addToPlaylistQueries.first.tracks.single.sourceId, 'a');
      // 沒有確認框：對話框已經關了。
      expect(find.byType(AlertDialog), findsNothing);
      expect(toasts.single.kind, ToastKind.success);
      expect(toasts.single.message, 'Added to 2 playlists');
      expect(toasts.single.action, isNull);
    });

    testWidgets('adds "n already there" when some songs were present', (
      tester,
    ) async {
      final h = _harness();
      _serveThree(h);
      h.plugin.onAddToPlaylist = (query) => _results([_present]);
      final toasts = _listenToasts(h);
      await h.pumpShell(tester);
      await _search(tester);
      await _openDialog(tester, 'Song a');

      await tester.tap(_check('Road trip'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(toasts.single.kind, ToastKind.success);
      expect(toasts.single.message, 'Added to 1 playlist, 1 already there');
    });

    testWidgets('adds "k failed" and Details, which lists the playlist and '
        'the reason', (tester) async {
      final h = _harness();
      _serveThree(h);
      h.plugin.onAddToPlaylist = (query) =>
          query.playlistId == 'p1' ? _results([_failed]) : _results([_added]);
      final toasts = _listenToasts(h);
      await h.pumpShell(tester);
      await _search(tester);
      await _openDialog(tester, 'Song a');

      await tester.tap(_check('Road trip'));
      await tester.tap(_check('Study'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(toasts.single.kind, ToastKind.warning);
      expect(toasts.single.message, 'Added to 1 playlist, 1 failed');
      expect(toasts.single.action?.label, 'Details');

      toasts.single.action!.onPressed();
      await tester.pumpAndSettle();

      expect(find.text('What went wrong'), findsOneWidget);
      expect(find.text('Road trip: 1 failed'), findsOneWidget);
      expect(find.textContaining('Too many requests'), findsOneWidget);
      expect(find.textContaining('Study'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('What went wrong'), findsNothing);
    });

    testWidgets('a playlist that failed as a whole counts all its songs', (
      tester,
    ) async {
      final h = _harness();
      _serveThree(h);
      h.plugin.onAddToPlaylist = (query) =>
          throw NetworkError(pluginId: 'fmp-test');
      final toasts = _listenToasts(h);
      await h.pumpShell(tester);
      await _search(tester);
      await _openDialog(tester, 'Song a');

      await tester.tap(_check('Road trip'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(toasts.single.message, 'Nothing was added, 1 failed');
      expect(toasts.single.action, isNotNull);
    });
  });

  group('the selection bar', () {
    Future<ShellHarness> selectTwo(
      WidgetTester tester, {
      required Set<String> writable,
      List<TrackInfo> extra = const [],
    }) async {
      final h = _harness(writable: writable);
      _serveThree(h);
      await h.pumpShell(tester);
      await _search(tester);
      await tester.longPress(find.widgetWithText(ListTile, 'Song a'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Song b'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('adds all the selected songs to the checked playlists', (
      tester,
    ) async {
      final h = await selectTwo(tester, writable: const {'fmp-test'});
      h.plugin.onAddToPlaylist = (query) =>
          _results([for (final _ in query.tracks) _added]);

      await tester.tap(find.byTooltip(_item));
      await tester.pumpAndSettle();
      await tester.tap(_check('Road trip'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(
        h.plugin.addToPlaylistQueries.single.tracks.map((t) => t.sourceId),
        ['a', 'b'],
      );
      // 送出了：離開選取模式。
      expect(find.text('2 selected'), findsNothing);
    });

    testWidgets('cancelling keeps the selection', (tester) async {
      await selectTwo(tester, writable: const {'fmp-test'});

      await tester.tap(find.byTooltip(_item));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
    });

    // 結果列自己的音源決定，不是選的音源（選的音源停用時會退回別的，畫面上的結果還是舊音源的）：
    // 這裡的結果屬於 `other`，選的音源是 `fmp-test`。
    Future<void> selectForeign(
      WidgetTester tester, {
      required Set<String> writable,
    }) async {
      final h = ShellHarness(
        libraryRead: true,
        libraryWrite: true,
        registryOfSources: true,
        onSearch: (query) => SearchPage(
          items: [
            for (final id in ['a', 'b'])
              TrackSummary(
                sourceTypeId: 'other',
                sourceId: id,
                title: 'Song $id',
              ),
          ],
          hasMore: false,
        ),
        extraOverrides: [
          remoteWritablePluginsProvider.overrideWithValue(writable),
        ],
      );
      await h.pumpShell(tester);
      await _search(tester);
      await tester.longPress(find.widgetWithText(ListTile, 'Song a'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Song b'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
    }

    testWidgets('follows the plugin of the results, not the selected '
        'source', (tester) async {
      await selectForeign(tester, writable: const {'fmp-test'});

      expect(find.byTooltip(_item), findsNothing);
    });

    // 對照：結果的音源能寫就有。
    testWidgets('has the button when the plugin of the results can write', (
      tester,
    ) async {
      await selectForeign(tester, writable: const {'other'});

      expect(find.byTooltip(_item), findsOneWidget);
    });

    // 對照：同樣的選取，插件不能寫就沒有這顆鈕。
    testWidgets('has no button when the plugin cannot write', (tester) async {
      await selectTwo(tester, writable: const {});

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byTooltip(_item), findsNothing);
      expect(find.byTooltip('Add to playlist…'), findsOneWidget);
    });
  });
}
