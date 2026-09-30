import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

void main() {
  Future<void> search(WidgetTester tester, String keyword) async {
    await tester.enterText(find.byType(TextField), keyword);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
  }

  group('states', () {
    testWidgets('no source can search', (tester) async {
      final h = ShellHarness(sources: []);
      await h.pumpShell(tester);

      expect(find.text('No sources to search'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('before searching, while loading, with no results', (
      tester,
    ) async {
      final pending = Completer<SearchPage>();
      final h = ShellHarness(onSearch: (_) => pending.future);
      await h.pumpShell(tester);
      expect(find.text('Type a keyword to search'), findsOneWidget);

      await search(tester, '  nothing  ');
      expect(
        find.bySemanticsLabel('Searching'),
        findsOneWidget,
        reason: 'the spinner has a label',
      );
      expect(h.plugin.searches.single.keyword, 'nothing');

      pending.complete(const SearchPage(items: [], hasMore: false));
      await tester.pump();
      expect(find.text('No results for “nothing”'), findsOneWidget);
    });

    testWidgets('only spaces does not search', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);

      await search(tester, '   ');
      expect(h.plugin.searches, isEmpty);
      expect(find.text('Type a keyword to search'), findsOneWidget);
    });
  });

  testWidgets('results show artwork, title, uploader and duration', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(tester);

    await search(tester, 'song');

    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Uploader a'), findsOneWidget);
    expect(find.text('3:05'), findsNWidgets(3));
    // 沒有封面時是佔位圖，不發請求。
    expect(find.byIcon(Icons.music_note), findsNWidgets(3));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('an error goes to a toast, and retry searches again', (
    tester,
  ) async {
    var fail = true;
    final h = ShellHarness(
      onSearch: (query) => fail
          ? throw RateLimited(pluginId: 'fmp-test')
          : SearchPage(items: [summary('a')], hasMore: false),
    );
    await h.pumpShell(tester);

    await search(tester, 'song');
    await tester.pumpAndSettle();
    expect(
      find.text('Too many requests to fmp-test. Try again later.'),
      findsOneWidget,
    );
    expect(find.text('Search failed'), findsOneWidget);
    expect(
      h.log.history.where((record) => record.message == 'Search failed'),
      hasLength(1),
    );

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Song a'), findsOneWidget);
    expect(h.plugin.searches, hasLength(2));
  });

  testWidgets('load more appends the next page', (tester) async {
    final h = ShellHarness(
      onSearch: (query) => SearchPage(
        items: [summary('p${query.page}')],
        hasMore: query.page < 2,
      ),
    );
    await h.pumpShell(tester);
    await search(tester, 'song');
    expect(find.text('Song p1'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Song p1'), findsOneWidget);
    expect(find.text('Song p2'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    expect([for (final query in h.plugin.searches) query.page], [1, 2]);
  });

  // 排序在兩次請求之間變了時，下一頁會重複上一頁已有的曲目（B 站搜尋會）。
  testWidgets('load more skips tracks already in the list', (tester) async {
    final h = ShellHarness(
      onSearch: (query) => SearchPage(
        items: [
          if (query.page == 1) ...[summary('a'), summary('b')],
          if (query.page == 2) ...[summary('b'), summary('c')],
        ],
        hasMore: query.page < 2,
      ),
    );
    await h.pumpShell(tester);
    await search(tester, 'song');

    await tester.tap(find.text('Load more'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Song b'), findsOneWidget);
    await tester.tap(find.text('Song c'));
    await tester.pump();
    expect(h.controller.queue.tracks.map((track) => track.sourceId), [
      'a',
      'b',
      'c',
    ]);
    expect(h.controller.queue.currentIndex, 2);
  });

  testWidgets('a newer search wins over a slower older one', (tester) async {
    final slow = Completer<SearchPage>();
    final h = ShellHarness(
      onSearch: (query) => query.keyword == 'old'
          ? slow.future
          : SearchPage(items: [summary('new')], hasMore: false),
    );
    await h.pumpShell(tester);

    await search(tester, 'old');
    await search(tester, 'new');
    slow.complete(SearchPage(items: [summary('old')], hasMore: false));
    await tester.pump();

    expect(find.text('Song new'), findsOneWidget);
    expect(find.text('Song old'), findsNothing);
  });

  testWidgets('tapping a result plays the whole list from it', (tester) async {
    final h = ShellHarness();
    await h.pumpShell(tester);
    await search(tester, 'song');

    await tester.tap(find.text('Song b'));
    await tester.pump();
    await tester.pump();

    final queue = h.controller.queue;
    expect(queue.tracks, const [
      TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: 'a'),
      TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: 'b'),
      TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: 'c'),
    ]);
    expect(queue.currentIndex, 1);
    // 播放列以曲目鍵找到顯示資料。
    expect(
      find.descendant(
        of: find.byType(PlayerBar),
        matching: find.text('Song b'),
      ),
      findsOneWidget,
    );
  });

  group('source chips', () {
    testWidgets('switching the source searches it again', (tester) async {
      final other = FakeSourcePlugin(
        (_) => const [],
        id: 'other',
        name: 'Other Source',
        onSearch: (_) => const SearchPage(items: [], hasMore: false),
      );
      final h = ShellHarness();
      h.sources.add(other);
      await h.pumpShell(tester);
      final chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .toList();
      expect(chips.map((chip) => chip.selected), [true, false]);

      await search(tester, 'song');
      await tester.tap(find.text('Other Source'));
      await tester.pump();
      await tester.pump();

      expect(other.searches.single.keyword, 'song');
      expect(find.text('No results for “song”'), findsOneWidget);
    });

    testWidgets('tapping the selected chip does not search again', (
      tester,
    ) async {
      final h = ShellHarness();
      h.sources.add(
        FakeSourcePlugin(
          (_) => const [],
          id: 'other',
          name: 'Other Source',
          onSearch: (_) => const SearchPage(items: [], hasMore: false),
        ),
      );
      await h.pumpShell(tester);
      await search(tester, 'song');

      // 還沒點過任何 chip：選的是清單的第一個。
      await tester.tap(find.text('Test Source'));
      await tester.pump();
      await tester.pump();

      expect(h.plugin.searches, hasLength(1));
      expect(find.text('Song a'), findsOneWidget);
    });

    testWidgets('the row scrolls sideways on a narrow window', (tester) async {
      final h = ShellHarness(sources: []);
      for (var i = 0; i < 8; i++) {
        h.sources.add(
          FakeSourcePlugin(
            (_) => const [],
            id: 'source-$i',
            name: 'Source number $i',
            onSearch: (_) => const SearchPage(items: [], hasMore: false),
          ),
        );
      }
      await h.pumpShell(tester, size: const Size(400, 800));
      final last = find.text('Source number 7');
      expect(last.hitTestable(), findsNothing);

      await tester.scrollUntilVisible(
        last,
        200,
        scrollable: find
            .ancestor(of: last, matching: find.byType(Scrollable))
            .first,
      );
      expect(last.hitTestable(), findsOneWidget);
    });
  });

  // ToastHost 在 Navigator 外面多包了一個 Overlay，它成了 root overlay：文字
  // 選取工具列與放大鏡插在那裡（12a 審查留下的）。
  group('text selection over the toast host', () {
    testWidgets('long press shows the toolbar and the magnifier', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();

      final field = find.byType(EditableText);
      final gesture = await tester.startGesture(
        tester.getTopLeft(field) + const Offset(10, 10),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(find.byType(TextMagnifier), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(TextMagnifier), findsNothing);
      final selectAll = find.text('Select all');
      expect(selectAll.hitTestable(), findsOneWidget);

      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      final selection = tester.widget<EditableText>(field).controller.selection;
      expect((selection.start, selection.end), (0, 'hello world'.length));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('right click shows the context menu', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();

      final field = find.byType(EditableText);
      await tester.tapAt(
        tester.getTopLeft(field) + const Offset(10, 10),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final selectAll = find.text('Select all');
      expect(selectAll.hitTestable(), findsOneWidget);

      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      final selection = tester.widget<EditableText>(field).controller.selection;
      expect((selection.start, selection.end), (0, 'hello world'.length));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
