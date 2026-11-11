import 'dart:io';

/// 測試零聯網（plan §3）：裝上後任何真實的 HTTP 連線都直接報錯。
///
/// `test/` 由 `flutter_test_config.dart` 裝；`integration_test/` 不吃那個設定，
/// 每個檔在 `main()` 裡自己呼叫（`test/architecture/integration_test_guard_test.dart`
/// 守著）。要在 binding 初始化之後呼叫：flutter_test 的 binding 初始化時會換上
/// 自己的 `HttpOverrides`（回 400 的假 client），會蓋掉先裝的這個。
void installNoNetworkGuard() {
  HttpOverrides.global = _NoNetwork();
}

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw NetworkAccessInTest();
  }
}

/// 真的 [HttpClient]，給 `live` tag 的測試用（例如交給 dio 的
/// `IOHttpClientAdapter(createHttpClient: realHttpClient)`）。在只屬於這次
/// 建立的 zone 裡換回 dart:io 預設的行為，不動全域的防線：插件宿主的網路
/// 請求從 fjs 的 bridge 回到 Dart，不一定跑在測試的 zone 裡。
HttpClient realHttpClient() =>
    HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealNetwork());

class _RealNetwork extends HttpOverrides {}

/// 測試裡有程式想連網。`live` tag 的測試要連網時用 [realHttpClient]。
class NetworkAccessInTest implements Exception {
  @override
  String toString() =>
      'NetworkAccessInTest: tests run offline (plan §3); '
      'replay a fixture instead, or tag the test `live`.';
}
