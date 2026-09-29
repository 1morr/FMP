import 'package:fmp/core/errors/app_error.dart';

/// 腳本拋出的值（JS 的 name、message、stack）。只當 [AppError] 的 cause，
/// 經 `log.report` 遮蔽後進 log，不給使用者看。
final class PluginScriptError implements Exception {
  const PluginScriptError(this.name, this.message, [this.jsStack = '']);

  final String name;
  final String message;
  final String jsStack;

  @override
  String toString() =>
      jsStack.isEmpty ? '$name: $message' : '$name: $message\n$jsStack';
}

/// `Unavailable` 的 `reason` 字串。插件的介面，與 enum 的名稱分開寫死。
String unavailableReasonWireName(UnavailableReason reason) => switch (reason) {
  UnavailableReason.region => 'region',
  UnavailableReason.copyright => 'copyright',
  UnavailableReason.membership => 'membership',
  UnavailableReason.age => 'age',
  UnavailableReason.previewOnly => 'previewOnly',
};

UnavailableReason? _reason(String? name) => switch (name) {
  'region' => UnavailableReason.region,
  'copyright' => UnavailableReason.copyright,
  'membership' => UnavailableReason.membership,
  'age' => UnavailableReason.age,
  'previewOnly' => UnavailableReason.previewOnly,
  _ => null,
};

/// `retryAfterSeconds` 再大也不超過這個（與 `parseRetryAfter` 的上限相同）：
/// 換成毫秒會超出 int，`Duration` 溢位成負的等待。
const _longestRetryAfter = Duration(days: 36500);

/// 把腳本拋出的結構化錯誤（`throw {fmpError: '<類別名>', ...}`，ADR 0014
/// §決定 5）轉成 [AppError]。
///
/// - `fmpError` 是 [AppError] 的十個子類名之一：對應的子類；`retryAfterSeconds`
///   （有限的非負數，上限 [_longestRetryAfter]）填 `retryAfter`；
/// - 名稱不認得、`Unavailable` 沒有合法的 `reason`：插件的 bug，
///   [UnexpectedError]。
///
/// 使用者訊息用子類的預設 key；插件給的 `message` 只進 cause。
AppError structuredScriptError({
  required String pluginId,
  required String fmpError,
  num? retryAfterSeconds,
  String? reason,
  String? message,
}) {
  final cause = PluginScriptError(fmpError, message ?? '');
  final stackTrace = StackTrace.current;
  final retryAfter =
      retryAfterSeconds != null &&
          retryAfterSeconds.isFinite &&
          retryAfterSeconds >= 0
      ? (retryAfterSeconds > _longestRetryAfter.inSeconds
            ? _longestRetryAfter
            : Duration(milliseconds: (retryAfterSeconds * 1000).round()))
      : null;
  AppError unexpected(String problem) => UnexpectedError(
    pluginId: pluginId,
    cause: PluginScriptError('InvalidStructuredError', problem),
    stackTrace: stackTrace,
  );
  return switch (fmpError) {
    'NetworkError' => NetworkError(
      pluginId: pluginId,
      retryAfter: retryAfter,
      cause: cause,
      stackTrace: stackTrace,
    ),
    'RateLimited' => RateLimited(
      pluginId: pluginId,
      retryAfter: retryAfter,
      cause: cause,
      stackTrace: stackTrace,
    ),
    'AuthRequired' => AuthRequired(
      pluginId: pluginId,
      cause: cause,
      stackTrace: stackTrace,
    ),
    'CredentialInvalid' => CredentialInvalid(
      pluginId: pluginId,
      cause: cause,
      stackTrace: stackTrace,
    ),
    'VerificationRequired' => VerificationRequired(
      pluginId: pluginId,
      cause: cause,
      stackTrace: stackTrace,
    ),
    'Unavailable' => switch (_reason(reason)) {
      final reason? => Unavailable(
        reason: reason,
        pluginId: pluginId,
        cause: cause,
        stackTrace: stackTrace,
      ),
      null => unexpected('Unavailable needs a valid reason, got "$reason"'),
    },
    'NotFound' => NotFound(
      pluginId: pluginId,
      cause: cause,
      stackTrace: stackTrace,
    ),
    'ParseError' => ParseError(
      pluginId: pluginId,
      cause: cause,
      stackTrace: stackTrace,
    ),
    'Unsupported' => Unsupported(
      pluginId: pluginId,
      cause: cause,
      stackTrace: stackTrace,
    ),
    'UnexpectedError' => UnexpectedError(
      pluginId: pluginId,
      cause: cause,
      stackTrace: stackTrace,
    ),
    _ => unexpected('unknown fmpError "$fmpError"'),
  };
}
