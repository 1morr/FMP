import 'dart:io';

import 'src/gate.dart';
import 'src/steps.dart' show runSteps;

/// 新版的閘門（plan §4）。在 `app/` 裡跑：
///
///     dart run tool/check.dart --quick
///     dart run tool/check.dart
///
/// `--quick`：產生 i18n、format、analyze、單元測試、文件閘門。
/// 完整版：quick 之後在 macOS、iOS 模擬器、Android 模擬器、Windows（`winpc`）
/// 建置並跑 integration_test；碰共用裝置的步驟先拿跨 worktree 的鎖
/// （`DeviceLock`）。步驟見 [gateSteps]，前置條件與鎖見 plan §4。
Future<void> main(List<String> args) async {
  final app = File.fromUri(Platform.script).parent.parent;
  final steps = gateSteps(
    quick: args.contains('--quick'),
    app: app,
    shell: gateShell(),
    out: stdout,
  );
  exit(await runSteps(steps, stdout));
}
