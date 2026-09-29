import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  await testMain();
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
