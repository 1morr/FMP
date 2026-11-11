import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/steps.dart';

void main() {
  final out = StringBuffer();
  setUp(out.clear);

  CheckStep step(String name, {required bool ok, List<String>? ran}) =>
      CheckStep(name, () async {
        ran?.add(name);
        return ok;
      });

  test('all steps passing exits 0', () async {
    final code = await runSteps([
      step('format', ok: true),
      step('analyze', ok: true),
    ], out);
    expect(code, 0);
  });

  test('any failing step exits non-zero, and later steps still run', () async {
    final ran = <String>[];
    final code = await runSteps([
      step('format', ok: false, ran: ran),
      step('analyze', ok: true, ran: ran),
    ], out);
    expect(code, isNot(0));
    expect(ran, ['format', 'analyze']);
    expect(out.toString(), contains('FAIL format'));
  });

  test('a step that throws counts as failed', () async {
    final code = await runSteps([
      CheckStep('doc gate', () async => throw StateError('broken')),
    ], out);
    expect(code, isNot(0));
  });

  test('check.dart without --quick refuses instead of passing', () async {
    final result = await Process.run('dart', ['run', 'tool/check.dart']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('--quick'));
  });
}
