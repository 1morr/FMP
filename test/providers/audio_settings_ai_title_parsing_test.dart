import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/providers/audio/audio_settings_provider.dart';
import '../support/audio_settings_notifier.dart';
import '../support/fakes/fake_settings_repository.dart';

void main() {
  group('AudioSettingsState AI title parsing settings', () {
    test('uses expected default values', () {
      const state = AudioSettingsState();

      expect(state.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
      expect(state.lyricsAiEndpoint, '');
      expect(state.lyricsAiModel, '');
      expect(state.lyricsAiTimeoutSeconds, 20);
      expect(state.lyricsAiApiKeyConfigured, isFalse);
      expect(state.allowPlainLyricsAutoMatch, isFalse);
    });

    test('copyWith updates AI settings and preserves unchanged values', () {
      const state = AudioSettingsState(
        lyricsAiTitleParsingMode: LyricsAiTitleParsingMode.off,
        lyricsAiEndpoint: 'https://example.com/v1/chat/completions',
        lyricsAiModel: 'gpt-4o-mini',
        lyricsAiTimeoutSeconds: 15,
        lyricsAiApiKeyConfigured: true,
      );

      final updated = state.copyWith(
        lyricsAiTitleParsingMode: LyricsAiTitleParsingMode.alwaysAi,
        lyricsAiModel: 'claude-haiku',
        lyricsAiApiKeyConfigured: false,
      );

      expect(
        updated.lyricsAiTitleParsingMode,
        LyricsAiTitleParsingMode.alwaysAi,
      );
      expect(updated.lyricsAiModel, 'claude-haiku');
      expect(updated.lyricsAiApiKeyConfigured, isFalse);
      expect(updated.lyricsAiEndpoint, state.lyricsAiEndpoint);
      expect(updated.lyricsAiTimeoutSeconds, state.lyricsAiTimeoutSeconds);
    });
  });

  group('AudioSettingsNotifier AI title parsing settings', () {
    test('normalizes timeout and API key configured state', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final repository = FakeSettingsRepository(Settings());
      final notifier = audioSettingsNotifierFor(repository);
      await Future<void>.delayed(Duration.zero);

      await notifier.setLyricsAiTimeoutSeconds(0);
      expect(notifier.state.lyricsAiTimeoutSeconds, 20);
      expect(repository.settings.lyricsAiTimeoutSeconds, 20);

      await notifier.setLyricsAiApiKey('  secret  ');
      expect(notifier.state.lyricsAiApiKeyConfigured, isTrue);

      await notifier.setLyricsAiApiKey('');
      expect(notifier.state.lyricsAiApiKeyConfigured, isFalse);
    });

    test('updates plain lyrics automatic matching setting', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final repository = FakeSettingsRepository(Settings());
      final notifier = audioSettingsNotifierFor(repository);
      await Future<void>.delayed(Duration.zero);

      await notifier.setAllowPlainLyricsAutoMatch(true);

      expect(notifier.state.allowPlainLyricsAutoMatch, isTrue);
      expect(repository.settings.allowPlainLyricsAutoMatch, isTrue);
    });
  });
}
