import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';

import '../plugins/plugin_harness.dart';
import '../support/memory_database.dart';

void main() {
  testWidgets('shows the app name, flavor, data directory and plugins', (
    tester,
  ) async {
    final database = memoryDatabase();
    await tester.runAsync(
      () => PluginRepository(database).install(
        InstalledPlugin(
          id: 'fmp-test',
          version: '1.0.0',
          manifestJson: '{}',
          script: testPluginFile.readAsStringSync(),
          installedAt: DateTime.utc(2026, 9, 30),
        ),
      ),
    );
    final redactor = Redactor();

    await tester.pumpWidget(
      appProviderScope(
        overrides: [
          dataDirectoryProvider.overrideWithValue(Directory('/data/fmp-dev')),
          appDatabaseProvider.overrideWithValue(database),
          redactorProvider.overrideWithValue(redactor),
          logProvider.overrideWithValue(
            Log(redactor: redactor, minimumLevel: LogLevel.debug),
          ),
        ],
        child: const FmpApp(flavor: AppFlavor.dev),
      ),
    );
    // 插件在背景 isolate 載入：spawn 與 port 的訊息要真的事件迴圈，所以在
    // runAsync 裡讓它跑，直到清單出現。
    final plugin = find.text('fmp-test 1.0.0');
    for (var round = 0; round < 100 && plugin.evaluate().isEmpty; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.text('FMP Dev'), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);
    expect(find.text('/data/fmp-dev'), findsOneWidget);
    expect(plugin, findsOneWidget);
  });
}
