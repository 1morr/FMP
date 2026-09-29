import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';

import '../plugin_harness.dart';

void main() {
  test('reads the manifest from the header without running the script', () {
    // 腳本本身語法錯誤也讀得到 manifest：標頭的解析不執行腳本。
    final file = PluginFile.parse(pluginSource('this is not javascript ((('));

    expect(file.manifest.id, 'plugin-a');
    expect(file.manifestJson, startsWith('{'));
    expect(file.manifestJson, endsWith('}'));
    expect(file.source, contains('this is not javascript'));
  });

  test('reads the test plugin', () {
    final file = PluginFile.parse(testPluginFile.readAsStringSync());

    expect(file.manifest.id, 'fmp-test');
    expect(file.manifest.allowedHosts, isEmpty);
  });

  test('allows a BOM and leading blank lines', () {
    final file = PluginFile.decode(
      Uint8List.fromList([
        0xEF, 0xBB, 0xBF, //
        ...utf8.encode('\n\n${pluginSource('')}'),
      ]),
    );

    expect(file.manifest.id, 'plugin-a');
    expect(file.source, isNot(startsWith('﻿')));
  });

  group('rejects as ParseError', () {
    for (final (description, source) in [
      ('no header', 'export function search() {}'),
      ('code before the header', '// hi\n${pluginSource('')}'),
      (
        'a header without its end',
        '/* ==FMP Plugin==\n{"id": "a"}\n*/ export function search() {}',
      ),
      (
        'a manifest containing */',
        pluginSource('').replaceFirst('"Plugin plugin-a"', '"a */ b"'),
      ),
    ]) {
      test(description, () {
        expect(() => PluginFile.parse(source), throwsA(isA<ParseError>()));
      });
    }

    test('bytes that are not UTF-8', () {
      expect(
        () => PluginFile.decode(Uint8List.fromList([0xFF, 0xFE, 0x00])),
        throwsA(isA<ParseError>()),
      );
    });
  });

  test('manifest errors come through unchanged', () {
    expect(
      () => PluginFile.parse(
        pluginSource('').replaceFirst('"apiVersion": 1', '"apiVersion": 9'),
      ),
      throwsA(isA<Unsupported>()),
    );
  });
}
