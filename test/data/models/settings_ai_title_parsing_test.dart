import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';

void main() {
  group('Lyrics AI title parsing settings', () {
    test('defaults to fallback after rules with empty connection fields', () {
      final settings = Settings();

      expect(settings.lyricsAiTitleParsingMode,
          LyricsAiTitleParsingMode.fallbackAfterRules);
      expect(settings.lyricsAiEndpoint, isEmpty);
      expect(settings.lyricsAiModel, isEmpty);
      expect(settings.lyricsAiTimeoutSeconds, 10);
    });

    test('round-trips title parsing mode through index', () {
      final settings = Settings();

      settings.lyricsAiTitleParsingMode =
          LyricsAiTitleParsingMode.alwaysForVideoSources;
      expect(settings.lyricsAiTitleParsingModeIndex, 2);
      expect(settings.lyricsAiTitleParsingMode,
          LyricsAiTitleParsingMode.alwaysForVideoSources);

      settings.lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.off;
      expect(settings.lyricsAiTitleParsingModeIndex, 0);
      expect(settings.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
    });

    test('invalid mode index falls back to fallbackAfterRules', () {
      final settings = Settings()..lyricsAiTitleParsingModeIndex = 99;

      expect(settings.lyricsAiTitleParsingMode,
          LyricsAiTitleParsingMode.fallbackAfterRules);
    });
  });
}
