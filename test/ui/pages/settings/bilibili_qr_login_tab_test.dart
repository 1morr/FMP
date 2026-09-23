import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/ui/pages/settings/bilibili_login_page.dart';

import '../../../support/fakes/fake_isar.dart';
import '../../../support/fakes/fake_secure_key_value_store.dart';

/// QR 碼登入的輪詢串流斷掉時，使用者要看得到原因。
///
/// 沒接 `onError` 的話，串流錯誤會變成沒有人接的非同步錯誤：畫面停在「等待掃碼」，
/// 使用者掃了也不會有任何反應。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a broken status poll is reported and marks the code expired', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.en);
    final polls = StreamController<QrCodePollResult>();
    addTearDown(polls.close);

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            bilibiliAccountServiceProvider.overrideWithValue(
              _ScriptedAccountService(polls.stream),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: BilibiliQrLoginTab(onLoginSuccess: () {})),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(t.account.qrWaiting), findsOneWidget);

    polls.addError(const SocketException('offline'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(t.error.networkError), findsOneWidget);
    expect(find.text(t.account.qrWaiting), findsNothing);
  });
}

/// 產生 QR 碼成功，輪詢交給測試控制；其餘成員都不該被碰到。
class _ScriptedAccountService extends BilibiliAccountService {
  _ScriptedAccountService(this._polls)
    : super(isar: FakeIsar(), secureStorage: MemorySecureKeyValueStore());

  final Stream<QrCodePollResult> _polls;

  @override
  Future<QrCodeData> generateQrCode() async =>
      QrCodeData(url: 'https://example.com/qr', qrcodeKey: 'key');

  @override
  Stream<QrCodePollResult> pollQrCodeStatus(String qrcodeKey) => _polls;
}
