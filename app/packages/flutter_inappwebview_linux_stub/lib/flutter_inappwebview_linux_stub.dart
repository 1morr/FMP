/// flutter_inappwebview 在 Linux 的實作：什麼都不登記（理由見 pubspec.yaml）。
///
/// `InAppWebViewPlatform.instance` 在 Linux 因此沒有值，用到就拋錯；App 在 Linux 宣告
/// 沒有登入 WebView，不會走到那裡。
abstract final class InAppWebViewLinuxStub {
  /// Flutter 的 Dart plugin registrant 在 Linux 啟動時呼叫。
  static void registerWith() {}
}
