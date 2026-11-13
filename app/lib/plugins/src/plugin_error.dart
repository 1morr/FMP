import 'package:fmp/core/errors/app_error.dart';

/// 插件回報錯誤用的固定代碼（brief〈插件〉）。插件丟 `new PluginError(code)`，
/// 宿主照 [toAppError] 轉成錯誤分類（brief〈錯誤、log 與診斷〉）。[wire] 是 JS 端的字串，
/// 列在 `app/plugins/host.d.ts`，兩邊要一起改（`test/plugins/
/// plugin_error_codes_test.dart` 守著）。
enum PluginErrorCode {
  network('network'),
  rateLimited('rate_limited'),
  loginRequired('login_required'),
  credentialInvalid('credential_invalid'),
  verificationRequired('verification_required'),
  unavailableRegion('unavailable_region'),
  unavailableCopyright('unavailable_copyright'),
  unavailableMembershipRequired('unavailable_membership_required'),
  unavailableTrialOnly('unavailable_trial_only'),
  notFound('not_found'),
  parseFailure('parse_failure'),
  unsupported('unsupported'),

  /// 宿主擋下了 manifest 沒宣告的網域；插件不自己丟。
  domainNotAllowed('domain_not_allowed'),

  /// 插件丟了沒有代碼的例外（程式錯誤，或回應的形狀不如預期）。
  internal('internal');

  const PluginErrorCode(this.wire);

  final String wire;

  /// 認不得的字串當成 [internal]。
  static PluginErrorCode fromWire(Object? wire) => values.firstWhere(
    (c) => c.wire == wire,
    orElse: () => PluginErrorCode.internal,
  );

  /// 轉成錯誤分類。[domainNotAllowed] 是插件的 manifest 與程式不一致，
  /// 使用者那邊等於這個插件做不到，歸 [Unsupported]；[internal] 多半是音源
  /// 的回應變了，歸 [ParseFailure]。
  AppError toAppError() => switch (this) {
    network => const NetworkError(),
    rateLimited => const RateLimited(),
    loginRequired => const LoginRequired(),
    credentialInvalid => const CredentialInvalid(),
    verificationRequired => const VerificationRequired(),
    unavailableRegion => const Unavailable(UnavailableReason.region),
    unavailableCopyright => const Unavailable(UnavailableReason.copyright),
    unavailableMembershipRequired => const Unavailable(
      UnavailableReason.membershipRequired,
    ),
    unavailableTrialOnly => const Unavailable(UnavailableReason.trialOnly),
    notFound => const NotFound(),
    parseFailure || internal => const ParseFailure(),
    unsupported || domainNotAllowed => const Unsupported(),
  };
}

/// 宿主這一側的失敗，經 bridge 交回 JS 時變成 `PluginError`。
class PluginFailure implements Exception {
  const PluginFailure(this.code, this.message);

  final PluginErrorCode code;
  final String message;

  @override
  String toString() => 'PluginFailure(${code.wire}: $message)';
}
