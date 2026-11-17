import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/real_run/driver.dart';

/// 實跑每一步讀回的畫面文字（docs/development.md〈實跑驅動〉）。
void main() {
  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(400, 300)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: child),
    );
  }

  testWidgets('reads the visible text in tree order, without icon glyphs', (
    tester,
  ) async {
    await show(
      tester,
      const Column(
        children: [
          Text('佇列'),
          Icon(IconData(0xe145, fontFamily: 'MaterialIcons')),
          Text.rich(
            TextSpan(
              text: '周末午後',
              children: [TextSpan(text: ' · lofi')],
            ),
          ),
          Text('   '),
        ],
      ),
    );

    expect(readBack(tester), ['佇列', '周末午後 · lofi']);
  });

  testWidgets('leaves out text that lies outside the window', (tester) async {
    await show(
      tester,
      const Stack(
        children: [
          Positioned(left: 10, top: 10, child: Text('看得到')),
          Positioned(left: 10, top: 600, child: Text('在視窗下面')),
        ],
      ),
    );

    expect(readBack(tester), ['看得到']);
  });

  testWidgets('reads only within the given part of the screen', (tester) async {
    await show(
      tester,
      const Column(
        children: [
          Text('導覽'),
          KeyedSubtree(key: Key('page'), child: Text('頁面')),
        ],
      ),
    );

    expect(readBack(tester, find.byKey(const Key('page'))), ['頁面']);
  });
}
