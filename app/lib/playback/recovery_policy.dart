import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';

// 播放失敗時怎麼辦（ADR 0018 §決定 7、design §5.3、§7.5）：純函數，計數由
// `PlaybackController` 保管與寫入。桌面輸出裝置失敗（暫停並提示）在 M2 PR 13。

/// 一次播放失敗。
@immutable
sealed class PlaybackFailure {
  const PlaybackFailure();
}

/// 解析串流時插件或網路層丟出的錯誤。
final class ResolveFailed extends PlaybackFailure {
  const ResolveFailed(this.error);

  final AppError error;
}

/// 插件回的候選只有試聽片段（`StreamResult.previewOnly`）。
final class PreviewOnly extends PlaybackFailure {
  const PreviewOnly();
}

/// 後端開不起來或解碼失敗。[httpStatus] 是開流被 HTTP 拒絕時的狀態碼，只有
/// mpv 拿得到（`SourceFailed.httpStatus`）；Android 一律是 `null`。
final class StreamUnopenable extends PlaybackFailure {
  const StreamUnopenable({this.httpStatus});

  final int? httpStatus;
}

/// 已經在播之後中斷，或提前結束。
final class StreamInterrupted extends PlaybackFailure {
  const StreamInterrupted();
}

/// 中途緩衝了 [bufferingStallTimeout] 還沒恢復（緩衝飢餓）。
final class BufferingStalled extends PlaybackFailure {
  const BufferingStalled();
}

/// [decideRecovery] 的結論。
@immutable
sealed class RecoveryAction {
  const RecoveryAction();
}

/// 等 [delay] 後從目前位置重試（重新解析）。[attempt] 從 1 起算。
final class RetryAfter extends RecoveryAction {
  const RetryAfter({required this.delay, required this.attempt});

  final Duration delay;
  final int attempt;
}

/// 停在這首等網路（design §5.3）：網路狀態回到 `online` 時立刻從目前位置重試。
/// 不算一次重試，也不算跳過。
final class WaitForNetwork extends RecoveryAction {
  const WaitForNetwork();
}

/// 作廢網址快取、重新解析一次，從目前位置再開（網址可能過期或被 CDN 拒絕）。
final class ReResolve extends RecoveryAction {
  const ReResolve();
}

/// 改開下一個候選串流。
final class TryNextCandidate extends RecoveryAction {
  const TryNextCandidate();
}

/// 照播試聽片段，並標「試聽」（D4）。
final class PlayAsPreview extends RecoveryAction {
  const PlayAsPreview();
}

/// 跳到下一首（臨時播放中是回到佇列）。
final class SkipTrack extends RecoveryAction {
  const SkipTrack();
}

/// 停下來（連續跳過到上限）。
final class StopPlayback extends RecoveryAction {
  const StopPlayback();
}

/// 重試的等待：1、3、9 秒，共 3 次。
const retryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 3),
  Duration(seconds: 9),
];

/// 連續跳過的上限：佇列長度與這個數字取小的。
const maxConsecutiveSkips = 10;

/// 中途緩衝多久算緩衝飢餓。
const bufferingStallTimeout = Duration(seconds: 15);

/// 一首正常播放（位置前進）累計這麼久，重試計數歸零。
const retryResetAfter = Duration(seconds: 10);

/// 開流被這些 HTTP 狀態碼拒絕時先重新解析：網址多半是過期或被 CDN 拒絕。
const reResolveStatuses = {403, 404, 410};

/// 依 [failure] 決定下一步。
///
/// - [network]：目前的網路狀態；不是 `online` 時，可能是網路造成的失敗都停下
///   等網路，不計次數（ADR 0018「不在 Online 時暫停計數」）。
/// - [skipPreviewClips]：「跳過試聽片段」設定。
/// - [retries]：這一首已經重試過幾次（正常播放 [retryResetAfter] 後歸零）。
/// - [reResolves]：這一首已經重新解析過幾次（換一首才歸零）。
/// - [candidateSwitched]：這一首已經換過一次候選（ADR 只換一次）。
/// - [hasOtherCandidate]：還有沒開過的候選。
/// - [consecutiveSkips]：前面已經連續跳過幾首（這一首不算）。
/// - [queueLength]：佇列的長度（臨時播放中另加臨時那一首）。
///
/// 要跳過時，若這一次跳過會讓連續跳過的次數達到佇列長度（或 10 首），就改成
/// [StopPlayback]：整個佇列都播不了時停下來，不一直繞。
RecoveryAction decideRecovery(
  PlaybackFailure failure, {
  required NetworkStatus network,
  required bool skipPreviewClips,
  required int retries,
  required int reResolves,
  required bool candidateSwitched,
  required bool hasOtherCandidate,
  required int consecutiveSkips,
  required int queueLength,
}) {
  final online = network == NetworkStatus.online;

  RecoveryAction skipOrStop() =>
      consecutiveSkips + 1 >= math.min(queueLength, maxConsecutiveSkips)
      ? const StopPlayback()
      : const SkipTrack();

  /// 網路造成的失敗：離線時等網路，否則照 [then]。
  RecoveryAction unlessOffline(RecoveryAction Function() then) =>
      online ? then() : const WaitForNetwork();

  RecoveryAction retryOrSkip() => retries < retryDelays.length
      ? RetryAfter(delay: retryDelays[retries], attempt: retries + 1)
      : skipOrStop();

  RecoveryAction reResolveOrSkip() =>
      reResolves == 0 ? const ReResolve() : skipOrStop();

  RecoveryAction candidateOrSkip() => !candidateSwitched && hasOtherCandidate
      ? const TryNextCandidate()
      : skipOrStop();

  return switch (failure) {
    ResolveFailed(:final error) => switch (error) {
      NetworkError() || RateLimited() => unlessOffline(retryOrSkip),
      // 無法取得（含只有試聽）、找不到、需登入與驗證類、不支援：重試也不會
      // 好。解析失敗與預期外同樣跳過，整個音源都壞時由連續跳過的上限停下。
      Unavailable() ||
      NotFound() ||
      AuthRequired() ||
      CredentialInvalid() ||
      VerificationRequired() ||
      Unsupported() ||
      ParseError() ||
      UnexpectedError() => skipOrStop(),
    },
    PreviewOnly() => skipPreviewClips ? skipOrStop() : const PlayAsPreview(),
    StreamInterrupted() => unlessOffline(retryOrSkip),
    BufferingStalled() => unlessOffline(reResolveOrSkip),
    // 沒有狀態碼（Android 一律如此）也可能是網址過期：先重新解析一次，仍失敗
    // 換候選一次，再不行跳過（擁有者 2026-10-06）。離線時連不上也是這個形狀，
    // 先等網路。
    StreamUnopenable(httpStatus: null) => unlessOffline(
      () => reResolves == 0 ? const ReResolve() : candidateOrSkip(),
    ),
    StreamUnopenable(:final httpStatus?)
        when reResolveStatuses.contains(httpStatus) =>
      reResolves == 0 ? const ReResolve() : candidateOrSkip(),
    StreamUnopenable() => candidateOrSkip(),
  };
}
