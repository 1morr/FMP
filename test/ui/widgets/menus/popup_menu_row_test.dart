import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/menus/popup_menu_row.dart';

/// 播放頁三點選單只有倍速一項時，`1.0x` 在手機上被斷成三行。
///
/// 選單寬度是 intrinsic 寬度向上取到 56dp 的倍數，而 `ListTile` 的 intrinsic
/// 少算了 trailing 前的 16dp。只有在標籤長度讓 intrinsic 剛好貼著級距邊界時才
/// 會壞 —— 實機是 `1.0x`；測試字型每個字元都是一個正方形，`1.25x` 落在同一種
/// 位置（82 + 5×16 = 162，取到 168，只剩 6dp 的餘裕吸收不了 16dp）。
void main() {
  Future<RenderParagraph> openMenuWith(
    WidgetTester tester,
    String label,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'speed',
                  child: PopupMenuRow(
                    icon: const Icon(Icons.speed),
                    label: label,
                    trailing: const Icon(Icons.chevron_right, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    return tester.renderObject<RenderParagraph>(find.text(label));
  }

  testWidgets('a short label beside a trailing icon stays whole on one line', (
    tester,
  ) async {
    final paragraph = await openMenuWith(tester, '1.25x');

    final unconstrained = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    addTearDown(unconstrained.dispose);

    expect(paragraph.size.height, unconstrained.height, reason: 'one line');
    expect(paragraph.didExceedMaxLines, isFalse, reason: 'not ellipsized');
    expect(paragraph.size.width, greaterThanOrEqualTo(unconstrained.width));
  });
}
