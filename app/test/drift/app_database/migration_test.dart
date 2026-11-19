import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;

/// 升級測試。改 schema 的流程照 architecture〈測試策略〉；`generated/` 是
/// `dart run drift_dev make-migrations` 依 `drift_schemas/` 的快照產生的
/// 各版本資料庫，不要手改。`make-migrations` 不會覆寫本檔。
///
/// 下面的「simple migrations」自動涵蓋每一對版本，加版本時不用改。某一步
/// 會改到既有欄位（型別、約束、搬資料，例如改插件的曲目 id 格式）時，照
/// https://drift.simonbinder.eu/migrations/tests/#verifying-data-integrity
/// 在本檔最後的 `data integrity` 加一條 `verifier.testWithDataIntegrity`：
/// 在舊版本放幾列資料，升級後逐欄比對。
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

  group('data integrity', () {
    // v1 沒有表：升級後佇列的兩張表是空的，App 從空佇列開始。
    test('from 1 to 2', () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 1,
        newVersion: 2,
        createOld: v1.DatabaseAtV1.new,
        createNew: v2.DatabaseAtV2.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {},
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.queueEntries).get(), isEmpty);
          expect(await newDb.select(newDb.queueStates).get(), isEmpty);
        },
      );
    });

    // v4 的 queue_entries 多一欄大封面：舊的列照舊讀得到，大封面是 null。
    test('from 3 to 4', () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 3,
        newVersion: 4,
        createOld: v3.DatabaseAtV3.new,
        createNew: v4.DatabaseAtV4.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch.insert(
            oldDb.queueEntries,
            const v3.QueueEntriesData(
              entryId: 1,
              playOrder: 0,
              pluginId: 'songs',
              trackId: 'a',
              title: 'Title a',
              author: 'Author a',
              coverUrl: 'https://img.example.com/a.webp',
            ),
          );
        },
        validateItems: (newDb) async {
          final row = await newDb.select(newDb.queueEntries).getSingle();
          expect(row.trackId, 'a');
          expect(row.coverUrl, 'https://img.example.com/a.webp');
          expect(row.coverLargeUrl, isNull);
        },
      );
    });
  });
}
