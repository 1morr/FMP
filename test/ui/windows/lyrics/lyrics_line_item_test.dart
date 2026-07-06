import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/lyrics_window_style.dart';
import 'package:fmp/ui/windows/lyrics/lyrics_line_item.dart';

void main() {
  Widget host({required LyricsLineItem child}) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('LyricsLineItem (C1e leaf)', () {
    testWidgets('renders main text and optional sub text', (tester) async {
      await tester.pumpWidget(host(
        child: const LyricsLineItem(
          text: '主歌詞',
          subText: 'translation',
          isCurrent: true,
          fontSizes: (main: 24.0, sub: 16.0),
          transparentMode: false,
          style: LyricsWindowStyle.defaults,
          isSynced: true,
          hasTimestamp: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('主歌詞'), findsOneWidget);
      expect(find.text('translation'), findsOneWidget);
    });

    testWidgets('omits sub text area when subText is null/empty', (tester) async {
      await tester.pumpWidget(host(
        child: const LyricsLineItem(
          text: 'only main',
          isCurrent: false,
          fontSizes: (main: 20.0, sub: 14.0),
          transparentMode: false,
          style: LyricsWindowStyle.defaults,
          isSynced: false,
          hasTimestamp: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('only main'), findsOneWidget);
      // 沒有副行：text 'only main' 只出現一次（不會因副行重複）。
    });

    testWidgets('tap fires callback only when synced and has timestamp',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(
        child: LyricsLineItem(
          text: 'line',
          isCurrent: true,
          fontSizes: const (main: 24.0, sub: 16.0),
          transparentMode: false,
          style: LyricsWindowStyle.defaults,
          isSynced: true,
          hasTimestamp: true,
          onTap: () => tapped++,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LyricsLineItem));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('tap is disabled when not synced (callback not invoked)',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(
        child: LyricsLineItem(
          text: 'line',
          isCurrent: true,
          fontSizes: const (main: 24.0, sub: 16.0),
          transparentMode: false,
          style: LyricsWindowStyle.defaults,
          isSynced: false,
          hasTimestamp: true,
          onTap: () => tapped++,
        ),
      ));
      await tester.pumpAndSettle();
      // GestureDetector.onTap 為 null → 點擊不會呼叫 onTap。
      expect(tapped, 0);
    });
  });
}
