import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/domain/legacy_import.dart';

/// `legacy_imports` 的一列：一次匯入舊版資料的紀錄（M5 design §6.4）。
@immutable
final class LegacyImportRecord {
  const LegacyImportRecord({
    required this.id,
    required this.source,
    required this.importedAt,
    required this.summary,
    required this.acknowledged,
    this.legacySchemaVersion,
    this.backupVersion,
  });

  final int id;
  final LegacyImportSource source;

  /// UTC，精度到毫秒。
  final DateTime importedAt;
  final int? legacySchemaVersion;
  final int? backupVersion;
  final ImportSummary summary;

  /// 結果對話框看過了。
  final bool acknowledged;

  @override
  bool operator ==(Object other) =>
      other is LegacyImportRecord &&
      other.id == id &&
      other.source == source &&
      other.importedAt == importedAt &&
      other.legacySchemaVersion == legacySchemaVersion &&
      other.backupVersion == backupVersion &&
      other.summary == summary &&
      other.acknowledged == acknowledged;

  @override
  int get hashCode => Object.hash(
    id,
    source,
    importedAt,
    legacySchemaVersion,
    backupVersion,
    summary,
    acknowledged,
  );

  @override
  String toString() => 'LegacyImportRecord(id: $id, ${source.name})';
}

/// `legacy_imports` 的讀取與「看過了」。寫入由 `StagingImport` 在匯入的同一個 transaction
/// 做，這裡不開寫入口。
final class LegacyImportsRepository {
  LegacyImportsRepository(this._database);

  final AppDatabase _database;

  /// 最新一筆還沒看過結果的紀錄（結果對話框用）；沒有為 `null`。
  Future<LegacyImportRecord?> latestUnacknowledged() async {
    final table = _database.legacyImportsTable;
    final row =
        await (_database.select(table)
              ..where((t) => t.acknowledged.equals(false))
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// 把 [id] 標成看過了；沒有這一列時什麼都不做。
  Future<void> acknowledge(int id) =>
      (_database.update(_database.legacyImportsTable)
            ..where((t) => t.id.equals(id)))
          .write(const LegacyImportsTableCompanion(acknowledged: Value(true)));

  /// 有沒有任何匯入紀錄（設定頁決定要不要提示）。
  Future<bool> hasAny() async {
    final row = await (_database.select(
      _database.legacyImportsTable,
    )..limit(1)).getSingleOrNull();
    return row != null;
  }

  static LegacyImportRecord _fromRow(LegacyImportRow row) => LegacyImportRecord(
    id: row.id,
    source: row.source,
    importedAt: row.importedAt,
    legacySchemaVersion: row.legacySchemaVersion,
    backupVersion: row.backupVersion,
    summary: ImportSummary.decode(row.summaryJson),
    acknowledged: row.acknowledged,
  );
}
