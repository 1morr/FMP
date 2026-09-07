import 'dart:async';
import 'dart:io';

import 'package:fmp/i18n/strings.g.dart';

import '../../core/errors/user_message.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/sources/source_exception.dart';
import 'audio_types.dart';

/// 一次播放失敗之後，只看那個錯誤就能得出的結論。
///
/// **措辭那一半已經不住在這裡。** `SourceApiException` 要跟使用者怎麼說，全 App
/// 都要問同一個問題（登入頁、搜尋、匯入、歌單），所以那個窮舉 switch 搬到了
/// `lib/core/errors/user_message.dart` 的 `sourceErrorReason`，這裡只轉發。
/// 原本寫在這裡的理由是「拆開會讓下一次新增 kind 的人改一半就走」—— 實際上
/// 重試判斷本來就是 `SourceErrorKind.isRetryable` / `.shouldSkipTrack` 兩個
/// getter，住在 `source_exception.dart` 的 enum 上，這個類別只是轉發；而措辭的
/// switch 是窮舉的，少一個 kind 分析器會先擋下來。
///
/// 留在這裡的是「這一次播放失敗之後要怎麼辦」：跳不跳這一首、進不進退避階梯、
/// 解析階段的例外可不可以重試。那些是播放才有的問題。
///
/// **它不碰 `PlayerState`、不碰佇列、不發 toast。** 誰在什麼時候把這些結論用出
/// 去是 `AudioController` 的事 —— 跳下一首、停掉後端、寫進 `state.error`，
/// 每一項都要動控制器的狀態，不屬於一個只認得例外物件的類別。
class PlaybackErrorPresenter with Logging {
  const PlaybackErrorPresenter();

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

  /// 錯誤的原因短句。實作在 `lib/core/errors/user_message.dart`。
  String reasonFor(SourceApiException error) => sourceErrorReason(error);

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
      'Unclassified playback error, not retrying: ${error.runtimeType} $error',
    );
    return false;
  }
}
