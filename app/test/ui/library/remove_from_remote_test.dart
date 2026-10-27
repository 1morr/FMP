import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/source_dto.dart';

import '../tracks/selection_bar_support.dart';

import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/library/remote_write_state.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:material_ui/material_ui.dart';

import '../support/destructive_support.dart';
import '../support/shell_harness.dart';

// 「從遠端歌單移除」與歌單詳情裡的遠端入口（M4 PR 14，ADR 0019 §決定 4，design §7.2、§10.6、
// §10.7）：只在可寫的匯入歌單、插件現在能寫時出現；先確認（列出首數）；`removed`／`notPresent`
// 的從本地刪、`failed` 的留著並提示與列出。入口條件各項的對照在 remote_write_state_test.dart；
// 寫入與背景刷新本身在 test/library/remote_playlist_writer_test.dart。

const _more = 'More options';
const _item = 'Remove from the remote playlist';
const _addItem = 'Add to remote playlist…';

TrackInfo _song(String id, {String source = 'fmp-test'}) => TrackInfo(
  sourceTypeId: source,
  sourceId: id,
  title: 'Song $id',
  uploader: 'Uploader $id',
  duration: const Duration(minutes: 3),
);

ShellHarness _harness({Set<String> writable = const {'fmp-test'}}) =>
    ShellHarness(
      libraryRead: true,
      libraryWrite: true,
      registryOfSources: true,
      extraOverrides: [
        remoteWritablePluginsProvider.overrideWithValue(writable),
      ],
    );

/// 外殼開在音樂庫，寫好一張歌單「Road」並開詳情。[imported] 時是匯入歌單（`writable` 由
/// [writable] 決定，曲目有 `remote_item_id` `r<曲目 id>`）。
Future<(ShellHarness, int)> _open(
  WidgetTester tester, {
  required List<TrackInfo> tracks,
  bool imported = true,
  bool writable = true,
  ShellHarness? harness,
}) async {
  final h = harness ?? _harness();
  await h.pumpShell(
    tester,
    size: const Size(400, 800),
    at: ShellDestination.library,
  );
  final id = (await tester.runAsync(() async {
    final container = h.container(tester);
    final repository = container.read(playlistRepositoryProvider);
    final id = imported
        ? (await repository.createImported(
            pluginId: 'fmp-test',
            remoteId: 'r1',
            info: const RemotePlaylistInfo(name: 'Road'),
          ))!
        : await repository.create(name: 'Road');
    await repository.addTracks(id, tracks);
    if (imported) {
      await repository.setWritable(id, writable: writable);
      final database = container.read(appDatabaseProvider);
      for (final track in tracks) {
        await database.customStatement(
          'UPDATE playlist_entries SET remote_item_id = ? WHERE track_key = ?',
          ['r${track.sourceId}', '${track.key}'],
        );
      }
    }
    return id;
  }))!;
  await _settle(tester, h);
  await tester.tap(find.text('Road'));
  await _settle(tester, h);
  expect(find.byType(PlaylistDetailPage), findsOneWidget);
  expect(find.byType(LibraryPage).hitTestable(), findsNothing);
  return (h, id);
}

Future<void> _settle(WidgetTester tester, ShellHarness h) async {
  for (var i = 0; i < 3; i++) {
    await h.loadSettings(tester);
  }
  await tester.pumpAndSettle();
}

Future<List<String>> _stored(
  WidgetTester tester,
  ShellHarness h,
  int id,
) async => [
  for (final entry in (await tester.runAsync(
    () => h.container(tester).read(playlistRepositoryProvider).entries(id),
  ))!)
    entry.track.sourceId,
];

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first;

Future<void> _openMenu(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(of: _row(title), matching: find.byTooltip(_more)),
  );
  await tester.pumpAndSettle();
}

RemoveFromPlaylistResponse _results(List<LibraryWriteStatus> statuses) =>
    RemoveFromPlaylistResponse(
      results: [
        for (final status in statuses)
          LibraryWriteResult(
            status: status,
            error: status == LibraryWriteStatus.failed
                ? Unavailable(
                    reason: UnavailableReason.region,
                    pluginId: 'fmp-test',
                  )
                : null,
          ),
      ],
    );

const _removed = LibraryWriteStatus.removed;
const _notPresent = LibraryWriteStatus.notPresent;
const _failed = LibraryWriteStatus.failed;

List<Toast> _listenToasts(ShellHarness h) {
  final toasts = <Toast>[];
  final subscription = h.toaster.toasts.listen(toasts.add);
  addTearDown(subscription.cancel);
  return toasts;
}

void main() {
  group('the menu items', () {
    testWidgets('a writable imported playlist has "remove" and "add" for the '
        'plugin', (tester) async {
      await _open(tester, tracks: [_song('a')]);

      await _openMenu(tester, 'Song a');

      expect(find.widgetWithText(MenuItemButton, _item), findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, _addItem), findsOneWidget);
    });

    // 對照：同一個畫面，各拿掉一個條件。
    testWidgets('a local playlist has no "remove from the remote"', (
      tester,
    ) async {
      await _open(tester, tracks: [_song('a')], imported: false);

      await _openMenu(tester, 'Song a');

      expect(find.text(_item), findsNothing);
      expect(find.widgetWithText(MenuItemButton, _addItem), findsOneWidget);
    });

    testWidgets('an imported playlist that is not writable has none', (
      tester,
    ) async {
      await _open(tester, tracks: [_song('a')], writable: false);

      await _openMenu(tester, 'Song a');

      expect(find.text(_item), findsNothing);
    });

    testWidgets('a signed out plugin has neither item', (tester) async {
      await _open(
        tester,
        tracks: [_song('a')],
        harness: _harness(writable: const {}),
      );

      await _openMenu(tester, 'Song a');

      expect(find.text(_item), findsNothing);
      expect(find.text(_addItem), findsNothing);
    });
  });

  group('removing one song', () {
    testWidgets('asks first, naming the count and the playlist', (
      tester,
    ) async {
      final (h, id) = await _open(tester, tracks: [_song('a'), _song('b')]);
      await _openMenu(tester, 'Song a');

      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pumpAndSettle();

      expect(find.text('Remove from the remote playlist?'), findsOneWidget);
      expect(
        find.textContaining('Remove the selected songs (1) from "Road"'),
        findsOneWidget,
      );
      expect(h.plugin.removeFromPlaylistQueries, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(h.plugin.removeFromPlaylistQueries, isEmpty);
      expect(await _stored(tester, h, id), ['a', 'b']);
    });

    testWidgets('sends sourceId and remoteItemId, deletes it locally and '
        'toasts', (tester) async {
      final (h, id) = await _open(tester, tracks: [_song('a'), _song('b')]);
      h.plugin.onRemoveFromPlaylist = (query) => _results([_removed]);
      final toasts = _listenToasts(h);
      await _openMenu(tester, 'Song a');

      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pumpAndSettle();
      expectDestructiveConfirm(tester, 'Remove');
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      final query = h.plugin.removeFromPlaylistQueries.single;
      expect(query.playlistId, 'r1');
      expect(query.items.single.sourceId, 'a');
      expect(query.items.single.remoteItemId, 'ra');
      expect(await _stored(tester, h, id), ['b']);
      expect(toasts.single.kind, ToastKind.success);
      expect(toasts.single.message, 'Removed 1 from the remote playlist');
    });

    testWidgets('a notPresent song is deleted locally too', (tester) async {
      final (h, id) = await _open(tester, tracks: [_song('a'), _song('b')]);
      h.plugin.onRemoveFromPlaylist = (query) => _results([_notPresent]);
      await _openMenu(tester, 'Song a');

      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(await _stored(tester, h, id), ['b']);
    });

    testWidgets('a failed song stays, is toasted and listed under Details', (
      tester,
    ) async {
      final (h, id) = await _open(tester, tracks: [_song('a'), _song('b')]);
      h.plugin.onRemoveFromPlaylist = (query) => _results([_failed]);
      final toasts = _listenToasts(h);
      await _openMenu(tester, 'Song a');

      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(await _stored(tester, h, id), ['a', 'b']);
      expect(toasts.single.kind, ToastKind.warning);
      expect(toasts.single.message, 'Nothing was removed, 1 failed');
      expect(toasts.single.action?.label, 'Details');

      toasts.single.action!.onPressed();
      await tester.pumpAndSettle();

      expect(find.text('What went wrong'), findsOneWidget);
      expect(find.text('Song a'), findsWidgets);
      expect(find.textContaining('region'), findsOneWidget);
    });

    // 確認框開著時那一列不見了（背景刷新改了清單）：選單的 `ref` 已隨那一列釋放，之後不能再讀它。
    testWidgets('still sends and reports when the row is gone before the '
        'confirmation', (tester) async {
      final (h, id) = await _open(tester, tracks: [_song('a'), _song('b')]);
      h.plugin.onRemoveFromPlaylist = (query) => _results([_failed]);
      final toasts = _listenToasts(h);
      await _openMenu(tester, 'Song a');
      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final repository = h.container(tester).read(playlistRepositoryProvider);
        final entries = await repository.entries(id);
        await repository.removeEntries(id, [entries.first.id]);
      });
      await _settle(tester, h);
      expect(find.text('Uploader a'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        h.plugin.removeFromPlaylistQueries.single.items.single.sourceId,
        'a',
      );
      expect(toasts.single.kind, ToastKind.warning);
    });

    testWidgets('a call that fails as a whole leaves everything and says '
        'why', (tester) async {
      final (h, id) = await _open(tester, tracks: [_song('a'), _song('b')]);
      h.plugin.onRemoveFromPlaylist = (query) =>
          throw AuthRequired(pluginId: 'fmp-test');
      final toasts = _listenToasts(h);
      await _openMenu(tester, 'Song a');

      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(await _stored(tester, h, id), ['a', 'b']);
      expect(toasts.single.kind, ToastKind.error);
      expect(
        toasts.single.message,
        startsWith("Couldn't remove from the remote playlist"),
      );
    });
  });

  group('the selection bar', () {
    Future<void> selectBoth(WidgetTester tester) async {
      await tester.longPress(_row('Song a'));
      await tester.pumpAndSettle();
      await tester.tap(_row('Song b'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
    }

    testWidgets('removes the selected songs after one confirmation and '
        'leaves the selection mode', (tester) async {
      final (h, id) = await _open(
        tester,
        tracks: [_song('a'), _song('b'), _song('c')],
      );
      h.plugin.onRemoveFromPlaylist = (query) =>
          _results([for (final _ in query.items) _removed]);
      await selectBoth(tester);

      await tapSelectionAction(tester, _item);
      expect(
        find.textContaining('Remove the selected songs (2) from "Road"'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(
        h.plugin.removeFromPlaylistQueries.single.items.map((i) => i.sourceId),
        ['a', 'b'],
      );
      expect(await _stored(tester, h, id), ['c']);
      expect(find.text('2 selected'), findsNothing);
    });

    testWidgets('cancelling the confirmation keeps the selection', (
      tester,
    ) async {
      final (h, id) = await _open(tester, tracks: [_song('a'), _song('b')]);
      await selectBoth(tester);

      await tapSelectionAction(tester, _item);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      expect(await _stored(tester, h, id), ['a', 'b']);
    });

    // 對照：本機歌單、不可寫的匯入歌單沒有這顆鈕。
    testWidgets('has no remove button in a local playlist', (tester) async {
      await _open(tester, tracks: [_song('a'), _song('b')], imported: false);
      await selectBoth(tester);

      expect(
        await selectionActionState(tester, _item),
        SelectionActionState.absent,
      );
      expect(
        await selectionActionState(tester, _addItem),
        SelectionActionState.enabled,
      );
    });

    testWidgets('has no remove button when the playlist is not writable', (
      tester,
    ) async {
      await _open(tester, tracks: [_song('a'), _song('b')], writable: false);
      await selectBoth(tester);

      expect(
        await selectionActionState(tester, _item),
        SelectionActionState.absent,
      );
    });
  });

  group('adding from a playlist with songs of several sources', () {
    const mixed = 'Add to remote playlist (select songs from one source)';

    testWidgets('is disabled with the reason when the selection mixes '
        'plugins', (tester) async {
      await _open(
        tester,
        tracks: [
          _song('a'),
          _song('b', source: 'other'),
        ],
        imported: false,
        harness: _harness(writable: const {'fmp-test', 'other'}),
      );
      await tester.longPress(_row('Song a'));
      await tester.pumpAndSettle();
      await tester.tap(_row('Song b'));
      await tester.pumpAndSettle();

      expect(
        await selectionActionState(tester, _addItem),
        SelectionActionState.absent,
      );
      expect(
        await selectionActionState(tester, mixed),
        SelectionActionState.disabled,
      );
    });

    // 對照：只選同一個插件的兩首，同樣的歌單就能按。
    testWidgets('is enabled when the selected songs share a plugin', (
      tester,
    ) async {
      await _open(
        tester,
        tracks: [
          _song('a'),
          _song('b'),
          _song('c', source: 'other'),
        ],
        imported: false,
        harness: _harness(writable: const {'fmp-test', 'other'}),
      );
      await tester.longPress(_row('Song a'));
      await tester.pumpAndSettle();
      await tester.tap(_row('Song b'));
      await tester.pumpAndSettle();

      expect(
        await selectionActionState(tester, _addItem),
        SelectionActionState.enabled,
      );
    });
  });
}
