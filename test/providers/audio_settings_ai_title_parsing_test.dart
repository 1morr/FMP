import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/providers/audio_settings_provider.dart';
import 'package:isar/isar.dart';

void main() {
  group('AudioSettingsState AI title parsing settings', () {
    test('uses expected default values', () {
      const state = AudioSettingsState();

      expect(
        state.lyricsAiTitleParsingMode,
        LyricsAiTitleParsingMode.off,
      );
      expect(state.lyricsAiEndpoint, '');
      expect(state.lyricsAiModel, '');
      expect(state.lyricsAiTimeoutSeconds, 10);
      expect(state.lyricsAiApiKeyConfigured, isFalse);
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
      final repository = _FakeSettingsRepository(Settings());
      final notifier = AudioSettingsNotifier(repository);
      await Future<void>.delayed(Duration.zero);

      await notifier.setLyricsAiTimeoutSeconds(0);
      expect(notifier.state.lyricsAiTimeoutSeconds, 10);
      expect(repository.settings.lyricsAiTimeoutSeconds, 10);

      await notifier.setLyricsAiApiKey('  secret  ');
      expect(notifier.state.lyricsAiApiKeyConfigured, isTrue);

      await notifier.setLyricsAiApiKey('');
      expect(notifier.state.lyricsAiApiKeyConfigured, isFalse);
    });
  });
}

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository(this.settings) : super(_FakeIsar());

  final Settings settings;

  @override
  Future<Settings> get() async => settings;

  @override
  Future<Settings> update(void Function(Settings settings) mutate) async {
    mutate(settings);
    return settings;
  }
}

class _FakeIsar extends Fake implements Isar {}
