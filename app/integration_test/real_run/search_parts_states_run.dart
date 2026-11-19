import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/parts.dart';
import 'package:fmp/search/search.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/search/search_query.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 15 的畫面狀態截圖（和 `docs/design/search.html` 的「B 站多 P 展開」與
/// 桌面「分 P 展開」並排比對用）：不聯網，搜尋結果與分 P 都是假的（App 打包
/// 的 bilibili 插件只用來畫音源標識、宣告 `listParts`），深淺色用測試綁定切。
/// 每種寬度、深淺色各截一張展開分 P；手機另截父列的 ⋮ 選單（頂端寫「3 個
/// 分 P 全部套用」）與第 2 個分 P 正在播（播放狀態換成假的）。
/// macOS 截寬版（1280×800）與中寬度（960×720），手機平台截窄版：
///
///     dart run tool/real_run.dart -d macos --out build/real_run-parts-states integration_test/real_run/search_parts_states_run.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a video with parts, expanded, in light and dark', (
    tester,
  ) async {
    final run = RealRun.attach(tester);
    final logDir = Directory.systemTemp.createTempSync('fmp_parts_states_');
    final log = await tester.runAsync(
      () => Log.open(logDir, minimumLevel: LogLevel.info),
    );
    final host = PluginHost(
      bundles: (await tester.runAsync(() => loadBundledPlugins(rootBundle)))!,
      log: log!,
    );
    final search = _StaticSearch();
    final playback = _FakePlayback();
    // 先取得 manifest 才能組假的曲目；分 P 的 override 等到有了再換。
    late List<Track> parts;
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          logProvider.overrideWithValue(log),
          pluginHostProvider.overrideWith((_) => host),
          searchProvider.overrideWith(() => search),
          playbackProvider.overrideWith(() => playback),
          partsProvider.overrideWith((ref, track) async => parts),
        ],
      ),
    );
    await run.waitFor(find.byType(HomePage));
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    final manifest = (await container.read(pluginHostProvider.future))
        .plugins
        .first
        .manifest;
    final video = _video(manifest.id);
    parts = _parts(manifest.id);
    final state = SearchState(
      query: '夜',
      sources: [
        SourceResults(
          manifest: manifest,
          isEnd: true,
          pages: [
            [
              _track(manifest.id, 'o1', '夜行列車（Live at 河岸留言）', '鹿野青', 280),
              video,
              _track(
                manifest.id,
                'o3',
                'Night Train to Nowhere',
                'Juno Vale',
                211,
              ),
              _track(
                manifest.id,
                'o5',
                'Midnight Ferry (lofi)',
                'lofi atlas',
                178,
              ),
            ],
          ],
        ),
      ],
    );

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> brightness(Brightness value) async {
      binding.platformDispatcher.platformBrightnessTestValue = value;
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
      if (find.byType(SearchPage).evaluate().isEmpty) await openSearch(tester);
      await settle();
      final pointer =
          FormFactor.of(tester.element(find.byType(SearchPage))).density ==
          Density.pointer;
      final kind = pointer ? PointerDeviceKind.mouse : PointerDeviceKind.touch;
      search.show(state);
      container.read(searchQueryProvider).text = state.query;
      await settle();

      // 父列（結果的第 2 首）的 ⋮ 選單：頂端摘要寫「3 個分 P 全部套用」。
      await brightness(Brightness.light);
      if (pointer) {
        await tester.tap(
          searchResultAt(1),
          kind: kind,
          buttons: kSecondaryButton,
        );
      } else {
        await tester.tap(
          find.descendant(
            of: searchResultAt(1),
            matching: find.byTooltip(t.queue.more),
          ),
        );
      }
      await run.waitFor(
        find.textContaining(t.search.parts.appliesToAll(count: 3)),
      );
      await run.step('$width-parent-menu');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle();

      // 展開分 P：收起時先截一張當對照。
      await run.step('$width-collapsed');
      await tester.tap(find.byTooltip(t.search.parts.expand), kind: kind);
      await run.waitFor(find.text(parts[2].title));
      await settle();
      for (final b in [Brightness.light, Brightness.dark]) {
        await brightness(b);
        await run.step('$width-${b.name}-expanded');
      }

      // 第 2 個分 P 正在播：它的列標成目前的曲目，父列不再標。
      playback.set(
        PlaybackState(
          track: parts[1],
          status: PlaybackStatus.playing,
          position: const Duration(minutes: 8, seconds: 12),
          duration: parts[1].duration,
        ),
      );
      await settle();
      for (final b in [Brightness.light, Brightness.dark]) {
        await brightness(b);
        await run.step('$width-${b.name}-part-playing');
      }
      playback.set(PlaybackState(track: video, status: PlaybackStatus.paused));
      await settle();
      await brightness(Brightness.light);
      // 收起，下一種寬度重新展開。
      await tester.tap(find.byTooltip(t.search.parts.collapse), kind: kind);
      await settle();
    }
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    await tester.runAsync(() async {
      await host.close();
      await log.close();
    });
    logDir.deleteSync(recursive: true);
  });
}

Track _track(String plugin, String id, String title, String author, int secs) =>
    Track(
      ref: TrackRef(pluginId: plugin, trackId: id),
      title: title,
      author: author,
      url: 'https://example.com/$id',
      duration: Duration(seconds: secs),
    );

/// 設計稿的多 P 影片：搜尋結果是它（曲目 id 是第一個分 P 的）。
Track _video(String plugin) => Track(
  ref: TrackRef(pluginId: plugin, trackId: 'BV1parts'),
  title: '【合集】深夜電台 夜行 BGM',
  author: '安靜的午後',
  playCount: 560000,
  url: 'https://example.com/BV1parts',
  duration: const Duration(hours: 1, minutes: 12, seconds: 40),
  partCount: 3,
);

List<Track> _parts(String plugin) => [
  Track(
    ref: TrackRef(pluginId: plugin, trackId: 'BV1parts'),
    title: '深夜電台 Vol.1',
    author: '安靜的午後',
    duration: const Duration(minutes: 24, seconds: 10),
  ),
  Track(
    ref: TrackRef(pluginId: plugin, trackId: 'BV1parts?p=2'),
    title: '深夜電台 Vol.2',
    author: '安靜的午後',
    duration: const Duration(minutes: 23, seconds: 52),
  ),
  Track(
    ref: TrackRef(pluginId: plugin, trackId: 'BV1parts?p=3'),
    title: '深夜電台 Vol.3',
    author: '安靜的午後',
    duration: const Duration(minutes: 24, seconds: 38),
  ),
];

/// 狀態由情境直接換的搜尋：不打插件。
class _StaticSearch extends Search {
  @override
  SearchState? build() => null;

  void show(SearchState? value) => state = value;

  @override
  Future<void> search(String query) async {}

  @override
  Future<void> sortBy(SearchSort sort) async {}

  @override
  void loadMore({String? only}) {}

  @override
  void retry(String pluginId) {}
}

/// 狀態由情境直接換的播放：不碰音訊後端。
class _FakePlayback extends Playback {
  @override
  PlaybackState? build() => null;

  void set(PlaybackState? next) => state = next;
}
