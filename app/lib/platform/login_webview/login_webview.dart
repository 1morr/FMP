import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Windows 的 WebView2 使用者資料在資料目錄下的這個子目錄（ADR 0029 §決定 9）：dev 與
/// prod 跟著資料目錄分開，「重設資料」刪資料目錄時一起刪掉。
const loginWebViewDirectoryName = 'webview';

/// 登入 WebView 要開的頁（manifest 的 `login.webView.url`）。
@immutable
final class LoginWebViewSpec {
  const LoginWebViewSpec({required this.url});

  final Uri url;
}

/// App 內網頁登入的 WebView（ADR 0029 §決定 9，design §6.4）。實作有 Android 與 Windows
/// （`flutter_inappwebview_login.dart`），由 `platform.dart` 組裝。
///
/// 只給登入用：WebView 的 cookie 是登入頁設的，取出後交給插件驗證；它們不經 App 的網路層，
/// 呼叫端不得把值寫進 log。UA 由實作決定（讓嵌入的 WebView 像一般瀏覽器是平台的事），不由
/// 插件給。
abstract interface class LoginWebView {
  /// 開 [spec] 的頁。每一頁載入完成時呼叫 [onLoadStop]（呼叫端在那時讀 cookie，完成與否
  /// 由呼叫端判斷，這一層不看網址也不看 cookie）。WebView 準備不起來（例如 Windows 沒有
  /// WebView2 runtime）時呼叫 [onError]。
  ///
  /// 要重新開一個 WebView（[reset] 之後）就以新的 `Key` 重建回傳的 widget。
  Widget build(
    LoginWebViewSpec spec, {
    required VoidCallback onLoadStop,
    required void Function(Object error, StackTrace stackTrace) onError,
  });

  /// [hosts] 這些網址讀得到的 cookie（名稱 → 值）。同名時前面的網址優先。只回這些網址
  /// 讀得到的：別的網域的同名 cookie 不在裡面。
  Future<Map<String, String>> cookies(List<Uri> hosts);

  /// 刪掉登入 WebView 的全部 cookie（登出、移除插件、重設資料）。平台可能靜默刪不掉，呼叫端
  /// 用 [cookies] 確認。沒有 cookie 時什麼都不做，可重複呼叫。
  Future<void> clearAll();

  /// 丟掉 WebView 的執行環境，下一個 [build] 重新建立（跳轉卡住時的重試）。呼叫前先把
  /// [build] 回傳的 widget 拿掉。Windows 重建 WebView2 的環境（同一個使用者資料目錄，登入
  /// 狀態留著）；Android 沒有環境可重建，什麼都不做（重建 widget 就是新的 WebView）。
  Future<void> reset();
}

/// 平台的登入 WebView；平台沒有這個能力（`PlatformCapabilities.loginWebView` 為假）時為
/// `null`。`main()` 以 `AppPlatform.loginWebView` override；沒 override 就讀會拋錯。
final loginWebViewProvider = Provider<LoginWebView?>(
  (ref) => throw UnimplementedError(
    'loginWebViewProvider is overridden by main() with the platform '
    'implementation',
  ),
);
