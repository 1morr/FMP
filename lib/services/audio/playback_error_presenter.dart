import 'dart:async';
import 'dart:io';

import 'package:fmp/i18n/strings.g.dart';

import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/sources/source_exception.dart';
import 'audio_types.dart';

/// 一次播放失敗之後，只看那個錯誤就能得出的結論。
///
/// 兩件事放在同一個類別裡，因為它們讀的是同一份知識：`SourceErrorKind`。
/// 「這個錯誤該不該重試」與「這個錯誤要跟使用者怎麼說」都是對同一個 kind 的
/// switch，拆成兩個檔案只會讓下一次新增 kind 的人改一半就走。
///
/// **它不碰 `PlayerState`、不碰佇列、不發 toast。** 誰在什麼時候把這些結論用出
/// 去是 `AudioController` 的事 —— 跳下一首、停掉後端、寫進 `state.error`，
/// 每一項都要動控制器的狀態，不屬於一個只認得例外物件的類別。
class PlaybackErrorPresenter with Logging {
  const PlaybackErrorPresenter();

  /// 音源 adapter 對這幾種情況會回一句固定的英文診斷。它們不比 kind 對應的翻譯
  /// 更有資訊量，卻會讓使用者看到一句沒翻譯的英文，所以一律當作「沒有診斷」。
  static const _syntheticDiagnostics = <String>{
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

  /// 「無法播放〈歌名〉：〈原因〉」。[skipped] 為 true 時換成已跳過的那一句。
  String cannotPlay(
    Track track,
    SourceApiException error, {
    bool skipped = false,
  }) {
    final reason = reasonFor(error);
    return skipped
        ? t.audio.cannotPlaySkippedReason(title: track.title, reason: reason)
        : t.audio.cannotPlayReason(title: track.title, reason: reason);
  }

  /// 「播放失敗：〈原因〉」。不指名歌曲的那一句。
  String playbackFailed(SourceApiException error) =>
      t.audio.playbackFailed(message: reasonFor(error));

  /// 錯誤的原因短句。adapter 給了有意義的診斷就用它，否則退回 kind 的翻譯。
  String reasonFor(SourceApiException error) {
    final diagnostic = _diagnosticOrNull(error);
    if (diagnostic != null) return diagnostic;

    return switch (error.kind) {
      SourceErrorKind.unavailable => t.audio.sourceErrorUnavailable,
      SourceErrorKind.geoRestricted => t.audio.sourceErrorGeoRestricted,
      SourceErrorKind.vipRequired => t.audio.sourceErrorVipRequired,
      SourceErrorKind.loginRequired => t.audio.sourceErrorLoginRequired,
      SourceErrorKind.permissionDenied =>
        error.sourceType == SourceIds.bilibili
            ? t.audio.sourceErrorBilibiliPermissionDenied
            : t.audio.sourceErrorPermissionDenied,
      SourceErrorKind.network => t.audio.sourceErrorNetwork,
      SourceErrorKind.timeout => t.audio.sourceErrorTimeout,
      SourceErrorKind.rateLimited => error.message,
      SourceErrorKind.unknown =>
        error.message.trim().isNotEmpty ? error.message : t.error.unknownError,
    };
  }

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

  /// 這一首該不該直接跳過，繼續播下一首。
  bool shouldSkipTrack(SourceApiException error) => error.kind.shouldSkipTrack;

  /// 這個音源錯誤該不該進退避階梯。
  bool shouldRetrySource(SourceApiException error) => error.kind.isRetryable;

  /// 「串流解析階段」拋出的例外可不可以重試。
  ///
  /// 這裡處理的是 Dart 例外（音源 adapter 或 `MediaHandoff` 拋的），不是後端播
  /// 放器的事件 —— 後者已由 [PlaybackEndReason] 型別化。判斷一律看型別：
  ///
  /// - 音源 adapter 把 dio 的錯誤全部包成 [SourceApiException]（三個 adapter
  ///   共 22 處 `on DioException catch`），所以 `DioException` 不會逃到這裡；
  /// - `MediaHandoff` 直接用 `dart:io` 的 `HttpClient`，會拋下面那幾種。
  bool isRetryable(Object error) {
    // 預算逾時走的是「已經換過一次 fallback 了，停下並通知」，不進退避階梯。
    // 必須排在 TimeoutException 之前 —— 這一行就是 D2 的決策本身。
    if (error is PlaybackTimeoutException) return false;
    if (error is SourceApiException) return error.kind.isRetryable;
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is TlsException) return true;
    if (error is TimeoutException) return true;

    // 沒有列舉到的型別一律不重試，但要留下痕跡 —— 靜默地「猜它是網路錯誤」
    // 正是 issue #41 那類 bug 的來源。看到這行就把該型別補進上面的清單。
    logWarning(
        'Unclassified playback error, not retrying: ${error.runtimeType} $error');
    return false;
  }
}
