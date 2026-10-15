import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/plugin_artwork.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/fake_artwork.dart';
import '../support/shell_harness.dart';

// 歌單的自訂封面（M4 PR 3，design §10.5；主對話的決定）：網址的網域要屬於某個已安裝且啟用的
// 插件的允許網域才收，之後經那個插件的媒體 client 讀；不屬於任何插件時寫明原因、不收；「使用
// 預設」清回第一首的封面。宿主沒有任意網址的讀取路徑。測試插件 `fmp-test` 的允許網域是
// `cdn.example`。

const _inPlugin = 'https://img.cdn.example/cover.jpg';

/// 記下封面向哪個插件的 cache manager 要了哪個網址；`fmp-test` 以外的插件沒有 cache manager
/// （同 App：不在插件清單上就沒有媒體 client）。
final class _Requests {
  final managers = <String>[];
  final urls = <String>[];
}

final class _RecordingManager implements BaseCacheManager {
  _RecordingManager(this._requests);

  final _Requests _requests;
  final _inner = FakeArtworkManager();

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    _requests.urls.add(url);
    return _inner.getFileStream(url);
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 外殼開在音樂庫（插件清單裡有 `fmp-test`），寫好歌單「Road」（一首、[artwork] 是自訂封面）。
Future<(ShellHarness, _Requests)> _open(
  WidgetTester tester, {
  List<TrackArtwork> artwork = const [],
}) async {
  // 記憶體的 ImageCache 跨測試留著：前一個測試讀過的網址不會再向 cache manager 要。
  imageCache
    ..clear()
    ..clearLiveImages();
  final requests = _Requests();
  final h = ShellHarness(
    registryOfSources: true,
    extraOverrides: [
      artworkCacheManagerProvider.overrideWith((ref, pluginId) {
        requests.managers.add(pluginId);
        return pluginId == 'fmp-test' ? _RecordingManager(requests) : null;
      }),
    ],
  );
  await h.pumpShell(
    tester,
    size: const Size(400, 800),
    at: ShellDestination.library,
  );
  await tester.runAsync(() async {
    final repository = h.container(tester).read(playlistRepositoryProvider);
    final id = await repository.create(name: 'Road', artwork: artwork);
    await repository.addTracks(id, [
      TrackInfo(
        sourceTypeId: 'fmp-test',
        sourceId: 'a',
        title: 'Song a',
        artwork: [TrackArtwork(url: Uri.parse('https://cdn.example/a.jpg'))],
      ),
    ]);
  });
  await _settle(tester, h);
  return (h, requests);
}

Future<void> _settle(WidgetTester tester, ShellHarness h) async {
  for (var i = 0; i < 3; i++) {
    await h.loadSettings(tester);
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

Future<Playlist> _stored(WidgetTester tester, ShellHarness h) async =>
    (await tester.runAsync(
      () =>
          h.container(tester).read(playlistRepositoryProvider).watchAll().first,
    ))!.single;

Future<void> _edit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More options').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
  expect(find.text('Edit playlist'), findsOneWidget);
}

Future<void> _enterUrl(WidgetTester tester, String url) async {
  await tester.enterText(find.widgetWithText(TextField, 'Image URL'), url);
  await tester.pump();
}

VoidCallback? _save(WidgetTester tester) => tester
    .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
    .onPressed;

void main() {
  testWidgets('a cover with several images is read through the plugin of the '
      'image that is picked, not the first one', (tester) async {
    // 匯入歌單的封面常有不同網域的多張：第一張（最大）不屬於任何插件，依尺寸挑中的是第二張。
    final (_, requests) = await _open(
      tester,
      artwork: [
        TrackArtwork(
          url: Uri.parse('https://other.example/big.jpg'),
          width: 2000,
        ),
        TrackArtwork(url: Uri.parse(_inPlugin), width: 100),
      ],
    );

    expect(requests.managers, contains('fmp-test'));
    expect(requests.urls, contains(_inPlugin));
    expect(requests.urls, isNot(contains('https://other.example/big.jpg')));
  });

  group('pluginForArtwork', () {
    final plugins = [
      FakeSourcePlugin((_) => [], id: 'one'),
      FakeSourcePlugin((_) => [], id: 'two'),
    ];

    test('is the first plugin whose allowed hosts take the URL', () {
      for (final url in [
        _inPlugin,
        'https://cdn.example/x.jpg',
        'https://IMG.CDN.Example/x.jpg',
        'https://cdn.example:8443/x.jpg',
      ]) {
        expect(pluginForArtwork(plugins, Uri.parse(url)), 'one', reason: url);
      }
    });

    test('is null for another host, a look-alike host, user info or plain '
        'http', () {
      for (final url in [
        'https://evil.test/x.jpg',
        'https://evilcdn.example/x.jpg',
        'https://cdn.example.evil.test/x.jpg',
        // host 是 evil.test，`cdn.example` 只是 user info。
        'https://cdn.example@evil.test/x.jpg',
        // 媒體 client 不發帶 user info 的請求。
        'https://user:secret@cdn.example/x.jpg',
        // 非 ASCII 的 host 留成百分比編碼，一律不收。
        'https://cdn.exämple/x.jpg',
        'http://cdn.example/x.jpg',
      ]) {
        expect(pluginForArtwork(plugins, Uri.parse(url)), isNull, reason: url);
      }
      expect(pluginForArtwork(const [], Uri.parse(_inPlugin)), isNull);
    });
  });

  testWidgets('a URL of an installed source is taken and read through that '
      "source's cache manager", (tester) async {
    final (h, requests) = await _open(tester);
    await _edit(tester);
    expect(find.text('The cover of the first song'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Image URL'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Custom'));
    await tester.pump();
    expect(find.text('A custom image'), findsOneWidget);
    expect(_save(tester), isNull, reason: 'no URL yet');

    await _enterUrl(tester, _inPlugin);
    expect(
      find.text("This URL doesn't belong to any installed source"),
      findsNothing,
    );
    expect(_save(tester), isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _settle(tester, h);

    expect((await _stored(tester, h)).artwork, [
      TrackArtwork(url: Uri.parse(_inPlugin)),
    ]);
    // 音樂庫的卡片以 `fmp-test` 的 cache manager 讀自訂封面，不是第一首的封面。
    expect(requests.managers, contains('fmp-test'));
    expect(requests.urls.last, _inPlugin);
  });

  testWidgets('a URL of no installed source is refused with the reason', (
    tester,
  ) async {
    final (h, requests) = await _open(tester);
    await _edit(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Custom'));
    await tester.pump();

    await _enterUrl(tester, 'https://evil.test/cover.jpg');
    expect(
      find.text("This URL doesn't belong to any installed source"),
      findsOneWidget,
    );
    expect(_save(tester), isNull);

    await _enterUrl(tester, 'http://cdn.example/cover.jpg');
    expect(find.text('Enter a URL that starts with https'), findsOneWidget);
    expect(_save(tester), isNull);

    await _enterUrl(tester, 'not a url');
    expect(find.text('Enter a URL that starts with https'), findsOneWidget);
    expect(_save(tester), isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _settle(tester, h);
    expect((await _stored(tester, h)).artwork, isEmpty);
    expect(requests.urls, isNot(contains('https://evil.test/cover.jpg')));
  });

  testWidgets('"Use default" clears the custom cover', (tester) async {
    final (h, requests) = await _open(
      tester,
      artwork: [TrackArtwork(url: Uri.parse(_inPlugin))],
    );
    // 音樂庫與首頁（外殼同時建著）的卡片各讀一次。
    expect(requests.urls, isNotEmpty);
    expect(requests.urls, everyElement(_inPlugin));
    await _edit(tester);
    expect(find.text('A custom image'), findsOneWidget);
    expect(find.widgetWithText(TextField, _inPlugin), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Use default'));
    await tester.pump();
    expect(find.text('The cover of the first song'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Image URL'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _settle(tester, h);

    expect((await _stored(tester, h)).artwork, isEmpty);
    expect(requests.urls.last, 'https://cdn.example/a.jpg');
  });

  // 那個插件後來移除了：封面是佔位圖（沒有插件可以讀它），但改名稱時照舊保留、不擋。
  testWidgets('an unchanged custom cover of a source gone since is kept', (
    tester,
  ) async {
    const gone = 'https://img.gone.example/cover.jpg';
    final (h, requests) = await _open(
      tester,
      artwork: [TrackArtwork(url: Uri.parse(gone))],
    );
    expect(requests.urls, isEmpty, reason: 'no source can read it');
    await _edit(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Road'), 'Road 2');
    await tester.pump();
    expect(
      find.text("This URL doesn't belong to any installed source"),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _settle(tester, h);

    final stored = await _stored(tester, h);
    expect(stored.name, 'Road 2');
    expect(stored.artwork, [TrackArtwork(url: Uri.parse(gone))]);
  });

  testWidgets('a new playlist can start with a custom cover', (tester) async {
    final (h, _) = await _open(tester);
    await tester.tap(find.byTooltip('New playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Fresh');
    await tester.tap(find.widgetWithText(TextButton, 'Custom'));
    await tester.pump();
    await _enterUrl(tester, _inPlugin);
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await _settle(tester, h);

    final fresh = (await tester.runAsync(
      () =>
          h.container(tester).read(playlistRepositoryProvider).watchAll().first,
    ))!.singleWhere((p) => p.name == 'Fresh');
    expect(fresh.artwork, [TrackArtwork(url: Uri.parse(_inPlugin))]);
  });
}
