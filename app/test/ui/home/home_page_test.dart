import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/plugins/plugins_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../support/plugin_page_harness.dart';
import '../support/shell_harness.dart';

// 首頁（M4 PR 2，ADR 0033 §決定 6，design §10.2）：最近播放、「查看全部」、首次啟動引導、
// 全空時的說明。

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
