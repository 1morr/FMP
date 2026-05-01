import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/services/lyrics/lyrics_ai_config_service.dart';

void main() {
  group('LyricsAiConfigService', () {
    test('returns unavailable when mode is off', () async {
      final settings = Settings()
        ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.off
        ..lyricsAiEndpoint = 'https://api.example.com/v1'
        ..lyricsAiModel = 'gpt-test'
        ..lyricsAiTimeoutSeconds = 10;
      final storage = _MemorySecureKeyValueStore({'lyrics_ai_api_key': 'key'});
      final service = LyricsAiConfigService(
        loadSettings: () async => settings,
        secureStorage: storage,
      );

      final config = await service.loadConfig();

      expect(config.isAvailable, isFalse);
    });

    test('returns available when all fields are present', () async {
      final settings = Settings()
        ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.alwaysAi
        ..lyricsAiEndpoint = ' https://api.example.com/v1 '
        ..lyricsAiModel = ' gpt-test '
        ..lyricsAiTimeoutSeconds = 15;
      final storage =
          _MemorySecureKeyValueStore({'lyrics_ai_api_key': ' key '});
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

    test('clamps invalid timeout to 10 seconds', () async {
      final settings = Settings()
        ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.alwaysAi
        ..lyricsAiEndpoint = 'https://api.example.com/v1'
        ..lyricsAiModel = 'gpt-test'
        ..lyricsAiTimeoutSeconds = 0;
      final service = LyricsAiConfigService(
        loadSettings: () async => settings,
        secureStorage: _MemorySecureKeyValueStore({'lyrics_ai_api_key': 'key'}),
      );

      final config = await service.loadConfig();

      expect(config.timeoutSeconds, 10);
    });

    test('stores trimmed key and clears key on empty', () async {
      final storage = _MemorySecureKeyValueStore();
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

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  _MemorySecureKeyValueStore([Map<String, String>? initialValues])
      : values = Map<String, String>.from(initialValues ?? const {});

  final Map<String, String> values;

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
