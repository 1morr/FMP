import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/plugin_bundle_gate.dart';
import '../../tool/src/steps.dart';

/// 閘門的打包產物檢查（ADR 0038、docs/app-development.md〈開發環境與閘門〉）：從原始碼重建一次插件，和提交
/// 的 `dist/` 逐位元組比對。npm 經 [Shell]，這裡換成假的，「重建」就是把
/// [_FakeShell.built] 寫進 `--outdir`。
void main() {
  late Directory app;
  late _FakeShell shell;
  final out = StringBuffer();

  setUp(() {
    out.clear();
    app = Directory.systemTemp.createTempSync('fmp_bundle_gate_');
    shell = _FakeShell();
  });
  tearDown(() => app.deleteSync(recursive: true));

  void plugin(String id, {String? committed}) {
    File('${app.path}/plugins/$id/manifest.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    if (committed != null) {
      File('${app.path}/plugins/$id/dist/plugin.js')
        ..createSync(recursive: true)
        ..writeAsStringSync(committed);
    }
  }

  Future<bool> runStep() =>
      pluginBundleStep(app: app, shell: shell, out: out).run();

  test('installs the locked tools, rebuilds into a temp dir and passes when '
      'every bundle matches', () async {
    plugin('a', committed: 'code a');
    plugin('b', committed: 'code b');
    shell.built = {'a': 'code a', 'b': 'code b'};

    expect(await runStep(), isTrue);
    expect(shell.ran, [
      'npm ci --no-audit --no-fund',
      startsWith('npm run build -- --outdir '),
    ]);
    expect(shell.ran.last, isNot(contains('${app.path}/plugins ')));
    // 重建不碰提交的產物。
    expect(
      File('${app.path}/plugins/a/dist/plugin.js').readAsStringSync(),
      'code a',
    );
  });

  test('fails and says how to fix it when a bundle is stale', () async {
    plugin('a', committed: 'code a');
    plugin('b', committed: 'old b');
    shell.built = {'a': 'code a', 'b': 'new b'};

    expect(await runStep(), isFalse);
    expect(
      out.toString(),
      allOf(
        contains('plugins/b/dist/plugin.js'),
        isNot(contains('plugins/a/dist/plugin.js')),
        contains('npm run build'),
      ),
    );
  });

  test('fails when a plugin has no committed bundle', () async {
    plugin('a');
    shell.built = {'a': 'code a'};

    expect(await runStep(), isFalse);
    expect(out.toString(), contains('plugins/a/dist/plugin.js'));
  });

  test('fails without building when npm ci fails', () async {
    plugin('a', committed: 'code a');
    shell.failing = 'npm ci';

    expect(await runStep(), isFalse);
    expect(shell.ran, ['npm ci --no-audit --no-fund']);
  });

  test('fails when the build (typecheck or esbuild) fails', () async {
    plugin('a', committed: 'code a');
    shell.failing = 'npm run build';

    expect(await runStep(), isFalse);
  });
}

class _FakeShell implements Shell {
  final ran = <String>[];
  Map<String, String> built = {};
  String? failing;

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    final command = [executable, ...arguments].join(' ');
    ran.add(command);
    expect(workingDirectory.path, endsWith('/plugins'));
    if (failing != null && command.startsWith(failing!)) return 1;
    final outdir = arguments.indexOf('--outdir');
    if (outdir >= 0) {
      built.forEach((id, code) {
        File('${arguments[outdir + 1]}/$id/dist/plugin.js')
          ..createSync(recursive: true)
          ..writeAsStringSync(code);
      });
    }
    return 0;
  }

  @override
  Future<String> capture(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) => throw UnimplementedError();
}
