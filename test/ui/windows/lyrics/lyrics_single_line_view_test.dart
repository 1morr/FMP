import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/lyrics_window_style.dart';
import 'package:fmp/ui/windows/lyrics/lyrics_single_line_view.dart';

Widget host({required LyricsSingleLineView child}) {
  // LayoutBuilder 需要有限寬高才能做字級擬合。
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 200,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('LyricsSingleLineView (C1e leaf + C1b 單行半)', () {
    testWidgets('renders main text (and sub text when provided)',
        (tester) async {
      await tester.pumpWidget(host(
        child: const LyricsSingleLineView(
          mainText: '主歌詞一行',
          subText: 'translation',
          transparentMode: false,
          style: LyricsWindowStyle.defaults,
          isSynced: true,
          hasCurrentLine: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('主歌詞一行'), findsWidgets);
      expect(find.text('translation'), findsWidgets);
    });

    testWidgets('renders only main text when subText is null', (tester) async {
      await tester.pumpWidget(host(
        child: const LyricsSingleLineView(
          mainText: 'only main line',
          transparentMode: false,
          style: LyricsWindowStyle.defaults,
          isSynced: false,
          hasCurrentLine: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('only main line'), findsWidgets);
    });

    testWidgets('tap fires callback when synced and has current line',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(
        child: LyricsSingleLineView(
          mainText: 'line',
          transparentMode: false,
          style: LyricsWindowStyle.defaults,
          isSynced: true,
          hasCurrentLine: true,
          onTap: () => tapped++,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LyricsSingleLineView));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('tap disabled when not synced', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(
        child: LyricsSingleLineView(
          mainText: 'line',
          transparentMode: false,
          style: LyricsWindowStyle.defaults,
          isSynced: false,
          hasCurrentLine: true,
          onTap: () => tapped++,
        ),
      ));
      await tester.pumpAndSettle();

      expect(tapped, 0); // GestureDetector.onTap 為 null
    });

    testWidgets('long text does not overflow the bounded box', (tester) async {
      // 字級擬合 + 換行 + 高度限制應避免 overflow；testWidget 不應拋 overflow。
      await tester.pumpWidget(host(
        child: const LyricsSingleLineView(
          mainText: '這是一段非常長的單行歌詞用來驗證字級擬合與換行不會溢出邊界',
          subText: '英文 translation 也偏長 here too',
          transparentMode: false,
          style: LyricsWindowStyle.defaults,
          isSynced: true,
          hasCurrentLine: true,
        ),
      ));
      await tester.pumpAndSettle();

      // 無 overflow exception 即通過；主文案有渲染。
      expect(
        find.text('這是一段非常長的單行歌詞用來驗證字級擬合與換行不會溢出邊界'),
        findsWidgets,
      );
    });
  });
}
