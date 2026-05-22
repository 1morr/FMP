import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/account_provider.dart';
import 'package:fmp/services/account/account_service.dart';

void main() {
  test('verifyAllAccountStatuses reports per-platform check failures',
      () async {
    final toastService = ToastService();
    addTearDown(toastService.dispose);

    final result = await verifyAllAccountStatuses(
      [
        _FakeAccountService(
          platform: SourceType.bilibili,
          loggedIn: true,
          check: () => throw StateError('network down'),
        ),
        _FakeAccountService(
          platform: SourceType.youtube,
          loggedIn: true,
          check: () async => const AccountCheckResult(
            status: AccountStatus.valid,
            isVip: false,
          ),
        ),
      ],
      toastService,
    );

    expect(result.checkedPlatforms, [SourceType.youtube]);
    expect(result.failedPlatforms, [SourceType.bilibili]);
    expect(result.hasFailures, isTrue);
  });
}

class _FakeAccountService extends AccountService {
  _FakeAccountService({
    required this.platform,
    required this.loggedIn,
    required Future<AccountCheckResult> Function() check,
  }) : _check = check;

  @override
  final SourceType platform;

  final bool loggedIn;
  final Future<AccountCheckResult> Function() _check;

  @override
  Future<AccountCheckResult> checkAccountStatus() => _check();

  @override
  Future<Account?> getCurrentAccount() async => Account()
    ..platform = platform
    ..isLoggedIn = loggedIn
    ..isVip = false;

  @override
  Future<bool> isLoggedIn() async => loggedIn;

  @override
  Future<void> logout() async {}

  @override
  Future<bool> needsRefresh() async => false;

  @override
  Future<bool> refreshCredentials() async => true;
}
