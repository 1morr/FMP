import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/widgets/layout/capped_draggable_sheet.dart';

/// 面板外殼要讓內容的點擊水波紋看得到。
///
/// 三個呼叫端都用 `showModalBottomSheet(backgroundColor: Colors.transparent)`
/// 開這個外殼，底色由外殼自己畫。底色畫在 Container 上時，內容的 ListTile 與
/// InkWell 把水波紋畫在更外層、透明的 Material 上，被 Container 蓋住 —— 點下去
/// 沒有任何回饋，只有 debug 模式會報一句 "ink splashes may be invisible"。
void main() {
  testWidgets('rows in the sheet paint their ink on the sheet surface', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.en);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => CappedDraggableSheet(
                  icon: Icons.info_outline,
                  title: 'Sheet',
                  onClose: () => Navigator.of(context).pop(),
                  bodySlivers: (context, _) => [
                    SliverToBoxAdapter(
                      child: ListTile(title: const Text('row'), onTap: () {}),
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // ListTile 在 debug 模式下發現水波紋會被蓋住時會回報錯誤。
    expect(tester.takeException(), isNull);

    // 水波紋畫在最近的 Material 上，那一層要帶著面板的底色。
    final surface = tester.widget<Material>(
      find
          .ancestor(of: find.text('row'), matching: find.byType(Material))
          .first,
    );
    final colorScheme = Theme.of(tester.element(find.text('row'))).colorScheme;
    expect(surface.color, colorScheme.surfaceContainerLow);
  });
}
