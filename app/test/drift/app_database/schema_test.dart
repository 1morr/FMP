import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_database.dart';
import 'generated/schema.dart';

/// 程式碼建出來的 schema 必須等於最新的快照（drift_schemas/app_database/）。
///
/// 改了 `lib/data/database/tables.dart` 卻沒 bump 版本、存新快照，這裡會紅。
/// 各版之間的升級測試由 `drift_dev make-migrations` 產生在同一個目錄
/// （`.trellis/spec/app/data/index.md`）。
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('schemaVersion is the latest snapshot', () {
    expect(memoryDatabase().schemaVersion, GeneratedHelper.versions.last);
  });

  test('a new database has exactly the snapshot schema', () async {
    // 記憶體資料庫是空的，開啟時由程式碼的 onCreate 建表；再拿它和快照比。
    final database = memoryDatabase();

    await verifier.migrateAndValidate(database, database.schemaVersion);
  });

  test('a schema that differs from the snapshot fails the check', () async {
    // 證明上一個測試不是空轉：多一個欄位就要比對失敗。
    final database = memoryDatabase();
    await database.customStatement(
      'ALTER TABLE plugin_storage ADD COLUMN extra TEXT',
    );

    await expectLater(
      verifier.migrateAndValidate(database, database.schemaVersion),
      throwsA(isA<SchemaMismatch>()),
    );
  });
}
