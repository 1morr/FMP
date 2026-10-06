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
///   所以 `MediaKitBackend` 把錯誤算在目前的來源上：還沒載入就是開不起來，
///   載入後只記 log（前瞻預開失敗的那一行也是）；換到前瞻、它還沒載入時的
///   錯誤算前瞻的。
/// - **標頭**：just_audio 以 `useProxyForRequestHeaders: false` 直接交給
///   ExoPlayer（不開本機 proxy，不需要明文流量）；media_kit 在 mpv 的
///   `on_load` hook 設 `http-header-fields`，以網址為鍵，同一個網址只有一組
///   標頭。
/// - **前瞻開不起來**（[setNext]）：ExoPlayer（media3 1.4.1）在播放中預備前瞻
///   失敗時不報錯，播完目前這首、換到前瞻的索引後才報（`ExoPlayerImplInternal`
///   只對正在播的項目拋 `maybeThrowPrepareError`），換過去那一刻的狀態還是
///   `ready`、沒有時長；mpv 預開前瞻失敗時馬上記一行錯誤（不帶項目），播完
///   目前這首時再開一次、`playlist-playing-pos` 換過去後再記一次。所以兩個
///   後端都等前瞻真的載入（有時長，或換過去後的第一次位置）才發
///   [SourceAdvanced]，載入前先收到錯誤就當成前瞻開不起來。
/// - **HTTP 狀態碼**（[SourceFailed.httpStatus]）：只有 mpv 有。它來自 ffmpeg 的
///   `HTTP error 403 Forbidden` 這行 warn log，而 mpv 只把 ffmpeg 的 log 交給行程裡
///   第一個還活著的實例（mpv `common/av_log.c` 的 `init_libav`；media_kit 在
///   `dispose` 後 5 秒才銷毀實例），App 只有一個後端所以拿得到。just_audio
///   0.10.6 只把 `ExoPlaybackException.getMessage()` 交給 Dart，開流失敗一律是
///   `Source error`，Android 一律是 `null`。
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
  ///
  /// 前瞻開不起來時不接上它，目前的來源照常播完：先發
  /// `SourceFailed(前瞻, BackendFailure.open)`，之後目前的來源結束時發
  /// [SourceEnded]（不是 [SourceAdvanced]）。失敗一定先到：它可能在設定時就到
  /// （Dart 端就失敗，例如 asset 不存在），也可能等到交接時才到（引擎播完目前
  /// 這首才開前瞻，兩個事件緊接著發）。
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
///
/// [id] 可以是前瞻：前瞻開不起來時不接上它（見 [AudioBackend.setNext]）。
final class SourceFailed extends BackendEvent {
  const SourceFailed({
    required this.id,
    required this.failure,
    this.cause,
    this.httpStatus,
  });

  final int id;
  final BackendFailure failure;

  /// 開流被 HTTP 拒絕時的狀態碼；引擎沒給就是 `null`（見 [AudioBackend]）。
  final int? httpStatus;

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
