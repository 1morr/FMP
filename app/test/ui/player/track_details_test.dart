import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/player/track_detail_parts.dart';
import 'package:fmp/ui/player/track_detail_provider.dart';
import 'package:fmp/ui/player/track_details.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// 詳細區（M3 design §11.2）：插件宣告 `trackDetail` 才多顯示欄位；每首第一次顯示時取一次，
// 結果進記憶體 LRU；失敗只在詳細區顯示與重試。

const _track = TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: 'a',
  title: 'Song a',
  uploader: 'Uploader a',
);

const _other = TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: 'b',
  title: 'Song b',
  uploader: 'Uploader b',
);

final _full = TrackDetail(
  description: 'About the song',
  publishedAt: DateTime.utc(2024, 5, 17, 12),
  album: 'The album',
  stats: [
    for (final kind in TrackStatKind.values)
      TrackStat(kind: kind, count: kind == TrackStatKind.view ? 46000000 : 3),
  ],
);

Future<ShellHarness> _pump(
  WidgetTester tester, {
  bool trackDetail = true,
  FutureOr<TrackDetail> Function(TrackDetailQuery query)? onDetail,
  TrackInfo track = _track,
  Size size = const Size(1000, 700),
}) async {
  final h = ShellHarness(trackDetail: trackDetail, registryOfSources: true);
  if (trackDetail) h.plugin.onTrackDetail = onDetail ?? (_) => _full;
  await h.pumpApp(
    tester,
    Scaffold(body: TrackDetails(track: track)),
    size: size,
  );
  await tester.pump();
  await tester.pump();
  return h;
}

void main() {
  group('the detail area', () {
    testWidgets('a plugin without trackDetail shows the existing data only', (
      tester,
    ) async {
      final h = await _pump(tester, trackDetail: false);

      expect(find.text('Uploader a'), findsOneWidget);
      expect(find.text('Test Source'), findsOneWidget);
      expect(find.text('Published'), findsNothing);
      expect(find.byType(TrackDetailPlaceholder), findsNothing);
      expect(h.plugin.trackDetailQueries, isEmpty);
    });

    testWidgets('a plugin with trackDetail adds the new fields', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await _pump(tester);

      expect(h.plugin.trackDetailQueries.single.sourceId, 'a');
      expect(find.text('Uploader a'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
      expect(find.textContaining('2024'), findsOneWidget);
      expect(find.text('Album'), findsOneWidget);
      expect(find.text('The album'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('About the song'), findsOneWidget);
      // 統計依 kind 翻譯，人數用同一套縮寫。
      expect(find.bySemanticsLabel('Views 46M'), findsOneWidget);
      for (final name in [
        'Likes',
        'Favorites',
        'Comments',
        'Shares',
        'Danmaku',
        'Coins',
      ]) {
        expect(find.bySemanticsLabel('$name 3'), findsOneWidget, reason: name);
      }
      handle.dispose();
    });

    testWidgets('an empty detail adds nothing', (tester) async {
      await _pump(tester, onDetail: (_) => const TrackDetail());

      expect(find.byType(TrackDetailFields), findsOneWidget);
      expect(find.text('Published'), findsNothing);
      expect(find.text('Description'), findsNothing);
    });

    testWidgets('the cid of a part track reaches the plugin', (tester) async {
      final h = await _pump(
        tester,
        track: const TrackInfo(
          sourceTypeId: 'fmp-test',
          sourceId: 'a',
          cid: 7,
          title: 'Part',
        ),
      );

      expect(h.plugin.trackDetailQueries.single.cid, 7);
    });

    testWidgets('while loading a placeholder stands in, then the data', (
      tester,
    ) async {
      final completer = Completer<TrackDetail>();
      await _pump(tester, onDetail: (_) => completer.future);

      expect(find.byType(TrackDetailPlaceholder), findsOneWidget);
      expect(find.text('Published'), findsNothing);

      completer.complete(_full);
      await tester.pump();
      await tester.pump();

      expect(find.byType(TrackDetailPlaceholder), findsNothing);
      expect(find.text('Published'), findsOneWidget);
    });

    testWidgets('a failure shows in the area only, and retry fetches again', (
      tester,
    ) async {
      var calls = 0;
      final h = await _pump(
        tester,
        onDetail: (_) {
          calls++;
          if (calls == 1) throw NetworkError(pluginId: 'fmp-test');
          return _full;
        },
      );

      expect(find.text('Could not load the details'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // 其他欄位還在，也沒有跳提示。
      expect(find.text('Uploader a'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(h.plugin.trackDetailQueries, hasLength(2));
      expect(find.text('Could not load the details'), findsNothing);
      expect(find.text('Published'), findsOneWidget);
    });

    testWidgets('a failure while offline says so', (tester) async {
      final h = await _pump(
        tester,
        onDetail: (_) => throw NetworkError(pluginId: 'fmp-test'),
      );
      await h.setNetwork(tester, NetworkStatus.noInterface);

      expect(find.text('Could not load the details'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('a long description folds and unfolds', (tester) async {
      await _pump(
        tester,
        onDetail: (_) => TrackDetail(
          description: List.generate(12, (i) => 'Line $i').join('\n'),
        ),
      );

      expect(find.text('Show more'), findsOneWidget);
      var text = tester.widget<Text>(
        find.textContaining('Line 0', findRichText: false),
      );
      expect(text.maxLines, 4);

      await tester.tap(find.text('Show more'));
      await tester.pump();

      expect(find.text('Show less'), findsOneWidget);
      text = tester.widget<Text>(
        find.textContaining('Line 0', findRichText: false),
      );
      expect(text.maxLines, isNull);
    });

    testWidgets('a short description has no unfold button', (tester) async {
      await _pump(tester);

      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('no avatar in the detail, no avatar in the row', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Published'), findsOneWidget);
      expect(find.byType(ClipOval), findsNothing);
    });

    testWidgets('the uploader avatar shows next to the uploader', (
      tester,
    ) async {
      await _pump(
        tester,
        onDetail: (_) => TrackDetail(
          uploaderAvatar: [
            Artwork(url: Uri.parse('https://example.test/a.png')),
          ],
        ),
      );

      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('a track shown again reads the memory cache', (tester) async {
      final current = ValueNotifier(_track);
      final h = ShellHarness(trackDetail: true, registryOfSources: true);
      h.plugin.onTrackDetail = (_) => _full;
      await h.pumpApp(
        tester,
        ValueListenableBuilder(
          valueListenable: current,
          builder: (context, track, _) =>
              Scaffold(body: TrackDetails(track: track)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(h.plugin.trackDetailQueries.map((q) => q.sourceId), ['a']);

      current.value = _other;
      await tester.pump();
      await tester.pump();
      expect(h.plugin.trackDetailQueries.map((q) => q.sourceId), ['a', 'b']);

      current.value = _track;
      await tester.pump();
      await tester.pump();

      // 回到第一首：不再呼叫，資料仍在。
      expect(h.plugin.trackDetailQueries.map((q) => q.sourceId), ['a', 'b']);
      expect(find.text('Published'), findsOneWidget);
    });

    testWidgets('a cached track shows its data in the first frame', (
      tester,
    ) async {
      final current = ValueNotifier(_track);
      final h = ShellHarness(trackDetail: true, registryOfSources: true);
      h.plugin.onTrackDetail = (_) => _full;
      await h.pumpApp(
        tester,
        ValueListenableBuilder(
          valueListenable: current,
          builder: (context, track, _) =>
              Scaffold(body: TrackDetails(track: track)),
        ),
      );
      await tester.pump();
      await tester.pump();
      current.value = _other;
      await tester.pump();
      await tester.pump();

      current.value = _track;
      await tester.pump();

      // 只 pump 一格：快取同步回傳，不閃一下佔位。
      expect(find.byType(TrackDetailPlaceholder), findsNothing);
      expect(find.text('Published'), findsOneWidget);
    });

    testWidgets('leaving and coming back while loading reuses the request', (
      tester,
    ) async {
      final shown = ValueNotifier(true);
      final completer = Completer<TrackDetail>();
      final h = ShellHarness(trackDetail: true, registryOfSources: true);
      h.plugin.onTrackDetail = (_) => completer.future;
      await h.pumpApp(
        tester,
        ValueListenableBuilder(
          valueListenable: shown,
          builder: (context, visible, _) => Scaffold(
            body: visible
                ? const TrackDetails(track: _track)
                : const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(TrackDetailPlaceholder), findsOneWidget);

      // 回應之前切走（分頁、收起面板）再回來。
      shown.value = false;
      await tester.pump();
      await tester.pump();
      shown.value = true;
      await tester.pump();
      await tester.pump();

      expect(h.plugin.trackDetailQueries, hasLength(1));
      completer.complete(_full);
      await tester.pump();
      await tester.pump();
      expect(find.text('Published'), findsOneWidget);
      expect(h.plugin.trackDetailQueries, hasLength(1));
    });
  });

  group('the memory cache', () {
    TrackDetail detail(int n) => TrackDetail(description: 'd$n');

    test('keeps the last 32 and drops the oldest one beyond that', () {
      final cache = TrackDetailCache();
      for (var i = 0; i < trackDetailCacheSize; i++) {
        cache.put('k$i', detail(i));
      }
      expect(cache.get('k0'), isNotNull);
      expect(cache.get('k31'), isNotNull);

      // 第 33 筆：k0 剛被讀過（最近用過），所以擠掉的是 k1。
      cache.put('k32', detail(32));

      expect(cache.get('k1'), isNull);
      expect(cache.get('k0'), isNotNull);
      expect(cache.get('k32'), isNotNull);
    });

    test('the 33rd entry evicts the oldest when nothing was read', () {
      final cache = TrackDetailCache();
      for (var i = 0; i <= trackDetailCacheSize; i++) {
        cache.put('k$i', detail(i));
      }

      expect(cache.get('k0'), isNull);
      expect(cache.get('k1'), isNotNull);
      expect(cache.get('k32'), isNotNull);
    });

    test('putting a key again replaces it without growing', () {
      final cache = TrackDetailCache(capacity: 2)
        ..put('a', detail(1))
        ..put('a', detail(2))
        ..put('b', detail(3));

      expect(cache.get('a')!.description, 'd2');
      expect(cache.get('b'), isNotNull);
    });
  });
}
