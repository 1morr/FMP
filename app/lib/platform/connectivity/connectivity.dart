import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 系統有沒有網路介面（ADR 0016 §決定 6、ADR 0009 §決定 6）。
///
/// 只回答「有沒有介面」：有介面不代表能上網（`connectivity_plus` 的 README
/// 也這樣說），能不能上網由網路層以請求結果判斷（`network_status.dart`）。
/// 實作只有 Android 與 Windows，由 `platform.dart` 組裝。
abstract interface class NetworkInterfaces {
  /// 現在有沒有網路介面。
  Future<bool> check();

  /// 每次系統回報網路介面改變時發出一次，值是改變後有沒有介面。介面換了
  /// （Wi-Fi 換成行動網路）而仍然有介面時也發出 `true`：網路層把它當成
  /// 「介面變化」。
  Stream<bool> get changes;
}

/// 平台的網路介面實作；平台沒有這個能力時為 `null`。`main()` 以
/// `AppPlatform.networkInterfaces` override；沒 override 就讀會拋錯。
final networkInterfacesProvider = Provider<NetworkInterfaces?>(
  (ref) => throw UnimplementedError(
    'networkInterfacesProvider is overridden by main() with the platform '
    'implementation',
  ),
);
