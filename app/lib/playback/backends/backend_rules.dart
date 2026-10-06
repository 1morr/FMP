// 兩個後端共用的規則（ADR 0018 §決定 3）：不含任何引擎型別的純函數。
//
// 翻譯仍在後端：只有後端知道自己面對的是 ExoPlayer 還是 mpv。搬到這裡的是規則
// 本身，兩個真後端在 `flutter test` 裡建不起來（just_audio 要 platform channel，
// media_kit 要 libmpv），規則是純函數，「同一份斷言跑在兩個實作與假後端上」才
// 做得到：`test/playback/backends/backend_rules_test.dart` 測規則，
// `audio_backend_contract.dart` 以同一份行為斷言跑假後端（`flutter test`）與
// 平台的真後端（`integration_test/audio_backend_contract_test.dart`）。
//
// 形狀照舊專案的 `playback_end_reason_rules.dart`、`next_media_plan.dart`。

/// 一個來源為什麼停下來。
enum TrackEndReason {
  /// 播到結尾。
  completed,

  /// 離結尾還遠就停了，或引擎從沒回報過時長：串流中斷、零位元組的回應。
  /// 上層當成傳輸中斷，從停下的位置重試（ADR 0018 §決定 7）。
  endedEarly,
}

/// 「位置離時長還差這麼多以上」就算提前結束。兩個引擎的位置回報都有間隔
/// （ExoPlayer 的事件外推、mpv 的 `time-pos`），1.5 秒容得下，舊專案同值。
const completionTolerance = Duration(milliseconds: 1500);

/// 引擎說目前的來源結束了（播完或接到前瞻）時，判斷是真的播完還是提前結束。
///
/// [position] 是結束前最後的位置，[duration] 是引擎回報的時長；`null` 或 0 是
/// 引擎從沒回報過時長，舊專案實測「連得上但零位元組」的串流就是這個形狀，
/// 所以算提前結束，不當成播完直接接下一首。
TrackEndReason classifyTrackEnd({
  required Duration position,
  required Duration? duration,
}) {
  if (duration == null || duration <= Duration.zero) {
    return TrackEndReason.endedEarly;
  }
  if (duration - position > completionTolerance) {
    return TrackEndReason.endedEarly;
  }
  return TrackEndReason.completed;
}

/// 讓後端的播放清單回到「目前＋最多一個前瞻」要做的修改。
final class LookAheadEdit {
  const LookAheadEdit._({required this.removeIndices, required this.append});

  /// 清單裡有 [itemCount] 個項目、正在播 [currentIndex]；[append] 是要不要接上
  /// 新的前瞻（`false` 是清掉）。
  ///
  /// 目前這個項目以外的全部移掉：之後的是舊的前瞻，之前的是剛播完的那一首
  /// （接上前瞻後由後端自己修剪）。留著的話每個項目都是一條開著的連線，而且
  /// 目前的項目不在 0，「下一個」就不一定是 1。清單是空的就什麼都不做：沒有
  /// 東西在播，也就沒有可以接上去的位置。
  factory LookAheadEdit.of({
    required int itemCount,
    required int currentIndex,
    required bool append,
  }) {
    if (itemCount <= 0 || currentIndex < 0 || currentIndex >= itemCount) {
      return const LookAheadEdit._(removeIndices: [], append: false);
    }
    return LookAheadEdit._(
      removeIndices: [
        for (var index = itemCount - 1; index >= 0; index--)
          if (index != currentIndex) index,
      ],
      append: append,
    );
  }

  /// 要移除的索引，由大到小：照這個順序移，前面的索引不會位移。
  final List<int> removeIndices;

  /// 移完後要不要把新的前瞻接在目前的項目之後（成為索引 1）。
  final bool append;
}

/// ffmpeg 回報 HTTP 錯誤的 log 行（mpv 以前綴 `ffmpeg` 轉出），例如
/// `http: HTTP error 403 Forbidden`：前面是 ffmpeg 的協定名稱（`http`、`https`）。
final _httpErrorLine = RegExp(r'^[a-z]+: HTTP error (\d{3})\b');

/// 從 mpv 轉出的一行 ffmpeg log 取出 HTTP 狀態碼；不是 HTTP 錯誤的那一行就是
/// `null`。
///
/// 只有 mpv 用得到：ExoPlayer 的狀態碼在 `InvalidResponseCodeException`
/// （`Response code: 403`）裡，但 just_audio 0.10.6 交給 Dart 的只有
/// `ExoPlaybackException.getMessage()`，開流失敗一律是 `Source error`
/// （`AudioPlayer.java` 的 `onPlayerError`），拿不到狀態碼（見 `AudioBackend`）。
int? httpStatusFromLogLine(String line) {
  final match = _httpErrorLine.firstMatch(line);
  return match == null ? null : int.parse(match.group(1)!);
}

/// 速度的範圍（舊版 `app_constants.dart` 的選項 0.5–2.0，design §7.6）。
const minSpeed = 0.5;
const maxSpeed = 2.0;

/// 夾到 [minSpeed]–[maxSpeed]：兩個後端在交給引擎之前都經過它。
double clampSpeed(double speed) => speed.clamp(minSpeed, maxSpeed).toDouble();

/// 夾到 0–1。
double clampVolume(double volume) => volume.clamp(0, 1).toDouble();

/// Android 音訊中斷的種類：audio_session 的 `AudioInterruptionType` 一對一
/// 轉過來（`AudioInterruptionEvent.type`）。暫停類是 `AUDIOFOCUS_LOSS_TRANSIENT`，
/// duck 是 `…_CAN_DUCK`，unknown 是 `AUDIOFOCUS_LOSS`（不會再拿回焦點：
/// audio_session 的原生端此時就放掉焦點，之後不會有結束的事件）。
enum InterruptionKind { pause, duck, unknown }

/// 中斷開始或結束時，後端要做的事（design §7.6）。
enum InterruptionResponse {
  /// 開始 duck：引擎的輸出減半（[outputVolume]），不改使用者的音量、不通知
  /// 上層。
  duck,

  /// duck 結束：輸出回到使用者的音量。
  unduck,

  /// 發 `Interrupted`：由控制器決定暫停。
  interrupted,

  /// 發 `InterruptionEnded(resume: true)`：控制器只在原本因中斷而暫停時續播。
  endedResumable,

  /// 發 `InterruptionEnded(resume: false)`。audio_session 不會發 unknown 類的
  /// 結束，這一支只讓對應是全的。
  ended,
}

/// [begin] 是中斷開始還是結束，[kind] 是 audio_session 給的種類。
///
/// 不用 just_audio 的內建處理（`handleInterruptions: false`）：0.10.6 在 duck
/// 結束時無條件把音量乘 2，音樂用途開始 duck 時卻不減半，會把使用者的音量放大
/// 一倍；而且它自己暫停、續播，控制器的狀態會和引擎分岔。
InterruptionResponse respondToInterruption({
  required bool begin,
  required InterruptionKind kind,
}) => switch ((begin, kind)) {
  (true, InterruptionKind.duck) => InterruptionResponse.duck,
  (false, InterruptionKind.duck) => InterruptionResponse.unduck,
  (true, InterruptionKind.pause || InterruptionKind.unknown) =>
    InterruptionResponse.interrupted,
  (false, InterruptionKind.pause) => InterruptionResponse.endedResumable,
  (false, InterruptionKind.unknown) => InterruptionResponse.ended,
};

/// [response] 之後引擎的輸出要不要減半：只有 duck 開始之後要，其他事件一律
/// 還原。
///
/// 不能只在 duck 結束時還原：audio_session 在暫停類、unknown 類中斷開始時就把
/// 它自己的 duck 記號歸零，之後拿回焦點報的是暫停類的結束；unknown 類則再也
/// 沒有事件（原生端已放掉焦點）。所以「duck 中來電」之後要在這裡還原，否則輸出
/// 一直是一半。
bool duckedAfter(InterruptionResponse response) =>
    response == InterruptionResponse.duck;

/// duck 時輸出乘上的倍數（舊版同值）。
const duckFactor = 0.5;

/// 交給引擎的音量：使用者的 [volume]，duck 時乘 [duckFactor]。
///
/// Android 8 起，以 `setWillPauseWhenDucked(false)`（audio_session 的預設）要求
/// 焦點的 App 由系統自動 duck，不會收到 `…_CAN_DUCK` 的回呼
/// （developer.android.com/media/optimize/audio-focus「Automatic ducking」）；
/// 收得到時就是系統沒有代為 duck，這裡自己減半。
double outputVolume(double volume, {required bool ducked}) =>
    ducked ? volume * duckFactor : volume;

/// mpv 在音訊輸出開不起來時、`[cplayer]` 那一行的開頭。
const _noAudioDevice = 'Could not open/initialize audio device';

/// mpv 的一行 log 是不是音訊輸出（裝置）開不起來：`[ao]`、`[ao/<驅動>]` 的
/// error，與接著的 `[cplayer] Could not open/initialize audio device -> no
/// sound.`。開流時選的裝置不在、播放中裝置被拔掉都是這一串（樣本見
/// `backend_rules_test.dart`）。
///
/// media_kit 只把 `[cplayer]` 那一行轉進 error stream，`[ao]` 的只在 log；而
/// 「could not open」看起來像來源開不起來（舊專案 issue #41），所以 error
/// stream 那邊另以 [isOutputDeviceFailureMessage] 認出來、不算在來源上。
bool isOutputDeviceFailure({
  required String prefix,
  required String level,
  required String text,
}) {
  if (level != 'error') return false;
  if (prefix == 'ao' || prefix.startsWith('ao/')) return true;
  return prefix == 'cplayer' && text.startsWith(_noAudioDevice);
}

/// media_kit 的 error stream 只給文字（不帶前綴）：這一行是音訊輸出開不起來，
/// 不是來源的錯誤。
bool isOutputDeviceFailureMessage(String text) =>
    text.startsWith(_noAudioDevice);
