import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/ui/common/empty_state.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell.dart';

/// 全 App 共用的空狀態（`docs/design/DESIGN.md`〈空狀態〉）：72 的圓角方塊，
/// 排在離內容頂端固定的高度（每種版面一個），換頁時圖示不動。
void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.zhTw));
  tearDown(
    () => LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale),
  );

  Finder box() => find.byKey(EmptyState.iconKey);

  Future<void> pumpAlone(WidgetTester tester, {double head = 0}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(
            brightness: Brightness.light,
            density: Density.touch,
          ),
          home: ShellInsets(
            padding: const EdgeInsets.only(top: 30),
            topBar: const ShellTopBar(top: 0, height: 50, left: 0, right: 0),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: 30 + head)),
                const EmptyState(icon: FmpIcons.queue, title: '佇列是空的'),
              ],
            ),
          ),
        ),
      );

  testWidgets('a 72 rounded square (radius 22, fill, icon 34 in label-2) '
      'at the fixed height below the content top, however tall the head '
      'above it is', (tester) async {
    final touch = EmptyState.topOf(
      const FormFactor(WidthClass.narrow, Density.touch),
    );
    for (final head in [0.0, 60.0]) {
      await pumpAlone(tester, head: head);
      final rect = tester.getRect(box());
      expect(rect.size, const Size(72, 72));
      expect(rect.top, 30 + touch, reason: 'head $head');
    }

    final decoration =
        tester.widget<DecoratedBox>(box()).decoration as BoxDecoration;
    final context = tester.element(box());
    expect(decoration.borderRadius, BorderRadius.circular(22));
    expect(decoration.shape, BoxShape.rectangle);
    expect(decoration.color, context.fmpColors.fill);

    final icon = tester.widget<FmpIcon>(
      find.descendant(of: box(), matching: find.byType(FmpIcon)),
    );
    expect(icon.size, 34);
    expect(icon.color, context.fmpColors.label2);
  });

  testWidgets('a head taller than the fixed height still leaves a gap', (
    tester,
  ) async {
    await pumpAlone(tester, head: 300);
    expect(tester.getRect(box()).top, 30 + 300 + EmptyState.minGap);
  });

  for (final (name, size, mouse) in [
    ('phone', const Size(390, 844), false),
    ('tablet', const Size(820, 1180), false),
    ('medium window', const Size(960, 720), true),
    ('wide', const Size(1280, 800), true),
  ]) {
    testWidgets('$name: the library and the empty queue put the icon at the '
        'same fixed height', (tester) async {
      if (mouse) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(buildRoot());
        await tester.pumpAndSettle();

        await openDestination(tester, Destination.library);
        expect(find.byType(LibraryPage), findsOneWidget);
        final context = tester.element(box());
        final expected =
            ShellInsets.of(context).top +
            EmptyState.topOf(FormFactor.of(context));
        expect(tester.getRect(box()).top, expected);

        await openDestination(tester, Destination.queue);
        expect(find.byType(QueuePage), findsOneWidget);
        expect(tester.getRect(box()).top, expected);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
