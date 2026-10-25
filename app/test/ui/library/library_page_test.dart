import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 音樂庫（M4 PR 2，ADR 0033 §決定 8，design §10.3、§10.5）：歷史入口、建立、編輯、刪除、
// 拖曳排序（清單與格狀，格狀另有螢幕閱讀器的移動動作）、全部加入佇列、隨機加入、佇列上限、離線。

const _more = 'More options';

TrackInfo _track(String id) =>
    TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id');

/// 外殼開在音樂庫；[seed] 先寫好歌單（名稱 → 曲目 id）。
Future<ShellHarness> _open(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  Map<String, List<String>> seed = const {},
  bool collapsePanel = false,
  ShellHarness? harness,
}) async {
  final h = harness ?? ShellHarness();
  await h.pumpShell(
    tester,
    size: size,
    at: ShellDestination.library,
    collapsePanel: collapsePanel,
  );
  await tester.runAsync(() async {
    final repository = h.container(tester).read(playlistRepositoryProvider);
    for (final MapEntry(key: name, value: ids) in seed.entries) {
      final id = await repository.create(name: name);
      await repository.addTracks(id, [for (final id in ids) _track(id)]);
    }
  });
  await _settle(tester, h);
  return h;
}

/// 資料庫的寫入與重讀跑完。
Future<void> _settle(WidgetTester tester, ShellHarness h) async {
  for (var i = 0; i < 3; i++) {
    await h.loadSettings(tester);
  }
  await tester.pumpAndSettle();
}

Future<List<Playlist>> _stored(WidgetTester tester, ShellHarness h) async =>
    (await tester.runAsync(
      () =>
          h.container(tester).read(playlistRepositoryProvider).watchAll().first,
    ))!;

Finder _card(String name) => find.ancestor(
  of: find.text(name),
  matching: find.byWidgetPredicate(
    (widget) => widget is ListTile || widget is InkWell,
  ),
);

Future<void> _openMenu(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: _card(name).first, matching: find.byTooltip(_more)),
  );
  await tester.pumpAndSettle();
}

Future<void> _drag(WidgetTester tester, String name, Offset by) async {
  final handle = find.descendant(
    of: _card(name).first,
    matching: find.byIcon(Icons.drag_handle),
  );
  final gesture = await tester.startGesture(tester.getCenter(handle));
  for (var step = 0; step < 8; step++) {
    await gesture.moveBy(by / 8);
    await tester.pump(const Duration(milliseconds: 30));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('History at the top opens the play history inside Library', (
    tester,
  ) async {
    await _open(tester);

    await tester.tap(find.widgetWithText(ListTile, 'History'));
    await tester.pumpAndSettle();

    // 看頁首的標題：頁面正中央可能是頁首與空狀態之間的空白，那裡不接點擊。
    expect(
      find
          .descendant(
            of: find.byType(HistoryPage),
            matching: find.text('Play history'),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(LibraryPage).hitTestable(), findsNothing);
  });

  testWidgets('without playlists it says how to create or import one', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('No playlists yet'), findsOneWidget);
    expect(
      find.text(
        'Choose "New playlist" to create one, or "Import" to bring one in.',
      ),
      findsOneWidget,
    );
    // 歷史入口一直在。
    expect(find.widgetWithText(ListTile, 'History'), findsOneWidget);
  });

  group('creating and editing', () {
    testWidgets('a new playlist needs a name and lands at the end', (
      tester,
    ) async {
      final h = await _open(tester, seed: {'First': []});

      await tester.tap(find.byTooltip('New playlist'));
      await tester.pumpAndSettle();
      expect(find.text('New playlist'), findsWidgets);
      FilledButton create() =>
          tester.widget(find.widgetWithText(FilledButton, 'Create'));
      expect(create().onPressed, isNull, reason: 'the name is required');
      await tester.enterText(find.widgetWithText(TextField, 'Name'), '  ');
      await tester.pump();
      expect(create().onPressed, isNull);
      expect(find.text('Enter a name'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Name'), ' Road ');
      await tester.enterText(
        find.widgetWithText(TextField, 'Description (optional)'),
        'Driving',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await _settle(tester, h);

      final stored = await _stored(tester, h);
      expect([for (final p in stored) p.name], ['First', 'Road']);
      expect(stored.last.description, 'Driving');
      expect(find.text('Playlist created'), findsOneWidget);
      expect(find.text('Road'), findsOneWidget);
      expect(find.text('Local · 0 songs'), findsNWidgets(2));
    });

    testWidgets('cancelling creates nothing', (tester) async {
      final h = await _open(tester);

      await tester.tap(find.byTooltip('New playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'X');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester, h);

      expect(await _stored(tester, h), isEmpty);
    });

    testWidgets('editing fills in the fields and saves the new ones', (
      tester,
    ) async {
      final h = await _open(
        tester,
        seed: {
          'Old': ['a'],
        },
      );

      await _openMenu(tester, 'Old');
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit playlist'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Old'), findsOneWidget);
      // 封面是第一首歌的封面（自訂封面還沒有）。
      expect(find.text('The cover of the first song'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Old'), 'New');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _settle(tester, h);

      expect([for (final p in await _stored(tester, h)) p.name], ['New']);
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Playlist saved'), findsOneWidget);
    });
  });

  group('deleting', () {
    testWidgets('asks first; cancelling keeps the playlist', (tester) async {
      final h = await _open(
        tester,
        seed: {
          'Keep': ['a'],
        },
      );

      await _openMenu(tester, 'Keep');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete the playlist?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester, h);

      expect(await _stored(tester, h), hasLength(1));
    });

    testWidgets('confirming deletes it', (tester) async {
      final h = await _open(
        tester,
        seed: {
          'Gone': ['a'],
          'Stay': [],
        },
      );

      await _openMenu(tester, 'Gone');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Delete'),
        ),
      );
      await _settle(tester, h);

      expect([for (final p in await _stored(tester, h)) p.name], ['Stay']);
      expect(find.text('Gone'), findsNothing);
      expect(find.text('Playlist deleted'), findsOneWidget);
    });
  });

  group('reordering', () {
    testWidgets('dragging the handle in the list writes the new order', (
      tester,
    ) async {
      final h = await _open(tester, seed: {'A': [], 'B': [], 'C': []});
      final height = tester.getSize(_card('A').first).height;

      await _drag(tester, 'A', Offset(0, 2 * height));
      await _settle(tester, h);

      expect(
        [for (final p in await _stored(tester, h)) p.name],
        ['B', 'C', 'A'],
      );
      final ys = [
        for (final name in ['B', 'C', 'A'])
          tester.getCenter(find.text(name)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
    });

    // 拖曳後先照新順序畫；寫入失敗時回到資料庫的順序並提示（同電台頁）。
    testWidgets('a reorder that fails to save goes back to the stored order', (
      tester,
    ) async {
      final h = await _open(tester, seed: {'A': [], 'B': [], 'C': []});
      await tester.runAsync(
        () => h
            .container(tester)
            .read(appDatabaseProvider)
            .customStatement(
              'CREATE TRIGGER fail_reorder BEFORE UPDATE OF sort_order '
              "ON playlists BEGIN SELECT RAISE(ABORT, 'test'); END",
            ),
      );
      final height = tester.getSize(_card('A').first).height;

      await _drag(tester, 'A', Offset(0, 2 * height));
      await _settle(tester, h);

      expect(
        [for (final p in await _stored(tester, h)) p.name],
        ['A', 'B', 'C'],
      );
      final ys = [
        for (final name in ['A', 'B', 'C'])
          tester.getCenter(find.text(name)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'shown as stored');
      expect(
        find.textContaining("Couldn't reorder the playlists:"),
        findsOneWidget,
      );
    });

    testWidgets('expanded and wider show a grid; dragging a card onto another '
        'moves it there', (tester) async {
      final h = await _open(
        tester,
        size: const Size(1400, 900),
        collapsePanel: true,
        seed: {
          'A': ['a'],
          'B': [],
          'C': [],
        },
      );
      expect(find.byType(ReorderableListView), findsNothing);
      // 三張卡在同一排。
      final ys = {
        for (final name in ['A', 'B', 'C'])
          tester.getCenter(find.text(name)).dy,
      };
      expect(ys, hasLength(1));
      expect(find.text('Local · 1 song'), findsOneWidget);

      await _drag(
        tester,
        'A',
        tester.getCenter(find.text('C')) - tester.getCenter(find.text('A')),
      );
      await _settle(tester, h);

      expect(
        [for (final p in await _stored(tester, h)) p.name],
        ['B', 'C', 'A'],
      );
    });

    // PR 2 留下的：格狀的拖曳只有指標能做，螢幕閱讀器以卡片的語意動作移動（清單版的
    // `ReorderableListView` 自帶同樣的動作）。
    testWidgets('in the grid a screen reader moves a card with the move '
        'actions of the list', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await _open(
        tester,
        size: const Size(1400, 900),
        collapsePanel: true,
        seed: {'A': [], 'B': [], 'C': []},
      );
      SemanticsNode card(String name) => tester.getSemantics(find.text(name));
      List<String> actions(String name) => [
        for (final id
            in card(name).getSemanticsData().customSemanticsActionIds ??
                const <int>[])
          CustomSemanticsAction.getAction(id)!.label!,
      ];
      Future<void> perform(String name, String action) async {
        final node = card(name);
        node.owner!.performAction(
          node.id,
          SemanticsAction.customAction,
          CustomSemanticsAction.getIdentifier(
            CustomSemanticsAction(label: action),
          ),
        );
        await _settle(tester, h);
      }

      expect(actions('A'), unorderedEquals(['Move right', 'Move to the end']));
      expect(
        actions('B'),
        unorderedEquals([
          'Move to the start',
          'Move left',
          'Move right',
          'Move to the end',
        ]),
      );
      expect(actions('C'), unorderedEquals(['Move to the start', 'Move left']));

      await perform('A', 'Move to the end');
      expect(
        [for (final p in await _stored(tester, h)) p.name],
        ['B', 'C', 'A'],
      );

      await perform('A', 'Move left');
      expect(
        [for (final p in await _stored(tester, h)) p.name],
        ['B', 'A', 'C'],
      );

      await perform('C', 'Move to the start');
      expect(
        [for (final p in await _stored(tester, h)) p.name],
        ['C', 'B', 'A'],
      );
      handle.dispose();
    });
  });

  group('adding to the queue', () {
    testWidgets('"Add all to queue" adds every song in order', (tester) async {
      final h = await _open(
        tester,
        seed: {
          'Mix': ['a', 'b', 'c'],
        },
      );

      await _openMenu(tester, 'Mix');
      await tester.tap(find.text('Add all to queue'));
      await _settle(tester, h);

      expect(
        [for (final e in h.controller.queue.entries) e.track.sourceId],
        ['a', 'b', 'c'],
      );
      expect(find.text('Added "Mix" to the queue'), findsOneWidget);
    });

    testWidgets('"Shuffle into queue" adds the same songs', (tester) async {
      final ids = [for (var i = 0; i < 10; i++) '$i'];
      final h = await _open(tester, seed: {'Mix': ids});

      await _openMenu(tester, 'Mix');
      await tester.tap(find.text('Shuffle into queue'));
      await _settle(tester, h);

      expect([
        for (final e in h.controller.queue.entries) e.track.sourceId,
      ], unorderedEquals(ids));
    });

    testWidgets('past the queue limit nothing is added', (tester) async {
      final h = await _open(
        tester,
        seed: {
          'Mix': ['a', 'b'],
        },
      );
      expect(
        h.controller.addToQueue([
          for (var i = 0; i < QueueModel.maxLength - 1; i++) _track('q$i'),
        ]),
        isTrue,
      );
      await tester.pump();

      await _openMenu(tester, 'Mix');
      await tester.tap(find.text('Add all to queue'));
      await _settle(tester, h);

      expect(h.controller.queue.entries, hasLength(QueueModel.maxLength - 1));
      expect(
        find.text(
          'The queue is full (10,000 songs at most); nothing was added',
        ),
        findsOneWidget,
      );
      expect(find.text('Added "Mix" to the queue'), findsNothing);
    });

    testWidgets('an empty playlist has nothing to add', (tester) async {
      await _open(tester, seed: {'Empty': []});

      await _openMenu(tester, 'Empty');

      for (final item in ['Add all to queue', 'Shuffle into queue']) {
        expect(
          tester
              .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, item))
              .onPressed,
          isNull,
          reason: item,
        );
      }
    });

    // Mix 中佇列不收（同搜尋與歷史的選單）：兩項停用並寫明原因，佇列不變。
    testWidgets('inside a Mix both are disabled', (tester) async {
      final h = ShellHarness(mix: true, registryOfSources: true);
      h.plugin.onMix = (query) => MixBatch(
        mixId: 'm1',
        title: 'Mix',
        tracks: [
          for (final id in ['m1', 'm2'])
            TrackSummary(sourceTypeId: 'fmp-test', sourceId: id, title: id),
        ],
      );
      await _open(
        tester,
        harness: h,
        seed: {
          'Road': ['a', 'b'],
        },
      );
      unawaited(h.controller.startMix(_track('seed')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.queue.mode, QueueMode.mix);

      await _openMenu(tester, 'Road');

      for (final item in [
        'Add all to queue (unavailable in a Mix)',
        'Shuffle into queue (unavailable in a Mix)',
      ]) {
        expect(
          tester
              .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, item))
              .onPressed,
          isNull,
          reason: item,
        );
      }
      expect(h.controller.queue.entries, hasLength(2));
    });
  });

  testWidgets('offline the local playlists show as usual', (tester) async {
    final h = await _open(
      tester,
      seed: {
        'Mix': ['a'],
      },
    );

    await h.setNetwork(tester, NetworkStatus.noInterface);
    await tester.pump();

    expect(find.text('No network connection'), findsOneWidget);
    expect(find.text('Mix'), findsOneWidget);
    expect(find.text('Local · 1 song'), findsOneWidget);
  });
}
