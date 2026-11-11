import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// 在真的平台上啟動 App（plan §3）。完整閘門在四個平台各跑一次。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app starts on the placeholder page', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 字串跟裝置語言走，所以用目前語言的翻譯比對。
    expect(find.text(t.app.name), findsOneWidget);
    expect(find.text(t.placeholder.subtitle), findsOneWidget);
  });
}
