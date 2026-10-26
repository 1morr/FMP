import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

void main() {
  Future<void> submit(WidgetTester tester, String keyword) async {
    await tester.enterText(find.byType(TextField), keyword);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
  }

  Future<ShellHarness> open(
    WidgetTester tester, {
    List<String> seeded = const [],
  }) async {
    final h = ShellHarness();
    await h.pumpShell(tester);
    await tester.runAsync(() async {
      final repository = h
          .container(tester)
          .read(searchHistoryRepositoryProvider);
      for (final query in seeded) {
        await repository.record(query);
        // 時間相同時依關鍵字排，隔開一毫秒讓順序是寫入的順序。
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    });
    await h.loadSettings(tester);
    return h;
  }

  Future<List<String>> stored(WidgetTester tester, ShellHarness h) async =>
      (await tester.runAsync(
        () async => [
          for (final e
              in await h
                  .container(tester)
                  .read(searchHistoryRepositoryProvider)
                  .list())
            e.query,
        ],
      ))!;

  testWidgets('an empty field lists the history, newest first', (tester) async {
    final h = await open(tester, seeded: ['old', 'new']);

    expect(find.text('Search history'), findsOneWidget);
    expect(find.text('Type a keyword to search'), findsNothing);
    final titles = [
      for (final tile in tester.widgetList<ListTile>(
        find.widgetWithIcon(ListTile, Icons.history),
      ))
        (tile.title! as Text).data,
    ];
    expect(titles, ['new', 'old']);
    expect(await stored(tester, h), ['new', 'old']);
  });

  testWidgets('without history the prompt stays', (tester) async {
    await open(tester);

    expect(find.text('Search history'), findsNothing);
    expect(find.text('Type a keyword to search'), findsOneWidget);
  });

  testWidgets('submitting records the keyword, trimmed', (tester) async {
    final h = await open(tester);

    await submit(tester, '  lofi  ');
    await h.loadSettings(tester);

    expect(await stored(tester, h), ['lofi']);
    // 結果顯示時不列歷史。
    expect(find.text('Search history'), findsNothing);
  });

  testWidgets('blank input records nothing', (tester) async {
    final h = await open(tester);

    await submit(tester, '   ');
    await h.loadSettings(tester);

    expect(await stored(tester, h), isEmpty);
  });

  testWidgets('tapping an entry searches it again and moves it up', (
    tester,
  ) async {
    final h = await open(tester, seeded: ['first', 'second']);

    await tester.tap(find.text('first'));
    await tester.pump();
    await tester.pump();
    await h.loadSettings(tester);

    expect(h.plugin.searches.single.keyword, 'first');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'first',
    );
    expect(await stored(tester, h), ['first', 'second']);
  });

  testWidgets('the cross deletes one entry', (tester) async {
    final h = await open(tester, seeded: ['a', 'b']);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'a'),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();
    await h.loadSettings(tester);

    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsOneWidget);
    expect(await stored(tester, h), ['b']);
  });

  testWidgets('clear empties the history without asking', (tester) async {
    final h = await open(tester, seeded: ['a', 'b']);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    await h.loadSettings(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(await stored(tester, h), isEmpty);
    expect(find.text('Search history'), findsNothing);
    expect(find.text('Type a keyword to search'), findsOneWidget);
  });
}
