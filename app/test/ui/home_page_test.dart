import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/charts/charts.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/chart.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/temporary_play.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/focus_ring.dart';
import 'package:fmp/ui/home/chart_rows.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:material_ui/material_ui.dart';

/// 首頁（`docs/design/home.html`）：近期熱門的各種狀態、繼續聽、四種版面與
/// 無障礙。排行榜的狀態由測試直接給（抓榜與快取在 `test/charts/`），插件只
/// 用來給 manifest，不會被呼叫。
void main() {
  const phone = Size(390, 844);
  const tablet = Size(820, 1180);
  const window = Size(1000, 760);
  const desktop = Size(1280, 800);
  final now = DateTime(2026, 11, 20, 12);

  late Directory logDir;
  late Log log;
  late PluginHost host;
  late _FakeCharts charts;
  late _FakeQueue queue;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_home_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    String manifest(String id, String name) => jsonEncode({
      'id': id,
      'name': name,
      'version': '1.0.0',
      'capabilities': ['charts', 'listParts'],
      'chartTitle': {'en': '$name chart', 'zh-TW': '$name 排行榜'},
      'domains': ['api.example.com'],
    });
    host = PluginHost(
      bundles: [
        PluginBundle(manifest: manifest('demo', 'Demo'), code: ''),
        PluginBundle(manifest: manifest('other', 'Other'), code: ''),
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

  PluginManifest manifestOf(String id) =>
      host.plugins.firstWhere((p) => p.manifest.id == id).manifest;

  Track track(String id, {String plugin = 'demo', int? parts}) => Track(
    ref: TrackRef(pluginId: plugin, trackId: id),
    title: 'Song $id',
    author: 'Artist $id',
    duration: const Duration(minutes: 3, seconds: 52),
    partCount: parts,
  );

  List<Track> ten([String plugin = 'demo']) => [
    for (var i = 1; i <= 10; i++) track('$plugin$i', plugin: plugin),
  ];

  SourceChart ready(
    String id, {
    List<Track>? tracks,
    Duration age = const Duration(minutes: 5),
    AppError? error,
  }) => SourceChart(
    manifest: manifestOf(id),
    chart: Chart(tracks: tracks ?? ten(id), fetchedAt: now.subtract(age)),
    error: error,
  );

  Future<void> start(
    WidgetTester tester,
    Size size, {
    List<SourceChart>? sources,
    Queue initialQueue = Queue.empty,
    TemporaryPlay? temporary,
    bool reduceMotion = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }
    charts = _FakeCharts(ChartsState(sources: sources ?? [ready('demo')]));
    queue = _FakeQueue(initialQueue);
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          pluginHostProvider.overrideWith((_) => host),
          chartsProvider.overrideWith(() => charts),
          chartsClockProvider.overrideWithValue(() => now),
          queueProvider.overrideWith(() => queue),
          temporaryPlayProvider.overrideWith(() => _FixedTemporary(temporary)),
        ],
      ),
    );
    await _settle(tester);
  }

  Finder rowTitled(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byWidgetPredicate(
      (w) => w is HomeTouchRow || w is ChartDeskRow,
    ),
  );

  group('phone', () {
    testWidgets('shows the top 5 of the chart under its title and expands to '
        '10 in place', (tester) async {
      await start(tester, phone);

      expect(find.text('近期熱門'), findsOneWidget);
      expect(find.text('Demo 排行榜 · 前 10 名'), findsOneWidget);
      expect(find.text('Song demo5'), findsOneWidget);
      expect(find.text('Song demo6'), findsNothing);

      await tester.tap(find.text('顯示第 6–10 名'));
      await _settle(tester);
      expect(find.text('Song demo10'), findsOneWidget);

      // 「收起」在第 10 名下面，捲上來才不被 dock 蓋住。
      await tester.drag(find.text('Song demo5'), const Offset(0, -300));
      await _settle(tester);
      await tester.tap(find.text('收起'));
      await _settle(tester);
      expect(find.text('Song demo6'), findsNothing);
    });

    testWidgets('asks for stale charts every time it shows', (tester) async {
      await start(tester, phone);
      expect(charts.staleChecks, 1);
    });

    testWidgets('tapping a ranked track plays it temporarily', (tester) async {
      await start(tester, phone);

      await tester.tap(find.text('Song demo2'));
      await tester.pump();

      expect(queue.calls, ['temporary demo2']);
    });

    testWidgets('a source chip switches to its chart and stays chosen', (
      tester,
    ) async {
      await start(tester, phone, sources: [ready('demo'), ready('other')]);

      await tester.tap(find.text('Other'));
      await _settle(tester);
      expect(find.text('Other 排行榜 · 前 10 名'), findsOneWidget);
      expect(find.text('Song other1'), findsOneWidget);
      expect(find.text('Song demo1'), findsNothing);
    });

    testWidgets('while loading the ranks show with skeleton rows', (
      tester,
    ) async {
      await start(
        tester,
        phone,
        sources: [SourceChart(manifest: manifestOf('demo'), loading: true)],
      );

      expect(find.byType(ChartSkeletonRow), findsNWidgets(5));
      expect(find.text('Demo 排行榜 · 前 10 名'), findsOneWidget);
    });

    testWidgets('a source that failed without a saved chart shows why and '
        'retries only itself', (tester) async {
      await start(
        tester,
        phone,
        sources: [
          ready('demo'),
          SourceChart(
            manifest: manifestOf('other'),
            error: const RateLimited(),
          ),
        ],
      );

      await tester.tap(find.text('Other'));
      await _settle(tester);
      expect(find.text('Other 的榜載入不了'), findsOneWidget);
      expect(find.text('請求太頻繁，被 Other 限流。其他音源照常顯示。'), findsOneWidget);

      await tester.tap(find.text('重試'));
      expect(charts.refreshes, ['other']);
    });

    testWidgets('offline with a saved chart keeps showing it and says how old '
        'it is', (tester) async {
      await start(
        tester,
        phone,
        sources: [
          ready(
            'demo',
            age: const Duration(hours: 3),
            error: const NetworkError(),
          ),
        ],
      );

      expect(find.text('沒有網路 · 這是 3 小時前的榜'), findsOneWidget);
      expect(find.text('Song demo1'), findsOneWidget);
    });

    testWidgets('another failure with a saved chart names the source', (
      tester,
    ) async {
      await start(
        tester,
        phone,
        sources: [
          ready(
            'demo',
            age: const Duration(minutes: 90),
            error: const RateLimited(),
          ),
        ],
      );

      expect(find.text('Demo 的榜更新不了 · 這是 1 小時前的榜'), findsOneWidget);
    });

    testWidgets('never loaded and offline is one card without chips', (
      tester,
    ) async {
      await start(
        tester,
        phone,
        sources: [
          SourceChart(
            manifest: manifestOf('demo'),
            error: const NetworkError(),
          ),
          SourceChart(
            manifest: manifestOf('other'),
            error: const NetworkError(),
          ),
        ],
      );

      expect(find.text('沒有網路，排行榜載入不了'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      await tester.tap(find.text('重試'));
      expect(charts.refreshes, [null]);
    });

    testWidgets('without a source that declares charts there is no section', (
      tester,
    ) async {
      await start(tester, phone, sources: const []);
      expect(find.text('近期熱門'), findsNothing);
    });

    testWidgets('pulling down refreshes every chart', (tester) async {
      await start(tester, phone);

      final drag = await tester.startGesture(
        tester.getCenter(find.text('Song demo1')),
      );
      for (var i = 0; i < 20; i++) {
        await drag.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(charts.refreshes, [null]);
    });

    testWidgets('a multi-part video shows its part count without an expand '
        'arrow', (tester) async {
      await start(
        tester,
        phone,
        sources: [
          ready('demo', tracks: [track('multi', parts: 3), ...ten().skip(1)]),
        ],
      );

      expect(find.text('3P'), findsOneWidget);
      expect(find.byTooltip('展開分 P'), findsNothing);
    });
  });

  group('continue listening', () {
    final upNext = Queue.empty
        .add([track('q1'), track('q2'), track('q3'), track('q4'), track('q5')])
        .jumpTo(0);

    testWidgets('shows what is playing, its place and the next 3; a next '
        'track plays from there', (tester) async {
      await start(tester, phone, initialQueue: upNext);
      await tester.scrollUntilVisible(find.text('Song q4'), 200);

      expect(find.text('繼續聽'), findsOneWidget);
      expect(find.text('第 1 / 5 首'), findsOneWidget);
      expect(find.text('Song q5'), findsNothing);

      // 捲上來，別讓 dock 蓋住。
      await tester.drag(find.text('Song q3'), const Offset(0, -200));
      await _settle(tester);
      await tester.tap(find.text('Song q3'));
      expect(queue.calls, ['playAt 2']);
    });

    testWidgets('the queue link opens the queue tab', (tester) async {
      await start(tester, phone, initialQueue: upNext);
      await tester.scrollUntilVisible(find.text('Song q4'), 200);

      await tester.tap(find.text('佇列').last);
      await _settle(tester);
      expect(find.byType(QueuePage), findsOneWidget);
    });

    testWidgets('during temporary play says where it goes back to', (
      tester,
    ) async {
      final playing = upNext.jumpTo(1);
      await start(
        tester,
        phone,
        initialQueue: playing,
        temporary: TemporaryPlay.start(
          [track('t')],
          previous: null,
          leaving: playing.current,
          position: Duration.zero,
        ),
      );
      await tester.scrollUntilVisible(find.text('Song q3'), 200);

      expect(find.text('臨時播放 · 播完回到佇列第 2 首'), findsOneWidget);
    });

    testWidgets('an empty queue has no section', (tester) async {
      await start(tester, phone);
      expect(find.text('繼續聽'), findsNothing);
    });
  });

  group('wide', () {
    final playing = Queue.empty.add([track('q1'), track('q2')]).jumpTo(0);

    testMac('one column per source, all expanding together', (tester) async {
      await start(tester, desktop, sources: [ready('demo'), ready('other')]);

      expect(find.text('· Demo 排行榜'), findsOneWidget);
      expect(find.text('· Other 排行榜'), findsOneWidget);
      final demo = tester.getTopLeft(rowTitled('Song demo1'));
      final other = tester.getTopLeft(rowTitled('Song other1'));
      expect(other.dy, demo.dy);
      expect(other.dx, greaterThan(demo.dx));
      expect(find.text('Song other6'), findsNothing);

      await tester.tap(find.text('顯示第 6–10 名'));
      await _settle(tester);
      expect(find.text('Song demo6'), findsOneWidget);
      expect(find.text('Song other6'), findsOneWidget);
      // 第 10 名的兩位數不折成兩行（名次欄只有 14 寬）。
      expect(tester.getSize(find.text('10').first).height, lessThan(20));
    });

    testMac('continue listening shows only with the detail panel '
        'collapsed', (tester) async {
      await start(tester, desktop, initialQueue: playing);
      expect(find.text('繼續聽'), findsNothing);

      await tester.tap(find.byTooltip('收起面板'));
      await _settle(tester);
      expect(find.text('繼續聽'), findsOneWidget);
    });

    testMac('a click selects, a double click or Enter plays', (tester) async {
      await start(tester, desktop);

      await tester.tap(find.text('Song demo2'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(queue.calls, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(queue.calls, ['temporary demo2']);

      await tester.tap(find.text('Song demo3'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Song demo3'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(queue.calls.last, 'temporary demo3');
    });

    testMac('hovering a row turns the rank into a play button and shows '
        'more', (tester) async {
      await start(tester, desktop);
      expect(find.byTooltip('更多'), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Song demo1')));
      await tester.pump();

      expect(find.byTooltip('播放'), findsOneWidget);
      expect(find.byTooltip('更多'), findsOneWidget);
    });
  });

  testMac('a narrow window shows one chart as 1–5 and 6–10 side by side', (
    tester,
  ) async {
    await start(tester, window);

    final first = tester.getTopLeft(rowTitled('Song demo1'));
    final sixth = tester.getTopLeft(rowTitled('Song demo6'));
    expect(sixth.dy, first.dy);
    expect(sixth.dx, greaterThan(first.dx));
  });

  testWidgets('a tablet shows one chart in two columns without durations', (
    tester,
  ) async {
    await start(tester, tablet);

    final first = tester.getTopLeft(rowTitled('Song demo1'));
    final sixth = tester.getTopLeft(rowTitled('Song demo6'));
    expect(sixth.dy, first.dy);
    expect(find.text('3:52'), findsNothing);
  });

  group('accessibility', () {
    testMac('a source chip draws the focus ring when reached by keyboard', (
      tester,
    ) async {
      await start(tester, window, sources: [ready('demo'), ready('other')]);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final ring = find.ancestor(
          of: find.text('Other'),
          matching: find.byType(FocusRing),
        );
        if (ring.evaluate().isNotEmpty &&
            tester.widget<FocusRing>(ring.first).visible) {
          return;
        }
      }
      fail('Tab never reached the Other chip');
    });

    testWidgets('on a phone the chips and the retry button take 44 tall '
        'taps', (tester) async {
      await start(
        tester,
        phone,
        sources: [
          SourceChart(manifest: manifestOf('demo'), error: const RateLimited()),
          ready('other'),
        ],
      );

      Finder tappable(String text) => find
          .ancestor(of: find.text(text), matching: find.byType(GestureDetector))
          .first;
      expect(tester.getSize(tappable('Demo')).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(tappable('重試')).height, greaterThanOrEqualTo(44));
    });

    testWidgets('with reduced motion expanding fades instead of growing', (
      tester,
    ) async {
      await start(tester, phone, reduceMotion: true);

      await tester.tap(find.text('顯示第 6–10 名'));
      await tester.pump();

      expect(find.byType(AnimatedSize), findsNothing);
      expect(
        find.ancestor(
          of: find.text('Song demo6'),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
      );
    });

    testWidgets('without reduced motion expanding grows in place', (
      tester,
    ) async {
      await start(tester, phone);
      expect(find.byType(AnimatedSize), findsOneWidget);
    });
  });
}

/// 桌面密度（macOS）的測試；跑完由框架還原平台。
void testMac(String description, WidgetTesterCallback body) => testWidgets(
  description,
  body,
  variant: TargetPlatformVariant.only(TargetPlatform.macOS),
);

class _FakeCharts extends Charts {
  _FakeCharts(this._initial);

  final ChartsState _initial;
  final refreshes = <String?>[];
  int staleChecks = 0;

  @override
  ChartsState build() => _initial;

  @override
  Future<void> refreshStale() async => staleChecks++;

  @override
  Future<void> refresh({String? only}) async => refreshes.add(only);
}

class _FakeQueue extends QueueController {
  _FakeQueue(this._initial);

  final Queue _initial;
  final calls = <String>[];

  @override
  Queue build() => _initial;

  @override
  Future<void> playTemporarily(Track track) async =>
      calls.add('temporary ${track.ref.trackId}');

  @override
  Future<void> playAt(int index) async => calls.add('playAt $index');
}

class _FixedTemporary extends TemporaryPlayHolder {
  _FixedTemporary(this._initial);

  final TemporaryPlay? _initial;

  @override
  TemporaryPlay? build() => _initial;
}

/// 等過場跑完（1 秒）；不用 pumpAndSettle：等化器與轉圈一直在動。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
