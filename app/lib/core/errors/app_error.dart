import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';

part 'report_error.dart';

/// 給使用者的錯誤訊息 key，ADR 0013 §決定 5 的類別表一列一個。
///
/// 值的名稱就是 slang 的 key（`lib/i18n/*.i18n.json` 的 `errors.` 之下），由
/// `lib/ui/errors/error_message.dart` 對到字串；改名等於改翻譯檔的 key。
/// 「不支援」與「預期外」在類別表裡共用通用訊息，所以 [Unsupported] 與
/// [UnexpectedError] 都預設 [unexpected]。
enum ErrorMessageKey {
  network,
  rateLimited,
  authRequired,
  credentialInvalid,
  verificationRequired,
  unavailable,
  notFound,
  parseError,
  unexpected,
}

/// i18n 訊息參數的名稱：封閉的清單，值一律是整數（[AppError.messageArgs]）。
///
/// 伺服器或插件給的文字沒有地方可放：音源名稱由呈現層以 [AppError.pluginId]
/// 查插件的顯示名稱，不經參數。M1 沒有訊息用到參數；第一個用到的訊息在呈現層
/// 的對應函式裡讀它。
enum ErrorMessageArg { count, seconds }

/// [Unavailable] 的原因（ADR 0013 §決定 1）。曲目上標示的就是它。
enum UnavailableReason { region, copyright, membership, age, previewOnly }

/// App 唯一的錯誤型別（ADR 0013 §決定 1）。
///
/// 音源在自己的目錄內把狀態碼與錯誤碼轉成它，未知例外在音源邊界以
/// [AppError.wrap] 包成 [UnexpectedError]；音源邊界以上只看得到 `AppError`。
/// UI 以 exhaustive `switch` 呈現，新增子類時編譯器會指出每個要補的地方。
///
/// **沒有可以直接顯示的字串**：使用者訊息只有 [messageKey] 與 [messageArgs]，
/// 由呈現層經 i18n 取得文字。原始 error 與 stackTrace 是函式庫私有欄位，
/// 只有 [AppErrorReport.report] 讀得到，而它交給 log 門面遮蔽後才寫出；
/// [toString] 也不含原始 error。`test/core/errors/app_error_surface_test.dart`
/// 列出全部公開成員，加欄位要一起改它。
sealed class AppError implements Exception {
  AppError._({
    required this.pluginId,
    required this.retryable,
    required this.retryAfter,
    required this.messageKey,
    required this.messageArgs,
    required this.expected,
    required this.networkRecordId,
    required this._cause,
    required this._stackTrace,
  });

  /// 包裝音源邊界捕捉到的例外：已經是 [AppError] 就原樣回傳，其他一律包成
  /// [UnexpectedError]（`expected` 為假，視為 bug）。
  factory AppError.wrap(
    Object error,
    StackTrace stackTrace, {
    String? pluginId,
  }) => switch (error) {
    AppError() => error,
    _ => UnexpectedError(
      pluginId: pluginId,
      cause: error,
      stackTrace: stackTrace,
    ),
  };

  /// 發生錯誤的音源（插件 id）；網路層以外、與音源無關的錯誤為 `null`。
  final String? pluginId;

  /// 網路層可不可以重試這個錯誤。只有 [NetworkError] 與 [RateLimited] 預設為
  /// 真，音源可以在建構時覆寫。請求是否冪等另外判斷（`retry_policy.dart`）。
  final bool retryable;

  /// 伺服器要求的等待時間（`Retry-After`），沒有就是 `null`。
  final Duration? retryAfter;

  /// 使用者訊息的 i18n key。每個子類有預設值，音源可以覆寫。
  final ErrorMessageKey messageKey;

  /// i18n 訊息的參數：名稱是封閉的 [ErrorMessageArg]，值只能是整數，型別上就
  /// 放不進伺服器或例外的原文（原文放 `cause`，只進 log）。
  final Map<ErrorMessageArg, int> messageArgs;

  /// 預期內的錯誤（網路、限流、需登入等）為真；解析失敗、不支援與預期外視為
  /// bug，為假。決定錯誤歷史的層級。
  final bool expected;

  /// 對應的網路紀錄 id（ADR 0011 §決定 4）。網路層建立錯誤時填入那次送出的
  /// 紀錄 id；沒有送出（例如網域不符）時為 `null`。
  final int? networkRecordId;

  final Object? _cause;
  final StackTrace? _stackTrace;

  /// log 與網路紀錄用的型別名稱（寫死的類別名，不是 `runtimeType`）。它是
  /// log 檔的持久化值，不是給使用者看的文字。
  String get typeName => _typeName(this);

  /// 只給 log 用。不含原始 error：原文可能帶憑證或伺服器訊息，只經
  /// [AppErrorReport.report] 交給門面遮蔽後寫出。
  @override
  String toString() {
    final parts = [
      if (pluginId case final id?) 'pluginId: $id',
      if (this case Unavailable(:final reason?)) 'reason: ${reason.name}',
      'retryable: $retryable',
      if (retryAfter case final delay?) 'retryAfter: $delay',
      if (networkRecordId case final id?) 'networkRecordId: $id',
    ];
    return '${_typeName(this)}(${parts.join(', ')})';
  }
}

/// log 用的型別名稱。不用 `runtimeType`：release 開了混淆時它會變。
String _typeName(AppError error) => switch (error) {
  NetworkError() => 'NetworkError',
  RateLimited() => 'RateLimited',
  AuthRequired() => 'AuthRequired',
  CredentialInvalid() => 'CredentialInvalid',
  VerificationRequired() => 'VerificationRequired',
  Unavailable() => 'Unavailable',
  NotFound() => 'NotFound',
  ParseError() => 'ParseError',
  Unsupported() => 'Unsupported',
  UnexpectedError() => 'UnexpectedError',
};

/// 傳輸失敗：連不上、逾時、連線中斷。網路層轉換。
final class NetworkError extends AppError {
  NetworkError({
    super.pluginId,
    super.retryable = true,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.network,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: true);
}

/// 限流：HTTP 429 或音源自己的限流錯誤碼。
final class RateLimited extends AppError {
  RateLimited({
    super.pluginId,
    super.retryable = true,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.rateLimited,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: true);
}

/// 這個動作需要登入，而目前沒有登入。
final class AuthRequired extends AppError {
  AuthRequired({
    super.pluginId,
    super.retryable = false,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.authRequired,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: true);
}

/// 憑證失效：音源的「憑證無效」判定表認定（ADR 0012）。刷新後重送由網路層
/// 另計，不經重試策略。
final class CredentialInvalid extends AppError {
  CredentialInvalid({
    super.pluginId,
    super.retryable = false,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.credentialInvalid,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: true);
}

/// 風控驗證：B 站 geetest、YouTube「確認你不是機器人」。
final class VerificationRequired extends AppError {
  VerificationRequired({
    super.pluginId,
    super.retryable = false,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.verificationRequired,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: true);
}

/// 內容存在但取不到，原因見 [reason]。
final class Unavailable extends AppError {
  Unavailable({
    this.reason,
    super.pluginId,
    super.retryable = false,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.unavailable,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: true);

  /// 取不到的原因；不知道時為 `null`（例如串流被 CDN 以 403 拒絕，重新解析
  /// 後仍被拒）。插件丟的 `Unavailable` 一定有原因（`structuredScriptError`）。
  final UnavailableReason? reason;
}

/// 內容不存在：已刪除、已下架、id 錯誤。
final class NotFound extends AppError {
  NotFound({
    super.pluginId,
    super.retryable = false,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.notFound,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: true);
}

/// 回應格式跟音源預期的不同。要改程式才會好，所以視為 bug。
final class ParseError extends AppError {
  ParseError({
    super.pluginId,
    super.retryable = false,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.parseError,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: false);
}

/// 音源或平台不支援這個動作。ADR 0013 §決定 5 視為 bug。
final class Unsupported extends AppError {
  Unsupported({
    super.pluginId,
    super.retryable = false,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.unexpected,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: false);
}

/// 其他所有錯誤；通常由 [AppError.wrap] 建立。
final class UnexpectedError extends AppError {
  UnexpectedError({
    super.pluginId,
    super.retryable = false,
    super.retryAfter,
    super.messageKey = ErrorMessageKey.unexpected,
    super.messageArgs = const {},
    super.networkRecordId,
    super.cause,
    super.stackTrace,
  }) : super._(expected: false);
}
