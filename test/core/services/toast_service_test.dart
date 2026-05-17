import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';

void main() {
  group('ToastService', () {
    testWidgets('new toast replaces the currently visible toast immediately',
        (tester) async {
      BuildContext? toastContext;

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

      ToastService.show(toastContext!, 'old toast');
      await tester.pump();

      expect(find.text('old toast'), findsOneWidget);

      ToastService.success(toastContext!, 'new toast');
      await tester.pump();

      expect(find.text('old toast'), findsNothing);
      expect(find.text('new toast'), findsOneWidget);
    });
  });
}
