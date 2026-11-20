import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/ui/common/focus_ring.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 鍵盤焦點的實跑（票 19b，`docs/design/DESIGN.md`〈無障礙〉）：只用 Tab 走一輪
/// 外殼與搜尋頁，每一站截圖看焦點外框；搜尋只打一次真的音源（spec〈共同
/// 規則〉的聯網規則）。桌面用：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/keyboard_focus_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Tab walks the shell and the search page with a focus ring', (
    tester,
  ) async {
    final run = await RealRun.launch(tester);
    final ring = find.byWidgetPredicate((w) => w is FocusRing && w.visible);

    /// 按 Tab 直到 [done]，最多 [max] 下。
    Future<void> tabUntil(bool Function() done, {int max = 40}) async {
      for (var i = 0; i < max && !done(); i++) {
        final focus = FocusManager.instance.primaryFocus;
        if (focus?.context?.widget is EditableText ||
            focus?.context?.findAncestorWidgetOfExactType<EditableText>() !=
                null) {
          // macOS 的輸入框把 Tab 交給輸入法，輸入法回 `insertTab:`，框架再
          // 轉成下一個焦點；模擬的按鍵到不了輸入法，這裡直接走那一步。
          focus!.nextFocus();
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        }
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(done(), isTrue);
    }

    /// 焦點在一顆寫著 [label] 的按鈕上（不是包著整頁的表格焦點）。
    bool focusedLabel(String label) {
      final focus = FocusManager.instance.primaryFocus;
      final context = focus?.context;
      return context != null &&
          focus!.debugLabel == 'ShellButton' &&
          ring.evaluate().isNotEmpty &&
          find
              .descendant(
                of: find.byElementPredicate((e) => e == context),
                matching: find.text(label),
              )
              .evaluate()
              .isNotEmpty;
    }

    // 外殼：導覽的「佇列」。
    await tabUntil(() => focusedLabel(t.shell.nav.queue));
    await run.step('shell-tab');

    // 搜尋一次，Tab 到第二個篩選 chip（音源）。
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    // 等結果回來（`searchResultAt` 的鍵；它本身沒有結果時會丟例外）。
    await run.waitFor(
      find.byWidgetPredicate((w) => w.key is ValueKey<TrackRef>),
    );
    // 桌面表格：Tab 進表格選到第一首、↓ 到第二首，Shift+F10 開它的選單。
    await tabUntil(
      () => FocusManager.instance.primaryFocus?.debugLabel == 'search results',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    await run.step('search-table');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await run.waitFor(find.text(t.queue.actions.addToQueue));
    await run.step('search-menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));

    // 再往下 Tab 到篩選 chip「全部」。
    await tabUntil(() => focusedLabel(t.search.all));
    await run.step('search-chip');
  });
}
