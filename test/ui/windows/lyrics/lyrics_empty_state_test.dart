import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/lyrics_window_style.dart';
import 'package:fmp/ui/windows/lyrics/lyrics_empty_state.dart';

void main() {
  Widget host({required bool transparent, required String text}) {
    return MaterialApp(
      home: Scaffold(
        body: LyricsEmptyState(
          transparentMode: transparent,
          style: LyricsWindowStyle.defaults,
          waitingText: text,
        ),
      ),
    );
  }

  group('LyricsEmptyState (C1a leaf)', () {
    testWidgets('renders the waiting text and lyrics icon', (tester) async {
      await tester.pumpWidget(host(transparent: false, text: '等待歌詞'));
      await tester.pumpAndSettle();

      expect(find.text('等待歌詞'), findsOneWidget);
      expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
    });

    testWidgets('builds without throwing in transparent mode', (tester) async {
      await tester.pumpWidget(host(transparent: true, text: 'Waiting'));
      await tester.pumpAndSettle();

      // 透明模式僅改變顏色/shadows，仍應渲染文案與圖示。
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
    });

    testWidgets('is a pure leaf: no channel or window_manager coupling',
        (tester) async {
      // 這個測試本身就是證明：leaf 可在無 desktop_multi_window engine 下 pump。
      await tester.pumpWidget(host(transparent: false, text: 'x'));
      await tester.pumpAndSettle();
      expect(find.byType(LyricsEmptyState), findsOneWidget);
    });
  });
}
