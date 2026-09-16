import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/ui/pages/settings/account_management_page.dart';

/// 帳號卡片的第三態：登入失效。
///
/// 兩態的時候使用者只看得到「未登入」，分不出「我沒登過」和「登入失效了」
/// （#93）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LocaleSettings.setLocale(AppLocale.en);
  });

  testWidgets('an expired account keeps its name and offers both actions', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      bilibili: Account()
        ..platform = SourceIds.bilibili
        ..userName = 'Expired User'
        ..isLoggedIn = false
        ..sessionExpired = true,
    );

    final subtitle = tester.widget<Text>(
      find.text('Expired User · ${t.account.sessionExpiredShort}'),
    );
    expect(
      subtitle.style?.color,
      Theme.of(tester.element(find.byType(Scaffold))).colorScheme.error,
    );

    expect(
      find.widgetWithText(FilledButton, t.account.relogin),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, t.account.logout),
      findsOneWidget,
    );
    // 失效不是已登入：歌單 / 電台入口這時候按了也只會失敗。
    expect(find.text(t.account.playlists), findsNothing);
    expect(
      find.widgetWithText(FilledButton, t.account.login),
      findsNWidgets(2),
    );
  });

  testWidgets('a never-logged-in account still shows one login button', (
    tester,
  ) async {
    await _pumpPage(tester);

    expect(find.text(t.account.notLoggedIn), findsNWidgets(3));
    expect(
      find.widgetWithText(FilledButton, t.account.login),
      findsNWidgets(3),
    );
    expect(find.text(t.account.relogin), findsNothing);
  });
}

Future<void> _pumpPage(WidgetTester tester, {Account? bilibili}) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: ProviderScope(
        overrides: [
          bilibiliAccountProvider.overrideWith(
            () => _StaticAccountNotifier(SourceIds.bilibili, bilibili),
          ),
          youtubeAccountProvider.overrideWith(
            () => _StaticAccountNotifier(SourceIds.youtube, null),
          ),
          neteaseAccountProvider.overrideWith(
            () => _StaticAccountNotifier(SourceIds.netease, null),
          ),
        ],
        child: const MaterialApp(home: AccountManagementPage()),
      ),
    ),
  );
  await tester.pump();
}

/// 固定回傳一列帳號的 [AccountNotifier]，不碰 Isar。
class _StaticAccountNotifier extends AccountNotifier {
  _StaticAccountNotifier(super.platform, this._account);

  final Account? _account;

  @override
  Account? build() => _account;
}
