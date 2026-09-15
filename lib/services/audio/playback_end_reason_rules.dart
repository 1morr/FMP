/// 兩個後端共用的「播放為什麼停下來」判定，不含任何引擎型別。
///
/// 翻譯責任仍然在後端 —— 只有後端知道自己面對的是 mpv 還是 ExoPlayer。搬出來
/// 的是**規則本身**：三份一字不差的 completion 判定曾經分別長在
/// `just_audio_service.dart`、`media_kit_audio_service.dart` 與
/// `test/support/fakes/fake_audio_service.dart` 裡，而兩個真後端在
/// `flutter test` 裡都建不起來（just_audio 要 platform channel，media_kit 要
/// libmpv）。「同一份斷言跑在三個後端上」因此只有在規則是可單獨測試的純函式時
/// 才是真的；後端各留三行轉呼叫。
///
/// `test/services/static_rules/audio_backend_shared_rules_static_rule_test.dart`
/// 釘住這件事：關鍵字表只准出現在本檔，複製一份回後端會紅。
library;

import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/services/audio/audio_types.dart';

/// 引擎宣告 completed 時，判斷是「真的播完」還是「提前結束」。
///
/// 位置與時長由後端自己看得最準，上層只需要結論。[duration] 為 null 或 0 代表
/// 引擎從未回報過時長 —— 實測「連得上但零位元組」的串流正是這個形狀，而它過去
/// 會被當成正常播完、直接跳下一首。
PlaybackEndReason classifyCompletion({
  Duration? duration,
  required Duration position,
}) {
  if (duration == null || duration.inMilliseconds <= 0) {
    return EndedPrematurely(at: position, expected: null);
  }
  if (duration - position > AppConstants.completionTolerance) {
    return EndedPrematurely(at: position, expected: duration);
  }
  return const EndedNaturally();
}

/// 把 mpv 的錯誤訊息翻成型別。
///
/// `could not open` 這個子字串在「媒體開不起來」與「音訊裝置開不起來」兩種語意
/// 上都成立，只有知道自己是哪個引擎的人分得出來。音訊裝置的判斷因此必須排在
/// 媒體開啟之前 —— 這正是 issue #41 的修法。
PlaybackEndReason classifyMpvMessage(String raw) {
  final text = raw.toLowerCase();

  if (text.contains('audio device') ||
      text.contains('audio output') ||
      text.contains('audio driver') ||
      text.contains('[ao]') ||
      text.startsWith('ao:')) {
    return OutputDeviceFailed(raw: raw);
  }

  if (text.startsWith('tcp:') ||
      text.contains('ffurl_read') ||
      text.contains('connection') ||
      text.contains('socket') ||
      text.contains('timed out') ||
      text.contains('unreachable')) {
    return TransportFailed(kind: transportKindOf(text), raw: raw);
  }

  if (text.contains('failed to open') ||
      text.contains('cannot open') ||
      text.contains('could not open') ||
      text.contains('no such file')) {
    return MediaUnopenable(raw: raw);
  }

  if (text.contains('decoder') || text.contains('could not decode')) {
    return DecoderFailed(raw: raw);
  }

  return UnclassifiedFailure(raw: raw);
}

/// 把 just_audio 的 `PlayerException` 翻成型別。
///
/// [code] 進簽名但不進階梯，這是實測結果而不是疏漏：ExoPlayer 把幾乎所有網路層
/// 問題都壓成 `code=0, message=Source error`，對整族失敗而言 code 是個常數，分
/// 不出任何東西 —— 分得出來的是訊息。把它留在簽名裡，是讓這句話待在做判斷的地
/// 方，而不是讓每個後端各自決定要不要看它。[raw] 是給診斷用的原文（後端會把
/// code 與 message 一起寫進去），**不是**判斷依據。
///
/// 分不出來的一律回 [UnclassifiedFailure]，而不是猜。
PlaybackEndReason classifyExoPlayerFailure({
  required int code,
  String? message,
  required String raw,
}) {
  final text = (message ?? '').toLowerCase();

  if (text.contains('audio track') ||
      text.contains('audio sink') ||
      text.contains('audiotrack')) {
    return OutputDeviceFailed(raw: raw);
  }

  if (text.contains('source error') ||
      text.contains('unable to connect') ||
      text.contains('socket') ||
      text.contains('timeout') ||
      text.contains('unexpected end of stream')) {
    // 刻意不走 [transportKindOf]：那張表是照 mpv 的措辭做的，對 ExoPlayer 的
    // `Source error` 一律回 unknown。這個被壓平的桶子實測以連線中斷為主，所以
    // 「不是逾時」預設成 reset —— 上層對 reset 會重取串流網址，對 unknown 不會。
    return TransportFailed(
      kind: text.contains('timeout')
          ? TransportFailureKind.timeout
          : TransportFailureKind.reset,
      raw: raw,
    );
  }

  if (text.contains('response code: 40') ||
      text.contains('response code: 41') ||
      text.contains('unrecognized input format') ||
      text.contains('none of the available extractors')) {
    return MediaUnopenable(raw: raw);
  }

  if (text.contains('decoder') || text.contains('decoding')) {
    return DecoderFailed(raw: raw);
  }

  return UnclassifiedFailure(raw: raw);
}

/// 從已經轉小寫的訊息裡判斷傳輸層失敗的細分類別。
///
/// 措辭表照 mpv／ffmpeg 與 Dart `SocketException` 的實際輸出做的；分不出來回
/// [TransportFailureKind.unknown]，因為猜錯的代價是上層選錯重試策略。
TransportFailureKind transportKindOf(String text) {
  if (text.contains('timed out') || text.contains('timeout')) {
    return TransportFailureKind.timeout;
  }
  if (text.contains('reset')) return TransportFailureKind.reset;
  if (text.contains('failed host lookup') ||
      text.contains('name resolution') ||
      text.contains('dns')) {
    return TransportFailureKind.dns;
  }
  if (text.contains('tls') ||
      text.contains('ssl') ||
      text.contains('certificate')) {
    return TransportFailureKind.tls;
  }
  if (text.contains('refused')) return TransportFailureKind.refused;
  return TransportFailureKind.unknown;
}
