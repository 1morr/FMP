import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/unsupported_platform_app.dart';
import 'package:fmp/core/app_flavor.dart';

void main() {
  final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;

  for (final (system, text) in [
    (const Locale('zh', 'TW'), '此平台尚未支援'),
    (const Locale('en', 'US'), "This platform isn't supported yet"),
  ]) {
    testWidgets('tells the user the platform is not supported in $system', (
      tester,
    ) async {
      dispatcher.localesTestValue = [system];
      addTearDown(dispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        appProviderScope(
          child: const UnsupportedPlatformApp(flavor: AppFlavor.dev),
        ),
      );

      expect(find.text(text), findsOneWidget);
    });
  }
}
