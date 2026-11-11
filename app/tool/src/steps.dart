import 'dart:io';

/// 閘門的一步；回傳 true 代表通過。
class CheckStep {
  CheckStep(this.name, this.run);

  final String name;
  final Future<bool> Function() run;
}

/// 依序跑完每一步（前面失敗也照跑，一次看到全部問題），最後印出結果。
/// 全部通過回 0，否則回 1。
Future<int> runSteps(List<CheckStep> steps, StringSink out) async {
  final failed = <String>[];
  for (final step in steps) {
    out.writeln('\n==> ${step.name}');
    bool ok;
    try {
      ok = await step.run();
    } catch (error) {
      out.writeln(error);
      ok = false;
    }
    if (!ok) failed.add(step.name);
  }

  out.writeln();
  for (final step in steps) {
    out.writeln('${failed.contains(step.name) ? 'FAIL' : 'ok  '} ${step.name}');
  }
  return failed.isEmpty ? 0 : 1;
}

/// 跑一個指令，輸出直接接到終端機。
CheckStep commandStep(
  String name,
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
}) {
  return CheckStep(name, () async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      mode: ProcessStartMode.inheritStdio,
      // Windows 上的 flutter、dart 是 .bat。
      runInShell: Platform.isWindows,
    );
    return await process.exitCode == 0;
  });
}
