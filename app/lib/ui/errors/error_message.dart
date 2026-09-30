import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/i18n/strings.g.dart';

/// [error] 給使用者看的訊息（ADR 0013 §決定 5 的類別表）。
///
/// 文字只來自翻譯檔：`messageKey` 對到 `errors.` 之下同名的字串，音源名稱是
/// [sourceName]（呈現層以 `pluginId` 查插件的顯示名稱），沒有就用通用的
/// 「音源」。`AppError` 沒有別的字串可以放進來（`messageArgs` 只收整數，M1 沒有
/// 訊息用到）。
String errorMessage(Translations t, AppError error, {String? sourceName}) {
  final errors = t.errors;
  final source = sourceName ?? errors.unknownSource;
  return switch (error.messageKey) {
    ErrorMessageKey.network => errors.network,
    ErrorMessageKey.rateLimited => errors.rateLimited(source: source),
    ErrorMessageKey.authRequired => errors.authRequired(source: source),
    ErrorMessageKey.credentialInvalid => errors.credentialInvalid(
      source: source,
    ),
    ErrorMessageKey.verificationRequired => errors.verificationRequired(
      source: source,
    ),
    ErrorMessageKey.unavailable => switch (error) {
      Unavailable(:final reason) => errors.unavailableBecause(
        reason: unavailableReasonText(t, reason),
      ),
      _ => errors.unavailable,
    },
    ErrorMessageKey.notFound => errors.notFound,
    ErrorMessageKey.parseError => errors.parseError(source: source),
    ErrorMessageKey.unexpected => errors.unexpected,
  };
}

/// [Unavailable] 的原因；曲目上標示的也是它。
String unavailableReasonText(Translations t, UnavailableReason reason) {
  final reasons = t.errors.unavailableReasons;
  return switch (reason) {
    UnavailableReason.region => reasons.region,
    UnavailableReason.copyright => reasons.copyright,
    UnavailableReason.membership => reasons.membership,
    UnavailableReason.age => reasons.age,
    UnavailableReason.previewOnly => reasons.previewOnly,
  };
}
