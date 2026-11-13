import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/main.dart' as app;
import 'package:fmp/platform/log_directory.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/no_network.dart';

/// 在真的平台上啟動 App（architecture〈測試策略〉）。完整閘門在四個平台各跑一次。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  testWidgets('the app opens its database, writes its log and starts on the '
      'placeholder page', (tester) async {
    // log 的時間到微秒，比對時往前留 1 秒。
    final startedAt = DateTime.now().toUtc().subtract(
      const Duration(seconds: 1),
    );

    await app.main();
    await tester.pumpAndSettle();

    // 字串跟裝置語言走，所以用目前語言的翻譯比對。
    expect(find.text(t.app.name), findsOneWidget);
    expect(find.text(t.placeholder.subtitle), findsOneWidget);

    // 資料庫開在這個平台由 platform/ 給的檔案上（票 07）。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FmpApp)),
    );
    final database = container.read(appDatabaseProvider);
    expect(await database.storedSchemaVersion(), 1);

    // 這次啟動的那一行寫進了平台給的 log 目錄（之前的執行可能留下舊的行）。
    final startedLine = await tester.runAsync(() async {
      final file = File('${(await logDirectory()).path}/${Log.fileName}');
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
