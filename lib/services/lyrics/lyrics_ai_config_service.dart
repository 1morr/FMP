import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/settings.dart';

abstract class SecureKeyValueStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class LyricsAiConfig {
  const LyricsAiConfig({
    required this.mode,
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.timeoutSeconds,
  });

  final LyricsAiTitleParsingMode mode;
  final String endpoint;
  final String apiKey;
  final String model;
  final int timeoutSeconds;

  bool get isAvailable =>
      mode != LyricsAiTitleParsingMode.off &&
      endpoint.isNotEmpty &&
      apiKey.isNotEmpty &&
      model.isNotEmpty;
}

class LyricsAiConfigService {
  LyricsAiConfigService({
    required Future<Settings> Function() loadSettings,
    SecureKeyValueStore? secureStorage,
    this.apiKeyStorageKey = 'lyrics_ai_api_key',
  })  : _loadSettings = loadSettings,
        _secureStorage = secureStorage ?? FlutterSecureKeyValueStore();

  final Future<Settings> Function() _loadSettings;
  final SecureKeyValueStore _secureStorage;
  final String apiKeyStorageKey;

  Future<LyricsAiConfig> loadConfig() async {
    final settings = await _loadSettings();
    final apiKey = await readApiKey();
    final timeoutSeconds = settings.lyricsAiTimeoutSeconds < 1
        ? 10
        : settings.lyricsAiTimeoutSeconds;

    return LyricsAiConfig(
      mode: settings.lyricsAiTitleParsingMode,
      endpoint: settings.lyricsAiEndpoint.trim(),
      apiKey: apiKey,
      model: settings.lyricsAiModel.trim(),
      timeoutSeconds: timeoutSeconds,
    );
  }

  Future<String> readApiKey() async {
    return (await _secureStorage.read(key: apiKeyStorageKey))?.trim() ?? '';
  }

  Future<void> saveApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: apiKeyStorageKey);
      return;
    }

    await _secureStorage.write(key: apiKeyStorageKey, value: trimmed);
  }
}
