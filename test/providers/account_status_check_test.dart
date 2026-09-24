import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/services/account/account_service.dart';
import 'package:fmp/services/account/session_expiry_notifier.dart';

import '../support/pump_until.dart';

void main() {
  test(
    'verifyAllAccountStatuses reports per-platform check failures',
    () async {
      final toastService = ToastService();
      addTearDown(toastService.dispose);

      final result = await verifyAllAccountStatuses(
        [
          _FakeAccountService(
            platform: SourceIds.bilibili,
            loggedIn: true,
            check: () => throw StateError('network down'),
          ),
          _FakeAccountService(
            platform: SourceIds.youtube,
            loggedIn: true,
            check: () async => const AccountCheckResult(
              status: AccountStatus.valid,
              isVip: false,
            ),
          ),
        ],
        toastService,
        sessionExpiry: SessionExpiryNotifier(toastService),
      );

      expect(result.checkedPlatforms, [SourceIds.youtube]);
      expect(result.failedPlatforms, [SourceIds.bilibili]);
      expect(result.hasFailures, isTrue);
    },
  );

  test('an invalid account is marked expired, not logged out', () async {
    final toastService = ToastService();
    addTearDown(toastService.dispose);
    final service = _FakeAccountService(
      platform: SourceIds.netease,
      loggedIn: true,
      check: () async =>
          const AccountCheckResult(status: AccountStatus.invalid),
    );

    await verifyAllAccountStatuses(
      [service],
      toastService,
      sessionExpiry: SessionExpiryNotifier(toastService),
    );

    // 登出會刪掉帳號列，帳號頁就再也分不出「沒登入過」和「登入失效」。
    expect(service.logoutCount, 0);
    expect(service.markExpiredCount, 1);
  });

  test('the expiry toast fires once across two detections', () async {
    final toastService = ToastService();
    addTearDown(toastService.dispose);
    final messages = <String>[];
    final subscription = toastService.messageStream.listen(
      (message) => messages.add(message.message),
    );
    addTearDown(subscription.cancel);

    final sessionExpiry = SessionExpiryNotifier(toastService);
    final service = _FakeAccountService(
      platform: SourceIds.bilibili,
      loggedIn: true,
      check: () async =>
          const AccountCheckResult(status: AccountStatus.invalid),
    );

    await verifyAllAccountStatuses(
      [service],
      toastService,
      sessionExpiry: sessionExpiry,
    );
    await pumpUntil(
      () => messages.isNotEmpty,
      reason: 'the first invalid status should toast once',
    );

    await verifyAllAccountStatuses(
      [service],
      toastService,
      sessionExpiry: sessionExpiry,
    );
    await drainEventQueue(
      reason:
          'the second detection must not add a toast; nothing else to '
          'wait for once the state is already expired',
    );

    expect(service.markExpiredCount, 2);
    expect(messages, hasLength(1));
  });
}

class _FakeAccountService extends AccountService {
  _FakeAccountService({
    required this.platform,
    required this.loggedIn,
    required Future<AccountCheckResult> Function() check,
  }) : _check = check;

  @override
  final String platform;

  final bool loggedIn;
  final Future<AccountCheckResult> Function() _check;

  int logoutCount = 0;
  int markExpiredCount = 0;

  @override
  Future<AccountCheckResult> checkAccountStatus() => _check();

  @override
  Future<Map<String, String>?> getAuthHeaders() async => null;

  @override
  Future<Account?> getCurrentAccount() async => Account()
    ..platform = platform
    ..isLoggedIn = loggedIn
    ..isVip = false;

  @override
  Future<bool> isLoggedIn() async => loggedIn;

  @override
  Future<void> logout() async => logoutCount++;

  @override
  Future<void> markSessionExpired() async => markExpiredCount++;

  @override
  Future<bool> needsRefresh() async => false;

  @override
  Future<bool> refreshCredentials() async => true;
}
