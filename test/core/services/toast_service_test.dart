import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/core/services/toast_service.dart';

void main() {
  group('ToastService', () {
    late BuildContext toastContext;

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                toastContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    }

    SnackBar shownSnackBar(WidgetTester tester) {
      return tester.widget<SnackBar>(find.byType(SnackBar));
    }

    testWidgets('new toast replaces the currently visible toast immediately',
        (tester) async {
      await pumpHost(tester);

      ToastService.show(toastContext, 'old toast');
      await tester.pump();

      expect(find.text('old toast'), findsOneWidget);

      ToastService.success(toastContext, 'new toast');
      await tester.pump();

      expect(find.text('old toast'), findsNothing);
      expect(find.text('new toast'), findsOneWidget);
    });

    testWidgets('each type uses its semantic background color and icon',
        (tester) async {
      await pumpHost(tester);
      final colorScheme = Theme.of(toastContext).colorScheme;

      final cases = <(void Function(), Color, IconData)>[
        (
          () => ToastService.show(toastContext, 'info toast'),
          colorScheme.primary,
          Icons.info,
        ),
        (
          () => ToastService.success(toastContext, 'success toast'),
          ToastService.successColor,
          Icons.check_circle,
        ),
        (
          () => ToastService.warning(toastContext, 'warning toast'),
          ToastService.warningColor,
          Icons.warning,
        ),
        (
          () => ToastService.error(toastContext, 'error toast'),
          colorScheme.error,
          Icons.error,
        ),
      ];

      expect(ToastService.successColor, Colors.green);
      expect(ToastService.warningColor, Colors.orange);

      for (final (show, expectedColor, expectedIcon) in cases) {
        show();
        await tester.pump();

        final snackBar = shownSnackBar(tester);
        expect(snackBar.backgroundColor, expectedColor);
        expect(find.byIcon(expectedIcon), findsOneWidget);

        final icon = tester.widget<Icon>(find.byIcon(expectedIcon));
        expect(icon.color, Colors.white);
      }
    });

    testWidgets('snack bar is floating with white text', (tester) async {
      await pumpHost(tester);

      ToastService.show(toastContext, 'styled toast');
      await tester.pump();

      final snackBar = shownSnackBar(tester);
      expect(snackBar.behavior, SnackBarBehavior.floating);

      final text = tester.widget<Text>(find.text('styled toast'));
      expect(text.style?.color, Colors.white);
    });

    testWidgets('default duration follows toast type', (tester) async {
      await pumpHost(tester);

      final shortCases = <void Function()>[
        () => ToastService.show(toastContext, 'info toast'),
        () => ToastService.success(toastContext, 'success toast'),
      ];
      for (final show in shortCases) {
        show();
        await tester.pump();
        expect(shownSnackBar(tester).duration, ToastDurations.short);
      }

      final longCases = <void Function()>[
        () => ToastService.warning(toastContext, 'warning toast'),
        () => ToastService.error(toastContext, 'error toast'),
      ];
      for (final show in longCases) {
        show();
        await tester.pump();
        expect(shownSnackBar(tester).duration, ToastDurations.long);
      }
    });

    testWidgets('explicit duration overrides the default', (tester) async {
      await pumpHost(tester);

      ToastService.show(
        toastContext,
        'custom duration toast',
        duration: const Duration(seconds: 5),
      );
      await tester.pump();

      expect(
        shownSnackBar(tester).duration,
        const Duration(seconds: 5),
      );
    });

    testWidgets('showWithAction attaches a tappable action', (tester) async {
      await pumpHost(tester);
      var actionTapped = false;

      ToastService.showWithAction(
        toastContext,
        'action toast',
        actionLabel: 'UNDO',
        onAction: () => actionTapped = true,
      );
      // 等 SnackBar 進場動畫完成，確保 action 可以被點擊
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final snackBar = shownSnackBar(tester);
      expect(snackBar.action, isNotNull);
      expect(snackBar.action!.label, 'UNDO');

      final actionButton = find.ancestor(
        of: find.text('UNDO'),
        matching: find.byType(TextButton),
      );
      await tester.tap(actionButton, warnIfMissed: false);
      expect(actionTapped, isTrue);
    });
  });
}
