import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 16 的真滑鼠例外（docs/development.md〈實跑驅動〉的例外；integration_test
/// 的點擊不經作業系統，看不到游標形狀與真的 hover）：匿名搜一次 B 站、播一
/// 首，截 `ready` 後讓裝置的滑鼠事件進 App，等 [_window] 讓外面的腳本用真滑鼠
/// 移到桌面播放膠囊的空白處、點一下、拖一段（`screencapture -C` 連游標一起
/// 截），最後讀回播放位置。只在桌面跑：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/capsule_hover_run.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a real mouse hovers, clicks and drags the transport capsule', (
    tester,
  ) async {
    final run = await RealRun.launch(tester);
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await run.waitFor(find.byTooltip(t.queue.more));
    await playSearchResult(tester, searchResultAt(0));
    await run.waitFor(find.byType(TransportBar));
    await run.waitForStatus(PlaybackStatus.playing);
    await run.step('ready');

    // 真滑鼠的事件照常進 App（測試綁定預設擋掉裝置的指標事件）。
    binding.shouldPropagateDevicePointerEvents = true;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransportBar)),
    );
    final until = DateTime.now().add(_window);
    while (DateTime.now().isBefore(until)) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    binding.shouldPropagateDevicePointerEvents = false;
    final state = container.read(playbackProvider)!;
    await run.step('after-mouse');
    // ignore: avoid_print -- 外面的腳本比對點與拖之後的位置。
    print('[capsule] ${state.position} / ${state.effectiveDuration}');
  });
}

/// 外面的腳本做完 hover、點、拖的時間。
const _window = Duration(seconds: 40);
