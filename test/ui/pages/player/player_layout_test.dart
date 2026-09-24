import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/pages/player/player_page.dart';

void main() {
  group('resolvePlayerLayout', () {
    test('splits at 840dp, not 1200dp', () {
      // 840 是 M3 Expanded 的下界。1199dp 的視窗以前和 600dp 拿到一樣的版面。
      expect(
        resolvePlayerLayout(const Size(839, 900), hasLyrics: true),
        PlayerLayoutMode.narrow,
      );
      expect(
        resolvePlayerLayout(const Size(840, 900), hasLyrics: true),
        PlayerLayoutMode.wideSplit,
      );
    });

    test('a wide but short window puts the cover beside the controls', () {
      // 橫向手機：寬度過關、高度不過關。以前只看寬度，於是它拿到雙欄；之後改
      // 成直向的單欄，封面被壓到約 6dp。它要的是封面與控制列並排。
      expect(
        resolvePlayerLayout(const Size(914, 411), hasLyrics: true),
        PlayerLayoutMode.shortSplit,
      );
      expect(
        resolvePlayerLayout(const Size(1200, 519), hasLyrics: true),
        PlayerLayoutMode.shortSplit,
      );
      expect(
        resolvePlayerLayout(const Size(1200, 520), hasLyrics: true),
        PlayerLayoutMode.wideSplit,
      );
    });

    test('no lyrics means no second column, however wide the window is', () {
      // 右欄以前是寫死的 flex: 7，所以沒有歌詞的曲目會把 58% 的畫面留給
      // 一句「暫無歌詞」。
      expect(
        resolvePlayerLayout(const Size(1700, 1000), hasLyrics: false),
        PlayerLayoutMode.wideSingle,
      );
      expect(
        resolvePlayerLayout(const Size(1700, 1000), hasLyrics: true),
        PlayerLayoutMode.wideSplit,
      );
    });

    test('a short window that is not wider than tall stays single column', () {
      expect(
        resolvePlayerLayout(const Size(400, 450), hasLyrics: true),
        PlayerLayoutMode.narrow,
      );
    });

    test('a narrow window is narrow whether or not it has lyrics', () {
      expect(
        resolvePlayerLayout(const Size(411, 900), hasLyrics: true),
        PlayerLayoutMode.narrow,
      );
      expect(
        resolvePlayerLayout(const Size(411, 900), hasLyrics: false),
        PlayerLayoutMode.narrow,
      );
    });
  });

  group('PlayerShortSplitContent', () {
    // 914dp × 411dp 的橫向手機扣掉狀態列與工具列，播放頁內容區約 331dp 高。
    const body = Size(914, 331);

    Future<void> pumpContent(WidgetTester tester, double controlsHeight) async {
      await tester.binding.setSurfaceSize(body);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerShortSplitContent(
              media: const AspectRatio(
                key: ValueKey('cover'),
                aspectRatio: 1,
                child: ColoredBox(color: Colors.grey),
              ),
              // 真的控制列是 Column；一個裸 SizedBox 會被父層約束夾小，量不到
              // 溢出。
              controls: Column(
                mainAxisSize: MainAxisSize.min,
                children: [SizedBox(height: controlsHeight, width: 300)],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the cover takes the full height left beside the controls', (
      tester,
    ) async {
      // 控制列約 272dp（標題兩行、歌手、進度條、按鈕列）。
      await pumpContent(tester, 272);

      final cover = tester.getSize(find.byKey(const ValueKey('cover')));
      expect(cover.height, body.height - 48);
      expect(tester.takeException(), isNull);
    });

    testWidgets('controls taller than the window scroll instead of clipping', (
      tester,
    ) async {
      // 字級 2.0 時控制列會比視窗高（實機量到溢出 43px）。
      await pumpContent(tester, 500);

      expect(tester.takeException(), isNull);
    });
  });
}
