import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/radio/radio_status_jobs.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/player/live_widgets.dart';
import 'package:fmp/ui/plugins/plugins_page.dart';
import 'package:fmp/ui/radio/radio_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/plugin_page_harness.dart';
import '../support/shell_harness.dart';

// 首頁（M4 PR 2、4，ADR 0033 §決定 6，design §10.2）：我的歌單、電台、最近播放、「查看全部」、
// 首次啟動引導、全空時的說明。

TrackInfo _track(String id) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: 'Song $id',
  uploader: 'Uploader $id',
);

/// 依序寫入播放歷史：最後一筆最新。
Future<void> _played(
  WidgetTester tester,
  ShellHarness h,
  List<String> ids,
) async {
  await tester.runAsync(() async {
    final repository = h.container(tester).read(playHistoryRepositoryProvider);
    for (final (index, id) in ids.indexed) {
      await repository.record(
        _track(id),
        playedAt: DateTime(2026, 10, 15, 8).add(Duration(minutes: index)),
        limit: 1000,
      );
    }
  });
  await h.loadSettings(tester);
}

/// 「最近播放」那一排卡片上的曲名，依畫面上的順序。
List<String> _cardTitles(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.textContaining(RegExp(r'^Song ')),
      skipOffstage: false,
    ),
  ))
    text.data!,
];

/// 寫歌單（名稱 → 曲目 id），依序建立＝`sort_order` 依序。
Future<void> _playlists(
  WidgetTester tester,
  ShellHarness h,
  Map<String, List<String>> seed,
) async {
  await tester.runAsync(() async {
    final repository = h.container(tester).read(playlistRepositoryProvider);
    for (final MapEntry(key: name, value: ids) in seed.entries) {
      final id = await repository.create(name: name);
      await repository.addTracks(id, [for (final id in ids) _track(id)]);
    }
  });
  await h.loadSettings(tester);
  await tester.pumpAndSettle();
}

/// 寫電台（房號 → 狀態），依序＝`sort_order` 依序。首頁已經在監看這張表：在假時間裡寫
/// （同 radio_page_test）。
Future<void> _stations(
  WidgetTester tester,
  ShellHarness h,
  Map<String, RadioLiveStatus?> seed,
) async {
  final repository = h.container(tester).read(radioRepositoryProvider);
  for (final MapEntry(key: roomId, value: status) in seed.entries) {
    await repository.add(
      pluginId: 'fmp-test',
      roomId: roomId,
      title: 'Station $roomId',
      hostName: 'Host $roomId',
      addedAt: DateTime.utc(2026, 10, 14),
      liveStatus: status,
    );
  }
  await h.loadSettings(tester);
  await tester.pumpAndSettle();
}

/// 畫面上有的區塊標題。
List<String> _sectionTitles(WidgetTester tester) => [
  for (final title in ['My playlists', 'Radio', 'Recently played'])
    if (find
        .descendant(
          of: find.byType(HomePage),
          matching: find.text(title),
          skipOffstage: false,
        )
        .evaluate()
        .isNotEmpty)
      title,
];

/// 區塊 [title] 的「查看全部」。
Finder _viewAll(String title) => find.descendant(
  of: find
      .ancestor(
        of: find.descendant(
          of: find.byType(HomePage),
          matching: find.text(title),
        ),
        matching: find.byType(Row),
      )
      .first,
  matching: find.text('View all'),
);

/// 首頁一排卡片裡符合 [pattern] 的文字，依畫面上的順序。
List<String> _cardTexts(WidgetTester tester, RegExp pattern) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.descendant(
        of: find.byType(HomePage),
        matching: find.byType(SingleChildScrollView),
      ),
      matching: find.textContaining(pattern),
      skipOffstage: false,
    ),
  ))
    text.data!,
];

void main() {
  testWidgets(
    'recent plays are the newest 20, not deduplicated, newest first',
    (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester, at: ShellDestination.home);
      // 22 筆，其中 x 播過兩次：兩次都在。
      await _played(tester, h, [for (var i = 0; i < 20; i++) '$i', 'x', 'x']);
      await tester.pumpAndSettle();

      expect(find.text('Recently played'), findsOneWidget);
      expect(_cardTitles(tester), [
        'Song x',
        'Song x',
        for (var i = 19; i >= 2; i--) 'Song $i',
      ]);
    },
  );

  testWidgets('tapping a recent play plays it temporarily', (tester) async {
    final h = ShellHarness();
    await h.pumpShell(tester, at: ShellDestination.home);
    await _played(tester, h, ['a', 'b']);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Song a'));
    await tester.pump();

    expect(h.controller.queue.mode, QueueMode.temporary);
    expect(h.controller.queue.current?.sourceId, 'a');
    expect(h.controller.queue.entries, isEmpty);
  });

  testWidgets('a new play shows up without leaving the page', (tester) async {
    final h = ShellHarness();
    await h.pumpShell(tester, at: ShellDestination.home);
    await _played(tester, h, ['a']);
    await tester.pumpAndSettle();
    expect(_cardTitles(tester), ['Song a']);

    await _played(tester, h, ['b']);
    await tester.pumpAndSettle();

    expect(_cardTitles(tester), ['Song b', 'Song a']);
  });

  testWidgets('"View all" opens the history inside Home and comes back', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(
      tester,
      size: const Size(400, 800),
      at: ShellDestination.home,
    );
    await _played(tester, h, ['a']);
    await tester.pumpAndSettle();

    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryPage).hitTestable(), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    // 首頁仍是選中的導覽項：歷史頁開在首頁的巢狀導覽裡。
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      ShellDestination.home.index,
    );

    await tester.tap(find.byTooltip('Back (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage).hitTestable(), findsOneWidget);
  });

  testWidgets('with nothing played Home explains what to do', (tester) async {
    final h = ShellHarness();
    await h.pumpShell(tester, at: ShellDestination.home);
    await h.loadSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(
      find.text('Search for songs and play them, or import a playlist'),
      findsOneWidget,
    );
    expect(find.text('Recently played'), findsNothing);
    // 有音源：說明不附「前往插件頁」。
    expect(find.text('Go to plugins'), findsNothing);
  });

  group('my playlists and radio', () {
    ShellHarness harness() {
      final h = ShellHarness(live: true);
      h.plugin.onResolveLive = (request) => [
        candidate('${request.roomId}.flv'),
      ];
      return h;
    }

    String padded(String prefix, int i) =>
        '$prefix${i.toString().padLeft(2, '0')}';

    testWidgets('sections without content are not shown', (tester) async {
      final h = harness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await _played(tester, h, ['a']);
      await tester.pumpAndSettle();
      expect(_sectionTitles(tester), ['Recently played']);

      await _playlists(tester, h, {'Mix tape': []});
      expect(_sectionTitles(tester), ['My playlists', 'Recently played']);
    });

    testWidgets('a playlist alone replaces the explanation', (tester) async {
      final h = harness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await _playlists(tester, h, {'Mix tape': []});

      expect(find.text('Nothing here yet'), findsNothing);
      expect(find.text('Mix tape'), findsOneWidget);
      expect(_sectionTitles(tester), ['My playlists']);
    });

    testWidgets('sections go playlists, radio, recently played', (
      tester,
    ) async {
      final h = harness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await _played(tester, h, ['a']);
      await _playlists(tester, h, {'Mix tape': []});
      await _stations(tester, h, {'r1': RadioLiveStatus.live});

      expect(_sectionTitles(tester), [
        'My playlists',
        'Radio',
        'Recently played',
      ]);
      final y = [
        for (final title in _sectionTitles(tester))
          tester
              .getTopLeft(
                find.descendant(
                  of: find.byType(HomePage),
                  matching: find.text(title),
                ),
              )
              .dy,
      ];
      expect(y, [...y]..sort());
    });

    testWidgets('playlists: the first 20 by sort_order, with kind and count', (
      tester,
    ) async {
      final h = harness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await _playlists(tester, h, {
        for (var i = 0; i < 21; i++) padded('List ', i): [],
        'Single': ['a'],
      });
      // 最後一張（'Single'）移到最前面：卡片依 sort_order，不依建立順序。
      await tester.runAsync(() async {
        final repository = h.container(tester).read(playlistRepositoryProvider);
        final ids = [for (final p in await repository.watchAll().first) p.id];
        await repository.reorder([ids.last, ...ids.take(ids.length - 1)]);
      });
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(_cardTexts(tester, RegExp(r'^(List|Single)')), [
        'Single',
        for (var i = 0; i < 19; i++) padded('List ', i),
      ]);
      final local = _cardTexts(tester, RegExp('^Local'));
      expect(local.where((text) => text == 'Local · 1 song'), hasLength(1));
      expect(local.where((text) => text == 'Local · 0 songs'), hasLength(19));
    });

    testWidgets('an imported playlist is labelled imported, not local', (
      tester,
    ) async {
      final h = harness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await tester.runAsync(() async {
        await h
            .container(tester)
            .read(playlistRepositoryProvider)
            .createImported(
              pluginId: 'fmp-test',
              remoteId: 'r1',
              info: const RemotePlaylistInfo(name: 'Remote list'),
            );
      });
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(_cardTexts(tester, RegExp('^(Local|Imported)')), [
        'Imported · 0 songs',
      ]);
    });

    testWidgets('tapping a playlist opens its detail inside Home', (
      tester,
    ) async {
      final h = harness();
      await h.pumpShell(
        tester,
        size: const Size(400, 800),
        at: ShellDestination.home,
      );
      await _playlists(tester, h, {
        'Mix tape': ['a'],
      });

      await tester.tap(find.text('Mix tape'));
      await tester.pumpAndSettle();

      expect(find.byType(PlaylistDetailPage).hitTestable(), findsOneWidget);
      // 開在首頁的巢狀導覽裡：導覽列沒被蓋住，首頁仍是選中的項目。
      expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        ShellDestination.home.index,
      );
      await tester.tap(find.byTooltip('Back (Esc)'));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage).hitTestable(), findsOneWidget);
    });

    testWidgets('radio: the first 20 by sort_order; tapping listens', (
      tester,
    ) async {
      final h = harness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await _stations(tester, h, {
        for (var i = 0; i < 22; i++) padded('r', i): RadioLiveStatus.offline,
      });
      // 最後一個移到最前面。
      final container = h.container(tester);
      final ids = [
        for (final s in container.read(radioStationsProvider).value!) s.id,
      ];
      await container.read(radioRepositoryProvider).reorder([
        ids.last,
        ...ids.take(ids.length - 1),
      ]);
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(_cardTexts(tester, RegExp(r'^Station ')), [
        'Station r21',
        for (var i = 0; i < 19; i++) 'Station ${padded('r', i)}',
      ]);

      await tester.tap(find.text('Station r21'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(nowPlayingLiveProvider)?.target.roomId, 'r21');
    });

    testWidgets('radio cards show the four statuses', (tester) async {
      final h = harness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await _stations(tester, h, {
        'a': RadioLiveStatus.live,
        'b': RadioLiveStatus.offline,
        'c': null,
        'd': RadioLiveStatus.offline,
      });
      final container = h.container(tester);
      container
          .read(radioQueryFailuresProvider.notifier)
          .mark(container.read(radioStationsProvider).value!.last.id);
      await tester.pumpAndSettle();

      Finder tag(String roomId, String text) => find.descendant(
        of: find.widgetWithText(InkWell, 'Station $roomId'),
        matching: find.text(text),
      );
      expect(tag('a', 'Live'), findsOneWidget);
      expect(tag('b', 'Offline'), findsOneWidget);
      expect(tag('c', 'Not checked yet'), findsOneWidget);
      expect(tag('d', 'Check failed'), findsOneWidget);
    });

    testWidgets('a station of an unavailable source says why and does not '
        'play', (tester) async {
      final h = ShellHarness(
        live: true,
        sourceUnavailable: (_, _) => 'Source disabled',
      );
      await h.pumpShell(tester, at: ShellDestination.home);
      await _stations(tester, h, {'r1': RadioLiveStatus.live});

      // 卡片照樣在、照樣有狀態標記。
      expect(
        find.descendant(
          of: find.widgetWithText(InkWell, 'Station r1'),
          matching: find.text('Live'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Station r1'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text("Can't play: Source disabled"),
        ),
        findsOneWidget,
      );
      expect(h.controller.queue.live, isNull);
      expect(h.plugin.liveRequests, isEmpty);
    });

    testWidgets('a failed read hides that section and is reported once', (
      tester,
    ) async {
      final h = ShellHarness(
        extraOverrides: [
          playlistOverviewsProvider.overrideWith(
            (ref) => Stream.error(StateError('playlists')),
          ),
          radioStationsProvider.overrideWith(
            (ref) => Stream.error(StateError('stations')),
          ),
        ],
      );
      await h.pumpShell(tester, at: ShellDestination.home);
      await _played(tester, h, ['a']);
      await tester.pumpAndSettle();

      expect(_sectionTitles(tester), ['Recently played']);
      // 音樂庫與電台頁（一直掛在外殼裡）各報一次；首頁不再報同一個失敗。
      expect(
        [
          for (final record in h.log.history)
            if (record.error case final error?
                when error.contains('playlists') || error.contains('stations'))
              record.message,
        ]..sort(),
        ['Failed to read the playlists', 'Failed to read the radio stations'],
      );
    });

    testWidgets('the explanation waits until every section has loaded', (
      tester,
    ) async {
      final stations = StreamController<List<RadioStation>>();
      addTearDown(stations.close);
      final h = ShellHarness(
        extraOverrides: [
          radioStationsProvider.overrideWith((ref) => stations.stream),
        ],
      );
      await h.pumpShell(tester, at: ShellDestination.home);
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
      // 最近播放與歌單都讀到了（空的），電台還沒：不先顯示說明。
      expect(find.text('Nothing here yet'), findsNothing);

      stations.add(const []);
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('"View all" switches to the library and to the radio', (
      tester,
    ) async {
      final h = harness();
      await h.pumpShell(tester, at: ShellDestination.home);
      await _playlists(tester, h, {'Mix tape': []});
      await _stations(tester, h, {'r1': RadioLiveStatus.live});

      await tester.tap(_viewAll('My playlists'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);

      await h.open(tester, ShellDestination.home);
      await tester.pumpAndSettle();
      await tester.tap(_viewAll('Radio'));
      await tester.pumpAndSettle();
      expect(find.byType(RadioPage).hitTestable(), findsOneWidget);
    });
  });

  group('the first-run onboarding (ADR 0030 §決定 12)', () {
    final alpha = pluginScript('plugin-a', name: 'Alpha');

    Future<PluginPageHarness> open(WidgetTester tester) async {
      final h = await PluginPageHarness.create(tester, registrySources: true);
      h.publish([alpha]);
      await h.shell.pumpShell(tester, at: ShellDestination.home);
      await h.settle(tester);
      return h;
    }

    Finder onHome(Finder finder) =>
        find.descendant(of: find.byType(HomePage), matching: finder);

    testWidgets('shows on Home without a search plugin and goes away once one '
        'is installed', (tester) async {
      final h = await open(tester);
      expect(
        onHome(find.text('Install plugins to start searching')),
        findsOneWidget,
      );

      await tester.tap(onHome(find.widgetWithText(FilledButton, 'Install')));
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Install'),
        ),
      );
      await h.settle(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect({for (final p in await h.stored(tester)) p.id}, {'plugin-a'});
      expect(find.text('Install plugins to start searching'), findsNothing);
      expect(onHome(find.text('Nothing here yet')), findsOneWidget);
    });

    testWidgets('"Later" leaves the explanation with a way to the plugins', (
      tester,
    ) async {
      final h = await open(tester);

      await tester.tap(onHome(find.widgetWithText(TextButton, 'Later')));
      await h.settle(tester);
      expect(find.text('Install plugins to start searching'), findsNothing);
      expect(onHome(find.text('Nothing here yet')), findsOneWidget);

      await tester.tap(onHome(find.text('Go to plugins')));
      await h.settle(tester);
      expect(find.byType(PluginsPage).hitTestable(), findsOneWidget);
    });
  });
}
