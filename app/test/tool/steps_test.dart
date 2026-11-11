import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/gate.dart';
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

  test('commands the gate runs start any adb server with mDNS off '
      '(ADB_MDNS=0, brief fact K15)', () async {
    final echoed = await gateShell().capture('sh', [
      '-c',
      r'echo "$ADB_MDNS"',
    ], workingDirectory: Directory.current);

    expect(echoed.trim(), '0');
  });
}
