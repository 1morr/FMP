import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/pages/player/player_page.dart';

void main() {
  group('resolvePlayerLayout', () {
    test('splits at 840dp, not 1200dp', () {
      // 840 是 M3 Expanded 的下界。1199dp 的視窗以前和 600dp 拿到一樣的版面。
      expect(resolvePlayerLayout(const Size(839, 900), hasLyrics: true),
          PlayerLayoutMode.narrow);
      expect(resolvePlayerLayout(const Size(840, 900), hasLyrics: true),
          PlayerLayoutMode.wideSplit);
    });

    test('a wide but short window stays single column', () {
      // 橫向手機：寬度過關、高度不過關。以前只看寬度，於是它拿到雙欄。
      expect(resolvePlayerLayout(const Size(1200, 519), hasLyrics: true),
          PlayerLayoutMode.narrow);
      expect(resolvePlayerLayout(const Size(1200, 520), hasLyrics: true),
          PlayerLayoutMode.wideSplit);
    });

    test('no lyrics means no second column, however wide the window is', () {
      // 右欄以前是寫死的 flex: 7，所以沒有歌詞的曲目會把 58% 的畫面留給
      // 一句「暫無歌詞」。
      expect(resolvePlayerLayout(const Size(1700, 1000), hasLyrics: false),
          PlayerLayoutMode.wideSingle);
      expect(resolvePlayerLayout(const Size(1700, 1000), hasLyrics: true),
          PlayerLayoutMode.wideSplit);
    });

    test('a narrow window is narrow whether or not it has lyrics', () {
      expect(resolvePlayerLayout(const Size(411, 900), hasLyrics: true),
          PlayerLayoutMode.narrow);
      expect(resolvePlayerLayout(const Size(411, 900), hasLyrics: false),
          PlayerLayoutMode.narrow);
    });
  });
}
