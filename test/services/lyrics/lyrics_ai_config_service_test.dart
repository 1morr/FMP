import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/services/lyrics/lyrics_ai_config_service.dart';

import '../../support/fakes/fake_secure_key_value_store.dart';

void main() {
  group('LyricsAiConfigService', () {
    test('uses unavailable off mode by default', () async {
      final service = LyricsAiConfigService(
        loadSettings: () async => Settings(),
        secureStorage: MemorySecureKeyValueStore(),
      );

      final config = await service.loadConfig();

      expect(config.mode, LyricsAiTitleParsingMode.off);
      expect(config.isAvailable, isFalse);
    });

    test('returns unavailable when mode is off', () async {
      final settings = Settings()
        ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.off
        ..lyricsAiEndpoint = 'https://api.example.com/v1'
        ..lyricsAiModel = 'gpt-test'
        ..lyricsAiTimeoutSeconds = 10;
      final storage = MemorySecureKeyValueStore({'lyrics_ai_api_key': 'key'});
      final service = LyricsAiConfigService(
        loadSettings: () async => settings,
        secureStorage: storage,
      );

      final config = await service.loadConfig();

      expect(config.mode, LyricsAiTitleParsingMode.off);
      expect(config.isAvailable, isFalse);
    });

    test('returns available when all fields are present', () async {
      final settings = Settings()
        ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.alwaysAi
        ..lyricsAiEndpoint = ' https://api.example.com/v1 '
        ..lyricsAiModel = ' gpt-test '
        ..lyricsAiTimeoutSeconds = 15;
      final storage = MemorySecureKeyValueStore({'lyrics_ai_api_key': ' key '});
      final service = LyricsAiConfigService(
        loadSettings: () async => settings,
        secureStorage: storage,
      );

      final config = await service.loadConfig();

      expect(config.isAvailable, isTrue);
      expect(config.endpoint, 'https://api.example.com/v1');
      expect(config.apiKey, 'key');
      expect(config.model, 'gpt-test');
      expect(config.timeoutSeconds, 15);
    });

    test('advanced mode is available with endpoint key and model', () async {
      final service = LyricsAiConfigService(
        loadSettings: () async => Settings()
          ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.advancedAiSelect
          ..lyricsAiEndpoint = 'https://example.test/v1'
          ..lyricsAiModel = 'test-model',
        secureStorage: MemorySecureKeyValueStore({'lyrics_ai_api_key': 'key'}),
      );

      final config = await service.loadConfig();

      expect(config.mode, LyricsAiTitleParsingMode.advancedAiSelect);
      expect(config.isAvailable, isTrue);
    });

    test('clamps invalid timeout to 20 seconds', () async {
      final settings = Settings()
        ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.alwaysAi
        ..lyricsAiEndpoint = 'https://api.example.com/v1'
        ..lyricsAiModel = 'gpt-test'
        ..lyricsAiTimeoutSeconds = 0;
      final service = LyricsAiConfigService(
        loadSettings: () async => settings,
        secureStorage: MemorySecureKeyValueStore({'lyrics_ai_api_key': 'key'}),
      );

      final config = await service.loadConfig();

      expect(config.timeoutSeconds, 20);
    });

    test('stores trimmed key and clears key on empty', () async {
      final storage = MemorySecureKeyValueStore();
      final service = LyricsAiConfigService(
        loadSettings: () async => Settings(),
        secureStorage: storage,
      );

      await service.saveApiKey('  secret  ');
      expect(storage.values['lyrics_ai_api_key'], 'secret');
      expect(await service.readApiKey(), 'secret');

      await service.saveApiKey('   ');
      expect(storage.values.containsKey('lyrics_ai_api_key'), isFalse);
      expect(await service.readApiKey(), '');
    });
  });
}
