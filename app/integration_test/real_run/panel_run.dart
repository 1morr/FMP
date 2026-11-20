import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/detail_panel.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 19c：真的開 App（首頁照常抓一次榜，其他不聯網），macOS 在寬版
/// （1280×800）收起、打開詳情面板，中寬度（960×720）叫出、收起浮動面板，
/// 各截動畫中途與結束；再截音樂庫與佇列的空狀態（深淺色）。手機平台只截
/// 空狀態。動畫放慢 [_slow] 倍才截得到中途（`RealRun.step` 截圖前先等畫面
/// 畫完）：
///
///     dart run tool/real_run.dart -d macos --out build/real_run-panel integration_test/real_run/panel_run.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the detail panel slides and the empty states line up', (
    tester,
  ) async {
    final run = await RealRun.launch(tester);
    final mac = defaultTargetPlatform == TargetPlatform.macOS;

    Future<void> wait(Duration duration) async {
      final until = DateTime.now().add(duration);
      while (DateTime.now().isBefore(until)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
    }

    /// 放慢動畫按下 [tooltip] 那顆，截一張動畫中途的 [name]，再恢復速度
    /// 等它跑完，截 `[name]` 去掉 `-mid` 的結束那張。
    Future<void> slowTap(String tooltip, String name) async {
      timeDilation = _slow;
      await tester.tap(find.byTooltip(tooltip).hitTestable().first);
      // 520ms × 30 ≈ 15.6 秒；等 1 秒，`step` 自己再等 0.8 秒，約在時間的
      // 12%：morph 前段走得快，位移約在一半。
      await wait(const Duration(seconds: 1));
      await run.step('$name-mid');
      timeDilation = 1;
      await wait(const Duration(seconds: 1));
      await run.step(name);
    }

    Future<void> brightness(Brightness value) async {
      binding.platformDispatcher.platformBrightnessTestValue = value;
      await wait(const Duration(milliseconds: 500));
    }

    Future<void> empties(String width) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        await brightness(b);
        await openDestination(tester, Destination.library);
        await run.step('$width-library-${b.name}');
        await openDestination(tester, Destination.queue);
        await run.step('$width-queue-${b.name}');
      }
      await brightness(Brightness.light);
      await openDestination(tester, Destination.home);
    }

    if (mac) {
      await run.system('resize-wide', 'resize', ['1280x800']);
      await wait(const Duration(seconds: 1));
      expect(find.byType(DetailPanel), findsOneWidget);
      await slowTap(t.shell.detail.hide, 'wide-hide');
      expect(find.byType(DetailPanel), findsNothing);
      await slowTap(t.shell.detail.show, 'wide-show');
      expect(find.byType(DetailPanel), findsOneWidget);
      await empties('wide');

      await run.system('resize-medium', 'resize', ['960x720']);
      await wait(const Duration(seconds: 1));
      await slowTap(t.shell.detail.show, 'medium-show');
      expect(find.byType(DetailPanel), findsOneWidget);
      await slowTap(t.shell.detail.hide, 'medium-hide');
      expect(find.byType(DetailPanel), findsNothing);
      await empties('medium');
    } else {
      await empties('narrow');
    }
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}

/// 截動畫中途時放慢的倍數。
const double _slow = 30;
