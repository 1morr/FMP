import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/legacy_import_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/platform/fonts/fonts.dart';

// 首次啟動匯入的進度畫面與失敗頁（M5 design §7.1、§7.2）。

typedef _Run = Future<void> Function(
  void Function(LegacyImportStep step) progress,
);

LegacyImportApp _app({
  required _Run run,
  Future<void> Function()? onStartBlank,
  Future<bool> Function(Object error, LegacyImportStep? step)? onExport,
}) => LegacyImportApp(
  flavor: AppFlavor.dev,
  fontFallback: FontFallback.none,
  run: run,
  onStartBlank: onStartBlank ?? () async {},
  onExport: onExport,
);

void main() {
  final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;

  setUp(() {
    dispatcher.localesTestValue = [const Locale('en', 'US')];
    addTearDown(dispatcher.clearLocalesTestValue);
  });

  testWidgets('shows the five steps and moves along with the progress', (
    tester,
  ) async {
    final gate = Completer<void>();
    late void Function(LegacyImportStep) report;
    await tester.pumpWidget(
      appProviderScope(
        child: _app(
          run: (progress) {
            report = progress;
            return gate.future;
          },
        ),
      ),
    );

    expect(find.text('Importing data from the old version'), findsOneWidget);
    for (final label in [
      'Reading the old data',
      'Converting',
      'Writing',
      'Verifying',
      'Finishing',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // 目前是第一步：一個轉圈，其餘是空圈。
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);

    report(LegacyImportStep.write);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));

    // 換檔與寫憑證都算最後一項。
    report(LegacyImportStep.credentials);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsNWidgets(4));
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);

    gate.complete();
    await tester.pump();
    // 成功沒有失敗頁；之後由 main() 換掉根。
    expect(find.text("Couldn't import the old data"), findsNothing);
  });

  testWidgets('a failure shows the step, a details hint and three buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      appProviderScope(
        child: _app(
          run: (progress) async {
            progress(LegacyImportStep.verify);
            throw const LegacyImportFailed(
              LegacyImportStep.verify,
              'Counts do not match',
            );
          },
          onExport: (_, _) async => true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text("Couldn't import the old data"), findsOneWidget);
    expect(find.text('Failed step: Verifying'), findsOneWidget);
    // 英文的原因只進 log 與診斷包，畫面只有翻譯過的步驟與提示。
    expect(find.textContaining('Counts do not match'), findsNothing);
    expect(
      find.text('Export the diagnostics to keep the details.'),
      findsOneWidget,
    );
    expect(
      find.text(
        "The old data wasn't changed. You can import it again later from "
        'Settings.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Export diagnostics'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextButton, 'Start with empty data'),
      findsOneWidget,
    );
  });

  testWidgets('retry runs the import again from the first step', (
    tester,
  ) async {
    var runs = 0;
    await tester.pumpWidget(
      appProviderScope(
        child: _app(
          run: (progress) async {
            runs++;
            if (runs == 1) {
              throw const LegacyImportFailed(LegacyImportStep.read, 'first');
            }
            // 第二次停在進度畫面（模擬進行中）。
            await Completer<void>().future;
          },
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('Export the diagnostics to keep the details.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();

    expect(runs, 2);
    expect(find.text('Importing data from the old version'), findsOneWidget);
    expect(find.text("Couldn't import the old data"), findsNothing);
  });

  testWidgets('export diagnostics passes the failure and its step', (
    tester,
  ) async {
    Object? exportedError;
    LegacyImportStep? exportedStep;
    await tester.pumpWidget(
      appProviderScope(
        child: _app(
          run: (_) async =>
              throw const LegacyImportFailed(LegacyImportStep.convert, 'x'),
          onExport: (error, step) async {
            exportedError = error;
            exportedStep = step;
            return true;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Export diagnostics'));
    await tester.pump();
    await tester.pump();

    expect(exportedError, isA<LegacyImportFailed>());
    expect(exportedStep, LegacyImportStep.convert);
    expect(find.text('Diagnostics exported'), findsOneWidget);
  });

  testWidgets('start with empty data hands control back to main()', (
    tester,
  ) async {
    var blank = 0;
    await tester.pumpWidget(
      appProviderScope(
        child: _app(
          run: (_) async =>
              throw const LegacyImportFailed(LegacyImportStep.write, 'x'),
          onStartBlank: () async => blank++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Start with empty data'));
    await tester.pump();

    expect(blank, 1);
  });

  testWidgets(
    'an error that is not an import failure shows no step and no details',
    (tester) async {
      await tester.pumpWidget(
        appProviderScope(
          child: _app(run: (_) async => throw StateError('with a path C:\\x')),
        ),
      );
      await tester.pump();

      expect(find.textContaining('StateError'), findsNothing);
      expect(
        find.text('Export the diagnostics to keep the details.'),
        findsOneWidget,
      );
      expect(find.textContaining('Failed step'), findsNothing);
    },
  );

  testWidgets('no export button without file dialogs', (tester) async {
    await tester.pumpWidget(
      appProviderScope(
        child: _app(
          run: (_) async =>
              throw const LegacyImportFailed(LegacyImportStep.read, 'x'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Export diagnostics'), findsNothing);
  });
}
