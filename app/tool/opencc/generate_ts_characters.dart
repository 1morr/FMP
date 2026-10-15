/// 由 OpenCC 的 `TSCharacters.txt`（同目錄、釘 commit 的副本）產生
/// `lib/core/matching/ts_characters.g.dart`：匹配用的繁→簡字級對照與 OpenCC 的
/// 授權全文（M4 design §8.2）。不連網，只讀這個目錄。
///
/// 在 `app/` 執行：`dart run tool/opencc/generate_ts_characters.dart`，產生檔要提交；
/// `test/core/matching/ts_characters_test.dart` 斷言重新產生的內容等於已提交的。
///
/// 比對只需要兩邊折成同一個字，不需要正確的簡體文字，所以：
/// - 多個候選取第一個；第一個就是自己的（OpenCC 標 `@tofu-risk` 的罕用字等）不列；
/// - 對照串接時一路走到底（`薴→苧`、`苧→苎` 寫成 `薴→苎`），折一次和折兩次一樣；
/// - 另加 [_supplement]。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// 字表沒有、但比對需要的字對：鍵 → 值，各一個字。
///
/// `著`：OpenCC 的 t2s 不在字表折它（`著` 也是簡體字），台灣的 `著` 是在 tw2s 由
/// `TWVariants.txt` 的 `着	著` 反查成 `着`。歌名常見 `想著你`／`想着你`，Dice 的
/// 雙字組完全不重疊，所以在這裡補上。
const _supplement = {'著': '着'};

const _tablePath = 'tool/opencc/TSCharacters.txt';
const _licensePath = 'tool/opencc/LICENSE';
const outputPath = 'lib/core/matching/ts_characters.g.dart';

final _commitLine = RegExp(r'^# FMP: commit ([0-9a-f]{40})', multiLine: true);

/// 產生檔的完整內容。[table] 是 `TSCharacters.txt` 的副本（含 `# FMP:` 檔頭），
/// [license] 是 OpenCC 的 `LICENSE`；兩者的換行可以是 CRLF。
String generateTsCharacters({required String table, required String license}) {
  table = table.replaceAll('\r\n', '\n');
  license = license.replaceAll('\r\n', '\n').trimRight();
  final commit = _commitLine.firstMatch(table)?.group(1);
  if (commit == null) {
    throw const FormatException('TSCharacters.txt: missing "# FMP: commit"');
  }

  final firstCandidate = <int, int>{};
  for (final (index, line) in table.split('\n').indexed) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final columns = line.split('\t');
    if (columns.length != 2) {
      throw FormatException('TSCharacters.txt:${index + 1}: expected one tab');
    }
    final key = _singleRune(columns[0], index);
    final value = _singleRune(columns[1].split(' ').first, index);
    if (firstCandidate.containsKey(key)) {
      throw FormatException('TSCharacters.txt:${index + 1}: duplicate key');
    }
    if (key != value) firstCandidate[key] = value;
  }
  for (final MapEntry(:key, :value) in _supplement.entries) {
    firstCandidate[key.runes.single] = value.runes.single;
  }

  final resolved = <int, int>{
    for (final key in firstCandidate.keys) key: _resolve(key, firstCandidate),
  };
  final keys = resolved.keys.toList()..sort();

  final buffer = StringBuffer()
    ..writeln('// 產生檔，不要手改：tool/opencc/generate_ts_characters.dart')
    ..writeln('// 來源：OpenCC data/dictionary/TSCharacters.txt，commit $commit')
    ..writeln('// （tool/opencc/TSCharacters.txt 的副本），授權 Apache-2.0。')
    ..writeln()
    ..writeln('/// 字表的來源 commit（BYVoid/OpenCC）。')
    ..writeln("const openCcCommit = '$commit';")
    ..writeln()
    ..writeln('/// 繁→簡的字級對照，碼位對碼位（M4 design §8.2）。')
    ..writeln('const tsCharacters = <int, int>{');
  for (final key in keys) {
    final value = resolved[key]!;
    buffer.writeln(
      '  ${_hex(key)}: ${_hex(value)}, '
      '// ${String.fromCharCode(key)}→${String.fromCharCode(value)}',
    );
  }
  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// OpenCC 的授權全文（`LicenseRegistry` 登記，`lib/app/licenses.dart`）。')
    ..writeln('// ignore: fmp_lints/fmp_url_literal — 授權全文裡的網址，不是請求的端點')
    ..writeln("const openCcLicense = r'''")
    ..write(license)
    ..writeln("''';");
  return buffer.toString();
}

int _singleRune(String text, int index) {
  final runes = text.runes;
  if (runes.length != 1) {
    throw FormatException(
      'TSCharacters.txt:${index + 1}: "$text" is not one character',
    );
  }
  return runes.single;
}

int _resolve(int key, Map<int, int> table) {
  final seen = {key};
  var current = table[key]!;
  while (table.containsKey(current)) {
    if (!seen.add(current)) {
      throw FormatException('TSCharacters.txt: cycle at ${_hex(key)}');
    }
    current = table[current]!;
  }
  return current;
}

String _hex(int rune) =>
    '0x${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}';

void main() {
  final appRoot = p.dirname(p.dirname(p.dirname(p.fromUri(Platform.script))));
  String read(String relative) =>
      File(p.join(appRoot, p.joinAll(relative.split('/')))).readAsStringSync();
  final output = generateTsCharacters(
    table: read(_tablePath),
    license: read(_licensePath),
  );
  File(p.join(appRoot, p.joinAll(outputPath.split('/'))))
      .writeAsStringSync(output);
  stdout.writeln('Wrote $outputPath');
}
