import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/repository_providers.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/pages/settings/audio_settings_page.dart';
import 'package:fmp/ui/pages/settings/lyrics_source_settings_page.dart';

import '../../../support/fakes/fake_settings_repository.dart';
import '../../../support/fakes/secure_storage_channel.dart';

/// 憑證儲存讀不到時這兩頁該長什麼樣（#89）。
///
/// 以前是一個永遠不會停的 `CircularProgressIndicator`：`isLoading` 預設 true，
/// 而 `readApiKey()` 的例外沒有人接，載入函式就在那一行結束了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget page) async {
    LocaleSettings.setLocale(AppLocale.en);
    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWith(
              (ref) => FakeSettingsRepository(Settings()),
            ),
          ],
          child: MaterialApp(home: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('audio settings loads and explains the failure', (tester) async {
    mockSecureStorageChannel(failing: true);

    await pump(tester, const AudioSettingsPage());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text(t.audioSettings.secureStorageUnavailable.title),
      findsOneWidget,
    );
    // 頁面其餘內容照樣在 —— 這一頁的設定全都在 Isar 裡，跟憑證儲存無關。
    expect(find.text(t.audioSettings.qualityLevel.title), findsOneWidget);
  });

  testWidgets('audio settings shows no notice when the store works', (
    tester,
  ) async {
    mockSecureStorageChannel();

    await pump(tester, const AudioSettingsPage());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text(t.audioSettings.secureStorageUnavailable.title),
      findsNothing,
    );
  });

  testWidgets('the AI key field says unreadable, not unconfigured', (
    tester,
  ) async {
    mockSecureStorageChannel(failing: true);

    await pump(tester, const LyricsSourceSettingsPage());
    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await tester.pumpAndSettle();

    // 「未設定」會讓使用者以為金鑰被清掉了，它其實還在。
    expect(
      find.text(t.settings.lyricsSourceSettings.aiApiKeyUnavailable),
      findsOneWidget,
    );
    expect(
      find.text(t.settings.lyricsSourceSettings.aiApiKeyEmpty),
      findsNothing,
    );
  });

  testWidgets('a stored key still reads as configured', (tester) async {
    mockSecureStorageChannel(values: const {'lyrics_ai_api_key': 'secret'});

    await pump(tester, const LyricsSourceSettingsPage());
    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await tester.pumpAndSettle();

    expect(
      find.text(t.settings.lyricsSourceSettings.aiApiKeyConfigured),
      findsOneWidget,
    );
  });
}
