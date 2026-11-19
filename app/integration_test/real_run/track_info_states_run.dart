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
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/shell/detail_content.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'driver.dart';

/// 票 17 的曲目資訊與詳情面板截圖（和 `docs/design/player.html`〈曲目資訊〉、
/// `docs/design/shell.html` 的 `.detail` 並排比對用）：不聯網，佇列、播放狀態、
/// 封面與曲目資訊都是假的（曲目資訊照稿的示範資料；App 打包的 bilibili 插件
/// 只用來畫音源標識），深淺色用測試綁定切。手機截播放頁的曲目資訊 sheet；
/// macOS 截寬版（1280×800）詳情面板有曲目、收起、沒有曲目，中寬度（960×720）
/// 浮出的詳情面板，兩種寬度的曲目資訊對話框：
///
///     dart run tool/real_run.dart -d macos --out build/real_run-track-info-states integration_test/real_run/track_info_states_run.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('track info and the detail panel in light and dark', (
    tester,
  ) async {
    final run = RealRun.attach(tester);
    final logDir = Directory.systemTemp.createTempSync('fmp_info_states_');
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
          // 稿的示範資料（`plInfoSheet` 與 `FMP.detailPanel` 的 t01）。
          trackInfoProvider.overrideWith(
            (ref, track) async => TrackInfo(
              album: '夜行',
              publishedAt: DateTime(2026, 3, 14),
              playCount: 376272,
              likeCount: 3122,
              commentCount: 8214,
              description:
                  '收錄於 2026 年專輯《夜行》。錄音在台北一間舊公寓完成，'
                  '鋼琴是房東留下的老琴，最後一段的雜音是窗外的末班車。',
            ),
          ),
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

    void play(int index) {
      queue.show(Queue.empty.add(tracks).jumpTo(index).withRepeat(Repeat.all));
      playback.set(
        PlaybackState(
          track: tracks[index],
          status: PlaybackStatus.playing,
          position: const Duration(minutes: 1, seconds: 36),
          duration: tracks[index].duration,
        ),
      );
    }

    /// 打開曲目資訊（[open] 點的那顆），兩種深淺色各截一張再關掉。
    Future<void> info(String name, Finder open) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        await brightness(b);
        await tester.tap(open, warnIfMissed: false);
        await run.waitFor(find.text(t.trackInfo.published));
        await tester.pump(const Duration(seconds: 1));
        await settle();
        await run.step('$name-${b.name}');
        await tester.tap(find.byKey(const Key('track-info-close')));
        await tester.pump(const Duration(seconds: 1));
        await settle();
      }
      await brightness(Brightness.light);
    }

    Future<void> openPlayer() async {
      final key = Key(mac ? 'transport-open' : 'mini-player');
      await run.waitFor(find.byKey(key));
      await tester.tap(find.byKey(key), warnIfMissed: false);
      await run.waitFor(find.byType(PlayerPage));
      await tester.pump(const Duration(seconds: 1));
      await settle();
    }

    Future<void> closePlayer() async {
      await tester.tap(find.byKey(const Key('player-collapse')));
      await tester.pump(const Duration(seconds: 1));
      await settle();
    }

    // 稿的詳情面板畫的是第 1 首「夜行列車」，播放頁是第 6 首。
    if (mac) {
      await run.system('resize-wide', 'resize', ['1280x800']);
      await settle();
      await both('wide-detail-empty');
      play(0);
      await settle();
      await run.waitFor(find.byKey(const Key('detail-description')));
      await settle();
      await both('wide-detail');
      await tester.tap(find.byTooltip(t.shell.detail.hide));
      await settle();
      await both('wide-detail-hidden');
      await tester.tap(find.byTooltip(t.shell.detail.show));
      await settle();
      play(5);
      await settle();
      await openPlayer();
      await info('wide-info', find.byKey(const Key('player-info')));
      await closePlayer();

      await run.system('resize-medium', 'resize', ['960x720']);
      await settle();
      play(0);
      await tester.tap(find.byTooltip(t.shell.detail.show));
      await run.waitFor(find.byKey(const Key('detail-description')));
      await settle();
      await both('medium-detail');
      // 浮出的面板拿到焦點，Esc 關掉。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle();
      expect(find.byType(DetailContent), findsNothing);
      play(5);
      await settle();
      await openPlayer();
      await info('medium-info', find.byKey(const Key('player-info')));
      await closePlayer();
    } else {
      play(5);
      await settle();
      await openPlayer();
      await info('narrow-info', find.byKey(const Key('player-signature')));
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
