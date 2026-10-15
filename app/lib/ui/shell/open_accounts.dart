import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 巢狀導覽裡的頁面（歌單詳情的「登入」）請外殼換到設定頁的「帳號」區塊。
///
/// 外殼在 `initState` 把 [handler] 接上（同 `SettingsBack`：不是會變的狀態，所以不是
/// Notifier）；沒有外殼時（單獨測一個頁面）什麼都不做。[pluginId] 是要登入的音源，目前帳號
/// 區塊每個音源一張卡、整個區塊一眼看得到，所以外殼還不用它定位。
final openAccountsProvider = Provider<OpenAccounts>((ref) => OpenAccounts());

final class OpenAccounts {
  void Function(String pluginId)? handler;

  void call(String pluginId) => handler?.call(pluginId);
}
