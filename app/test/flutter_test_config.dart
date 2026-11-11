import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 測試零聯網（plan §3）：任何真實的 HTTP 連線都直接報錯。
///
/// 先初始化 binding，因為 flutter_test 的 binding 初始化時會換上自己的
/// `HttpOverrides`（回 400 的假 client），會蓋掉先裝的這個。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _NoNetwork();
  await testMain();
}

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw NetworkAccessInTest();
  }
}

/// 測試裡有程式想連網。`live` tag 的測試要連網時，用
/// [HttpOverrides.runWithHttpOverrides] 包一個不覆寫任何方法的
/// [HttpOverrides] 子類別，換回真的 client。
class NetworkAccessInTest implements Exception {
  @override
  String toString() =>
      'NetworkAccessInTest: tests run offline (plan §3); '
      'replay a fixture instead, or tag the test `live`.';
}
