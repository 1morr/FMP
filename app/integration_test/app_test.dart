import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/main.dart' as app;
import 'package:integration_test/integration_test.dart';

import '../test/support/no_network.dart';

/// 在真的平台上啟動 App（plan §3）。完整閘門在四個平台各跑一次。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();

  testWidgets('the app opens its database and starts on the placeholder page', (
    tester,
  ) async {
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
  });

  testWidgets('integration tests cannot open a real HTTP connection', (
    tester,
  ) async {
    expect(() => HttpClient(), throwsA(isA<NetworkAccessInTest>()));
  });
}
