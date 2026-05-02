import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';

void main() {
  group('Lyrics AI title parsing settings', () {
    test('defaults to AI off with empty connection fields', () {
      final settings = Settings();

      expect(settings.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
      expect(settings.lyricsAiTitleParsingModeIndex, 0);
      expect(settings.allowPlainLyricsAutoMatch, isFalse);
      expect(settings.lyricsAiEndpoint, isEmpty);
      expect(settings.lyricsAiModel, isEmpty);
      expect(settings.lyricsAiTimeoutSeconds, 10);
    });

    test('maps legacy fallback index to off', () {
      final settings = Settings()..lyricsAiTitleParsingModeIndex = 1;

      expect(settings.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
    });

    test('round-trips stable AI mode indexes', () {
      final settings = Settings();

      settings.lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.alwaysAi;
      expect(settings.lyricsAiTitleParsingModeIndex, 2);

      settings.lyricsAiTitleParsingMode =
          LyricsAiTitleParsingMode.advancedAiSelect;
      expect(settings.lyricsAiTitleParsingModeIndex, 3);

      settings.lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.off;
      expect(settings.lyricsAiTitleParsingModeIndex, 0);
    });

    test('invalid mode index resolves to off', () {
      final settings = Settings()..lyricsAiTitleParsingModeIndex = 99;

      expect(settings.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
    });
  });
}
