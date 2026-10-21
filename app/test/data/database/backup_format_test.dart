import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/backup_format.dart';

import '../../support/memory_database.dart';

// 表的歸類閘門（ADR 0034 §如何確認）：資料庫的每一張表必須恰好在「不帶走」或「帶走」其中
// 一份清單裡。新加的表沒有歸類就紅，由加表的 PR 決定它是裝置專屬（或帶秘密）還是要跟著備份走。

/// 清單與實際的表對不上的地方；全部對上是空的。順序與格式不影響結果。
List<String> classificationProblems({
  required Iterable<String> tables,
  required Iterable<String> excluded,
  required Iterable<String> carried,
}) {
  final actual = tables.toSet();
  final excludedSet = excluded.toSet();
  final carriedSet = carried.toSet();
  return [
    for (final table in actual)
      if (!excludedSet.contains(table) && !carriedSet.contains(table))
        'unclassified: $table',
    for (final table in excludedSet.followedBy(carriedSet))
      if (!actual.contains(table)) 'unknown: $table',
    for (final table in excludedSet.intersection(carriedSet))
      'in both lists: $table',
    if (excluded.length != excludedSet.length ||
        carried.length != carriedSet.length)
      'duplicate entries',
  ];
}

void main() {
  // 只讀表的定義，不開連線，所以不必關閉。
  final tables = AppDatabase(NativeDatabase.memory()).allTables
      .map((table) => table.actualTableName)
      .toList();

  group('table classification gate', () {
    test('every table is either excluded or carried', () {
      expect(
        classificationProblems(
          tables: tables,
          excluded: backupExcludedTables,
          carried: backupCarriedTables,
        ),
        isEmpty,
      );
    });

    test('a table missing from both lists is reported', () {
      for (final dropped in [...backupExcludedTables, ...backupCarriedTables]) {
        final problems = classificationProblems(
          tables: tables,
          excluded: backupExcludedTables.where((table) => table != dropped),
          carried: backupCarriedTables.where((table) => table != dropped),
        );
        expect(problems, ['unclassified: $dropped']);
      }
    });

    test('a new table that nobody classified is reported', () {
      expect(
        classificationProblems(
          tables: [...tables, 'brand_new_table'],
          excluded: backupExcludedTables,
          carried: backupCarriedTables,
        ),
        ['unclassified: brand_new_table'],
      );
    });

    test('a list entry for a table that does not exist is reported', () {
      expect(
        classificationProblems(
          tables: tables,
          excluded: backupExcludedTables,
          carried: [...backupCarriedTables, 'gone_table'],
        ),
        ['unknown: gone_table'],
      );
    });

    test('a table in both lists is reported', () {
      expect(
        classificationProblems(
          tables: tables,
          excluded: [...backupExcludedTables, 'tracks'],
          carried: backupCarriedTables,
        ),
        ['in both lists: tracks'],
      );
    });

    test('order and formatting of the lists do not matter', () {
      expect(
        classificationProblems(
          tables: tables.reversed,
          excluded: backupExcludedTables.reversed,
          carried: backupCarriedTables.reversed,
        ),
        isEmpty,
      );
    });
  });

  group('device columns', () {
    test('name real columns of carried tables', () async {
      final database = memoryDatabase();
      for (final MapEntry(key: table, value: columns)
          in backupDeviceColumns.entries) {
        expect(backupCarriedTables, contains(table));
        final info = await database
            .customSelect('PRAGMA table_info("$table")')
            .get();
        final names = info.map((row) => row.read<String>('name')).toSet();
        expect(names, containsAll(columns));
      }
      final info = await database
          .customSelect('PRAGMA table_info("$backupDevMarkerTable")')
          .get();
      expect(
        info.map((row) => row.read<String>('name')),
        contains(backupDevMarkerColumn),
      );
    });
  });
}
