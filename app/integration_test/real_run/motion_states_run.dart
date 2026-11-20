import 'dart:convert';
import 'dart:io';

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
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/parts.dart';
import 'package:fmp/search/search.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/search/search_query.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';

/// 票 19d 的不聯網補拍：搜尋結果、分 P、播放與封面都是假的（App 打包的
/// bilibili 插件只用來畫音源標識、宣告 `listParts`；封面是記憶體裡的兩張色塊），
/// 佇列用真的佇列控制。截換歌（封面交叉淡出）、搜尋多選、展開分 P 與佇列移除
/// 一首的動畫中途（放慢 30 倍，`RealRun.slowly`）與結束。真的開 App 的那一段在
/// `motion_run.dart`；這支在那支截壞了、要重跑時用，不再打 B 站：
///
///     dart run tool/real_run.dart -d macos --out build/real_run-motion-states integration_test/real_run/motion_states_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('parts grow open and a removed queue row folds away', (
    tester,
  ) async {
    final run = RealRun.attach(tester);
    final logDir = Directory.systemTemp.createTempSync('fmp_motion_states_');
    final log = await tester.runAsync(
      () => Log.open(logDir, minimumLevel: LogLevel.info),
    );
    final host = PluginHost(
      bundles: (await tester.runAsync(() => loadBundledPlugins(rootBundle)))!,
      log: log!,
    );
    final search = _StaticSearch();
    late List<Track> parts;
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          logProvider.overrideWithValue(log),
          pluginHostProvider.overrideWith((_) => host),
          searchProvider.overrideWith(() => search),
          playbackProvider.overrideWith(_FakePlayback.new),
          partsProvider.overrideWith((ref, track) async => parts),
          coverImageLoaderProvider.overrideWithValue(
            (url) =>
                MemoryImage(base64Decode(_covers[url == 'cover-o1' ? 0 : 1])),
          ),
        ],
      ),
    );
    await run.waitFor(find.byType(HomePage));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    final plugin = (await container.read(pluginHostProvider.future))
        .plugins
        .first
        .manifest;
    final video = Track(
      ref: TrackRef(pluginId: plugin.id, trackId: 'BV1parts'),
      title: '【合集】深夜電台 夜行 BGM',
      author: '安靜的午後',
      url: 'https://example.com/BV1parts',
      duration: const Duration(hours: 1, minutes: 12, seconds: 40),
      partCount: 3,
    );
    Track song(String id, String title, int secs, {String? trackId}) => Track(
      ref: TrackRef(pluginId: plugin.id, trackId: trackId ?? id),
      title: title,
      author: '安靜的午後',
      url: 'https://example.com/$id',
      coverUrl: 'cover-$id',
      duration: Duration(seconds: secs),
    );
    parts = [
      song('p1', '深夜電台 Vol.1', 1450, trackId: 'BV1parts'),
      song('p2', '深夜電台 Vol.2', 1432, trackId: 'BV1parts?p=2'),
      song('p3', '深夜電台 Vol.3', 1478, trackId: 'BV1parts?p=3'),
    ];
    final songs = [
      song('o1', '夜行列車（Live at 河岸留言）', 280),
      song('o3', 'Night Train to Nowhere', 211),
      song('o5', 'Midnight Ferry (lofi)', 178),
    ];

    // 展開分 P。
    await openSearch(tester);
    final pointer =
        FormFactor.of(tester.element(find.byType(SearchPage))).density ==
        Density.pointer;
    final kind = pointer ? PointerDeviceKind.mouse : PointerDeviceKind.touch;
    search.show(
      SearchState(
        query: '夜',
        sources: [
          SourceResults(
            manifest: plugin,
            isEnd: true,
            pages: [
              [songs[0], video, songs[1], songs[2]],
            ],
          ),
        ],
      ),
    );
    container.read(searchQueryProvider).text = '夜';
    await run.wait(const Duration(seconds: 1));
    // 換歌：迷你播放器或播放膠囊的封面交叉淡出（兩首的封面是不同色塊）。
    final queue = container.read(queueProvider.notifier);
    await queue.add(songs);
    await queue.playAt(0);
    await run.wait(const Duration(seconds: 1));
    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );
    await run.slowly(
      'song-change',
      () => tester.tap(
        find
            .descendant(
              of: controls,
              matching: find.byTooltip(t.nowPlaying.next),
            )
            .first,
      ),
      after: const Duration(milliseconds: 500),
    );

    // 搜尋多選：動作列從底部滑入（手機的 dock 同時往下離開）。
    final results = find.byWidgetPredicate((w) => w.key is ValueKey<TrackRef>);
    if (pointer) {
      await tester.tap(results.at(0), kind: PointerDeviceKind.mouse);
      await run.wait(const Duration(milliseconds: 600));
      await run.slowly('multi-select', () async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.tap(results.at(2), kind: PointerDeviceKind.mouse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      });
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    } else {
      await run.slowly('multi-select', () async {
        final press = await tester.startGesture(
          tester.getCenter(results.at(0)),
        );
        await run.wait(kLongPressTimeout + const Duration(milliseconds: 100));
        await press.up();
      });
      await tester.tap(find.text(t.search.selection.cancel));
    }
    await run.wait(const Duration(seconds: 1));

    await run.slowly(
      'parts-expand',
      () => tester.tap(find.byTooltip(t.search.parts.expand), kind: kind),
      after: const Duration(milliseconds: 500),
    );

    // 佇列移除：三首、第二首正在播（換歌那步換過去的），移除第一首（播過的）。
    await openDestination(tester, Destination.queue);
    await run.wait(const Duration(seconds: 1));
    await run.step('queue-before');
    final firstTitle = find.text(songs[0].title).last;
    await run.slowly('queue-remove', () async {
      if (pointer) {
        await tester.tap(firstTitle, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      } else {
        await tester.tap(
          find
              .descendant(
                of: find.ancestor(
                  of: firstTitle,
                  matching: find.byWidgetPredicate(
                    (w) => w.runtimeType.toString() == 'QueueTouchRow',
                  ),
                ),
                matching: find.byKey(const Key('queue-remove')),
              )
              .first,
        );
      }
      expect(container.read(queueProvider).entries, hasLength(2));
    });

    await tester.runAsync(() async {
      await host.close();
      await log.close();
    });
    logDir.deleteSync(recursive: true);
  });
}

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

/// 不碰音訊後端的播放：播一首就停在暫停、位置 0。
class _FakePlayback extends Playback {
  @override
  PlaybackState? build() => null;

  @override
  Future<void> play(Track track, {Duration from = Duration.zero}) async =>
      state = PlaybackState(track: track, status: PlaybackStatus.paused);

  @override
  Future<void> stop() async => state = null;

  @override
  void preloadNext(Track? track) {}
}

/// 兩張 8×8 的色塊（橘、藍）當封面，換歌時看得出交叉淡出。
const _covers = [
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGN4VmGDFTEMLQkAN6BmgaudJikAAAAASUVORK5CYII=',
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGOwyXuGFTEMLQkA6IJkAWQbBcgAAAAASUVORK5CYII=',
];
