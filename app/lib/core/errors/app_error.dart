/// 錯誤分類（brief §13）。插件與播放的錯誤都轉成這些類別，UI 以 exhaustive
/// `switch` 依類別決定顯示提示、要求登入或只記錄。
///
/// [toString] 是 log 用的名稱，寫死而不用 `runtimeType`：release 版的混淆
/// 會改掉型別名稱。
sealed class AppError implements Exception {
  const AppError();
}

/// 連不上、逾時、連線中斷。
final class NetworkError extends AppError {
  const NetworkError();

  @override
  String toString() => 'NetworkError';
}

/// 音源限流或風控。
final class RateLimited extends AppError {
  const RateLimited();

  @override
  String toString() => 'RateLimited';
}

/// 要登入才能做。
final class LoginRequired extends AppError {
  const LoginRequired();

  @override
  String toString() => 'LoginRequired';
}

/// 有登入，但憑證失效或被拒。
final class CredentialInvalid extends AppError {
  const CredentialInvalid();

  @override
  String toString() => 'CredentialInvalid';
}

/// 音源要求人工驗證（例如驗證碼）。
final class VerificationRequired extends AppError {
  const VerificationRequired();

  @override
  String toString() => 'VerificationRequired';
}

/// 曲目存在，但在目前帳號下聽不了。
final class Unavailable extends AppError {
  const Unavailable(this.reason);

  final UnavailableReason reason;

  @override
  String toString() => 'Unavailable(${reason.name})';
}

/// [Unavailable] 的原因。
enum UnavailableReason {
  /// 地區限制。
  region,

  /// 版權下架。
  copyright,

  /// 需會員。
  membershipRequired,

  /// 只有試聽。
  trialOnly,
}

/// 曲目、歌單或帳號不存在。
final class NotFound extends AppError {
  const NotFound();

  @override
  String toString() => 'NotFound';
}

/// 音源的回應解析不了。
final class ParseFailure extends AppError {
  const ParseFailure();

  @override
  String toString() => 'ParseFailure';
}

/// 插件或平台做不到這件事。
final class Unsupported extends AppError {
  const Unsupported();

  @override
  String toString() => 'Unsupported';
}
