import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/matching/normalize.dart';
import 'package:fmp/core/matching/ts_characters.g.dart';

import '../../../tool/opencc/generate_ts_characters.dart';

/// 繁簡字表（M4 design §8.2）：產生檔對得上釘住的 OpenCC 副本，字對與折疊的性質。
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  final table = read('tool/opencc/TSCharacters.txt');
  final license = read('tool/opencc/LICENSE');

  test('the committed table equals a fresh generation from tool/opencc', () {
    expect(
      read(outputPath),
      generateTsCharacters(table: table, license: license),
      reason: 'run `dart run tool/opencc/generate_ts_characters.dart`',
    );
  });

  test('the generated header names the pinned OpenCC commit', () {
    final commit = RegExp(
      r'^# FMP: commit ([0-9a-f]{40})',
      multiLine: true,
    ).firstMatch(table)!.group(1);
    expect(openCcCommit, commit);
    expect(read(outputPath), contains('commit $commit'));
  });

  test('the generator refuses a copy without the commit header', () {
    final withoutHeader = table
        .split('\n')
        .where((line) => !line.startsWith('# FMP:'))
        .join('\n');
    expect(
      () => generateTsCharacters(table: withoutHeader, license: license),
      throwsFormatException,
    );
  });

  test('the generator refuses a line that is not one character to one', () {
    expect(
      () => generateTsCharacters(table: '$table萬萬\t万\n', license: license),
      throwsFormatException,
    );
  });

  test('the generator refuses a duplicate key and a cycle', () {
    expect(table, contains('\n萬\t'));
    for (final extra in ['萬\t万\n', '苎\t薴\n']) {
      expect(
        () => generateTsCharacters(table: '$table$extra', license: license),
        throwsFormatException,
        reason: extra,
      );
    }
    // 對照組：一行新的、不重複也不成環的字對照樣接受。
    expect(
      generateTsCharacters(table: '$table𠀀\t一\n', license: license),
      contains('0x20000: 0x4E00'),
    );
  });

  test('known pairs fold to the simplified character', () {
    const pairs = {'週': '周', '倫': '伦', '乾': '干', '著': '着'};
    for (final MapEntry(:key, :value) in pairs.entries) {
      expect(
        tsCharacters[key.runes.single],
        value.runes.single,
        reason: '$key → $value',
      );
    }
    expect(foldText('週杰倫'), '周杰伦');
    expect(foldText('乾隆'), '干隆');
    expect(foldText('想著你'), '想着你');
  });

  test('a chain is followed to its end (薴→苧→苎)', () {
    expect(foldText('薴'), '苎');
    expect(foldText('苧'), '苎');
  });

  test('simplified text passes through unchanged', () {
    const simplified = '周杰伦 后来 说好不哭 干杯 想着你 爱情转移 七里香 发现 里面';
    expect(foldText(simplified), simplified);
  });

  test('folding twice equals folding once: no value is also a key', () {
    final both = tsCharacters.values.toSet().intersection(
      tsCharacters.keys.toSet(),
    );
    expect(both, isEmpty);
  });

  test('the license text is OpenCC\'s Apache-2.0', () {
    expect(openCcLicense, startsWith('Apache License\nVersion 2.0'));
    expect(openCcLicense, license.trimRight());
  });
}
