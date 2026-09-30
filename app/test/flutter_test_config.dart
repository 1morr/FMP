import 'dart:async';
import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/quickjs.dart';

/// 測試預設零聯網的第二道防線（ADR 0015 §決定 3；第一道是 `dart_test.yaml`
/// 把 `live` tag 設成跳過）。
///
/// 建立真實 [HttpClient] 直接拋 [StateError]。要聯網的測試在自己的 zone 以
/// `HttpOverrides.runWithHttpOverrides` 放行，見
/// `.trellis/spec/app/testing/index.md`。
///
/// 先初始化測試 binding：它初始化時會把 [HttpOverrides.global] 換成
/// flutter_test 自己的假 client（回 400），順序反過來這道防線就被蓋掉。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = NoNetworkHttpOverrides();
  // 插件執行環境的測試要真的跑 QuickJS（見 support/quickjs.dart）。
  loadQuickJsForTests();
  // golden（alchemist）只比 CI 版：文字畫成色塊、不畫陰影，Windows 產生的檔
  // 在 CI 的 Linux 上也對得上。平台版（真的字）各平台的字形不同，不提交也不跑。
  await AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
    ),
    run: () async => testMain(),
  );
}

/// 建立 [HttpClient] 就拋錯的 [HttpOverrides]。
final class NoNetworkHttpOverrides extends HttpOverrides {
  /// 錯誤訊息的開頭，測試以它確認擋下的是這道防線。
  static const message = 'Real network access is blocked in tests';

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw StateError(
      '$message (test/flutter_test_config.dart). Inject a fake client, or '
      'allow it in the test zone with HttpOverrides.runWithHttpOverrides.',
    );
  }
}
