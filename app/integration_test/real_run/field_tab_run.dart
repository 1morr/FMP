import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 真的按鍵能不能從搜尋欄 Tab 出去（票 19b）：macOS 的輸入框把 Tab 交給輸入
/// 法，`flutter_test` 模擬的按鍵到不了那一層，所以由系統（System Events，
/// 不動游標）送一下真的 Tab，讀回焦點移到哪。不聯網，欄位空著。桌面用：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/field_tab_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a real Tab moves focus out of the search field', (tester) async {
    final run = await RealRun.launch(tester);

    await openSearch(tester);
    await tester.pumpAndSettle();
    bool inField() {
      final context = FocusManager.instance.primaryFocus?.context;
      return context != null &&
          (context.widget is EditableText ||
              context.findAncestorWidgetOfExactType<EditableText>() != null);
    }

    expect(inField(), isTrue);
    await run.step('field-focused');

    await run.system('tab', 'press-key', ['tab']);
    await tester.pump(const Duration(milliseconds: 500));
    // ignore: avoid_print -- 焦點移到哪留在實跑的輸出裡。
    print('[focus] ${FocusManager.instance.primaryFocus}');
    await run.step('after-tab');
    expect(inField(), isFalse);
  });
}
