import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/equalizer.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/now_playing/play_modes.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/queue/queue_rows.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/shell/nav_rail.dart';
import 'package:fmp/ui/shell/phone_dock.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/shell/side_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 佇列頁（`docs/design/queue.html`）：手機的觸控列表打開時捲到正在播的那首，
/// 能拖動排序、移除、清空（要確認）；桌面的表格用滑鼠與鍵盤操作。佇列用
/// 真的 [QueueController]，播放換成假的。
void main() {
  const phone = Size(390, 844);
  const desktop = Size(1280, 800);
  const narrowWindow = Size(960, 720);

  late Directory logDir;
  late Log log;
  late PluginHost host;
  late _FakePlayback playback;
  late ProviderContainer container;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_queue_page_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    host = PluginHost(
      bundles: [
        PluginBundle(
          manifest: jsonEncode({
            'id': 'demo',
            'name': 'Demo Source',
            'version': '1.0.0',
            'capabilities': ['search', 'resolveStream'],
            'domains': ['api.example.com'],
            'mark': {
              'short': 'Dm',
              'color': '#FB7299',
              'paths': [
                {'pathData': 'M1 1h14v14H1z', 'fillColor': '#FB7299'},
              ],
            },
          }),
          code: '',
        ),
      ],
      log: log,
    );
  });
  tearDown(() async {
    LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale);
    await host.close();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  /// 第 [n] 首（從 1 數）：三分鐘。
  Track song(int n) => Track(
    ref: TrackRef(pluginId: 'demo', trackId: 't$n'),
    title: 'Song $n',
    author: 'Artist $n',
    duration: const Duration(minutes: 3),
  );

  /// 開在首頁、放進 [count] 首、第 [current] 首（從 1 數）正在播，再從導覽
  /// 進到佇列頁。
  Future<void> start(
    WidgetTester tester,
    Size size, {
    int count = 30,
    int current = 21,
    TargetPlatform? platform,
    Track? temporary,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    playback = _FakePlayback();
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          pluginHostProvider.overrideWith((_) => host),
          playbackProvider.overrideWith(() => playback),
        ],
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    final queue = container.read(queueProvider.notifier);
    if (count > 0) {
      await queue.add([for (var i = 1; i <= count; i++) song(i)]);
      await queue.playAt(current - 1);
    }
    if (temporary != null) {
      // 正在播的那首播到 1:36，臨時播放後回來時倒退 10 秒、從 1:26 繼續。
      if (count > 0) {
        playback.set(
          PlaybackState(
            track: song(current),
            status: PlaybackStatus.paused,
            position: const Duration(minutes: 1, seconds: 36),
          ),
        );
      }
      await queue.playTemporarily(temporary);
      // 暫停：等化器停住，pumpAndSettle 才等得完。
      playback.set(
        PlaybackState(track: temporary, status: PlaybackStatus.paused),
      );
    }
    playback.played.clear();
    final label = t.shell.nav.queue;
    final dock = find.descendant(
      of: find.byType(PhoneDock),
      matching: find.text(label),
    );
    final side = find.descendant(
      of: find.byType(SideBar),
      matching: find.text(label),
    );
    final rail = find.descendant(
      of: find.byType(NavRail),
      matching: find.text(label),
    );
    await tester.tap(
      dock.evaluate().isNotEmpty
          ? dock
          : side.evaluate().isNotEmpty
          ? side
          : rail,
    );
    await tester.pumpAndSettle();
  }

  List<String> order() => [
    for (final entry in container.read(queueProvider).entries)
      entry.track.title,
  ];
  String? current() => container.read(queueProvider).current?.track.title;

  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  Finder rowOf(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byWidgetPredicate(
      (w) => w is QueueTouchRow || w is QueueTableRow,
    ),
  );

  double top(WidgetTester tester, String title) =>
      tester.getTopLeft(find.text(title)).dy;

  /// 按住 [from]，一小步一小步拖 [dy]（排序是看每一步的位置），再放開。
  Future<void> dragBy(WidgetTester tester, Finder from, double dy) async {
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 50));
    final steps = (dy.abs() / 10).ceil();
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, dy.sign * 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 在指定平台的桌面上跑：測試結束前要把平台設回去，不然框架的檢查會擋。
  void desktopTest(
    String name,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  group('phone', () {
    testWidgets('opens scrolled to the playing track with two played tracks '
        'above it', (tester) async {
      await start(tester, phone);

      expect(scrollPosition(tester).pixels, greaterThan(0));
      expect(find.text('Song 21'), findsOneWidget);
      // 正在播的落在第三列，上面露出兩首播過的。
      expect(top(tester, 'Song 19'), inInclusiveRange(62, 62 + 60));
      expect(top(tester, 'Song 20'), inInclusiveRange(62 + 60, 62 + 120));
      expect(top(tester, 'Song 21'), inInclusiveRange(62 + 120, 62 + 180));
      expect(top(tester, 'Song 18'), lessThan(62));
    });

    testWidgets('shows the totals, the played count and the up next fold', (
      tester,
    ) async {
      await start(tester, phone);
      expect(find.text('接下來'), findsOneWidget);
      expect(find.text('9 首 · 27 分'), findsOneWidget);

      scrollPosition(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('30 首 · 1 小時 30 分'), findsOneWidget);
      expect(find.text('已播放 20 首'), findsOneWidget);
    });

    testWidgets('tapping the large or the small title scrolls back to the '
        'playing track', (tester) async {
      await start(tester, phone);
      final home = scrollPosition(tester).pixels;

      scrollPosition(tester).jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue-title')));
      await tester.pumpAndSettle();
      expect(scrollPosition(tester).pixels, home);

      scrollPosition(tester).jumpTo(scrollPosition(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue-small-title')));
      await tester.pumpAndSettle();
      expect(scrollPosition(tester).pixels, home);
    });

    testWidgets('dragging the handle reorders without changing the playing '
        'track', (tester) async {
      await start(tester, phone);
      final handle = find.descendant(
        of: rowOf('Song 22'),
        matching: find.byType(QueueDragHandle),
      );

      await dragBy(tester, handle, 130);

      expect(order().sublist(20, 25), [
        'Song 21',
        'Song 23',
        'Song 24',
        'Song 22',
        'Song 25',
      ]);
      expect(current(), 'Song 21');
    });

    testWidgets('a track dragged over the fold above the playing one counts '
        'as played', (tester) async {
      await start(tester, phone);
      final handle = find.descendant(
        of: rowOf('Song 22'),
        matching: find.byType(QueueDragHandle),
      );

      await dragBy(tester, handle, -110);

      expect(order().sublist(19, 23), [
        'Song 20',
        'Song 22',
        'Song 21',
        'Song 23',
      ]);
      expect(current(), 'Song 21');
      expect(container.read(queueProvider).currentIndex, 21);
    });

    testWidgets('after the playing last track is removed, every row counts '
        'as played', (tester) async {
      await start(tester, phone, count: 3, current: 3);

      await tester.tap(
        find.descendant(
          of: rowOf('Song 3'),
          matching: find.byKey(const Key('queue-remove')),
        ),
      );
      await tester.pumpAndSettle();

      expect(current(), isNull);
      expect(find.text('已播放 2 首'), findsOneWidget);
      expect(find.text('接下來'), findsNothing);
      expect(find.byType(Equalizer), findsNothing);
    });

    testWidgets('the cross removes a track, and removing the playing one '
        'plays the next', (tester) async {
      await start(tester, phone);

      await tester.tap(
        find.descendant(
          of: rowOf('Song 23'),
          matching: find.byKey(const Key('queue-remove')),
        ),
      );
      await tester.pumpAndSettle();
      expect(order(), isNot(contains('Song 23')));
      expect(current(), 'Song 21');

      await tester.tap(
        find.descendant(
          of: rowOf('Song 21'),
          matching: find.byKey(const Key('queue-remove')),
        ),
      );
      await tester.pumpAndSettle();
      expect(current(), 'Song 22');
      expect(playback.played.map((t) => t.title), ['Song 22']);
    });

    testWidgets('tapping a row plays from that track', (tester) async {
      await start(tester, phone);

      await tester.tap(find.text('Song 24'));
      await tester.pumpAndSettle();

      expect(current(), 'Song 24');
      expect(playback.played.map((t) => t.title), ['Song 24']);
    });

    testWidgets('the equalizer moves only while playing', (tester) async {
      await start(tester, phone);
      // 第一條的高度：跳動時隨時間變，停住時不變。
      double bar() => tester
          .getSize(
            find
                .descendant(
                  of: find.byType(Equalizer),
                  matching: find.byType(Container),
                )
                .first,
          )
          .height;
      final still = bar();
      await tester.pump(const Duration(milliseconds: 300));
      expect(bar(), still);

      playback.set(
        PlaybackState(track: song(21), status: PlaybackStatus.playing),
      );
      await tester.pump();
      final before = bar();
      await tester.pump(const Duration(milliseconds: 300));
      expect(bar(), isNot(before));
    });

    testWidgets('the equalizer holds still when motion is reduced', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await start(tester, phone);
      playback.set(
        PlaybackState(track: song(21), status: PlaybackStatus.playing),
      );
      await tester.pump();
      final bar = find
          .descendant(
            of: find.byType(Equalizer),
            matching: find.byType(Container),
          )
          .first;
      final before = tester.getSize(bar).height;
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(bar).height, before);
    });
  });

  group('clearing', () {
    Future<void> openConfirm(WidgetTester tester) async {
      await tester.tap(find.byTooltip('清空佇列'));
      await tester.pumpAndSettle();
      expect(find.text('清空佇列？'), findsOneWidget);
      expect(find.text('會移除佇列裡全部 30 首曲目並停止播放。歌單不受影響。'), findsOneWidget);
    }

    testWidgets('cancel leaves the queue alone, confirm empties it and '
        'stops playback', (tester) async {
      await start(tester, phone);

      await openConfirm(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('清空佇列？'), findsNothing);
      expect(order(), hasLength(30));
      expect(playback.stops, 0);

      await openConfirm(tester);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(order(), isEmpty);
      expect(playback.stops, 1);
      expect(find.text('佇列是空的'), findsOneWidget);
    });

    testWidgets('Esc cancels and Enter does not confirm', (tester) async {
      await start(tester, phone);

      await openConfirm(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('清空佇列？'), findsOneWidget);
      expect(order(), hasLength(30));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('清空佇列？'), findsNothing);
      expect(order(), hasLength(30));
    });
  });

  group('empty queue', () {
    testWidgets('explains itself, leads to search and the library, and '
        'disables clearing', (tester) async {
      await start(tester, phone, count: 0);

      expect(find.text('佇列是空的'), findsOneWidget);
      expect(find.text('從搜尋或歌單加入曲目，就會排在這裡'), findsOneWidget);
      expect(find.textContaining('首 ·'), findsNothing);

      await tester.tap(find.byTooltip('清空佇列'));
      await tester.pumpAndSettle();
      expect(find.text('清空佇列？'), findsNothing);
      expect(
        tester.widget<GlassIconButton>(find.byType(GlassIconButton)).onTap,
        isNull,
      );

      await tester.tap(find.text('打開音樂庫'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
    });

    testWidgets('the search button opens search', (tester) async {
      await start(tester, phone, count: 0);

      await tester.tap(find.text('去搜尋'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage), findsOneWidget);
    });
  });

  group('臨時播放', () {
    const detour = Track(
      ref: TrackRef(pluginId: 'demo', trackId: 'x'),
      title: 'Detour',
      author: 'Someone',
      duration: Duration(minutes: 4, seconds: 5),
    );
    final card = find.byKey(const Key('queue-temporary'));

    /// 卡片的下緣到 [button] 下緣的距離：卡片的高照量到的字算對了，就是
    /// 底部內距，不會多出空白也不會溢出。
    double gapBelow(WidgetTester tester, String button) =>
        tester.getBottomLeft(card).dy -
        tester.getBottomLeft(find.widgetWithText(FmpButton, button)).dy;

    testWidgets('phone: the card sits above the track to go back to and says '
        'where and from when playback goes back', (tester) async {
      await start(tester, phone, temporary: detour);

      expect(card, findsOneWidget);
      expect(tester.getTopLeft(card).dy, greaterThan(62));
      expect(
        tester.getTopLeft(card).dy,
        lessThan(tester.getTopLeft(find.text('Song 21')).dy),
      );
      expect(
        find.descendant(of: card, matching: find.text('Detour')),
        findsOneWidget,
      );
      expect(find.text('不在佇列裡'), findsOneWidget);
      expect(
        find.textContaining(
          '播完或切歌後回到下方第 21 首「Song 21」，從 1:26 繼續（倒退 10 秒）',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('回來時從 1:26 繼續', findRichText: true),
        findsOneWidget,
      );
      // 正在播的不在佇列裡：佇列的列沒有等化器，只有卡片裡有。
      expect(
        find.descendant(of: rowOf('Song 21'), matching: find.byType(Equalizer)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byType(Equalizer)),
        findsOneWidget,
      );
      expect(gapBelow(tester, '下一首播放'), moreOrLessEquals(24));
    });

    testWidgets('phone: 現在回到佇列 goes back right away', (tester) async {
      await start(tester, phone, temporary: detour);

      await tester.tap(find.widgetWithText(FmpButton, '現在回到佇列'));
      await tester.pumpAndSettle();

      expect(playback.played.map((t) => t.title), ['Song 21']);
      expect(card, findsNothing);
    });

    testWidgets('phone: 下一首播放 puts the track after the one to go back to '
        'and makes it the current one', (tester) async {
      await start(tester, phone, temporary: detour);

      await tester.tap(find.widgetWithText(FmpButton, '下一首播放'));
      await tester.pumpAndSettle();

      expect(order().sublist(19, 23), [
        'Song 20',
        'Song 21',
        'Detour',
        'Song 22',
      ]);
      expect(current(), 'Detour');
      expect(playback.played, isEmpty);
      expect(card, findsNothing);
    });

    testWidgets('phone: with nothing to go back to, the card only offers '
        '下一首播放', (tester) async {
      await start(tester, phone, current: 30, temporary: detour);
      await container.read(queueProvider.notifier).remove(29);
      await tester.pumpAndSettle();
      scrollPosition(tester).jumpTo(scrollPosition(tester).maxScrollExtent);
      await tester.pumpAndSettle();

      expect(card, findsOneWidget);
      expect(find.widgetWithText(FmpButton, '現在回到佇列'), findsNothing);
      expect(find.textContaining('播完或切歌後', findRichText: true), findsNothing);
      expect(gapBelow(tester, '下一首播放'), moreOrLessEquals(24));
    });

    desktopTest('desktop: the card has its actions at the top right and the '
        'playback time', (tester) async {
      await start(
        tester,
        desktop,
        platform: TargetPlatform.windows,
        temporary: detour,
      );

      expect(card, findsOneWidget);
      expect(
        find.textContaining(
          '播完或按上一首／下一首，回到下方第 21 首「Song 21」，從 1:26 繼續（倒退 10 秒）',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('0:00 / 4:05')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Demo Source')),
        findsOneWidget,
      );
      final back = tester.getTopRight(find.widgetWithText(FmpButton, '現在回到佇列'));
      expect(back.dx, greaterThan(tester.getCenter(card).dx));
      // 卡片下緣到回去那行字的下緣是底部內距 12 加外距 8。
      final line = find.textContaining('播完或按上一首', findRichText: true);
      expect(
        tester.getBottomLeft(card).dy - tester.getBottomLeft(line).dy,
        moreOrLessEquals(20, epsilon: 1),
      );
      expect(
        find.textContaining('回來時從 1:26 繼續', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('desktop table', () {
    Future<void> startDesktop(WidgetTester tester) =>
        start(tester, desktop, platform: TargetPlatform.windows);

    desktopTest('has a header, numbered rows, the source name and the key '
        'hints', (tester) async {
      await startDesktop(tester);

      final home = scrollPosition(tester).pixels;
      scrollPosition(tester).jumpTo(0);
      await tester.pumpAndSettle();
      for (final label in ['曲目', '音源', '時長']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Alt↑'), findsOneWidget);
      expect(find.text('Enter'), findsOneWidget);
      scrollPosition(tester).jumpTo(home);
      await tester.pumpAndSettle();
      expect(find.byType(QueueTableRow), findsWidgets);
      expect(find.text('22'), findsOneWidget);
      expect(
        find.descendant(
          of: rowOf('Song 22'),
          matching: find.text('Demo Source'),
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FmpButton, '清空佇列'), findsOneWidget);
    });

    desktopTest('the context menu plays from here, moves to next and '
        'removes', (tester) async {
      await startDesktop(tester);

      await tester.tap(find.text('Song 25'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('從這首開始播放'), findsOneWidget);
      expect(find.text('移到下一首'), findsOneWidget);
      expect(find.text('從佇列移除'), findsOneWidget);

      await tester.tap(find.text('移到下一首'));
      await tester.pumpAndSettle();
      expect(order().sublist(20, 23), ['Song 21', 'Song 25', 'Song 22']);
      expect(current(), 'Song 21');
    });

    desktopTest('the context menu works from the keyboard and closes on Esc', (
      tester,
    ) async {
      await startDesktop(tester);

      await tester.tap(find.text('Song 25'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('移到下一首'), findsNothing);

      // 第一項先拿到焦點；往下一項是「移到下一首」。
      await tester.tap(find.text('Song 25'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(order().sublist(20, 23), ['Song 21', 'Song 25', 'Song 22']);
    });

    desktopTest('Enter plays the selected row, Alt+Down and Alt+Up move it, '
        'Delete and Backspace remove it', (tester) async {
      await startDesktop(tester);

      await tester.tap(find.text('Song 24'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(current(), 'Song 24');

      await tester.tap(find.text('Song 26'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(order().sublist(24, 27), ['Song 25', 'Song 27', 'Song 26']);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(order().sublist(24, 27), ['Song 25', 'Song 26', 'Song 27']);

      // 刪掉之後選取移到下一列，連按能一路刪；Backspace 也算。
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(order(), isNot(contains('Song 26')));
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(order(), isNot(contains('Song 27')));
      expect(order(), hasLength(28));
    });

    desktopTest('double click plays from that row', (tester) async {
      await startDesktop(tester);

      await tester.tap(find.text('Song 23'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Song 23'));
      await tester.pumpAndSettle();

      expect(current(), 'Song 23');
      expect(playback.played.map((t) => t.title), ['Song 23']);
    });

    desktopTest('the clear button is in the top bar', (tester) async {
      await startDesktop(tester);

      await tester.tap(find.widgetWithText(FmpButton, '清空佇列'));
      await tester.pumpAndSettle();

      expect(find.text('清空佇列？'), findsOneWidget);
    });
  });

  desktopTest('a narrow desktop window puts the clear button in the title '
      'row', (tester) async {
    await start(tester, narrowWindow, platform: TargetPlatform.macOS);
    scrollPosition(tester).jumpTo(0);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(QueuePage),
        matching: find.byType(GlassIconButton),
      ),
      findsNothing,
    );
    final clear = find.widgetWithText(FmpButton, '清空佇列');
    expect(clear, findsOneWidget);
    expect(find.text('⌥↑'), findsOneWidget);
    expect(
      (tester.getCenter(clear).dy -
              tester.getCenter(find.byKey(const Key('queue-title'))).dy)
          .abs(),
      lessThan(60),
    );
  });

  /// 隨機與循環的切換鈕（brief〈播放〉、`queue.html`〈手機：隨機、拖動與臨時
  /// 播放〉）。
  group('play modes', () {
    Finder toggle(String label) =>
        find.byWidgetPredicate((w) => w is PlayModeToggle && w.label == label);
    bool pressed(WidgetTester tester, String label) =>
        tester.widget<PlayModeToggle>(toggle(label)).on;

    testWidgets('佇列畫面永遠是播放順序、摺線在正在播的那首下方：turning shuffle '
        'on puts the playing track first with the shuffled rest under the '
        'fold, and off restores the order', (tester) async {
      await start(tester, phone);
      final original = order();

      await tester.tap(toggle('隨機'));
      await tester.pumpAndSettle();

      expect(pressed(tester, '隨機'), isTrue);
      expect(order().first, 'Song 21');
      expect(find.text('隨機順序 · 29 首 · 1 小時 27 分'), findsOneWidget);
      expect(find.text('已播放 20 首'), findsNothing);
      scrollPosition(tester).jumpTo(0);
      await tester.pumpAndSettle();
      final firstRow = find.byType(QueueTouchRow).first;
      expect(
        find.descendant(of: firstRow, matching: find.text('Song 21')),
        findsOneWidget,
      );

      await tester.tap(toggle('隨機'));
      await tester.pumpAndSettle();

      expect(pressed(tester, '隨機'), isFalse);
      expect(order(), original);
      expect(current(), 'Song 21');
      expect(find.text('9 首 · 27 分'), findsOneWidget);
      expect(playback.played, isEmpty);
    });

    testWidgets('the repeat toggle cycles off, list and single, and the line '
        'under the queue says what happens after the last track', (
      tester,
    ) async {
      await start(tester, phone);
      Future<void> scrollToEnd() async {
        final position = scrollPosition(tester);
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
      }

      await scrollToEnd();
      expect(pressed(tester, '循環'), isFalse);
      expect(find.text('循環關閉：最後一首播完就停止'), findsOneWidget);

      await tester.tap(toggle('循環'));
      await tester.pumpAndSettle();
      expect(pressed(tester, '列表循環'), isTrue);
      expect(find.text('列表循環開著：最後一首播完回到第 1 首'), findsOneWidget);

      await tester.tap(toggle('隨機'));
      await tester.pumpAndSettle();
      await scrollToEnd();
      expect(find.text('列表循環開著：最後一首播完回到第 1 首，並重新打亂'), findsOneWidget);

      await tester.tap(toggle('列表循環'));
      await tester.pumpAndSettle();
      expect(pressed(tester, '單曲循環'), isTrue);
      expect(find.text('單曲循環開著：一直重複正在播的那首'), findsOneWidget);

      await tester.tap(toggle('單曲循環'));
      await tester.pumpAndSettle();
      expect(pressed(tester, '循環'), isFalse);
    });

    testWidgets('on touch the toggle answers taps a little outside its 34 '
        'high pill, up to 44', (tester) async {
      await start(tester, phone);
      final center = tester.getCenter(toggle('隨機'));

      await tester.tapAt(center + const Offset(0, 20));
      await tester.pumpAndSettle();

      expect(pressed(tester, '隨機'), isTrue);
    });

    testWidgets('an empty queue can still set shuffle and repeat', (
      tester,
    ) async {
      await start(tester, phone, count: 0);

      await tester.tap(toggle('隨機'));
      await tester.tap(toggle('循環'));
      await tester.pumpAndSettle();

      expect(container.read(queueProvider).shuffled, isTrue);
      expect(container.read(queueProvider).repeat, Repeat.all);
    });

    desktopTest('on the desktop the toggles sit in the top bar next to the '
        'clear button and stay in sync with the transport capsule', (
      tester,
    ) async {
      await start(tester, desktop, platform: TargetPlatform.windows);
      playback.set(
        PlaybackState(
          track: container.read(queueProvider).current!.track,
          // 暫停：播放中的等化器一直動，等不到畫面靜止。
          status: PlaybackStatus.paused,
        ),
      );
      await tester.pumpAndSettle();

      final clear = find.widgetWithText(FmpButton, '清空佇列');
      expect(
        (tester.getCenter(toggle('隨機')).dy - tester.getCenter(clear).dy).abs(),
        lessThan(2),
      );

      final transportShuffle = find.descendant(
        of: find.byType(TransportBar),
        matching: find.bySemanticsLabel('隨機'),
      );
      await tester.tap(transportShuffle);
      await tester.pumpAndSettle();
      expect(pressed(tester, '隨機'), isTrue);

      await tester.tap(toggle('循環'));
      // 頂列疊著拖動視窗的區域，它的雙擊讓單擊等到雙擊逾時才算數。
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TransportBar),
          matching: find.bySemanticsLabel('列表循環'),
        ),
        findsOneWidget,
      );
    });

    for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
      desktopTest('on ${platform.name} a top-bar toggle reacts on the next '
          'frame', (tester) async {
        await start(tester, desktop, platform: platform);

        await tester.tap(toggle('隨機'));
        await tester.pump();

        expect(pressed(tester, '隨機'), isTrue);
      });
    }

    desktopTest('double-clicking the empty top bar over scrolled rows '
        'maximizes the window and plays nothing', (tester) async {
      const channel = MethodChannel('fmp/window');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await start(tester, desktop, platform: TargetPlatform.windows);
      // 打開時捲到正在播的那首，列從頂列底下捲過去。
      expect(scrollPosition(tester).pixels, greaterThan(100));
      const empty = Offset(500, 40);
      expect(
        find
            .byType(QueueTableRow)
            .evaluate()
            .where(
              (e) => tester.getRect(find.byWidget(e.widget)).contains(empty),
            ),
        isNotEmpty,
        reason: 'a row lies under the empty top bar',
      );

      await tester.tapAt(empty);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(empty);
      await tester.pumpAndSettle();

      expect(calls, contains('zoom'));
      expect(playback.played, isEmpty);
    });

    desktopTest('a narrow desktop window puts the toggles in the title row', (
      tester,
    ) async {
      await start(tester, narrowWindow, platform: TargetPlatform.macOS);
      scrollPosition(tester).jumpTo(0);
      await tester.pumpAndSettle();

      expect(
        (tester.getCenter(toggle('隨機')).dy -
                tester.getCenter(find.byKey(const Key('queue-title'))).dy)
            .abs(),
        lessThan(60),
      );
    });
  });
}

/// 假的播放：記下播了哪些曲目、停了幾次，狀態由測試直接設。
class _FakePlayback extends Playback {
  final played = <Track>[];
  int stops = 0;

  @override
  PlaybackState? build() => null;

  void set(PlaybackState next) => state = next;

  @override
  Future<void> play(Track track, {Duration from = Duration.zero}) async =>
      played.add(track);

  @override
  Future<void> stop() async => stops++;
}
