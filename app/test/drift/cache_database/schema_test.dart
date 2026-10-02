import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/cache/cache_database.dart';

import 'generated/schema.dart';

/// 快取庫的 schema 必須等於最新的快照（drift_schemas/cache_database/）。
///
/// 快取庫版本不同就清空重建、沒有逐步 migration（`CacheDatabase.migration`），
/// 快照只用來守「改了 `lib/data/cache/cache_tables.dart` 卻沒 bump 版本」：
/// 版本沒變的話，已經在使用者手上的舊表不會被重建。
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  CacheDatabase memoryCache() {
    final database = CacheDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(database.close);
    return database;
  }

  test('schemaVersion is the latest snapshot', () {
    expect(memoryCache().schemaVersion, GeneratedHelper.versions.last);
  });

  test('a new cache database has exactly the snapshot schema', () async {
    final database = memoryCache();

    await verifier.migrateAndValidate(database, database.schemaVersion);
  });

  test('a schema that differs from the snapshot fails the check', () async {
    // 證明上一個測試不是空轉：多一個欄位就要比對失敗。
    final database = memoryCache();
    await database.customStatement(
      'ALTER TABLE cache_entries ADD COLUMN extra TEXT',
    );

    await expectLater(
      verifier.migrateAndValidate(database, database.schemaVersion),
      throwsA(isA<SchemaMismatch>()),
    );
  });
}
