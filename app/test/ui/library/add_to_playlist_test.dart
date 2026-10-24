import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/queue/queue_view.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 「加入歌單…」（M4 PR 3，ADR 0019 §決定 4、ADR 0033 §決定 11，design §10.6）：對話框只列本機
// 歌單、可勾多張、新增的那張直接勾上、加入後提示、同一首可重複加入；入口在搜尋（含分 P 的
// 影片）、歷史、佇列與首頁「最近播放」的卡片。歌單詳情的入口在 `playlist_detail_page_test.dart`。

const _more = 'More options';
const _item = 'Add to playlist…';

/// 寫好歌單（名稱 → 曲目 id）；[imported] 的是匯入歌單，[mix] 的是 Mix 歌單。回傳名稱 → id。
Future<Map<String, int>> _seed(
  WidgetTester tester,
  ShellHarness h, {
  Map<String, List<String>> local = const {},
  List<String> imported = const [],
  List<String> mix = const [],
}) async {
  final ids = (await tester.runAsync(() async {
    final repository = h.container(tester).read(playlistRepositoryProvider);
    final ids = <String, int>{};
    for (final MapEntry(key: name, value: songs) in local.entries) {
      final id = await repository.create(name: name);
      await repository.addTracks(id, [
        for (final song in songs) summary(song).toTrackInfo(),
      ]);
      ids[name] = id;
    }
    for (final (index, name) in imported.indexed) {
      ids[name] = (await repository.createImported(
        pluginId: 'fmp-test',
        remoteId: 'r$index',
        info: RemotePlaylistInfo(name: name),
      ))!;
    }
    for (final name in mix) {
      ids[name] = await repository.createMix(
        name: name,
        pluginId: 'fmp-test',
        seedSourceId: 'seed',
      );
    }
    return ids;
  }))!;
  await _settle(tester, h);
  return ids;
}

Future<void> _settle(WidgetTester tester, ShellHarness h) async {
  for (var i = 0; i < 3; i++) {
    await h.loadSettings(tester);
  }
  await tester.pumpAndSettle();
}

/// 歌單 [id] 的曲目（曲目 id 加 cid）。
Future<List<String>> _stored(
  WidgetTester tester,
  ShellHarness h,
  int id,
) async => [
  for (final entry in (await tester.runAsync(
    () => h.container(tester).read(playlistRepositoryProvider).entries(id),
  ))!)
    '${entry.track.sourceId}${entry.track.cid ?? ''}',
];

Future<void> _search(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'song');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump();
}

/// 搜尋結果 [title] 那一列的「⋯」→「加入歌單…」。
Future<void> _addFromRow(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(ListTile, title),
      matching: find.byTooltip(_more),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, _item));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

/// 對話框裡 [name] 那一列的勾選框。
Finder _check(String name) => find.widgetWithText(CheckboxListTile, name);

bool _checked(WidgetTester tester, String name) =>
    tester.widget<CheckboxListTile>(_check(name)).value ?? false;

FilledButton _addButton(WidgetTester tester) =>
    tester.widget(find.widgetWithText(FilledButton, 'Add'));

void main() {
  group('the dialog', () {
    testWidgets('lists only local playlists; checking several adds the song '
        'to each and says so', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      final ids = await _seed(
        tester,
        h,
        local: {
          'Road': ['x'],
          'Late': [],
        },
        imported: ['Remote'],
        mix: ['Chill'],
      );
      await _search(tester);

      await _addFromRow(tester, 'Song a');

      expect(find.text('Add to playlist'), findsOneWidget);
      expect(_check('Road'), findsOneWidget);
      expect(_check('Late'), findsOneWidget);
      expect(find.text('Remote'), findsNothing, reason: 'imported');
      expect(find.text('Chill'), findsNothing, reason: 'mix');
      expect(find.text('1 song'), findsOneWidget);
      expect(_addButton(tester).onPressed, isNull, reason: 'nothing checked');

      await tester.tap(_check('Road'));
      await tester.tap(_check('Late'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(tester, h);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Added to 2 playlists'), findsOneWidget);
      expect(await _stored(tester, h, ids['Road']!), ['x', 'a']);
      expect(await _stored(tester, h, ids['Late']!), ['a']);
      expect(await _stored(tester, h, ids['Remote']!), isEmpty);
      expect(await _stored(tester, h, ids['Chill']!), isEmpty);
    });

    testWidgets('a playlist made from the dialog is checked right away', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await _seed(tester, h, local: {'Road': []});
      await _search(tester);
      await _addFromRow(tester, 'Song b');

      await tester.tap(find.widgetWithText(ListTile, 'New playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Fresh');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await _settle(tester, h);

      expect(_check('Fresh'), findsOneWidget);
      expect(_checked(tester, 'Fresh'), isTrue);
      expect(_checked(tester, 'Road'), isFalse);

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(tester, h);

      expect(find.text('Added to "Fresh"'), findsOneWidget);
      final fresh = (await tester.runAsync(
        () => h
            .container(tester)
            .read(playlistRepositoryProvider)
            .watchAll()
            .first,
      ))!.singleWhere((p) => p.name == 'Fresh');
      expect(fresh.kind, PlaylistKind.local);
      expect(await _stored(tester, h, fresh.id), ['b']);
    });

    testWidgets('without local playlists it says so and still offers a new '
        'one', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await _seed(tester, h, imported: ['Remote']);
      await _search(tester);

      await _addFromRow(tester, 'Song a');

      expect(find.text('No local playlists yet'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'New playlist'), findsOneWidget);
      expect(find.text('Remote'), findsNothing);
    });

    testWidgets('the same song can be added again; Cancel adds nothing', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      final ids = await _seed(
        tester,
        h,
        local: {
          'Road': ['a'],
        },
      );
      await _search(tester);

      await _addFromRow(tester, 'Song a');
      await tester.tap(_check('Road'));
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester, h);
      expect(await _stored(tester, h, ids['Road']!), ['a']);

      await _addFromRow(tester, 'Song a');
      expect(_checked(tester, 'Road'), isFalse, reason: 'a new dialog');
      await tester.tap(_check('Road'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(tester, h);

      expect(await _stored(tester, h, ids['Road']!), ['a', 'a']);
      expect(find.text('Added to "Road"'), findsOneWidget);
    });
  });

  group('the entries', () {
    Future<void> addTo(WidgetTester tester, ShellHarness h) async {
      await tester.tap(_check('Road'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(tester, h);
    }

    // 影片列的「加入歌單…」同「加入佇列」：有多個分 P 時是全部分 P（還沒取過就先取）。
    testWidgets('a multi-part video in the search results adds all its parts', (
      tester,
    ) async {
      final h = ShellHarness(
        multiPart: true,
        registryOfSources: true,
        onSearch: (_) =>
            SearchPage(items: [summary('v', partCount: 2)], hasMore: false),
      );
      h.plugin.onMultiPart = (_) => const MultiPartResult(
        parts: [
          MultiPart(cid: 11, title: 'One', index: 1),
          MultiPart(cid: 12, title: 'Two', index: 2),
        ],
      );
      await h.pumpShell(tester);
      final ids = await _seed(tester, h, local: {'Road': []});
      await _search(tester);

      await _addFromRow(tester, 'Song v');
      await addTo(tester, h);

      expect(h.plugin.multiPartQueries, hasLength(1));
      expect(await _stored(tester, h, ids['Road']!), ['v11', 'v12']);
    });

    testWidgets('parts that cannot be fetched show an error and open no '
        'dialog', (tester) async {
      final h = ShellHarness(
        multiPart: true,
        registryOfSources: true,
        onSearch: (_) =>
            SearchPage(items: [summary('v', partCount: 2)], hasMore: false),
      );
      h.plugin.onMultiPart = (_) => throw RateLimited(pluginId: 'fmp-test');
      await h.pumpShell(tester);
      final ids = await _seed(tester, h, local: {'Road': []});
      await _search(tester);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Song v'),
          matching: find.byTooltip(_more),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(h.plugin.multiPartQueries, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Too many requests'), findsWidgets);
      expect(await _stored(tester, h, ids['Road']!), isEmpty);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a part of an expanded video adds that part', (tester) async {
      final h = ShellHarness(
        multiPart: true,
        registryOfSources: true,
        onSearch: (_) =>
            SearchPage(items: [summary('v', partCount: 2)], hasMore: false),
      );
      h.plugin.onMultiPart = (_) => const MultiPartResult(
        parts: [
          MultiPart(cid: 11, title: 'One', index: 1),
          MultiPart(cid: 12, title: 'Two', index: 2),
        ],
      );
      await h.pumpShell(tester);
      final ids = await _seed(tester, h, local: {'Road': []});
      await _search(tester);
      await tester.tap(find.byTooltip('Show parts'));
      await tester.pump();
      await tester.pump();

      await _addFromRow(tester, 'P2 Two');
      await addTo(tester, h);

      expect(await _stored(tester, h, ids['Road']!), ['v12']);
    });

    testWidgets('a play history entry', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      final ids = await _seed(tester, h, local: {'Road': []});
      await tester.runAsync(
        () => h
            .container(tester)
            .read(playHistoryRepositoryProvider)
            .record(
              summary('h').toTrackInfo(),
              playedAt: DateTime(2026, 10, 15, 8),
              limit: 100,
            ),
      );
      await h.openHistory(tester);
      await _settle(tester, h);

      await _addFromRow(tester, 'Song h');
      await addTo(tester, h);

      expect(await _stored(tester, h, ids['Road']!), ['h']);
    });

    testWidgets('a song in the queue', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, size: const Size(1000, 800));
      final ids = await _seed(tester, h, local: {'Road': []});
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 200));
      await h.openQueue(tester);
      expect(find.byType(QueueView), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Song b'),
          matching: find.byTooltip(_more),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pumpAndSettle();
      await addTo(tester, h);

      expect(await _stored(tester, h, ids['Road']!), ['b']);
      expect(h.controller.queue.entries, hasLength(2), reason: 'unchanged');
    });
  });

  // PR 2 留下的：首頁「最近播放」的卡片有曲目選單（右鍵、長按、「⋯」同一份）。
  group('a recent play on Home', () {
    Future<ShellHarness> openHome(WidgetTester tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await tester.runAsync(
        () => h
            .container(tester)
            .read(playHistoryRepositoryProvider)
            .record(
              const TrackInfo(
                sourceTypeId: 'fmp-test',
                sourceId: 'r',
                title: 'Song r',
                uploader: 'Uploader r',
              ),
              playedAt: DateTime(2026, 10, 15, 8),
              limit: 100,
            ),
      );
      await _settle(tester, h);
      expect(find.text('Recently played'), findsOneWidget);
      return h;
    }

    const items = ['Play', 'Play next', 'Add to queue', _item];

    testWidgets('right click, long press and "⋯" open the same menu', (
      tester,
    ) async {
      await openHome(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Song r')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      for (final item in items) {
        expect(find.widgetWithText(MenuItemButton, item), findsOneWidget);
      }
      // 首頁不是歷史頁：沒有「從歷史移除」。
      expect(
        find.widgetWithText(MenuItemButton, 'Remove from history'),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, _item), findsNothing);

      await tester.longPress(find.text('Song r'));
      await tester.pumpAndSettle();
      for (final item in items) {
        expect(find.widgetWithText(MenuItemButton, item), findsOneWidget);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();
      for (final item in items) {
        expect(find.widgetWithText(MenuItemButton, item), findsOneWidget);
      }
    });

    testWidgets('"Add to playlist…" and "Add to queue" work from the card', (
      tester,
    ) async {
      final h = await openHome(tester);
      final ids = await _seed(tester, h, local: {'Road': []});

      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, _item));
      await tester.pumpAndSettle();
      await tester.tap(_check('Road'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await _settle(tester, h);
      expect(await _stored(tester, h, ids['Road']!), ['r']);

      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Add to queue'));
      await tester.pumpAndSettle();
      expect(
        [for (final e in h.controller.queue.entries) e.track.sourceId],
        ['r'],
      );
    });

    // 卡片（點一下播放）與「⋯」是兩個語意節點：螢幕閱讀器分得出兩個動作。
    testWidgets('the card and "⋯" are separate for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openHome(tester);

      expect(
        tester.getSemantics(find.text('Song r')),
        isSemantics(
          label: 'Song r\nUploader r',
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byTooltip(_more)),
        isSemantics(tooltip: _more, isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });
}
