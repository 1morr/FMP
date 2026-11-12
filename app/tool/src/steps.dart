import 'dart:convert';
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

/// 跑外部指令的邊界；測試換成假的。
abstract interface class Shell {
  /// 跑指令，輸出直接接到終端機，回傳退出碼。
  Future<int> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  });

  /// 跑指令並回傳 stdout；退出碼非零時丟 [ProcessException]。
  Future<String> capture(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  });
}

class ProcessShell implements Shell {
  const ProcessShell({this.environment = const {}});

  /// 加在每個指令的環境變數上（其餘照這個行程的環境）。
  final Map<String, String> environment;

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      mode: ProcessStartMode.inheritStdio,
      environment: environment,
      // Windows 上的 flutter、dart 是 .bat。
      runInShell: Platform.isWindows,
    );
    return process.exitCode;
  }

  @override
  Future<String> capture(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      environment: environment,
      runInShell: Platform.isWindows,
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      // winpc 的錯誤訊息是 cp950；照 stdout 寬鬆解碼，免得 FormatException 蓋掉
      // 下面的 ProcessException（指令與退出碼）。
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    return result.stdout as String;
  }
}

/// 跑一個指令當作一步，退出碼 0 才算通過。
CheckStep commandStep(
  String name,
  Shell shell,
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
}) {
  return CheckStep(
    name,
    () async =>
        await shell.run(
          executable,
          arguments,
          workingDirectory: workingDirectory,
        ) ==
        0,
  );
}
