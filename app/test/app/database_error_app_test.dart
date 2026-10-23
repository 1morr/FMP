import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/database_error_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/fonts/fonts.dart';

DatabaseErrorApp _app({
  Object error = const FormatException('file is not a database'),
  Future<void> Function()? onRetry,
  Future<bool> Function(Object error)? onExport,
}) => DatabaseErrorApp(
  flavor: AppFlavor.dev,
  error: error,
  fontFallback: FontFallback.none,
  onRetry: onRetry ?? () async {},
  onExport: onExport,
);

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

      await tester.pumpWidget(appProviderScope(child: _app()));

      expect(find.text(title), findsOneWidget);
      expect(
        find.text('FormatException: file is not a database'),
        findsOneWidget,
      );
    });
  }

  testWidgets('retry runs the open again and shows a new error when it '
      'fails', (tester) async {
    dispatcher.localesTestValue = [const Locale('en', 'US')];
    addTearDown(dispatcher.clearLocalesTestValue);
    var attempts = 0;
    await tester.pumpWidget(
      appProviderScope(
        child: _app(
          onRetry: () async {
            attempts++;
            throw StateError('still locked');
          },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    await tester.pump();

    expect(attempts, 1);
    expect(find.text('Bad state: still locked'), findsOneWidget);
    // 再按一次還是會重跑。
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    expect(attempts, 2);
  });

  testWidgets('export diagnostics passes the shown error and reports the '
      'outcome; a cancelled export says nothing', (tester) async {
    dispatcher.localesTestValue = [const Locale('en', 'US')];
    addTearDown(dispatcher.clearLocalesTestValue);
    final exported = <Object>[];
    var saved = true;
    await tester.pumpWidget(
      appProviderScope(
        child: _app(
          onExport: (error) async {
            exported.add(error);
            return saved;
          },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Export diagnostics'));
    await tester.pump();
    await tester.pump();
    expect(exported.single, isA<FormatException>());
    expect(find.text('Diagnostics exported'), findsOneWidget);

    saved = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Export diagnostics'));
    await tester.pump();
    await tester.pump();
    expect(exported, hasLength(2));
    expect(find.text('Diagnostics exported'), findsNothing);
    expect(find.text("Couldn't export the diagnostics"), findsNothing);
  });

  testWidgets('no export button when the platform has no file dialogs', (
    tester,
  ) async {
    dispatcher.localesTestValue = [const Locale('en', 'US')];
    addTearDown(dispatcher.clearLocalesTestValue);
    await tester.pumpWidget(appProviderScope(child: _app()));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Export diagnostics'), findsNothing);
  });
}
