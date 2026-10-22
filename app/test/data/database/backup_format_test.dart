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
    // 閘門自己的雙向驗證：單欄主鍵算唯一、一般欄位與複合主鍵的欄位不算。
    test('unique column detection tells keys from other columns', () async {
      final database = memoryDatabase();
      final settings = await _uniqueColumns(database, 'source_settings');
      expect(settings, contains('plugin_id'));
      expect(settings, isNot(contains('browse_as_logged_in')));
      final origins = await _uniqueColumns(database, 'track_origins');
      expect(origins, isNot(contains('track_key')));
      expect(origins, isNot(contains('origin_plugin_id')));
    });

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
      for (final MapEntry(key: table, value: spec)
          in backupDeviceKeyedColumns.entries) {
        expect(backupCarriedTables, contains(table));
        final info = await database
            .customSelect('PRAGMA table_info("$table")')
            .get();
        final names = info.map((row) => row.read<String>('name')).toSet();
        expect(names, containsAll([spec.key, ...spec.columns]));
        // 鍵要能唯一對應一列：是主鍵，或有單欄的 unique index。
        final unique = await _uniqueColumns(database, table);
        expect(unique, contains(spec.key), reason: '$table.${spec.key}');
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

/// [table] 裡能唯一對應一列的欄位：單欄主鍵，或單欄 unique index 的欄位。
Future<Set<String>> _uniqueColumns(AppDatabase database, String table) async {
  final info = await database.customSelect('PRAGMA table_info("$table")').get();
  final keyColumns = info.where((row) => row.read<int>('pk') > 0).toList();
  final unique = <String>{
    if (keyColumns.length == 1) keyColumns.single.read<String>('name'),
  };
  for (final index
      in await database.customSelect('PRAGMA index_list("$table")').get()) {
    if (index.read<int>('unique') != 1) continue;
    final cols = await database
        .customSelect('PRAGMA index_info("${index.read<String>('name')}")')
        .get();
    if (cols.length == 1) unique.add(cols.single.read<String>('name'));
  }
  return unique;
}
