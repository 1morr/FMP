import 'dart:async';
import 'dart:io';

import '../../data/models/source_ids.dart';
import '../../data/sources/source_exception.dart';
import '../../i18n/strings.g.dart';

/// 音源 adapter 對這幾種情況會回一句固定的英文診斷。它們不比 kind 對應的翻譯
/// 更有資訊量，卻會讓使用者看到一句沒翻譯的英文，所以一律當作「沒有診斷」。
const _syntheticDiagnostics = <String>{
  'VIP song, payment required',
  'No playback rights due to copyright or region restrictions',
  'Login required',
  'Playback permission denied',
  'No stream URL available',
  'Video unavailable',
  'Access forbidden (HTTP 403)',
  'Resource not found (HTTP 404)',
  'Service temporarily unavailable (HTTP 503)',
};

/// 音源錯誤的原因短句。adapter 給了有意義的診斷就用它，否則退回 kind 的翻譯。
///
/// 這個 switch 是窮舉的 —— `SourceErrorKind` 多一個成員時分析器會擋下來，
/// 那正是它可以離開 `PlaybackErrorPresenter` 的原因。
String sourceErrorReason(SourceApiException error) {
  final diagnostic = _diagnosticOrNull(error);
  if (diagnostic != null) return diagnostic;

  return switch (error.kind) {
    SourceErrorKind.unavailable => t.audio.sourceErrorUnavailable,
    SourceErrorKind.geoRestricted => t.audio.sourceErrorGeoRestricted,
    SourceErrorKind.vipRequired => t.audio.sourceErrorVipRequired,
    SourceErrorKind.loginRequired => t.audio.sourceErrorLoginRequired,
    SourceErrorKind.permissionDenied => error.sourceType == SourceIds.bilibili
        ? t.audio.sourceErrorBilibiliPermissionDenied
        : t.audio.sourceErrorPermissionDenied,
    SourceErrorKind.network => t.audio.sourceErrorNetwork,
    SourceErrorKind.timeout => t.audio.sourceErrorTimeout,
    SourceErrorKind.rateLimited => error.message,
    SourceErrorKind.unknown =>
      error.message.trim().isNotEmpty ? error.message : t.error.unknownError,
  };
}

/// 任何例外 → 使用者讀得懂的一句話。
///
/// **回傳值裡不會有 Dart 例外的原文。** 使用者看到 `Exception: <伺服器原文>`
/// 這種字串是 04 報告的 P1-7：標題翻譯了，真正要讀的細節仍是未翻譯的平台訊息。
/// 原文屬於 log，不屬於畫面 —— 呼叫端要嘛走 `ToastService.failure`（它會寫
/// log），要嘛自己在 catch 處 `AppLogger.error` 留全文。
///
/// 只認得下面這幾類：音源 adapter 統一包裝過的 [SourceApiException]、
/// `dart:io` 的網路與檔案系統例外、`dart:async` 的逾時。**沒列到的型別一律回
/// 「發生錯誤」** —— 靜默地猜它是網路錯誤正是 issue #41 那類 bug 的來源。
String userMessageFor(Object error) => switch (error) {
      SourceApiException() => sourceErrorReason(error),
      SocketException() || HttpException() || TlsException() =>
        t.error.networkError,
      TimeoutException() => t.error.connectionTimeout,
      FormatException() => t.error.dataFormatError,
      PathAccessException() => t.error.noPermission,
      _ => t.error.unknownError,
    };

String? _diagnosticOrNull(SourceApiException error) {
  final message = error.message.trim();
  if (message.isEmpty) return null;
  if (_isLowSignal(error, message)) return null;
  if (_syntheticDiagnostics.contains(message)) return null;
  return message;
}

/// 一個純數字或與 `code` 相同的訊息對使用者沒有任何意義。
bool _isLowSignal(SourceApiException error, String message) {
  if (message == error.code) return true;
  return RegExp(r'^-?\d+$').hasMatch(message);
}
