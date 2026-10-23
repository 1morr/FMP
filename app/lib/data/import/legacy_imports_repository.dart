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

  /// 把 [pluginIds] 補記進最新一筆紀錄的 `reloginPlatforms`（已有的不重複）：換上資料庫之後
  /// 才寫憑證失敗的平台，帳號列會在 `CredentialStore` 載入時被對齊刪掉，結果對話框要如實說
  /// 需要重新登入。沒有紀錄或 [pluginIds] 為空時什麼都不做。
  Future<void> addReloginPlatforms(Iterable<String> pluginIds) async {
    final ids = pluginIds.toList();
    if (ids.isEmpty) return;
    final table = _database.legacyImportsTable;
    await _database.transaction(() async {
      final row =
          await (_database.select(table)
                ..orderBy([(t) => OrderingTerm.desc(t.id)])
                ..limit(1))
              .getSingleOrNull();
      if (row == null) return;
      final summary = ImportSummary.decode(row.summaryJson);
      final relogin = [
        ...summary.reloginPlatforms,
        for (final id in ids)
          if (!summary.reloginPlatforms.contains(id)) id,
      ];
      final updated = ImportSummary(
        collections: summary.collections,
        unimportedSettings: summary.unimportedSettings,
        reloginPlatforms: relogin,
      );
      await (_database.update(table)..where((t) => t.id.equals(row.id))).write(
        LegacyImportsTableCompanion(summaryJson: Value(updated.encode())),
      );
    });
  }

  /// 資料庫裡被曲目、歌單的遠端資料、電台、帳號參照到的插件 id（結果對話框判斷要不要提示
  /// 安裝音源）。
  Future<Set<String>> referencedPluginIds() async {
    final rows = await _database
        .customSelect(
          'SELECT source_type_id AS id FROM tracks '
          'UNION SELECT plugin_id FROM playlist_remote '
          'UNION SELECT plugin_id FROM radio_stations '
          'UNION SELECT plugin_id FROM accounts',
          readsFrom: {
            _database.tracksTable,
            _database.playlistRemoteTable,
            _database.radioStationsTable,
            _database.accountsTable,
          },
        )
        .get();
    return {for (final row in rows) row.read<String>('id')};
  }

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
