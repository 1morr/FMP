import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/radio/radio_status_jobs.dart';
import 'package:fmp/scheduler/background_scheduler.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/player/live_widgets.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

// 電台頁（ADR 0031 §決定 4、M3 design §9.3）：四種狀態、音源不能用的列、收聽、排序、刪除、
// 以網址新增、刷新（線上與離線）、空清單、離線照常顯示存的狀態。

const _more = 'More options';

/// 外殼開在電台頁；插件清單就是測試插件（宣告 `live`）。狀態間隔設成關閉，排程器不會自己
/// 跑狀態工作，只有手動刷新。
Future<ShellHarness> _openRadio(
  WidgetTester tester, {
  ShellHarness? harness,
  Size size = const Size(800, 800),
  NetworkStatus? network,
  Future<void> Function(ShellHarness h)? seed,
}) async {
  final h = harness ?? _harness();
  await h.pumpShell(tester, size: size, collapsePanel: true);
  if (network != null) await h.setNetwork(tester, network);
  await h.loadSettings(tester);
  final container = h.container(tester);
  // 資料在假時間裡寫（記憶體資料庫只靠微任務）：電台頁已經在監看這張表，runAsync 裡的
  // 交易會等不到假時間裡那個查詢放開的鎖。排程器在寫好之後才起。
  await container
      .read(networkSettingsRepositoryProvider)
      .write(radioStatusIntervalMinutes: 0);
  if (seed != null) await seed(h);
  await h.loadSettings(tester);
  // App 裡 `FmpApp` 常駐這兩個（Riverpod 3 沒人聽的 provider 會被暫停）。
  container
    ..listen(backgroundSchedulerProvider, (_, _) {})
    ..listen(radioStatusJobsProvider, (_, _) {});
  await _settle(tester);
  await tester.tap(find.text('Radio'));
  await _settle(tester);
  return h;
}

ShellHarness _harness({
  String? Function(Ref ref, String pluginId)? sourceUnavailable,
}) {
  final h = ShellHarness(
    live: true,
    registryOfSources: true,
    sourceUnavailable: sourceUnavailable ?? (_, _) => null,
  );
  h.plugin
    ..onResolveLive = ((request) => [candidate('${request.roomId}.flv')])
    ..onLiveStatus = ((query) => LiveRoom(
      roomId: query.roomId,
      title: 'Now on ${query.roomId}',
      hostName: 'Host ${query.roomId}',
      status: LiveRoomStatus.live,
      online: 1200,
    ));
  return h;
}

/// 資料庫、排程器與插件的非同步工作跑完。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// 寫一個電台（插件預設是測試插件）。
Future<void> _add(
  ShellHarness h,
  WidgetTester tester,
  String roomId, {
  String pluginId = 'fmp-test',
  RadioLiveStatus? status,
  String? liveTitle,
}) async {
  await h
      .container(tester)
      .read(radioRepositoryProvider)
      .add(
        pluginId: pluginId,
        roomId: roomId,
        title: 'Station $roomId',
        hostName: 'Host $roomId',
        addedAt: DateTime.utc(2026, 10, 14),
        liveStatus: status,
        liveTitle: liveTitle,
      );
}

/// 資料庫裡的電台（經 `radioStationsProvider` 的監看，依 `sort_order`）。排程器起來之後
/// 不在 runAsync 裡讀資料庫（見 [_openRadio]）。
Future<List<String>> _storedRooms(ShellHarness h, WidgetTester tester) async {
  await _settle(tester);
  final stations = h.container(tester).read(radioStationsProvider).value!;
  return [for (final station in stations) station.roomId];
}

Finder _row(String roomId) => find.widgetWithText(ListTile, 'Station $roomId');

Finder _tagOf(String roomId) =>
    find.descendant(of: _row(roomId), matching: find.byType(StatusTag));

Finder _toast(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

/// 標題列的排序鈕：進入手動排序模式。
Future<void> _enterSort(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Sort'));
  await tester.pumpAndSettle();
}

Future<void> _addFromUrl(WidgetTester tester, String url) async {
  await tester.tap(find.byTooltip('Add from a URL'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    url,
  );
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
  await _settle(tester);
}

void main() {
  group('the list', () {
    testWidgets('each of the four statuses has its own tag; a failed check '
        'does not look offline', (tester) async {
      final h = await _openRadio(
        tester,
        seed: (h) async {
          await _add(h, tester, 'a', status: RadioLiveStatus.live);
          await _add(h, tester, 'b', status: RadioLiveStatus.offline);
          await _add(h, tester, 'c');
          await _add(h, tester, 'd', status: RadioLiveStatus.offline);
        },
      );
      final stations = h.container(tester).read(radioStationsProvider).value!;
      // 「查詢失敗」只在記憶體（D10），資料庫裡那一列仍是未開播。
      h
          .container(tester)
          .read(radioQueryFailuresProvider.notifier)
          .mark(stations.last.id);
      await tester.pump();

      String tagText(String roomId) =>
          tester.widget<StatusTag>(_tagOf(roomId)).text;
      expect(tagText('a'), 'Live');
      expect(tagText('b'), 'Offline');
      expect(tagText('c'), 'Not checked yet');
      expect(tagText('d'), 'Check failed');

      final offline = tester.widget<StatusTag>(_tagOf('b'));
      final failed = tester.widget<StatusTag>(_tagOf('d'));
      expect(failed.icon, isNot(offline.icon));
      expect(failed.background, isNot(offline.background));
      // 封面、標題、主播都在。
      expect(
        find.descendant(of: _row('a'), matching: find.textContaining('Host a')),
        findsOneWidget,
      );
    });

    testWidgets('a live station shows its live title, an offline one does '
        'not', (tester) async {
      await _openRadio(
        tester,
        seed: (h) async {
          await _add(
            h,
            tester,
            'a',
            status: RadioLiveStatus.live,
            liveTitle: 'Tonight',
          );
          await _add(
            h,
            tester,
            'b',
            status: RadioLiveStatus.offline,
            liveTitle: 'Yesterday',
          );
        },
      );

      expect(
        find.descendant(of: _row('a'), matching: find.text('Tonight')),
        findsOneWidget,
      );
      expect(find.text('Yesterday'), findsNothing);
    });

    testWidgets('stations of a disabled or missing source stay, say why and '
        'do not play', (tester) async {
      final h = await _openRadio(
        tester,
        harness: _harness(
          sourceUnavailable: (_, pluginId) => switch (pluginId) {
            'off' => 'Source disabled',
            'gone' => 'Source not installed',
            _ => null,
          },
        ),
        seed: (h) async {
          await _add(h, tester, 'a', pluginId: 'off');
          await _add(h, tester, 'b', pluginId: 'gone');
        },
      );

      expect(
        find.descendant(
          of: _row('a'),
          matching: find.textContaining('Source disabled'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('b'),
          matching: find.textContaining('Source not installed'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Host a'), findsNothing);

      await tester.tap(_row('a'));
      await tester.pump();
      expect(_toast("Can't play: Source disabled"), findsOneWidget);
      expect(h.controller.queue.live, isNull);
      expect(h.plugin.liveRequests, isEmpty);
    });

    testWidgets('empty: explains both ways to add one', (tester) async {
      await _openRadio(tester);

      final empty = find.byType(EmptyState);
      expect(
        find.descendant(of: empty, matching: find.text('No stations yet')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: empty,
          matching: find.textContaining('"Live rooms"'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: empty, matching: find.textContaining('by its URL')),
        findsOneWidget,
      );
      // 空清單的按鈕開同一個對話框。
      await tester.tap(
        find.descendant(of: empty, matching: find.text('Add from a URL')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add a station from a URL'), findsOneWidget);
    });

    testWidgets('offline, the list shows the stored status as it is', (
      tester,
    ) async {
      final h = await _openRadio(
        tester,
        network: NetworkStatus.noInterface,
        seed: (h) async {
          await _add(h, tester, 'a', status: RadioLiveStatus.live);
          await _add(h, tester, 'b', status: RadioLiveStatus.offline);
        },
      );

      expect(tester.widget<StatusTag>(_tagOf('a')).text, 'Live');
      expect(tester.widget<StatusTag>(_tagOf('b')).text, 'Offline');
      expect(find.byType(OfflineMessage), findsNothing);
      expect(h.plugin.liveStatusQueries, isEmpty);
    });
  });

  group('listening', () {
    testWidgets('tapping a station listens to it and marks its row', (
      tester,
    ) async {
      final h = await _openRadio(
        tester,
        seed: (h) async {
          await _add(
            h,
            tester,
            'a',
            status: RadioLiveStatus.live,
            liveTitle: 'Tonight',
          );
          await _add(h, tester, 'b');
        },
      );

      await tester.tap(_row('a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final live = h.controller.queue.live!.target;
      expect((live.pluginId, live.roomId), ('fmp-test', 'a'));
      // 標題取最近查到的直播標題。
      expect(live.title, 'Tonight');
      expect(h.plugin.liveRequests.single.roomId, 'a');
      expect(tester.widget<ListTile>(_row('a')).selected, isTrue);
      expect(tester.widget<ListTile>(_row('b')).selected, isFalse);
    });
  });

  group('editing', () {
    testWidgets('dragging the handle reorders the stations', (tester) async {
      final h = await _openRadio(
        tester,
        seed: (h) async {
          for (final id in ['a', 'b', 'c']) {
            await _add(h, tester, id);
          }
        },
      );
      await _enterSort(tester);
      final height = tester.getSize(_row('a')).height;

      final handle = find.descendant(
        of: _row('a'),
        matching: find.byIcon(Icons.drag_handle),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      for (var step = 0; step < 8; step++) {
        await gesture.moveBy(Offset(0, 2 * height / 8));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(await _storedRooms(h, tester), ['b', 'c', 'a']);
      final ys = [
        for (final id in ['b', 'c', 'a']) tester.getCenter(_row(id)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
    });

    // 拖曳後先照新順序畫（樂觀更新）；寫入失敗時回到資料庫的順序並提示，畫面與資料庫一致。
    testWidgets('a reorder that fails to save goes back to the stored order', (
      tester,
    ) async {
      final h = await _openRadio(
        tester,
        seed: (h) async {
          for (final id in ['a', 'b', 'c']) {
            await _add(h, tester, id);
          }
          // 只讓排序的寫入失敗：改 `sort_order` 的 UPDATE 一律中止。
          await h
              .container(tester)
              .read(appDatabaseProvider)
              .customStatement(
                'CREATE TRIGGER fail_reorder BEFORE UPDATE OF sort_order '
                "ON radio_stations BEGIN SELECT RAISE(ABORT, 'test'); END",
              );
        },
      );
      await _enterSort(tester);
      final height = tester.getSize(_row('a')).height;

      final handle = find.descendant(
        of: _row('a'),
        matching: find.byIcon(Icons.drag_handle),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      for (var step = 0; step < 8; step++) {
        await gesture.moveBy(Offset(0, 2 * height / 8));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(await _storedRooms(h, tester), ['a', 'b', 'c']);
      final ys = [
        for (final id in ['a', 'b', 'c']) tester.getCenter(_row(id)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'shown as stored');
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining("Couldn't reorder the stations:"),
        ),
        findsOneWidget,
      );
    });

    testWidgets('only the handle drags, the rest of the row does not', (
      tester,
    ) async {
      final h = await _openRadio(
        tester,
        seed: (h) async {
          for (final id in ['a', 'b']) {
            await _add(h, tester, id);
          }
        },
      );

      await _enterSort(tester);
      await tester.drag(_row('a'), const Offset(0, 200));
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(await _storedRooms(h, tester), ['a', 'b']);
    });

    testWidgets('removing asks first; cancelling keeps the station', (
      tester,
    ) async {
      final h = await _openRadio(tester, seed: (h) => _add(h, tester, 'a'));

      Future<void> openRemove() async {
        await tester.tap(
          find.descendant(of: _row('a'), matching: find.byTooltip(_more)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, 'Remove'));
        await tester.pumpAndSettle();
        expect(find.text('Remove the station?'), findsOneWidget);
      }

      await openRemove();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _settle(tester);
      expect(await _storedRooms(h, tester), ['a']);

      await openRemove();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pump();
      await _settle(tester);
      expect(await _storedRooms(h, tester), isEmpty);
      expect(_toast('Station removed'), findsOneWidget);
      expect(_row('a'), findsNothing);
    });
  });

  group('layout and sorting', () {
    Future<void> seedLive(ShellHarness h, WidgetTester tester) async {
      await _add(h, tester, 'a', status: RadioLiveStatus.offline);
      await _add(h, tester, 'b', status: RadioLiveStatus.live);
      await _add(h, tester, 'c');
      await _add(h, tester, 'd', status: RadioLiveStatus.live);
    }

    List<String> shownOrder(WidgetTester tester) {
      // 清單由上到下，網格由左到右、再下一排。
      Offset at(String room) => tester.getCenter(find.text('Station $room'));
      return ['a', 'b', 'c', 'd']..sort((x, y) {
        final byRow = at(x).dy.compareTo(at(y).dy);
        return byRow != 0 ? byRow : at(x).dx.compareTo(at(y).dx);
      });
    }

    testWidgets('live stations come first, the rest keep their order', (
      tester,
    ) async {
      final h = await _openRadio(tester, seed: (h) => seedLive(h, tester));
      expect(shownOrder(tester), ['b', 'd', 'a', 'c']);
      // 資料庫的順序沒有動。
      expect(await _storedRooms(h, tester), ['a', 'b', 'c', 'd']);
    });

    testWidgets('sort mode shows the stored order with handles; Done leaves', (
      tester,
    ) async {
      await _openRadio(tester, seed: (h) => seedLive(h, tester));
      expect(find.byIcon(Icons.drag_handle), findsNothing);

      await _enterSort(tester);
      expect(shownOrder(tester), ['a', 'b', 'c', 'd']);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(4));
      // 排序模式裡標題列只有「完成」。
      expect(find.byTooltip('Add from a URL'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.drag_handle), findsNothing);
      expect(shownOrder(tester), ['b', 'd', 'a', 'c']);
      expect(find.byTooltip('Sort'), findsOneWidget);
    });

    testWidgets('the sort button is off while the list is empty', (
      tester,
    ) async {
      await _openRadio(tester);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.sort))
            .onPressed,
        isNull,
      );
    });

    for (final (width, grid) in [
      (500.0, false),
      (800.0, false),
      (1100.0, true),
    ]) {
      testWidgets('at $width wide the stations are '
          '${grid ? 'a grid of round covers' : 'a list'}', (tester) async {
        await _openRadio(
          tester,
          size: Size(width, 800),
          seed: (h) => seedLive(h, tester),
        );
        expect(find.byType(GridView), grid ? findsOneWidget : findsNothing);
        expect(find.byType(ListTile), grid ? findsNothing : findsWidgets);
        expect(find.byType(ClipOval), grid ? findsWidgets : findsNothing);
        // 網格也是開播優先。
        expect(shownOrder(tester), ['b', 'd', 'a', 'c']);
      });
    }

    testWidgets('a grid cell listens on tap and removes from its menu', (
      tester,
    ) async {
      final h = await _openRadio(
        tester,
        size: const Size(1100, 800),
        seed: (h) => _add(h, tester, 'a', status: RadioLiveStatus.live),
      );
      await tester.tap(find.byTooltip(_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove the station?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      await _settle(tester);
      expect(await _storedRooms(h, tester), isEmpty);
    });
  });

  group('adding from a URL', () {
    testWidgets('a recognised URL is added', (tester) async {
      final h = await _openRadio(tester);
      h.plugin.onLiveRoomFromUrl = (query) =>
          query.url == 'https://fmp.test/live/r1'
          ? const LiveRoomRef(roomId: 'r1')
          : null;

      await _addFromUrl(tester, 'https://fmp.test/live/r1');

      expect(_toast('Added to Radio'), findsOneWidget);
      expect(await _storedRooms(h, tester), ['r1']);
      expect(find.widgetWithText(ListTile, 'Now on r1'), findsOneWidget);
    });

    testWidgets('a station already in the list says so', (tester) async {
      final h = await _openRadio(tester, seed: (h) => _add(h, tester, 'r1'));
      h.plugin.onLiveRoomFromUrl = (_) => const LiveRoomRef(roomId: 'r1');

      await _addFromUrl(tester, 'https://fmp.test/live/r1');

      expect(_toast('Already in your stations'), findsOneWidget);
      expect(await _storedRooms(h, tester), ['r1']);
    });

    testWidgets('a URL no plugin knows says so', (tester) async {
      final h = await _openRadio(tester);
      h.plugin.onLiveRoomFromUrl = (_) => null;

      await _addFromUrl(tester, 'https://example.com/whatever');

      expect(_toast("This URL isn't recognized"), findsOneWidget);
      expect(await _storedRooms(h, tester), isEmpty);
    });

    testWidgets('a plugin that fails is shown as an error', (tester) async {
      final h = await _openRadio(tester);
      h.plugin.onLiveRoomFromUrl = (_) =>
          throw NetworkError(pluginId: 'fmp-test');

      await _addFromUrl(tester, 'https://fmp.test/live/r1');

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining("Couldn't add the station:"),
        ),
        findsOneWidget,
      );
      expect(await _storedRooms(h, tester), isEmpty);
    });
  });

  group('refreshing', () {
    testWidgets('online, every station is checked and the list updates', (
      tester,
    ) async {
      final h = await _openRadio(
        tester,
        seed: (h) => _add(h, tester, 'a', status: RadioLiveStatus.offline),
      );
      expect(tester.widget<StatusTag>(_tagOf('a')).text, 'Offline');

      await tester.tap(find.byTooltip('Refresh status'));
      await _settle(tester);

      expect(h.plugin.liveStatusQueries.single.roomId, 'a');
      expect(tester.widget<StatusTag>(_tagOf('a')).text, 'Live');
      expect(
        find.descendant(of: _row('a'), matching: find.text('Now on a')),
        findsOneWidget,
      );
      expect(_toast('Station status updated'), findsOneWidget);
    });

    testWidgets('offline, nothing is sent and the page says the status is '
        'the last known one', (tester) async {
      final h = await _openRadio(
        tester,
        network: NetworkStatus.noInterface,
        seed: (h) => _add(h, tester, 'a', status: RadioLiveStatus.offline),
      );

      await tester.tap(find.byTooltip('Refresh status'));
      await _settle(tester);

      expect(h.plugin.liveStatusQueries, isEmpty);
      expect(find.textContaining('Offline, not refreshed'), findsOneWidget);
      expect(tester.widget<StatusTag>(_tagOf('a')).text, 'Offline');

      // 回到線上就收起。
      await h.setNetwork(tester, NetworkStatus.online);
      await tester.pump();
      expect(find.textContaining('Offline, not refreshed'), findsNothing);
    });

    testWidgets('refresh is off while the list is empty', (tester) async {
      await _openRadio(tester);

      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull,
      );
    });
  });

  group('the live player', () {
    testWidgets('the provider follows the room being listened to', (
      tester,
    ) async {
      final h = await _openRadio(
        tester,
        seed: (h) => _add(h, tester, 'a', status: RadioLiveStatus.live),
      );

      await tester.tap(_row('a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        h.container(tester).read(nowPlayingLiveProvider)?.target.roomId,
        'a',
      );

      unawaited(h.controller.stopLive());
      await tester.pump();
      expect(h.container(tester).read(nowPlayingLiveProvider), isNull);
    });
  });
}
