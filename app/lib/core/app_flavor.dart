/// App 的建置版本（Flutter flavor）。
///
/// 值來自 `package:flutter/services.dart` 的 `appFlavor`：`--flavor` 或
/// `pubspec.yaml` 的 `default-flavor: dev`。原生端的身分（Android
/// applicationId、Windows AUMID、單一實例鎖）由同一個 flavor 在建置時決定，
/// 見 `app/AGENTS.md` § App 身分。
enum AppFlavor {
  dev,
  prod;

  /// 解析 `appFlavor`。沒有值或不認得就拋錯：不猜是哪個版本，免得開發版
  /// 誤用正式版的資料。
  static AppFlavor parse(String? name) => switch (name) {
    'dev' => dev,
    'prod' => prod,
    _ => throw ArgumentError.value(name, 'appFlavor', 'expected dev or prod'),
  };

  /// 使用者看到的 App 名稱，與原生端的顯示名稱一致（身分測試核對）。
  String get displayName => switch (this) {
    prod => 'FMP',
    dev => 'FMP Dev',
  };
}
