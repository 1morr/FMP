import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 結束目前的 App 行程，能的話再啟動一個新的（重設資料、從備份還原之後用）。
///
/// 兩個平台的差別由 `PlatformCapabilities.restartsItself` 宣告：Windows 自己起來，Android
/// 沒有正規的「重啟自己」，行程結束後由使用者再開。呼叫之前要先把 log 寫完
/// （`LogFile.flush`），結束後不會再有機會。
abstract interface class AppRestarter {
  Future<void> restart();
}

/// 目前平台的重啟實作。`main()` 以 `AppPlatform.restarter` override；沒 override 就讀會拋錯。
final appRestarterProvider = Provider<AppRestarter>(
  (ref) => throw UnimplementedError(
    'appRestarterProvider is overridden by main() with the platform '
    'implementation',
  ),
);
