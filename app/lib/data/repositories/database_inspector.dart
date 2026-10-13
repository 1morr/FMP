import 'dart:typed_data';

import 'package:drift/drift.dart';

import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';

/// 一張表與它的筆數。
typedef TableCount = ({String name, int count});

/// 表的一頁：[columns] 是欄位名，每一列的值與它對齊；值已經過遮蔽，`null` 是 SQL 的 NULL。
typedef TablePage = ({
  List<String> columns,
  List<List<String?>> rows,
  int total,
});

/// 一筆外鍵違規（`PRAGMA foreign_key_check` 的一列）。
typedef ForeignKeyViolation = ({String table, int? rowId, String parent});

/// [DatabaseInspector.check] 的報告。
final class DatabaseCheckReport {
  const DatabaseCheckReport({
    required this.integrityMessages,
    required this.foreignKeyViolations,
    required this.orphanTracks,
  });

  /// `PRAGMA integrity_check` 回報的問題；沒問題時是空的（SQLite 回單一個 `ok`）。
  final List<String> integrityMessages;
  final List<ForeignKeyViolation> foreignKeyViolations;

  /// 啟動維護清單會刪的孤兒曲目數；它不是損壞，只顯示。
  final int orphanTracks;

  /// 資料庫本身有問題（孤兒曲目不算：它由啟動維護清單處理）。
  bool get hasProblems =>
      integrityMessages.isNotEmpty || foreignKeyViolations.isNotEmpty;
}

/// Debug 頁「資料庫」區塊的唯讀查詢（ADR 0025 §決定 8）：表與筆數、分頁瀏覽、檢查。
/// 不寫任何東西。
///
/// 瀏覽的值一律經 [Redactor]；`plugin_storage` 的 `value` 欄整欄遮蔽（插件的 storage
/// 可能放 cookie 一類的東西）。憑證本來就不在資料庫（ADR 0012）。`installed_plugins` 的
/// `script` 只顯示長度：它是公開的插件原始碼（YouTube 約 800 KB），整份跑遮蔽要上百毫秒，
/// 開表會卡。
final class DatabaseInspector {
  DatabaseInspector(this._database, this._redactor);

  /// 每頁的列數。
  static const pageSize = 50;

  final AppDatabase _database;
  final Redactor _redactor;

  /// 整欄遮蔽的欄位：表名 → 欄名。
  static const maskedColumns = {
    'plugin_storage': {'value'},
  };

  /// 只顯示長度的欄位：表名 → 欄名。
  static const lengthOnlyColumns = {
    'installed_plugins': {'script'},
  };

  Future<List<TableCount>> tables() async {
    final result = <TableCount>[];
    for (final table in _database.allTables) {
      final name = table.actualTableName;
      result.add((name: name, count: await _count(name)));
    }
    return result;
  }

  Future<int> _count(String name) async {
    final row = await _database
        .customSelect('SELECT COUNT(*) AS n FROM "$name"')
        .getSingle();
    return row.read<int>('n');
  }

  /// 表 [name] 的第 [page] 頁（從 0 起）。[name] 不在 `allTables` 裡丟出
  /// [ArgumentError]：表名會進 SQL 字串，只認資料庫自己的表。
  ///
  /// 讀的是儲存的原值（時間是 epoch 毫秒、列舉是字串），不經型別轉換器。
  Future<TablePage> rows(String name, int page) async {
    if (page < 0) throw RangeError.value(page, 'page');
    final known = _database.allTables.any(
      (table) => table.actualTableName == name,
    );
    if (!known) throw ArgumentError.value(name, 'name', 'not a table');
    final total = await _count(name);
    final result = await _database
        .customSelect(
          'SELECT * FROM "$name" LIMIT $pageSize OFFSET ${page * pageSize}',
        )
        .get();
    final masked = maskedColumns[name] ?? const <String>{};
    final lengthOnly = lengthOnlyColumns[name] ?? const <String>{};
    final columns = result.isEmpty
        ? [
            for (final row
                in await _database
                    .customSelect('PRAGMA table_info("$name")')
                    .get())
              row.read<String>('name'),
          ]
        : result.first.data.keys.toList();
    return (
      columns: columns,
      rows: [
        for (final row in result)
          [
            for (final column in columns)
              masked.contains(column)
                  ? redactedValue
                  : lengthOnly.contains(column)
                  ? _length(row.data[column])
                  : _show(row.data[column]),
          ],
      ],
      total: total,
    );
  }

  static String? _length(Object? value) => switch (value) {
    null => null,
    String(:final length) => '<$length characters>',
    Uint8List(:final length) => '<blob $length bytes>',
    _ => '<${value.runtimeType}>',
  };

  String? _show(Object? value) => switch (value) {
    null => null,
    Uint8List(:final length) => '<blob $length bytes>',
    _ => _redactor.redact('$value'),
  };

  Future<DatabaseCheckReport> check() async {
    final integrity = await _database
        .customSelect('PRAGMA integrity_check')
        .get();
    final messages = [
      for (final row in integrity)
        if (row.read<String>('integrity_check') != 'ok')
          _redactor.redact(row.read<String>('integrity_check')),
    ];
    final foreignKeys = await _database
        .customSelect('PRAGMA foreign_key_check')
        .get();
    return DatabaseCheckReport(
      integrityMessages: messages,
      foreignKeyViolations: [
        for (final row in foreignKeys)
          (
            table: row.read<String>('table'),
            rowId: row.readNullable<int>('rowid'),
            parent: row.read<String>('parent'),
          ),
      ],
      orphanTracks: await TracksRepository(_database).countOrphans(),
    );
  }
}
