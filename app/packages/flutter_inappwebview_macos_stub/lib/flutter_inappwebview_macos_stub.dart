/// flutter_inappwebview 在 macOS 的實作：什麼都不登記（理由見 pubspec.yaml）。
///
/// `InAppWebViewPlatform.instance` 在 macOS 因此沒有值，用到就拋錯；App 在 macOS 宣告
/// 沒有登入 WebView，不會走到那裡。
abstract final class InAppWebViewMacosStub {
  /// Flutter 的 Dart plugin registrant 在 macOS 啟動時呼叫。
  static void registerWith() {}
}
