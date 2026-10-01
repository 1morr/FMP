import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:fmp/platform/connectivity/connectivity.dart';

/// Android 與 Windows 共用的實作：`connectivity_plus`。
///
/// 兩個平台的差異在套件的原生端，Dart 這邊相同：
///
/// - Android：`ConnectivityManager` 的預設網路。Android 8 起 App 在背景收不到
///   變化，回到前景時要再 [check] 一次（README；由 `FmpApp` 在 `resumed` 時做）。
/// - Windows：只把 Network List Manager 判定「連得上網際網路」（NCSI）的連線
///   算成有介面（套件 `network_manager.cpp` 的 `GetConnectedAdapterIds`），所以
///   工作列顯示「沒有網際網路」時這裡也是沒有介面。
///
/// 系統的呼叫從建構子注入，測試不碰平台通道。
final class ConnectivityPlusInterfaces implements NetworkInterfaces {
  ConnectivityPlusInterfaces({required this._check, required this._changes});

  /// 以套件的單例接上系統。
  factory ConnectivityPlusInterfaces.system() {
    final connectivity = Connectivity();
    return ConnectivityPlusInterfaces(
      check: connectivity.checkConnectivity,
      changes: () => connectivity.onConnectivityChanged,
    );
  }

  final Future<List<ConnectivityResult>> Function() _check;
  final Stream<List<ConnectivityResult>> Function() _changes;

  @override
  Future<bool> check() async => (await _check()).hasConnectivity;

  /// 套件只在連線種類的清單改變時發出（`Stream.distinct`），所以這裡每一筆
  /// 都是一次介面變化。
  @override
  Stream<bool> get changes =>
      _changes().map((results) => results.hasConnectivity);
}
