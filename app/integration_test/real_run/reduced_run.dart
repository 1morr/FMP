import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/home/chart_rows.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/phone_dock.dart';
import 'package:integration_test/integration_test.dart';

import 'driver.dart';

/// 票 19d 的實跑：手機平台的系統開了「減少動態效果」（iOS 的減少動態效果、
/// Android 的移除動畫）時，導覽換頁的選取膠囊只淡入淡出、曲目 ⋮ sheet 只淡入，
/// 而且照原本的時長（不是直接跳過，事實 K35）。放慢 30 倍（`RealRun.slowly`）
/// 截中途。只用開 App 時照常抓到的榜，不搜尋、不播放。系統設定在跑之前打開、
/// 跑完關回，包在同一把裝置鎖裡（Android；先記下三個值，關回時照原值）：
///
///     dart run tool/device_lock.dart -- bash -c '
///       for k in animator_duration_scale transition_animation_scale window_animation_scale; do
///         adb shell settings put global $k 0; done
///       dart run tool/real_run.dart -d android --out build/real_run-reduced integration_test/real_run/reduced_run.dart
///       adb shell settings delete global animator_duration_scale
///       adb shell settings put global transition_animation_scale 1.0
///       adb shell settings put global window_animation_scale 1.0'
///
/// App 沒讀到這個設定時，情境一開始就失敗。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('with reduced motion the tab pill and the sheet fade', (
    tester,
  ) async {
    final run = await RealRun.launch(tester);
    expect(
      FmpMotion.reduced(tester.element(find.byType(PhoneDock))),
      isTrue,
      reason: 'turn on the system reduce motion setting before this run',
    );

    final tab = find.descendant(
      of: find.byType(PhoneDock),
      matching: find.text(Destination.queue.label(t)),
    );
    await run.slowly('tab-queue', () => tester.tap(tab));
    await run.slowly(
      'tab-home',
      () => tester.tap(
        find.descendant(
          of: find.byType(PhoneDock),
          matching: find.text(Destination.home.label(t)),
        ),
      ),
    );

    // 榜的第一首的 ⋮：sheet 只淡入。
    final row = find.byType(HomeTouchRow);
    await run.waitFor(row, timeout: const Duration(seconds: 30));
    await run.slowly(
      'sheet',
      () => tester.tap(
        find.descendant(of: row.first, matching: find.byTooltip(t.queue.more)),
      ),
    );
  });
}
