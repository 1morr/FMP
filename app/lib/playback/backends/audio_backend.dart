import 'package:flutter/foundation.dart';

import 'package:fmp/core/network/media_headers.dart';
import 'package:fmp/playback/backends/backend_rules.dart';
import 'package:fmp/playback/playback_state.dart';

/// 播放引擎的介面（ADR 0018 §決定 3）：`JustAudioBackend`（Android）與
/// `MediaKitBackend`（Windows）兩個實作，平台層宣告用哪一個
/// （`PlaybackSupport.backend`）。只由 `PlaybackSession` 呼叫。
///
/// **只持有「目前＋一個前瞻」**：[open] 換掉整個清單，[setNext] 設定或清掉
/// 前瞻；前瞻接上後，後端自己把播完的那一個移掉（[LookAheadEdit]）。後端不
/// 知道佇列，也不解析網址。
///
/// 狀態、位置與事件都帶 [BackendSource.id]：broadcast stream 是非同步送達的，
/// 換來源之後還可能收到上一個來源的值，`PlaybackSession` 以 id 過濾。
///
/// 收斂不了的差異：
///
/// - **Android 的音訊焦點**：just_audio 在每次 `play()` 經 audio_session 要求
///   焦點，只在失去焦點（`AUDIOFOCUS_LOSS`）或引擎卸載時放掉，換來源、
///   `stop()` 都不放；所以整個 App 只用一個 `AudioPlayer`，不在換歌時重建
///   （ADR 0018 §決定 3）。Windows 沒有音訊焦點。
/// - **前瞻怎麼預備**：just_audio 以 `useLazyPreparation: false` 讓 ExoPlayer
///   一接上就預備第二個項目；mpv 靠 `prefetch-playlist=yes`。交接都由引擎
///   自己做（gapless），這裡只收到 [SourceAdvanced]。
/// - **錯誤是誰的**：ExoPlayer 的錯誤帶項目索引；mpv 只給一行 log，不帶項目，
///   所以 [MediaKitBackend] 把錯誤算在目前的來源上，前瞻預備時的錯誤也一樣
///   （只影響「還沒載入」的判斷）。
/// - **標頭**：just_audio 以 `useProxyForRequestHeaders: false` 直接交給
///   ExoPlayer（不開本機 proxy，不需要明文流量）；media_kit 在 mpv 的
///   `on_load` hook 設 `http-header-fields`，以網址為鍵，同一個網址只有一組
///   標頭。
abstract interface class AudioBackend {
  /// 狀態的變化。
  Stream<BackendStatus> get status;

  /// 目前來源的位置；播放中持續發出，seek 後也發出。
  Stream<SourceProgress> get progress;

  /// 來源的交接、結束與失敗。
  Stream<BackendEvent> get events;

  /// 以 [source] 取代整個清單（目前與前瞻），從 [start] 開始；[play] 為假時
  /// 載入後停在暫停。開不起來不丟出，發 [SourceFailed]（[BackendFailure.open]）。
  Future<void> open(
    BackendSource source, {
    Duration start = Duration.zero,
    bool play = true,
  });

  /// 設定目前來源之後的前瞻；`null` 清掉。沒有目前的來源時什麼都不做。
  Future<void> setNext(BackendSource? next);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// 停止並清空清單。不放掉 Android 的音訊焦點（見上）。
  Future<void> stop();

  Future<void> dispose();
}

/// 交給後端的一個串流。
///
/// [headers] 在建構時就經過 `mediaRequestHeaders`（ADR 0012）：只留媒體請求
/// 的 header，所以交給播放引擎的東西不可能帶 `Cookie` 之類的憑證。
@immutable
final class BackendSource {
  BackendSource({
    required this.id,
    required this.url,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(mediaRequestHeaders(headers));

  /// `PlaybackSession` 給的代號，事件以它指回這個來源。
  final int id;

  /// `https` 網址，或 App 內附的 `asset:///…`。
  final Uri url;
  final Map<String, String> headers;
}

/// 後端的狀態。
@immutable
final class BackendStatus {
  const BackendStatus({
    required this.sourceId,
    required this.playing,
    required this.phase,
  });

  /// 狀態屬於哪個來源；清單是空的時為 `null`。
  final int? sourceId;

  /// 要不要出聲（暫停時為假）。播到清單結尾時為假。
  final bool playing;
  final BackendPhase phase;

  @override
  bool operator ==(Object other) =>
      other is BackendStatus &&
      other.sourceId == sourceId &&
      other.playing == playing &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(sourceId, playing, phase);

  @override
  String toString() =>
      'BackendStatus(sourceId: $sourceId, playing: $playing, '
      'phase: ${phase.name})';
}

enum BackendPhase {
  /// 沒有來源。
  idle,

  /// 開流中，或中途等資料。
  buffering,

  /// 載入好了，可以出聲。
  ready,

  /// 播到清單結尾。
  ended,
}

/// 某個來源的位置。
@immutable
final class SourceProgress {
  const SourceProgress({required this.sourceId, required this.progress});

  final int sourceId;
  final PlaybackProgress progress;
}

/// 後端的事件。
@immutable
sealed class BackendEvent {
  const BackendEvent();
}

/// 前瞻接上了：[from] 結束（[end]），[to] 成為目前的來源。
final class SourceAdvanced extends BackendEvent {
  const SourceAdvanced({
    required this.from,
    required this.to,
    required this.end,
  });

  final int from;
  final int to;
  final TrackEndReason end;
}

/// 目前的來源結束，沒有前瞻可接。
final class SourceEnded extends BackendEvent {
  const SourceEnded({required this.id, required this.end});

  final int id;
  final TrackEndReason end;
}

/// 來源失敗。後端不自己跳到下一個。
final class SourceFailed extends BackendEvent {
  const SourceFailed({required this.id, required this.failure, this.cause});

  final int id;
  final BackendFailure failure;

  /// 引擎給的原始錯誤，可能帶完整的串流網址：只以 `error` 交給 log 門面
  /// （經 `Redactor` 遮蔽），不放進訊息或畫面。
  final Object? cause;
}

enum BackendFailure {
  /// 還沒載入就失敗：開不起來、格式解不了。上層換下一個候選（ADR 0018
  /// §決定 7）。
  open,

  /// 已經在播之後中斷。上層從目前位置重試。
  interrupted,
}
