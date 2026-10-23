import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/settings/playback_settings.dart';

// 舊版「播放歷史保留筆數」→ 新版（M5 design §5.9）。轉換器用它截斷播放歷史（PR 3），設定的
// 轉換（PR 5）寫 `play_history_limit` 時沿用同一個函式，兩邊不會各算一份。

/// 舊版的預設保留筆數（舊 `Settings.playHistoryLimit` 的初值）。
const legacyDefaultPlayHistoryLimit = 10000;

/// 新版的預設保留筆數（設定的預設只寫在 `PlaybackPreferencesNotifier.resolve`）。
int get newDefaultPlayHistoryLimit =>
    PlaybackPreferencesNotifier.resolve(PlaybackSettings.empty)
        .playHistoryLimit;

/// 要寫進 `playback_settings.play_history_limit` 的值；`null` 是不寫（新版的預設生效）。
///
/// - 不合法（Isar 的型別預設 `-2^63`、零或負數）或等於舊預設：`null`（ADR 0011：空＝沒設定過）；
/// - 否則取「不小於舊值的最小選項」，比最大選項大就取最大選項：匯入時不能就把歷史裁掉。
int? convertPlayHistoryLimit(int legacyLimit) {
  if (legacyLimit <= 0 || legacyLimit == legacyDefaultPlayHistoryLimit) {
    return null;
  }
  for (final option in playHistoryLimitOptions) {
    if (option >= legacyLimit) return option;
  }
  return playHistoryLimitOptions.last;
}

/// 轉換後實際生效的保留筆數：[convertPlayHistoryLimit] 的結果，或新版的預設。
int effectivePlayHistoryLimit(int legacyLimit) =>
    convertPlayHistoryLimit(legacyLimit) ?? newDefaultPlayHistoryLimit;
