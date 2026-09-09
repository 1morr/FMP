import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/secure_key_value_store.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/services/lyrics/lyrics_ai_config_service.dart';

import '../support/audio_settings_notifier.dart';
import '../support/fakes/fake_secure_key_value_store.dart';
import '../support/fakes/fake_settings_repository.dart';
import '../support/fakes/secure_storage_channel.dart';

/// 憑證儲存讀不到時的降級（#89）。
///
/// `SecureKeyValueStore` 把平台失敗翻成 `SecureStorageUnavailable`，三個 account
/// service 都各自接住降級成登出。issue #35 只列了那三個 `read()`，漏掉音訊設定
/// 這一路 —— 例外一逸出，`isLoading` 就永遠停在 true，音訊設定頁是一個永久的
/// spinner。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioSettingsNotifier with an unreadable credential store', () {
    test('finishes loading instead of spinning forever', () async {
      mockSecureStorageChannel(failing: true);
      final settings = Settings()
        ..lyricsAiEndpoint = 'https://api.example.com/v1'
        ..lyricsAiModel = 'gpt-test';
      final notifier = audioSettingsNotifierFor(
        FakeSettingsRepository(settings),
      );

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.isLoading, isFalse);
      // Isar 裡的設定照樣載入 —— 讀不到的只有金鑰。
      expect(notifier.state.lyricsAiEndpoint, 'https://api.example.com/v1');
      expect(notifier.state.lyricsAiModel, 'gpt-test');
    });

    test('flags the failure instead of claiming there is no key', () async {
      mockSecureStorageChannel(failing: true);
      final notifier = audioSettingsNotifierFor(
        FakeSettingsRepository(Settings()),
      );

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.secureStorageUnavailable, isTrue);
      // 金鑰可能還在，只是這台機器解不開，所以「已設定」也不能說是 true。
      expect(notifier.state.lyricsAiApiKeyConfigured, isFalse);
    });

    test('a working store leaves the flag clear', () async {
      mockSecureStorageChannel(values: const {'lyrics_ai_api_key': 'secret'});
      final notifier = audioSettingsNotifierFor(
        FakeSettingsRepository(Settings()),
      );

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.secureStorageUnavailable, isFalse);
      expect(notifier.state.lyricsAiApiKeyConfigured, isTrue);
    });
  });

  group('LyricsAiConfigService with an unreadable credential store', () {
    test('reports AI as unavailable instead of throwing', () async {
      final service = LyricsAiConfigService(
        loadSettings: () async => Settings()
          ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.alwaysAi
          ..lyricsAiEndpoint = 'https://api.example.com/v1'
          ..lyricsAiModel = 'gpt-test',
        secureStorage: UnavailableSecureKeyValueStore(),
      );

      // 歌詞自動匹配會踩到這條路徑，往上丟只會讓整次匹配失敗。
      final config = await service.loadConfig();

      expect(config.apiKey, isEmpty);
      expect(config.isAvailable, isFalse);
      expect(config.endpoint, 'https://api.example.com/v1');
    });

    test('readApiKey still tells the caller the store is unreadable', () async {
      final store = UnavailableSecureKeyValueStore();
      final service = LyricsAiConfigService(
        loadSettings: () async => Settings(),
        secureStorage: store,
      );

      // 這裡刻意不吞：呼叫端要能分辨「沒有金鑰」與「讀不到金鑰」，設定頁的
      // 提示就是靠這個分辨的。
      await expectLater(
        service.readApiKey(),
        throwsA(isA<SecureStorageUnavailable>()),
      );
      expect(store.readCount, 1);
    });
  });
}
