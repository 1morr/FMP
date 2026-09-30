import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fmp/core/errors/app_error.dart';

// 播放失敗時怎麼辦（ADR 0018 §決定 7 的 M1 部分）：純函數，狀態由
// `PlaybackController` 保管與寫入。M1 沒有連線偵測（「不在 Online 時暫停
// 計數」）、試聽片段的設定（一律跳過，等於設定的預設值）、緩衝飢餓與輸出裝置
// 失敗的處理、正常播放 10 秒後重試計數歸零（M1 換歌才歸零），也沒有提示 UI
// （PR 12 接 Toaster）。

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

/// 後端開不起來或解碼失敗。
final class StreamUnopenable extends PlaybackFailure {
  const StreamUnopenable();
}

/// 已經在播之後中斷，或提前結束。
final class StreamInterrupted extends PlaybackFailure {
  const StreamInterrupted();
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

/// 改開下一個候選串流。
final class TryNextCandidate extends RecoveryAction {
  const TryNextCandidate();
}

/// 跳到下一首。
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

/// 依 [failure] 決定下一步。
///
/// - [retries]：這一首已經重試過幾次。
/// - [candidateSwitched]：這一首已經換過一次候選（ADR 只換一次）。
/// - [hasOtherCandidate]：還有沒開過的候選。
/// - [consecutiveSkips]：前面已經連續跳過幾首（這一首不算）。
/// - [queueLength]：佇列的長度。
///
/// 要跳過時，若這一次跳過會讓連續跳過的次數達到佇列長度（或 10 首），就改成
/// [StopPlayback]：整個佇列都播不了時停下來，不一直繞。
RecoveryAction decideRecovery(
  PlaybackFailure failure, {
  required int retries,
  required bool candidateSwitched,
  required bool hasOtherCandidate,
  required int consecutiveSkips,
  required int queueLength,
}) {
  RecoveryAction skipOrStop() =>
      consecutiveSkips + 1 >= math.min(queueLength, maxConsecutiveSkips)
      ? const StopPlayback()
      : const SkipTrack();

  RecoveryAction retryOrSkip() => retries < retryDelays.length
      ? RetryAfter(delay: retryDelays[retries], attempt: retries + 1)
      : skipOrStop();

  return switch (failure) {
    ResolveFailed(:final error) => switch (error) {
      NetworkError() || RateLimited() => retryOrSkip(),
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
    StreamUnopenable() =>
      !candidateSwitched && hasOtherCandidate
          ? const TryNextCandidate()
          : skipOrStop(),
    StreamInterrupted() => retryOrSkip(),
  };
}
