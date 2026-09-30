import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/database_error_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/fonts/fonts.dart';

void main() {
  final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;

  for (final (system, title) in [
    (const Locale('zh', 'TW'), '無法開啟資料庫'),
    (const Locale('zh', 'CN'), '无法打开数据库'),
    (const Locale('en', 'US'), "Can't open the database"),
  ]) {
    testWidgets('says the database cannot be opened in $system', (
      tester,
    ) async {
      dispatcher.localesTestValue = [system];
      addTearDown(dispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        appProviderScope(
          child: DatabaseErrorApp(
            flavor: AppFlavor.dev,
            error: const FormatException('file is not a database'),
            fontFallback: FontFallback.none,
          ),
        ),
      );

      expect(find.text(title), findsOneWidget);
      expect(
        find.text('FormatException: file is not a database'),
        findsOneWidget,
      );
    });
  }
}
