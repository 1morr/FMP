import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/core/secure_key_value_store.dart';
import 'package:fmp/data/models/settings.dart';

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

class LyricsAiConfigService with Logging {
  LyricsAiConfigService({
    required Future<Settings> Function() loadSettings,
    SecureKeyValueStore? secureStorage,
    this.apiKeyStorageKey = 'lyrics_ai_api_key',
  }) : _loadSettings = loadSettings,
       _secureStorage = secureStorage ?? FlutterSecureKeyValueStore();

  final Future<Settings> Function() _loadSettings;
  final SecureKeyValueStore _secureStorage;
  final String apiKeyStorageKey;

  Future<LyricsAiConfig> loadConfig() async {
    final settings = await _loadSettings();
    // 「讀不到金鑰」與「沒設定金鑰」對這裡的結論是同一個：AI 解析不可用。
    // 差別在於呼叫端要不要跟使用者解釋，那是 [readApiKey] 的例外負責的事 ——
    // 這條路徑會被歌詞自動匹配踩到，往上丟只會讓整次匹配失敗。
    String apiKey;
    try {
      apiKey = await readApiKey();
    } on SecureStorageUnavailable catch (error) {
      logWarning('Lyrics AI key store unavailable: $error');
      apiKey = '';
    }
    final timeoutSeconds = settings.lyricsAiTimeoutSeconds < 1
        ? AppConstants.lyricsAiDefaultTimeoutSeconds
        : settings.lyricsAiTimeoutSeconds;

    return LyricsAiConfig(
      mode: settings.lyricsAiTitleParsingMode,
      endpoint: settings.lyricsAiEndpoint.trim(),
      apiKey: apiKey,
      model: settings.lyricsAiModel.trim(),
      timeoutSeconds: timeoutSeconds,
    );
  }

  /// 讀出已存的 API key，沒存過就是空字串。
  ///
  /// 憑證儲存本身讀不出來時**丟 [SecureStorageUnavailable]**，不吞成空字串：
  /// 「解不開既有密文」與「沒有金鑰」對使用者是兩件事，前者要告訴他金鑰還在、
  /// 只是這台機器現在讀不到（#89）。每個呼叫端自己決定怎麼降級。
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
