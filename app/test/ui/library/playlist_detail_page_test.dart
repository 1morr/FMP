import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 歌單詳情（M4 PR 3，ADR 0033 §決定 9，design §10.4）：從音樂庫開、標頭、分 P 分組、臨時播放、
// 本機歌單的拖曳重排與移除、匯入歌單沒有這兩項、全部加入與隨機加入（上限、空歌單、Mix）、
// 音源不可用、離線、歌單被刪掉。

const _more = 'More options';

TrackInfo _song(String id, {String source = 'fmp-test'}) => TrackInfo(
  sourceTypeId: source,
  sourceId: id,
  title: 'Song $id',
  uploader: 'Uploader $id',
  duration: const Duration(minutes: 3, seconds: 5),
);

/// 影片 [video] 的第 [index] 個分 P（標題 `Part n`，影片標題 `Video <id>`）。
TrackInfo _part(String video, int index) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: video,
  cid: 100 + index,
  title: 'Part $index',
  uploader: 'Uploader $video',
  duration: const Duration(seconds: 30),
  partIndex: index,
  parentTitle: 'Video $video',
);

/// 外殼開在音樂庫，寫好一張歌單「Road」（[tracks]；[imported] 時是匯入歌單），點它的卡片
/// 開詳情。
Future<(ShellHarness, int)> _open(
  WidgetTester tester, {
  List<TrackInfo> tracks = const [],
  bool imported = false,
  String? description,
  Size size = const Size(400, 800),
  ShellHarness? harness,
}) async {
  final h = harness ?? ShellHarness();
  await h.pumpShell(tester, size: size, at: ShellDestination.library);
  final id = (await tester.runAsync(() async {
    final repository = h.container(tester).read(playlistRepositoryProvider);
    final id = imported
        ? (await repository.createImported(
            pluginId: 'fmp-test',
            remoteId: 'r1',
            info: RemotePlaylistInfo(name: 'Road', description: description),
          ))!
        : await repository.create(name: 'Road', description: description);
    await repository.addTracks(id, tracks);
    return id;
  }))!;
  await _settle(tester, h);
  await tester.tap(find.text('Road'));
  await _settle(tester, h);
  expect(find.byType(PlaylistDetailPage), findsOneWidget);
  expect(find.byType(LibraryPage).hitTestable(), findsNothing);
  return (h, id);
}

/// 資料庫的寫入與重讀跑完。
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
    '${entry.track.sourceId}${entry.track.cid ?? ''}',
];

/// 曲目列（[ListTile]），以畫面上的標題找。
Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first;

Future<void> _openMenu(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(of: _row(title), matching: find.byTooltip(_more)),
  );
  await tester.pumpAndSettle();
}

Future<void> _drag(WidgetTester tester, String title, Offset by) async {
  final handle = find.descendant(
    of: _row(title),
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

MenuItemButton _item(WidgetTester tester, String label) =>
    tester.widget(find.widgetWithText(MenuItemButton, label));

ButtonStyleButton _button(WidgetTester tester, String label) => tester.widget(
  find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<ButtonStyleButton>(),
  ),
);

/// 畫面上（由上而下）的曲目標題。
List<String> _titlesInOrder(WidgetTester tester, List<String> titles) =>
    [...titles]..sort(
      (a, b) => tester
          .getCenter(find.text(a))
          .dy
          .compareTo(tester.getCenter(find.text(b)).dy),
    );

void main() {
  group('opening', () {
    testWidgets('a playlist card opens its details inside Library; back '
        'returns', (tester) async {
      await _open(tester, tracks: [_song('a')]);

      expect(find.byType(LibraryPage).hitTestable(), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        ShellDestination.library.index,
      );

      await tester.tap(find.byTooltip('Back (Esc)'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);
    });

    testWidgets('the wide grid opens the details too', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(
        tester,
        size: const Size(1400, 900),
        at: ShellDestination.library,
        collapsePanel: true,
      );
      await tester.runAsync(
        () => h
            .container(tester)
            .read(playlistRepositoryProvider)
            .create(name: 'Road'),
      );
      await _settle(tester, h);
      expect(find.byType(ReorderableListView), findsNothing);

      await tester.tap(find.text('Road'));
      await _settle(tester, h);

      expect(find.byType(PlaylistDetailPage), findsOneWidget);
      expect(find.byType(LibraryPage).hitTestable(), findsNothing);
    });

    testWidgets('the header shows the name, kind, count and description', (
      tester,
    ) async {
      await _open(
        tester,
        tracks: [_song('a'), _song('b')],
        description: 'For the drive',
      );

      expect(find.text('Road').hitTestable(), findsOneWidget);
      expect(find.text('Local · 2 songs').hitTestable(), findsOneWidget);
      expect(find.text('For the drive'), findsOneWidget);
    });

    testWidgets('an empty playlist says how to add songs', (tester) async {
      await _open(tester);

      expect(find.text('This playlist has no songs yet'), findsOneWidget);
      expect(
        find.text('Choose "Add to playlist…" in a song\'s menu'),
        findsOneWidget,
      );
      for (final label in ['Add all to queue', 'Shuffle into queue']) {
        expect(_button(tester, label).onPressed, isNull, reason: label);
      }
    });

    testWidgets('a playlist deleted while open says so', (tester) async {
      final (h, id) = await _open(tester, tracks: [_song('a')]);

      await tester.runAsync(
        () => h.container(tester).read(playlistRepositoryProvider).delete(id),
      );
      await _settle(tester, h);

      expect(find.text('This playlist no longer exists'), findsOneWidget);
    });
  });

  group('the songs', () {
    testWidgets('consecutive parts of one video are grouped under its title; '
        'a single part shows the video title too', (tester) async {
      await _open(
        tester,
        tracks: [
          _song('a'),
          _part('v', 1),
          _part('v', 2),
          _song('b'),
          _part('w', 3),
        ],
      );

      expect(find.text('Video v'), findsOneWidget);
      expect(find.text('P1 Part 1'), findsOneWidget);
      expect(find.text('P2 Part 2'), findsOneWidget);
      // 群組標題是一個語意標題，不是一首（不能點）。
      expect(
        tester.getSemantics(find.text('Video v')),
        isSemantics(isHeader: true, label: 'Video v\nUploader v'),
      );
      // 只有一個分 P：不成群組，標題照「影片 · 分 P」。
      expect(find.text('Video w · P3 Part 3'), findsOneWidget);
      expect(find.text('Video w'), findsNothing);
      expect(
        _titlesInOrder(tester, [
          'Song a',
          'Video v',
          'P1 Part 1',
          'P2 Part 2',
          'Song b',
          'Video w · P3 Part 3',
        ]),
        [
          'Song a',
          'Video v',
          'P1 Part 1',
          'P2 Part 2',
          'Song b',
          'Video w · P3 Part 3',
        ],
      );
      // 分 P 沒有自己的封面，縮排到和影片標題對齊。
      expect(
        tester.getTopLeft(find.text('P1 Part 1')).dx,
        closeTo(tester.getTopLeft(find.text('Video v')).dx, 1),
      );
      expect(
        find.descendant(
          of: _row('P1 Part 1'),
          matching: find.byType(ArtworkImage),
        ),
        findsNothing,
      );
    });

    testWidgets('tapping a song or a part plays it as a temporary track', (
      tester,
    ) async {
      final (h, _) = await _open(
        tester,
        tracks: [_song('a'), _part('v', 1), _part('v', 2)],
      );

      await tester.tap(find.text('P2 Part 2'));
      await tester.pump();

      expect(h.controller.queue.mode, QueueMode.temporary);
      expect(h.controller.queue.current?.cid, 102);
      expect(h.controller.queue.entries, isEmpty);
    });

    testWidgets('the menu opens the same items by right click, long press '
        'and "⋯"; Play next and Add to queue add the song', (tester) async {
      final (h, _) = await _open(tester, tracks: [_song('a'), _song('b')]);
      const items = [
        'Play',
        'Play next',
        'Add to queue',
        'Add to playlist…',
        'Remove from playlist',
      ];

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Song a')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      for (final item in items) {
        expect(find.widgetWithText(MenuItemButton, item), findsOneWidget);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Song a'));
      await tester.pumpAndSettle();
      for (final item in items) {
        expect(find.widgetWithText(MenuItemButton, item), findsOneWidget);
      }
      await tester.tap(find.widgetWithText(MenuItemButton, 'Add to queue'));
      await tester.pumpAndSettle();
      expect(find.text('Added to the queue'), findsOneWidget);

      await _openMenu(tester, 'Song b');
      await tester.tap(find.widgetWithText(MenuItemButton, 'Play next'));
      await tester.pumpAndSettle();
      expect(
        [for (final e in h.controller.queue.entries) e.track.sourceId],
        ['a', 'b'],
      );
    });

    testWidgets('a song of a source that cannot be used shows why', (
      tester,
    ) async {
      await _open(
        tester,
        harness: ShellHarness(
          sourceUnavailable: (ref, pluginId) =>
              pluginId == 'gone' ? 'Source not installed' : null,
        ),
        tracks: [
          _song('a'),
          _song('x', source: 'gone'),
        ],
      );

      expect(find.text('Uploader a'), findsOneWidget);
      expect(find.text('Uploader x'), findsNothing);
      expect(find.text('Source not installed'), findsOneWidget);
    });

    testWidgets('offline the songs show as usual', (tester) async {
      final (h, _) = await _open(tester, tracks: [_song('a')]);

      await h.setNetwork(tester, NetworkStatus.noInterface);
      await tester.pump();

      expect(find.text('No network connection'), findsOneWidget);
      expect(find.text('Song a'), findsOneWidget);
    });
  });

  group('editing a local playlist', () {
    testWidgets('dragging a handle writes the new order', (tester) async {
      final (h, id) = await _open(
        tester,
        tracks: [_song('a'), _song('b'), _song('c')],
      );
      final height = tester.getSize(_row('Song a')).height;

      await _drag(tester, 'Song a', Offset(0, 2 * height));
      await _settle(tester, h);

      expect(await _stored(tester, h, id), ['b', 'c', 'a']);
      expect(_titlesInOrder(tester, ['Song a', 'Song b', 'Song c']), [
        'Song b',
        'Song c',
        'Song a',
      ]);
    });

    testWidgets('a part dragged out of its video leaves the group', (
      tester,
    ) async {
      final (h, id) = await _open(
        tester,
        tracks: [_part('v', 1), _part('v', 2), _song('a')],
      );
      final height = tester.getSize(_row('Song a')).height;

      await _drag(tester, 'P1 Part 1', Offset(0, 2 * height));
      await _settle(tester, h);

      expect(await _stored(tester, h, id), ['v102', 'a', 'v101']);
      expect(find.text('Video v'), findsNothing);
      expect(find.text('Video v · P2 Part 2'), findsOneWidget);
      expect(find.text('Video v · P1 Part 1'), findsOneWidget);
    });

    testWidgets('a reorder that fails to save goes back to the stored order', (
      tester,
    ) async {
      final (h, id) = await _open(
        tester,
        tracks: [_song('a'), _song('b'), _song('c')],
      );
      await tester.runAsync(
        () => h
            .container(tester)
            .read(appDatabaseProvider)
            .customStatement(
              'CREATE TRIGGER fail_move BEFORE UPDATE OF position '
              "ON playlist_entries BEGIN SELECT RAISE(ABORT, 'test'); END",
            ),
      );
      final height = tester.getSize(_row('Song a')).height;

      await _drag(tester, 'Song a', Offset(0, 2 * height));
      await _settle(tester, h);

      expect(await _stored(tester, h, id), ['a', 'b', 'c']);
      expect(_titlesInOrder(tester, ['Song a', 'Song b', 'Song c']), [
        'Song a',
        'Song b',
        'Song c',
      ]);
      expect(
        find.textContaining("Couldn't reorder the songs:"),
        findsOneWidget,
      );
    });

    testWidgets('"Remove from playlist" removes only that entry', (
      tester,
    ) async {
      final (h, id) = await _open(
        tester,
        tracks: [_song('a'), _song('b'), _song('a')],
      );

      // 同一首出現兩次：移除第二個。
      await tester.tap(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text('Song a'),
                    matching: find.byType(ListTile),
                  )
                  .last,
              matching: find.byTooltip(_more),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, 'Remove from playlist'),
      );
      await _settle(tester, h);

      expect(await _stored(tester, h, id), ['a', 'b']);
      expect(find.text('Local · 2 songs'), findsOneWidget);
    });
  });

  // ADR 0019 §決定 4：匯入歌單的曲目不能在本地增刪或重排。
  testWidgets('an imported playlist has no handles and no Remove', (
    tester,
  ) async {
    await _open(tester, imported: true, tracks: [_song('a'), _song('b')]);

    expect(find.text('Imported · 2 songs'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byType(ReorderableListView), findsNothing);
    await _openMenu(tester, 'Song a');
    expect(find.widgetWithText(MenuItemButton, 'Play'), findsOneWidget);
    expect(
      find.widgetWithText(MenuItemButton, 'Add to playlist…'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(MenuItemButton, 'Remove from playlist'),
      findsNothing,
    );
  });

  group('adding to the queue', () {
    testWidgets('"Add all to queue" adds every song in order', (tester) async {
      final (h, _) = await _open(
        tester,
        tracks: [_song('a'), _part('v', 1), _song('b')],
      );

      await tester.tap(find.text('Add all to queue'));
      await _settle(tester, h);

      expect(
        [for (final e in h.controller.queue.entries) e.track.sourceId],
        ['a', 'v', 'b'],
      );
      expect(find.text('Added "Road" to the queue'), findsOneWidget);
    });

    testWidgets('"Shuffle into queue" adds the same songs', (tester) async {
      final ids = [for (var i = 0; i < 10; i++) '$i'];
      final (h, _) = await _open(
        tester,
        tracks: [for (final id in ids) _song(id)],
      );

      await tester.tap(find.text('Shuffle into queue'));
      await _settle(tester, h);

      expect([
        for (final e in h.controller.queue.entries) e.track.sourceId,
      ], unorderedEquals(ids));
      expect(h.controller.queue.shuffleEnabled, isFalse);
    });

    testWidgets('past the queue limit nothing is added', (tester) async {
      final (h, _) = await _open(tester, tracks: [_song('a'), _song('b')]);
      expect(
        h.controller.addToQueue([
          for (var i = 0; i < QueueModel.maxLength - 1; i++) _song('q$i'),
        ]),
        isTrue,
      );
      await tester.pump();

      await tester.tap(find.text('Add all to queue'));
      await _settle(tester, h);

      expect(h.controller.queue.entries, hasLength(QueueModel.maxLength - 1));
      expect(
        find.text(
          'The queue is full (10,000 songs at most); nothing was added',
        ),
        findsOneWidget,
      );
      expect(find.text('Added "Road" to the queue'), findsNothing);
    });

    // Mix 中佇列不收：兩個鈕與列選單的「下一首播放」「加入佇列」停用並寫明原因；「加入歌單…」
    // 不動佇列，照常。
    testWidgets('inside a Mix the buttons and the queue items are disabled', (
      tester,
    ) async {
      final h = ShellHarness(mix: true, registryOfSources: true);
      h.plugin.onMix = (query) => MixBatch(
        mixId: 'm1',
        title: 'Mix',
        tracks: [
          for (final id in ['m1', 'm2'])
            TrackSummary(sourceTypeId: 'fmp-test', sourceId: id, title: id),
        ],
      );
      await _open(tester, harness: h, tracks: [_song('a'), _song('b')]);
      unawaited(h.controller.startMix(_song('seed')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.queue.mode, QueueMode.mix);

      for (final label in [
        'Add all to queue (unavailable in a Mix)',
        'Shuffle into queue (unavailable in a Mix)',
      ]) {
        expect(_button(tester, label).onPressed, isNull, reason: label);
      }
      await _openMenu(tester, 'Song a');
      for (final item in [
        'Play next (unavailable in a Mix)',
        'Add to queue (unavailable in a Mix)',
      ]) {
        expect(_item(tester, item).onPressed, isNull, reason: item);
      }
      expect(_item(tester, 'Add to playlist…').onPressed, isNotNull);
      expect(h.controller.queue.entries, hasLength(2));
    });
  });
}
