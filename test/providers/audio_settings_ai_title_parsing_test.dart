import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/providers/audio_settings_provider.dart';

void main() {
  group('AudioSettingsState AI title parsing settings', () {
    test('uses expected default values', () {
      const state = AudioSettingsState();

      expect(
        state.lyricsAiTitleParsingMode,
        LyricsAiTitleParsingMode.fallbackAfterRules,
      );
      expect(state.lyricsAiEndpoint, '');
      expect(state.lyricsAiModel, '');
      expect(state.lyricsAiTimeoutSeconds, 10);
      expect(state.lyricsAiApiKeyConfigured, isFalse);
    });

    test('copyWith updates AI settings and preserves unchanged values', () {
      const state = AudioSettingsState(
        lyricsAiTitleParsingMode: LyricsAiTitleParsingMode.fallbackAfterRules,
        lyricsAiEndpoint: 'https://example.com/v1/chat/completions',
        lyricsAiModel: 'gpt-4o-mini',
        lyricsAiTimeoutSeconds: 15,
        lyricsAiApiKeyConfigured: true,
      );

      final updated = state.copyWith(
        lyricsAiTitleParsingMode:
            LyricsAiTitleParsingMode.alwaysForVideoSources,
        lyricsAiModel: 'claude-haiku',
        lyricsAiApiKeyConfigured: false,
      );

      expect(
        updated.lyricsAiTitleParsingMode,
        LyricsAiTitleParsingMode.alwaysForVideoSources,
      );
      expect(updated.lyricsAiModel, 'claude-haiku');
      expect(updated.lyricsAiApiKeyConfigured, isFalse);
      expect(updated.lyricsAiEndpoint, state.lyricsAiEndpoint);
      expect(updated.lyricsAiTimeoutSeconds, state.lyricsAiTimeoutSeconds);
    });
  });
}
