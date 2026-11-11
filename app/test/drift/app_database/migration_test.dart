import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database.dart';

import 'generated/schema.dart';

/// 升級測試（plan §3）。每個 schema 版本的快照在 `drift_schemas/`，
/// `generated/` 是 `dart run drift_dev make-migrations` 依快照產生的各版本
/// 資料庫，不要手改。`make-migrations` 不會覆寫本檔。
///
/// 下一個 schema 版本照這樣做：
///
/// 1. 改表，把 `AppDatabase.schemaVersion` 加一，跑
///    `dart run drift_dev make-migrations`：多一個快照、`generated/` 多一版、
///    `lib/data/database.steps.dart` 更新。
/// 2. 在 `AppDatabase.migration` 用 `stepByStep(fromNToM: …)` 寫這一步。
/// 3. 下面「simple migrations」自動涵蓋新的每一對版本，不用改。
/// 4. 這一步會改到既有欄位（型別、約束、搬資料）時，照
///    https://drift.simonbinder.eu/migrations/tests/#verifying-data-integrity
///    加一條 `verifier.testWithDataIntegrity` 的測試，放在本檔最後。
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the schema version matches the latest snapshot', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 版本加了卻沒跑 make-migrations，這裡就紅。
    expect(db.schemaVersion, GeneratedHelper.versions.last);
  });

  test('a new database matches the latest snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, db.schemaVersion);
  });

  group('simple migrations', () {
    // 從每個舊版本的空資料庫升到每個較新的版本，驗證 schema 跟快照一致。
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      for (final toVersion in versions.skip(i + 1)) {
        test('from $fromVersion to $toVersion', () async {
          final schema = await verifier.schemaAt(fromVersion);
          final db = AppDatabase(schema.newConnection());
          addTearDown(db.close);

          await verifier.migrateAndValidate(db, toVersion);
        });
      }
    }
  });
}
