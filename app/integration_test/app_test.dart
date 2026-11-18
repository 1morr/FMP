import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/main.dart' as app;
import 'package:fmp/platform/app_data_directory.dart';
import 'package:fmp/platform/log_directory.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/no_network.dart';
import '../test/support/scratch_data.dart';

/// 在真的平台上啟動 App（architecture〈測試策略〉）。完整閘門在四個平台各跑一次。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  testWidgets('the app opens its database, writes its log and starts on the '
      'home page', (tester) async {
    // log 的時間到微秒，比對時往前留 1 秒。
    final startedAt = DateTime.now().toUtc().subtract(
      const Duration(seconds: 1),
    );

    // 資料放在閘門給的隔離目錄、先清空，不寫擁有者 dev 版的資料庫與 log
    // （docs/development.md〈平台〉）。
    await useScratchData(
      howToRun:
          'integration_test/app_test.dart starts the real app: pass '
          '--dart-define=FMP_SCRATCH_DATA=fmp-integration-test so it does not '
          "write the dev app's data (docs/development.md〈平台〉).",
    );
    await app.main();
    await tester.pumpAndSettle();

    // App 打開在外殼的首頁（票 05）。
    expect(find.byType(HomePage), findsOneWidget);

    // 資料庫開在隔離目錄裡由 platform/ 給的檔案上，是新建的（票 07、10）。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FmpApp)),
    );
    final database = container.read(appDatabaseProvider)!;
    expect(await database.storedSchemaVersion(), database.schemaVersion);

    // 這次啟動的那一行寫進了平台給的 log 目錄。
    final startedLine = await tester.runAsync(() async {
      final file = File(
        '${logDirectory(await appDataDirectory()).path}/${Log.fileName}',
      );
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        if (file.existsSync()) {
          for (final line in file.readAsLinesSync().reversed) {
            final time = DateTime.tryParse(line.split(' ').first);
            if (line.endsWith(' INFO App started') &&
                time != null &&
                !time.isBefore(startedAt)) {
              return line;
            }
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    });
    expect(startedLine, isNotNull, reason: 'no fresh "App started" in fmp.log');
  });

  testWidgets('integration tests cannot open a real HTTP connection', (
    tester,
  ) async {
    expect(() => HttpClient(), throwsA(isA<NetworkAccessInTest>()));
  });
}
