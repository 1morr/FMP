import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:material_ui/material_ui.dart';

/// 每個圖示的路徑（照 `docs/design/assets/kit.js` 搬過來）都解析得了、畫得出來；
/// 抄錯一個字母時這裡會紅。
void main() {
  testWidgets('every icon parses and paints', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Wrap(
          children: [for (final icon in FmpIcons.values) FmpIcon(icon)],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(FmpIcon), findsNWidgets(FmpIcons.values.length));
  });
}
