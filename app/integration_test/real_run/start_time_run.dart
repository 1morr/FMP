import 'start_time.dart';

/// 票 11 的量測情境：看門狗的門檻（「開始載入到出聲」「播放中途卡住」）照
/// 四平台量到的最慢值再留餘裕（`start_time.dart`）。跑法見
/// docs/development.md〈實跑驅動〉：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/start_time_run.dart
void main() => startTimeScenario();
