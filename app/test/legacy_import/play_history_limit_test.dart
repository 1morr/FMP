import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/legacy_import/play_history_limit.dart';
import 'package:fmp/settings/playback_settings.dart';

void main() {
  test('the new default comes from the settings resolver', () {
    expect(
      newDefaultPlayHistoryLimit,
      PlaybackPreferencesNotifier.resolve(PlaybackSettings.empty)
          .playHistoryLimit,
    );
    expect(newDefaultPlayHistoryLimit, 10000);
  });

  group('convertPlayHistoryLimit', () {
    const legacyNullLong = -9223372036854775808;
    final cases = <int, int?>{
      // 不合法：不寫。
      legacyNullLong: null,
      0: null,
      -5: null,
      // 等於舊預設：不寫（新版預設生效）。
      10000: null,
      // 選項內的值：原樣。
      1000: 1000,
      5000: 5000,
      50000: 50000,
      // 不在選項內：取不小於它的最小選項。
      1: 1000,
      999: 1000,
      1001: 5000,
      4999: 5000,
      5001: 10000,
      10001: 50000,
      49999: 50000,
      // 比最大選項大：取最大選項，不裁掉歷史。
      50001: 50000,
      1000000: 50000,
    };
    for (final entry in cases.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(convertPlayHistoryLimit(entry.key), entry.value);
      });
    }
  });

  test('effectivePlayHistoryLimit falls back to the new default', () {
    expect(effectivePlayHistoryLimit(10000), 10000);
    expect(effectivePlayHistoryLimit(-9223372036854775808), 10000);
    expect(effectivePlayHistoryLimit(3000), 5000);
    expect(effectivePlayHistoryLimit(80000), 50000);
  });

  test('every option converts to itself', () {
    for (final option in playHistoryLimitOptions) {
      expect(
        effectivePlayHistoryLimit(option),
        option,
        reason: 'option $option',
      );
    }
  });
}
