import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 對 `Isar` 實例的成員存取。
///
/// `\s*` 是必要的：dart format 會在 `.` 前面斷行。開頭的否定判斷擋掉
/// `myIsar.` 這種以 isar 結尾的變數名，只認 `isar` / `_isar` 本身。
final _isarMemberAccessPattern = RegExp(
  r'(?<![A-Za-z0-9_])_?isar\s*\.\s*[a-z]',
);

/// 唯一允許直接碰 `Isar` 實例的地方。
///
/// 兩個 `lib/providers/database/` 的豁免不是「還沒收乾淨」，是那兩個檔案定義上
/// 就是拿著 `Isar` 實例的那一層：`database_migration.dart` 在 `Isar.open()` 之後
/// 跑遷移，`database_catalog.dart` 的 `query: (isar) => …` 閉包本身就是偵錯檢視器。
const _allowedPathPrefixes = <String>[
  'lib/data/repositories/',
];

const _allowedFiles = <String>[
  'lib/providers/database/database_catalog.dart',
  'lib/providers/database/database_migration.dart',
];

void main() {
  group('Isar boundary', () {
    test('only the data layer touches the Isar instance', () {
      final offenders = <String>[];
      var scanned = 0;

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path.endsWith('.g.dart')) continue;
        if (_isAllowed(path)) continue;

        scanned++;
        offenders.addAll(
          isarBoundaryOffenders(path, entity.readAsStringSync()),
        );
      }

      // 掃描本身要有作用 —— 路徑寫錯時 offenders 也會是空的。
      expect(scanned, greaterThan(100));
      expect(offenders, isEmpty);
    });

    test('every allowlist entry still exists', () {
      for (final path in _allowedFiles) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '$path is allowlisted but no longer exists',
        );
      }
      for (final prefix in _allowedPathPrefixes) {
        expect(
          Directory(prefix).existsSync(),
          isTrue,
          reason: '$prefix is allowlisted but no longer exists',
        );
      }
    });

    test('guard detects a service reaching for a collection', () {
      const source = '''
class ImportService {
  final Isar _isar;
  Future<void> save(Track track) async {
    await _isar.writeTxn(() => _isar.tracks.put(track));
  }
}
''';

      expect(
        isarBoundaryOffenders('lib/services/import/import_service.dart', source),
        contains(contains('import_service.dart')),
      );
    });

    test('guard detects the access even when dart format splits the line', () {
      const source = 'final rows = await _isar\n    .tracks\n    .where()\n'
          '    .findAll();';

      expect(
        isarBoundaryOffenders('lib/services/example.dart', source),
        isNotEmpty,
      );
    });

    test('guard ignores the import line for the isar package', () {
      const source = "import 'package:isar_community/isar.dart';\n"
          "export 'package:isar_community/isar.dart';\n"
          'class Thing {}';

      expect(
        isarBoundaryOffenders('lib/services/example.dart', source),
        isEmpty,
      );
    });

    test('guard ignores static members and lookalike identifiers', () {
      const source = 'final sentinel = Isar.minLong;\n'
          'final open = someIsar.tracks;\n'
          'final id = isarId;';

      expect(
        isarBoundaryOffenders('lib/services/example.dart', source),
        isEmpty,
      );
    });

    test('guard ignores a comment that merely mentions the call', () {
      const source = '// 舊版在這裡直接寫 isar.tracks.put(track)，現在走 repository。\n'
          '/// 見 `isar.playlists` 的說明。\n'
          'class Thing {}';

      expect(
        isarBoundaryOffenders('lib/services/example.dart', source),
        isEmpty,
      );
    });
  });
}

bool _isAllowed(String path) {
  return _allowedPathPrefixes.any(path.startsWith) ||
      _allowedFiles.contains(path);
}

/// 掃一個檔案，回報它直接碰 `Isar` 實例的地方。
///
/// 純函式，不碰檔案系統 —— 上面的 meta 測試用合成字串驗證這個 guard 自己
/// 抓不抓得到違規，也驗證它不會誤報。
List<String> isarBoundaryOffenders(String path, String source) {
  final offenders = <String>[];
  final lines = source.split('\n');

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    // import/export 行寫的是 `package:isar_community/isar.dart`，不是成員存取。
    if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
      continue;
    }
    // 註解裡提到某個呼叫不算違規。
    if (trimmed.startsWith('//')) continue;

    // 換行斷開的成員存取要看得到下一行，所以比對時把下一行接上；
    // 但下一行如果是註解或 import 就不接。
    final next = index + 1 < lines.length ? lines[index + 1] : '';
    final nextTrimmed = next.trimLeft();
    final joinable = !nextTrimmed.startsWith('//') &&
        !nextTrimmed.startsWith('import ') &&
        !nextTrimmed.startsWith('export ');
    final probe = joinable ? '$line\n$next' : line;

    if (_isarMemberAccessPattern.hasMatch(probe)) {
      offenders.add(
        '$path:${index + 1} reaches the Isar instance directly; '
        'add a repository method instead',
      );
    }
  }

  return offenders;
}
