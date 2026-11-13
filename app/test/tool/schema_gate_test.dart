import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/schema_gate.dart';
import '../../tool/src/steps.dart';

/// 閘門的 schema 快照檢查（architecture〈測試策略〉）：程式裡的 schema 要跟最新版本的快照
/// 一字不差。`drift_dev schema dump` 經 [Shell]，這裡換成假的，直接寫出
/// 「目前的 schema」。
void main() {
  late Directory app;
  late Directory snapshots;
  late _FakeShell shell;
  final out = StringBuffer();

  setUp(() {
    out.clear();
    app = Directory.systemTemp.createTempSync('fmp_schema_gate_');
    snapshots = Directory('${app.path}/drift_schemas/app_database')
      ..createSync(recursive: true);
    shell = _FakeShell();
  });
  tearDown(() => app.deleteSync(recursive: true));

  void snapshot(int version, String content) =>
      File('${snapshots.path}/drift_schema_v$version.json')
          .writeAsStringSync(content);

  Future<bool> runStep() =>
      schemaSnapshotStep(app: app, shell: shell, out: out).run();

  test('passes when the code matches the latest snapshot', () async {
    snapshot(1, '{"entities": []}');
    shell.currentSchema = '{"entities": []}';

    expect(await runStep(), isTrue);
    expect(shell.ran, [
      startsWith('dart run drift_dev schema dump lib/data/database.dart '),
    ]);
  });

  test('fails when the code differs from the latest snapshot, and says how '
      'to make a new one', () async {
    snapshot(1, '{"entities": []}');
    shell.currentSchema = '{"entities": [{"name": "tracks"}]}';

    expect(await runStep(), isFalse);
    expect(
      out.toString(),
      allOf(
        contains('drift_schemas/app_database/drift_schema_v1.json'),
        contains('dart run drift_dev make-migrations'),
      ),
    );
  });

  test('compares with the highest version, not the last one by name', () async {
    snapshot(2, '{"v": 2}');
    snapshot(10, '{"v": 10}');
    shell.currentSchema = '{"v": 10}';

    expect(await runStep(), isTrue);

    shell.currentSchema = '{"v": 2}';
    expect(await runStep(), isFalse);
  });

  test('fails when there is no snapshot yet', () async {
    shell.currentSchema = '{"entities": []}';

    expect(await runStep(), isFalse);
    expect(out.toString(), contains('dart run drift_dev make-migrations'));
  });

  test('fails when the schema dump fails', () async {
    snapshot(1, '{"entities": []}');
    shell.dumpExitCode = 1;

    expect(await runStep(), isFalse);
  });
}

class _FakeShell implements Shell {
  final ran = <String>[];
  String currentSchema = '';
  int dumpExitCode = 0;

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    ran.add([executable, ...arguments].join(' '));
    if (dumpExitCode == 0) {
      File(arguments.last).writeAsStringSync(currentSchema);
    }
    return dumpExitCode;
  }

  @override
  Future<String> capture(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) => throw UnimplementedError();
}
