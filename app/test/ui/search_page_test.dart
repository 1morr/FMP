import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/web_links.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/search.dart';
import 'package:fmp/search/search_history.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/search/search_parts.dart';
import 'package:fmp/ui/shell/phone_dock.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell.dart';

/// 照稿的搜尋頁（`docs/design/search.html`）：搜尋紀錄、結果、單一音源出錯、
/// 找不到、排序、⋮ 選單、多選與桌面表格。搜尋的狀態與佇列換成假的，畫面
/// 只看它們；跨插件搜尋本身在 `test/search/search_test.dart`。
void main() {
  const phone = Size(390, 844);
  const tablet = Size(820, 1180);
  const desktop = Size(1280, 800);

  late Directory logDir;
  late Log log;
  late PluginHost host;
  late _FakeQueue queue;
  late _FakeSearch search;
  late _FakeLinks links;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_search_page_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    host = PluginHost(
      bundles: [
        PluginBundle(manifest: _songs.source, code: ''),
        PluginBundle(manifest: _busy.source, code: ''),
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

  /// 開 App、進搜尋頁；[state] 不是 null 時欄位填好它的查詢（像剛搜過）。
  Future<void> start(
    WidgetTester tester,
    Size size, {
    SearchState? state,
    bool mouse = false,
  }) async {
    if (mouse) {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
    }
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    queue = _FakeQueue();
    search = _FakeSearch(state);
    links = _FakeLinks();
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          logProvider.overrideWithValue(log),
          pluginHostProvider.overrideWith((_) => host),
          queueProvider.overrideWith(() => queue),
          searchProvider.overrideWith(() => search),
          webLinksProvider.overrideWithValue(links),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openSearch(tester);
    if (state != null) {
      await tester.enterText(find.byType(TextField), state.query);
    }
    await tester.pumpAndSettle();
  }

  /// 測試結束前還原平台（框架在 tearDown 之前檢查）。
  void done() => debugDefaultTargetPlatformOverride = null;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SearchPage)));

  group('search history', () {
    testWidgets('lists past searches; a tap searches again, × removes one, '
        'and Clear removes all', (tester) async {
      await start(tester, phone);
      final history = container(tester).read(searchHistoryProvider.notifier);
      await history.record('鹿野青');
      await history.record('夜行列車');
      await tester.pumpAndSettle();

      expect(find.text('搜尋紀錄'), findsOneWidget);
      expect(find.text('夜行列車'), findsOneWidget);

      await tester.tap(find.text('鹿野青'));
      await tester.pumpAndSettle();
      expect(search.calls, ['search 鹿野青']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '鹿野青',
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('刪除這筆紀錄').first);
      await tester.pumpAndSettle();
      expect(find.text('夜行列車'), findsNothing);
      expect(find.text('鹿野青'), findsOneWidget);

      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('搜尋紀錄'), findsNothing);
      expect(await container(tester).read(searchHistoryProvider.future), []);
    });

    testWidgets('while typing, only matching searches stay', (tester) async {
      await start(tester, phone);
      final history = container(tester).read(searchHistoryProvider.notifier);
      await history.record('lofi study');
      await history.record('夏夜漫遊 live');
      await history.record('夜行列車');

      await tester.enterText(find.byType(TextField), '夜');
      await tester.pumpAndSettle();

      expect(find.textContaining('行列車'), findsOneWidget);
      expect(find.textContaining('漫遊'), findsOneWidget);
      expect(find.text('lofi study'), findsNothing);
    });
  });

  group('results', () {
    testWidgets('a row shows the source, author, play count and length, and '
        'a tap plays it temporarily', (tester) async {
      await start(tester, phone, state: _results());

      expect(find.text('線上結果'), findsOneWidget);
      expect(find.text('夜行列車'), findsOneWidget);
      expect(find.text('SG · 鹿野青 · 8.4萬次播放'), findsOneWidget);
      expect(find.text('4:05'), findsOneWidget);
      expect(find.text('已載入全部'), findsOneWidget);

      await tester.tap(find.text('夜行列車'));
      expect(queue.calls, ['playTemporarily 1']);
    });

    testWidgets('the sort button lists only what the plugins declare, and '
        'choosing one searches again', (tester) async {
      await start(tester, phone, state: _results());

      await tester.tap(find.text('綜合排序'));
      await tester.pumpAndSettle();
      expect(find.text('最多播放'), findsOneWidget);
      expect(find.text('最新發布'), findsNothing);

      await tester.tap(find.text('最多播放'));
      await tester.pumpAndSettle();
      expect(search.calls, ['sort viewCount']);
      expect(find.text('最多播放'), findsOneWidget);
    });

    testWidgets('a source that failed says why and retries only itself; the '
        'filter shows one source', (tester) async {
      await start(
        tester,
        phone,
        state: _results(
          busy: SourceResults(
            manifest: _busyManifest,
            error: const RateLimited(),
          ),
        ),
      );

      expect(find.text('BUSY 暫時無法搜尋'), findsOneWidget);
      expect(find.text('請求太頻繁，被 BUSY 限流。其他音源照常顯示。'), findsOneWidget);
      expect(find.text('夜行列車'), findsOneWidget);

      await tester.tap(find.text('重試'));
      expect(search.calls, ['retry busy']);

      // chip 太多時往左捲（照稿），先把它捲進來。
      await tester.ensureVisible(find.text('BUSY'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BUSY'));
      await tester.pumpAndSettle();
      expect(find.text('夜行列車'), findsNothing);
      expect(find.text('BUSY 暫時無法搜尋'), findsOneWidget);
    });

    testWidgets('without a network the source says so', (tester) async {
      await start(
        tester,
        phone,
        state: SearchState(
          query: '夜',
          sources: [
            SourceResults(
              manifest: _songsManifest,
              error: const NetworkError(),
            ),
          ],
        ),
      );
      expect(find.text('連不上網路。'), findsOneWidget);
    });

    testWidgets('nothing found when every source came back empty', (
      tester,
    ) async {
      await start(
        tester,
        phone,
        state: SearchState(
          query: '夜',
          sources: [
            SourceResults(
              manifest: _songsManifest,
              pages: const [[]],
              isEnd: true,
            ),
          ],
        ),
      );
      expect(find.text('找不到「夜」'), findsOneWidget);
      expect(find.text('線上結果'), findsNothing);
    });

    testWidgets('skeleton rows hold the place while sources are loading', (
      tester,
    ) async {
      await start(
        tester,
        phone,
        state: SearchState(
          query: '夜',
          sources: [SourceResults(manifest: _songsManifest, loading: true)],
        ),
      );
      expect(find.byType(SearchSkeletonRow), findsNWidgets(5));
    });

    testWidgets('scrolling to the end loads the next page', (tester) async {
      await start(
        tester,
        phone,
        state: SearchState(
          query: '夜',
          sources: [
            SourceResults(
              manifest: _songsManifest,
              pages: [
                [for (var i = 0; i < 30; i++) _track('$i')],
              ],
            ),
          ],
        ),
      );
      expect(search.calls, isEmpty);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(search.calls, contains('more'));
    });
  });

  group('more menu', () {
    testWidgets('on a phone the more button opens the track sheet; a link '
        'can be copied or opened in the browser', (tester) async {
      await start(tester, phone, state: _results());
      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add(call.arguments);
          return null;
        },
      );

      await tester.tap(find.byTooltip('更多').first);
      await tester.pumpAndSettle();
      for (final label in ['播放', '下一首播放', '加入佇列', '複製連結', '在瀏覽器開啟']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('臨時播放，不動佇列'), findsOneWidget);

      await tester.tap(find.text('複製連結'));
      await tester.pumpAndSettle();
      expect(copied, [
        {'text': 'https://example.com/1'},
      ]);
      expect(find.text('已複製連結'), findsOneWidget);

      await tester.tap(find.byTooltip('更多').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('在瀏覽器開啟'));
      await tester.pumpAndSettle();
      expect(links.opened, [Uri.parse('https://example.com/1')]);
    });

    testWidgets('a track without a link, like one restored from the saved '
        'queue, has no copy link or open in browser', (tester) async {
      await start(tester, phone, state: _results());

      await tester.tap(find.byTooltip('更多').last);
      await tester.pumpAndSettle();

      expect(find.text('加入佇列'), findsOneWidget);
      expect(find.text('複製連結'), findsNothing);
      expect(find.text('在瀏覽器開啟'), findsNothing);
    });

    testWidgets('the menu plays next or adds to the queue', (tester) async {
      await start(tester, phone, state: _results());

      await tester.tap(find.byTooltip('更多').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一首播放'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入佇列'));
      await tester.pumpAndSettle();

      expect(queue.calls, ['playNext 1', 'add 1']);
    });

    testWidgets('on a tablet the more button grows a menu, not a sheet', (
      tester,
    ) async {
      await start(tester, tablet, state: _results());

      await tester.tap(find.byTooltip('更多').first);
      await tester.pumpAndSettle();
      expect(find.text('加入佇列'), findsOneWidget);
      expect(find.text('臨時播放，不動佇列'), findsNothing);
    });
  });

  testWidgets('on a phone a long press starts picking several tracks, which '
      'the action bar adds to the queue in order', (tester) async {
    await start(tester, phone, state: _results());
    expect(find.byType(PhoneDock), findsOneWidget);

    await tester.longPress(find.text('晴天'));
    await tester.pumpAndSettle();
    expect(find.text('已選擇 1 首'), findsOneWidget);
    expect(find.byType(PhoneDock), findsNothing);

    await tester.tap(find.text('夜行列車'));
    await tester.pumpAndSettle();
    expect(find.text('已選擇 2 首'), findsOneWidget);
    expect(queue.calls, isEmpty);

    await tester.tap(find.text('加入佇列'));
    await tester.pumpAndSettle();
    expect(queue.calls, ['add 1,2']);
    expect(find.byType(PhoneDock), findsOneWidget);
  });

  group('desktop table', () {
    testWidgets('a click selects, a double click or ↩ plays, and a missing '
        'play count shows a dash', (tester) async {
      await start(tester, desktop, state: _results(), mouse: true);

      expect(find.text('8.4萬'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('「夜」'), findsNothing); // 標題是一整段 rich text
      expect(find.textContaining('的搜尋結果'), findsOneWidget);

      await tester.tap(find.text('晴天'), kind: PointerDeviceKind.mouse);
      await tester.pump(kDoubleTapTimeout);
      expect(queue.calls, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(queue.calls, ['playTemporarily 2']);

      await tester.tap(find.text('夜行列車'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('夜行列車'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(queue.calls, ['playTemporarily 2', 'playTemporarily 1']);
      done();
    });

    testWidgets('⌘ click picks several and the action bar acts on them; Esc '
        'clears the selection', (tester) async {
      await start(tester, desktop, state: _results(), mouse: true);

      await tester.tap(find.text('夜行列車'), kind: PointerDeviceKind.mouse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.tap(find.text('晴天'), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.text('已選擇 2 首'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('已選擇 2 首'), findsNothing);

      await tester.tap(find.text('夜行列車'), kind: PointerDeviceKind.mouse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('晴天'), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一首播放'));
      await tester.pumpAndSettle();
      expect(queue.calls, ['playNext 1,2']);
      done();
    });

    testWidgets('a right click opens the menu with the track on top', (
      tester,
    ) async {
      await start(tester, desktop, state: _results(), mouse: true);

      await tester.tap(
        find.text('夜行列車'),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('夜行列車'), findsNWidgets(2));
      await tester.tap(find.text('加入佇列'));
      await tester.pumpAndSettle();

      expect(queue.calls, ['add 1']);
      done();
    });
  });

  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 5)), '0:05');
    expect(formatDuration(const Duration(minutes: 12, seconds: 3)), '12:03');
    expect(formatDuration(const Duration(hours: 2, seconds: 9)), '2:00:09');
  });

  test('formatCount', () {
    const zh = ('萬', '億');
    expect(formatCount(9999, chineseUnits: zh), '9999');
    expect(formatCount(84321, chineseUnits: zh), '8.4萬');
    expect(formatCount(210000, chineseUnits: zh), '21萬');
    expect(formatCount(123456789, chineseUnits: zh), '1.2億');
    expect(formatCount(999, chineseUnits: null), '999');
    expect(formatCount(84321, chineseUnits: null), '84.3K');
    expect(formatCount(4700000, chineseUnits: null), '4.7M');
  });
}

String _manifest(String id, String short, {List<String>? sorts}) => jsonEncode({
  'id': id,
  'name': id.toUpperCase(),
  'version': '1.0.0',
  'capabilities': ['search'],
  'domains': ['api.example.com'],
  'searchSorts': ?sorts,
  'mark': {
    'short': short,
    'color': '#FB7299',
    'paths': [
      {'pathData': 'M1 1h14v14H1z', 'fillColor': '#FB7299'},
    ],
  },
});

final _songs = (
  source: _manifest('songs', 'SG', sorts: ['relevance', 'viewCount']),
);
final _busy = (source: _manifest('busy', 'BS'));
final _songsManifest = PluginManifest.parse(_songs.source);
final _busyManifest = PluginManifest.parse(_busy.source);

Track _track(
  String id, {
  String title = 'T',
  int? playCount,
  String? url,
  Duration? duration,
}) => Track(
  ref: TrackRef(pluginId: 'songs', trackId: id),
  title: title == 'T' ? 'T$id' : title,
  author: '鹿野青',
  playCount: playCount,
  url: url,
  duration: duration,
);

/// 搜「夜」的結果：第一首有播放數與網址，第二首都沒有。
SearchState _results({SourceResults? busy}) => SearchState(
  query: '夜',
  sources: [
    SourceResults(
      manifest: _songsManifest,
      isEnd: true,
      pages: [
        [
          _track(
            '1',
            title: '夜行列車',
            playCount: 84321,
            url: 'https://example.com/1',
            duration: const Duration(minutes: 4, seconds: 5),
          ),
          _track('2', title: '晴天'),
        ],
      ],
    ),
    ?busy,
  ],
);

/// 固定的搜尋狀態，記下畫面叫了什麼。
class _FakeSearch extends Search {
  _FakeSearch(this._initial);

  final SearchState? _initial;
  final calls = <String>[];

  @override
  SearchState? build() => _initial;

  @override
  Future<void> search(String query) async {
    calls.add('search $query');
    state = SearchState(query: query, sources: _initial?.sources ?? const []);
  }

  @override
  Future<void> sortBy(SearchSort sort) async {
    calls.add('sort ${sort.name}');
    state = SearchState(
      query: state!.query,
      sort: sort,
      sources: state!.sources,
    );
  }

  @override
  void loadMore() => calls.add('more');

  @override
  void retry(String pluginId) => calls.add('retry $pluginId');
}

class _FakeQueue extends QueueController {
  final calls = <String>[];

  @override
  Queue build() => Queue.empty;

  String _ids(List<Track> tracks) => tracks.map((t) => t.ref.trackId).join(',');

  @override
  Future<void> playTemporarily(Track track) async =>
      calls.add('playTemporarily ${track.ref.trackId}');

  @override
  Future<void> playNext(List<Track> tracks) async =>
      calls.add('playNext ${_ids(tracks)}');

  @override
  Future<void> add(List<Track> tracks) async =>
      calls.add('add ${_ids(tracks)}');
}

class _FakeLinks extends WebLinks {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}
