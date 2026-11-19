import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'driver.dart';

/// 票 16 的播放頁截圖（和 `docs/design/player.html` 並排比對用）：不聯網，
/// 佇列、播放狀態與封面都是假的（封面照設計稿的配色畫在記憶體裡；App 打包
/// 的 bilibili 插件只用來畫音源標識），深淺色用測試綁定切。佇列照稿 64 首、
/// 正在播第 6 首「星屑ランデブー」1:36 / 4:09、列表循環。手機截封面、佇列
/// 畫面、滑到一半、⋮ sheet；macOS 截寬版（1280×800）與中寬度（960×720）
/// 的兩欄、關掉佇列與 ⋮ 選單：
///
///     dart run tool/real_run.dart -d macos --out build/real_run-player-states integration_test/real_run/player_states_run.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the player page in light and dark', (tester) async {
    final run = RealRun.attach(tester);
    final logDir = Directory.systemTemp.createTempSync('fmp_player_states_');
    final log = await tester.runAsync(
      () => Log.open(logDir, minimumLevel: LogLevel.info),
    );
    final host = PluginHost(
      bundles: (await tester.runAsync(() => loadBundledPlugins(rootBundle)))!,
      log: log!,
    );
    final covers = <String, Uint8List>{};
    final playback = _FakePlayback();
    final queue = _FakeQueue();
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          logProvider.overrideWithValue(log),
          pluginHostProvider.overrideWith((_) => host),
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
    final plugin = (await container.read(pluginHostProvider.future))
        .plugins
        .first
        .manifest
        .id;
    final tracks = [for (var i = 0; i < 64; i++) _track(plugin, i)];
    for (var i = 0; i < tracks.length; i++) {
      final png = await tester.runAsync(() => _cover(i == 5 ? -1 : i));
      covers[tracks[i].coverUrl!] = png!;
      covers[tracks[i].coverLargeUrl!] = png;
    }
    container
      ..read(queueProvider)
      ..read(playbackProvider);
    queue.show(Queue.empty.add(tracks).jumpTo(5).withRepeat(Repeat.all));
    playback.set(
      PlaybackState(
        track: tracks[5],
        status: PlaybackStatus.playing,
        position: const Duration(minutes: 1, seconds: 36),
        duration: tracks[5].duration,
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> brightness(Brightness value) async {
      binding.platformDispatcher.platformBrightnessTestValue = value;
      await settle();
    }

    Future<void> both(String name) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        await brightness(b);
        await run.step('$name-${b.name}');
      }
      await brightness(Brightness.light);
    }

    Future<void> openPlayer() async {
      await run.waitFor(
        find.byKey(Key(mac ? 'transport-open' : 'mini-player')),
      );
      await tester.tap(
        find.byKey(Key(mac ? 'transport-open' : 'mini-player')),
        warnIfMissed: false,
      );
      await run.waitFor(find.byType(PlayerPage));
      await tester.pump(const Duration(seconds: 1));
      await settle();
    }

    Future<void> closePlayer() async {
      await tester.tap(find.byKey(const Key('player-collapse')));
      await tester.pump(const Duration(seconds: 1));
      await settle();
    }

    final widths = mac ? ['wide', 'medium'] : ['narrow'];
    for (final width in widths) {
      if (mac) {
        await run.system('resize-$width', 'resize', [
          width == 'wide' ? '1280x800' : '960x720',
        ]);
        await settle();
      }
      await openPlayer();
      if (mac) {
        await both('$width-columns');
        // 關掉右欄的佇列：左欄移到中間。
        await tester.tap(find.byKey(const Key('player-queue-toggle')));
        await tester.pump(const Duration(seconds: 1));
        await settle();
        await both('$width-queue-off');
        await tester.tap(find.byKey(const Key('player-queue-toggle')));
        await tester.pump(const Duration(seconds: 1));
        await settle();
      } else {
        await both('$width-cover');
        // 往右滑到一半（稿的「滑到一半」是往左滑到歌詞；歌詞 M4 才有）。
        final pages = find.byKey(const Key('player-pages'));
        final gesture = await tester.startGesture(tester.getCenter(pages));
        await gesture.moveBy(const Offset(20, 0));
        await gesture.moveBy(Offset(tester.getSize(pages).width * .42 - 20, 0));
        await settle();
        await run.step('$width-swiping');
        await gesture.up();
        await settle();
        await tester.tap(find.byKey(const Key('player-dot-queue')));
        await tester.pump(const Duration(seconds: 1));
        await settle();
        await both('$width-queue');
        await tester.tap(find.byKey(const Key('player-dot-cover')));
        await tester.pump(const Duration(seconds: 1));
        await settle();
      }
      // ⋮：手機是底部 sheet，桌面是玻璃選單；跟主題走。
      for (final b in [Brightness.light, Brightness.dark]) {
        await brightness(b);
        await tester.tap(find.byKey(const Key('player-more')));
        await run.waitFor(find.text(t.search.actions.copyLink));
        await settle();
        await run.step('$width-more-${b.name}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(seconds: 1));
        await settle();
        if (!mac &&
            find.text(t.search.actions.copyLink).evaluate().isNotEmpty) {
          await tester.tapAt(const Offset(20, 200));
          await tester.pump(const Duration(seconds: 1));
          await settle();
        }
      }
      await brightness(Brightness.light);
      await closePlayer();
    }
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    await tester.runAsync(() async {
      await host.close();
      await log.close();
    });
    logDir.deleteSync(recursive: true);
  });
}

/// 設計稿的曲目（`kit.js` 的 `FMP.tracks`）輪著用；第 6 首（index 5）是稿的
/// `PL_T`「星屑ランデブー」，第 7 首是「Glass Harbor」。
Track _track(String plugin, int i) {
  const names = [
    ('夜行列車', '鹿野青', 252),
    ('【中文翻唱】群青の街', '栗子Kuri', 258),
    ('海岸線', '許晴川', 271),
    ('不眠的城', '夏目透', 235),
    ('【初音未來】ネオンの海', 'ねこじゃらしP', 238),
    ('星屑ランデブー', '藍井ほたる', 249),
    ('Glass Harbor', 'Mira Ochoa', 224),
    ('霧中燈塔', '鹿野青', 310),
    ('Northbound (Live at Hollow Hall)', 'The Lanterns', 358),
    ('雨天的貓', '白芷', 201),
    ('【合唱】春風十里 十人版', '青木社', 286),
  ];
  final (title, author, secs) = names[i < names.length ? i : 6 + i % 5];
  return Track(
    ref: TrackRef(pluginId: plugin, trackId: 'demo$i'),
    title: title,
    author: author,
    duration: Duration(seconds: secs),
    coverUrl: 'https://example.com/cover/$i',
    coverLargeUrl: 'https://example.com/cover/$i/large',
    url: 'https://example.com/video/$i',
  );
}

/// 設計稿 `FMP.cover` 的配色（`PALETTES`）：底色、一個大圓、一個小圓。
/// [i] 是 -1 時用稿的 `PL_T` 那張（`#E0AFA0`、`#463F3A`、`#F4F3EE`）。
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
  final colors = i < 0
      ? const [0xFFE0AFA0, 0xFF463F3A, 0xFFF4F3EE]
      : palettes[i % palettes.length];
  const size = 400.0;
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

/// 狀態由情境直接換的播放：不碰音訊後端。
class _FakePlayback extends Playback {
  @override
  PlaybackState? build() => null;

  void set(PlaybackState value) => state = value;

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

  @override
  void toggleShuffle() {}

  @override
  void cycleRepeat() {}
}
