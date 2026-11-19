import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/charts/charts.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/chart.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'driver.dart';

/// 票 18 的首頁截圖（和 `docs/design/home.html` 並排比對用）：不聯網，排行榜、
/// 佇列、播放狀態與封面都是假的（榜照稿 `HM_RANK.bilibili` 的示範資料；App
/// 打包的 bilibili 插件只用來給 manifest），深淺色用測試綁定切。手機截打開、
/// 展開、第一次打開、載入中、失敗、沒有網路（有快取、從沒載入過）、有快取但
/// 更新不了；macOS
/// 截寬版（1280×800）詳情面板開著、收起並展開、載入中、失敗、沒有網路、滑過
/// 一列，窄視窗（960×720）打開、失敗、沒有網路：
///
///     dart run tool/real_run.dart -d macos --out build/real_run-home-states integration_test/real_run/home_states_run.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home page states in light and dark', (tester) async {
    final run = RealRun.attach(tester);
    final logDir = Directory.systemTemp.createTempSync('fmp_home_states_');
    final log = await tester.runAsync(
      () => Log.open(logDir, minimumLevel: LogLevel.info),
    );
    final host = PluginHost(
      bundles: (await tester.runAsync(() => loadBundledPlugins(rootBundle)))!,
      log: log!,
    );
    final now = DateTime(2026, 11, 20, 12);
    final covers = <String, Uint8List>{};
    final charts = _FakeCharts();
    final playback = _FakePlayback();
    final queue = _FakeQueue();
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          logProvider.overrideWithValue(log),
          pluginHostProvider.overrideWith((_) => host),
          chartsProvider.overrideWith(() => charts),
          chartsClockProvider.overrideWithValue(() => now),
          playbackProvider.overrideWith(() => playback),
          queueProvider.overrideWith(() => queue),
          coverImageLoaderProvider.overrideWithValue(
            (url) => MemoryImage(covers[url] ?? covers.values.first),
          ),
        ],
      ),
    );
    await run.waitFor(find.byType(HomePage));
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    final manifest = (await container.read(pluginHostProvider.future)).plugins
        .firstWhere(
          (p) => p.manifest.capabilities.contains(PluginCapability.charts),
        )
        .manifest;
    final ranked = [for (var i = 0; i < 10; i++) _ranked(manifest.id, i)];
    final queued = [for (var i = 0; i < 64; i++) _queued(manifest.id, i)];
    for (final (i, track) in [...ranked, ...queued].indexed) {
      covers[track.coverUrl!] = (await tester.runAsync(() => _cover(i)))!;
    }

    Future<void> settle() async {
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> both(String name) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        binding.platformDispatcher.platformBrightnessTestValue = b;
        await settle();
        await run.step('$name-${b.name}');
      }
      binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await settle();
    }

    void show(SourceChart source) =>
        charts.show(ChartsState(sources: [source]));
    SourceChart ready({AppError? error, Duration age = Duration.zero}) =>
        SourceChart(
          manifest: manifest,
          chart: Chart(tracks: ranked, fetchedAt: now.subtract(age)),
          error: error,
        );

    /// 稿的繼續聽：佇列 64 首、正在播第 6 首。
    void playing() {
      queue.show(Queue.empty.add(queued).jumpTo(5));
      playback.set(
        PlaybackState(
          track: queued[5],
          status: PlaybackStatus.playing,
          position: const Duration(minutes: 1, seconds: 36),
          duration: queued[5].duration,
        ),
      );
    }

    void firstRun() {
      queue.show(Queue.empty);
      playback.clear();
    }

    Future<void> states(String width) async {
      show(SourceChart(manifest: manifest, loading: true));
      await settle();
      await both('$width-loading');
      show(SourceChart(manifest: manifest, error: const RateLimited()));
      await settle();
      await both('$width-failed');
      show(ready(error: const NetworkError(), age: const Duration(hours: 3)));
      await settle();
      await both('$width-offline-cached');
      show(ready(error: const RateLimited(), age: const Duration(hours: 3)));
      await settle();
      await both('$width-stale-cached');
      show(SourceChart(manifest: manifest, error: const NetworkError()));
      await settle();
      await both('$width-offline-never');
    }

    final scroll = find.descendant(
      of: find.byType(HomePage),
      matching: find.byType(Scrollable),
    );

    if (mac) {
      await run.system('resize-wide', 'resize', ['1280x800']);
      playing();
      show(ready());
      await settle();
      await both('wide');
      // 稿的第二張：收起詳情面板、展開到 10 名。
      await tester.tap(find.byTooltip(t.shell.detail.hide));
      await settle();
      await tester.tap(find.text(t.home.showMore(from: 6, to: 10)));
      await settle();
      await both('wide-expanded-hidden');
      await tester.drag(scroll.first, const Offset(0, -400));
      await settle();
      await both('wide-continue');
      await tester.drag(scroll.first, const Offset(0, 400));
      await tester.tap(find.text(t.home.showLess));
      await tester.tap(find.byTooltip(t.shell.detail.show));
      await settle();
      // 滑過第 2 名：名次變播放鈕、尾端浮出 ⋮（Flutter 裡的滑鼠，不動游標）。
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text(ranked[1].title)));
      await settle();
      await both('wide-hover');
      await mouse.moveTo(Offset.zero);
      await mouse.removePointer();
      await states('wide');

      await run.system('resize-medium', 'resize', ['960x720']);
      show(ready());
      playing();
      await settle();
      await both('medium');
      await tester.drag(scroll.first, const Offset(0, -400));
      await settle();
      await both('medium-continue');
      await tester.drag(scroll.first, const Offset(0, 400));
      await settle();
      await states('medium');
    } else {
      firstRun();
      show(ready());
      await settle();
      await both('narrow-first-run');
      playing();
      await settle();
      await both('narrow');
      await tester.drag(scroll.first, const Offset(0, -380));
      await settle();
      await both('narrow-continue');
      await tester.drag(scroll.first, const Offset(0, 380));
      await settle();
      await tester.tap(find.text(t.home.showMore(from: 6, to: 10)));
      await settle();
      await tester.drag(scroll.first, const Offset(0, -240));
      await settle();
      await both('narrow-expanded');
      await tester.tap(find.text(t.home.showLess));
      await tester.drag(scroll.first, const Offset(0, 600));
      await settle();
      await states('narrow');
    }
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    await tester.runAsync(() async {
      await host.close();
      await log.close();
    });
    logDir.deleteSync(recursive: true);
  });
}

/// 稿的 B 站榜（`home.html` 的 `HM_RANK.bilibili`）。
Track _ranked(String plugin, int i) {
  const names = [
    ('【原創】晚安，末班車', '河堤貓', 232),
    ('【中文翻唱】群青の街', '栗子Kuri', 258),
    ('海岸線', '許晴川', 271),
    ('【鋼琴】千年之後 即興改編', '琴鍵上的鯨', 344),
    ('【初音未來】ネオンの海', 'ねこじゃらしP', 238),
    ('【合唱】春風十里 十人版', '青木社', 286),
    ('【吉他彈唱】山海之間', '阿葉', 245),
    ('霧中燈塔', '鹿野青', 310),
    ('【古箏】青花瓷 重編', '弦上小滿', 220),
    ('【翻唱】夜のむこう 女聲版', '栗子Kuri', 262),
  ];
  final (title, author, secs) = names[i];
  return Track(
    ref: TrackRef(pluginId: plugin, trackId: 'rank$i'),
    title: title,
    author: author,
    duration: Duration(seconds: secs),
    coverUrl: 'https://example.com/rank/$i',
    url: 'https://example.com/video/rank$i',
  );
}

/// 佇列裡的曲目（`kit.js` 的 `FMP.tracks` 輪著用）；第 6 首是正在播的。
Track _queued(String plugin, int i) {
  const names = [
    ('不眠的城', '夏目透', 235),
    ('Glass Harbor', 'Mira Ochoa', 224),
    ('雨天的貓', '白芷', 201),
    ('Northbound (Live at Hollow Hall)', 'The Lanterns', 358),
    ('星屑ランデブー', '藍井ほたる', 249),
    ('夜行列車', '鹿野青', 252),
    ('海岸線', '許晴川', 271),
    ('不眠的城', '夏目透', 235),
    ('霧中燈塔', '鹿野青', 310),
  ];
  final (title, author, secs) = names[i % names.length];
  return Track(
    ref: TrackRef(pluginId: plugin, trackId: 'queue$i'),
    title: title,
    author: author,
    duration: Duration(seconds: secs),
    coverUrl: 'https://example.com/queue/$i',
  );
}

/// 稿 `FMP.cover` 的配色：底色、一個大圓、一個小圓。
Future<Uint8List> _cover(int i) async {
  const palettes = [
    [0xFF1B1F3B, 0xFFF25F5C, 0xFFFFE066],
    [0xFF0B3D2E, 0xFF7BD389, 0xFFF2F7F2],
    [0xFFFFD6E0, 0xFF6D28D9, 0xFF1E1B4B],
    [0xFFF4A261, 0xFF264653, 0xFFE9C46A],
    [0xFF3A0CA3, 0xFFF72585, 0xFF4CC9F0],
    [0xFFF1FAEE, 0xFF457B9D, 0xFF1D3557],
    [0xFF0F172A, 0xFF38BDF8, 0xFFF0ABFC],
    [0xFFFAF3DD, 0xFF2A9D8F, 0xFFE76F51],
  ];
  final colors = palettes[i % palettes.length];
  const size = 160.0;
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, size, size),
      Paint()..color = Color(colors[0]),
    )
    ..drawCircle(
      const Offset(size * .42, size * .44),
      size * .36,
      Paint()..color = Color(colors[1]),
    )
    ..drawCircle(
      const Offset(size * .72, size * .74),
      size * .12,
      Paint()..color = Color(colors[2]),
    );
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// 排行榜的狀態由情境直接給：不抓榜。
class _FakeCharts extends Charts {
  @override
  ChartsState build() => const ChartsState();

  void show(ChartsState value) => state = value;

  @override
  Future<void> refreshStale() async {}

  @override
  Future<void> refresh({String? only}) async {}
}

/// 狀態由情境直接換的播放：不碰音訊後端。
class _FakePlayback extends Playback {
  @override
  PlaybackState? build() => null;

  void set(PlaybackState value) => state = value;

  void clear() => state = null;

  @override
  Future<void> playPause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  void preloadNext(Track? track) {}
}

/// 佇列由情境直接給。
class _FakeQueue extends QueueController {
  @override
  Queue build() => Queue.empty;

  void show(Queue value) => state = value;
}
