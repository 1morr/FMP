import 'package:fmp/ui/windows/lyrics_display_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LyricsDisplayMode (C1c)', () {
    test('fromIndex maps the three wire values', () {
      expect(LyricsDisplayMode.fromIndex(0), LyricsDisplayMode.original);
      expect(LyricsDisplayMode.fromIndex(1), LyricsDisplayMode.preferTranslated);
      expect(LyricsDisplayMode.fromIndex(2), LyricsDisplayMode.preferRomaji);
    });

    test('fromIndex is lenient: out-of-range and null fall back to original', () {
      expect(LyricsDisplayMode.fromIndex(null), LyricsDisplayMode.original);
      expect(LyricsDisplayMode.fromIndex(-1), LyricsDisplayMode.original);
      expect(LyricsDisplayMode.fromIndex(3), LyricsDisplayMode.original);
      expect(LyricsDisplayMode.fromIndex(99), LyricsDisplayMode.original);
    });

    test('next cycles original → preferTranslated → preferRomaji → original', () {
      expect(LyricsDisplayMode.original.next, LyricsDisplayMode.preferTranslated);
      expect(
        LyricsDisplayMode.preferTranslated.next,
        LyricsDisplayMode.preferRomaji,
      );
      expect(LyricsDisplayMode.preferRomaji.next, LyricsDisplayMode.original);
    });

    test('modeIndex stays aligned with the host IPC contract (0/1/2)', () {
      // 線傳值必須固定為 0/1/2，與主視窗 LyricsWindowService 合約一致；
      // 改變須同步兩端。
      expect(LyricsDisplayMode.original.modeIndex, 0);
      expect(LyricsDisplayMode.preferTranslated.modeIndex, 1);
      expect(LyricsDisplayMode.preferRomaji.modeIndex, 2);
    });

    test('every mode has a distinct toolbar icon', () {
      final icons = LyricsDisplayMode.values.map((m) => m.icon).toSet();
      expect(icons.length, LyricsDisplayMode.values.length);
    });
  });
}
