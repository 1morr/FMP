import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/gate.dart';
import '../../tool/src/steps.dart';

/// `tool/check.dart` 組出的步驟（plan §4）。只看步驟名稱，不執行。
void main() {
  final app = Directory.current;

  List<String> names({required bool quick}) => [
    for (final step in gateSteps(
      quick: quick,
      app: app,
      shell: const ProcessShell(),
      out: StringBuffer(),
    ))
      step.name,
  ];

  const quickSteps = [
    'i18n (slang)',
    'codegen (build_runner)',
    'format',
    'analyze',
    'test',
    'schema snapshot (drift)',
    'doc gate',
  ];

  test('--quick runs only the quick steps', () {
    expect(names(quick: true), quickSteps);
  });

  test('the full gate runs the quick steps first, then builds and '
      'integration tests on all four platforms', () {
    final full = names(quick: false);

    expect(full.take(quickSteps.length), quickSteps);
    expect(full.skip(quickSteps.length), [
      'build macos',
      'build ios',
      'build android',
      'build windows',
      'integration_test macos: integration_test/app_test.dart',
      'integration_test ios: integration_test/app_test.dart',
      'integration_test android: integration_test/app_test.dart',
      'integration_test windows: integration_test/app_test.dart',
    ]);
  });
}
