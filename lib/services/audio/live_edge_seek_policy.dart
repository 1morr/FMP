/// 「跳到直播最新進度」要往哪裡跳，以及跳了到底有沒有動。
///
/// 兩個後端過去不等價：just_audio 有兩段階梯（duration → buffered），media_kit
/// 只有第一段。搬出來之後兩邊跑同一個。
///
/// 兩步的相對重要性依引擎而異，實測過：mpv 對 Bilibili 直播 FLV 會給出 duration
/// （開流後約 50 秒才出現，且永遠 ≥ 緩衝邊界），所以 Windows 上先成立的是第一
/// 步；ExoPlayer 對直播常常根本沒有 duration，第二步才是主力。
library;

import 'package:fmp/core/constants/app_constants.dart';

/// 這一步是拿什麼當「直播最前端」。
enum LiveEdgeSeekStrategy {
  /// 引擎回報的總時長。有些直播流會給，給了就最準。
  duration('duration edge'),

  /// 已緩衝到的位置。直播流的 duration 通常是 null，但緩衝位置一直有。
  buffered('buffered edge');

  const LiveEdgeSeekStrategy(this.label);

  /// 寫進日誌的名字 —— 實機驗證只看得到這一行，所以兩步要分得出來。
  final String label;
}

/// 階梯上的一步：往 [target] 跳，這一步是用 [strategy] 從 [edge] 算出來的。
class LiveEdgeSeekCandidate {
  const LiveEdgeSeekCandidate({
    required this.strategy,
    required this.edge,
    required this.target,
  });

  final LiveEdgeSeekStrategy strategy;

  /// 這一步認定的最前端。
  final Duration edge;

  /// 實際要 seek 的位置 —— [edge] 往回退 [liveEdgeMargin]。
  final Duration target;
}

/// 可跳範圍短於這個值就不跳。
///
/// 直播流剛連上時 duration／buffered 都可能是零點幾秒，往那裡跳等於跳回開頭。
const Duration liveEdgeMinimumSpan = Duration(seconds: 5);

/// 離最前端留這麼多餘裕，同時也是「算不算真的動了」的門檻。
///
/// 同一個值兼兩用是刻意的：跳到最前端減一秒之後，位置只挪動不到一秒的話，跟
/// 「串流自己繼續播了一下」分不出來，那就不能算 seek 成功。
const Duration liveEdgeMargin = Duration(seconds: 1);

/// seek 之後等多久才回頭看位置。
///
/// 值在 [AppConstants.seekVerificationDelay]；階梯的三個數字放在一起，改其中
/// 一個的人看得到另外兩個。just_audio 那份原本是寫死的 300ms 字面值；兩個後端
/// 都讀這裡，不要在後端裡再寫一份。
const Duration liveEdgeSeekVerificationDelay =
    AppConstants.seekVerificationDelay;

/// 依序該試哪幾步，0 到 2 步。
///
/// 兩步都給就照這個順序試：duration 準但常常沒有，buffered 一定有但只到緩衝
/// 邊界。空清單代表兩邊都短到不值得跳，呼叫端該去重連而不是 seek。
List<LiveEdgeSeekCandidate> liveEdgeCandidates({
  Duration? duration,
  required Duration buffered,
}) => [
  if (duration != null && duration >= liveEdgeMinimumSpan)
    LiveEdgeSeekCandidate(
      strategy: LiveEdgeSeekStrategy.duration,
      edge: duration,
      target: duration - liveEdgeMargin,
    ),
  if (buffered >= liveEdgeMinimumSpan)
    LiveEdgeSeekCandidate(
      strategy: LiveEdgeSeekStrategy.buffered,
      edge: buffered,
      target: buffered - liveEdgeMargin,
    ),
];

/// 位置真的挪動了才算 seek 成功。
///
/// 不可 seek 的串流上 mpv 與 ExoPlayer 都**不會**報錯，只是安靜地不動 ——
/// 回傳值騙不了人的唯一辦法就是回頭量位置。
bool seekTookEffect(Duration before, Duration after) =>
    (after - before).abs() > liveEdgeMargin;
