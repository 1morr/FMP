import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';

/// 新版的 drift 資料庫：開在 `platform/` 給的檔案上（architecture〈依賴規則〉）。
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('fmp_db_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('opens an empty database file at the current schema version', () async {
    final db = AppDatabase.open(File('${dir.path}/fmp.sqlite'));
    addTearDown(db.close);

    expect(await db.storedSchemaVersion(), db.schemaVersion);
  });

  test('reopens an existing database file', () async {
    final file = File('${dir.path}/fmp.sqlite');
    final first = AppDatabase.open(file);
    await first.storedSchemaVersion();
    await first.close();

    final second = AppDatabase.open(file);
    addTearDown(second.close);

    expect(await second.storedSchemaVersion(), second.schemaVersion);
  });

  test('a database file that cannot be opened gives null and an error in the '
      'log', () async {
    final log = await Log.open(
      Directory('${dir.path}/logs'),
      minimumLevel: LogLevel.debug,
    );
    // 路徑上是一個資料夾，SQLite 開不了。
    final file = File('${dir.path}/fmp.sqlite');
    Directory(file.path).createSync();

    expect(await AppDatabase.openOrNull(file, log), isNull);
    await log.close();
    expect(
      File('${dir.path}/logs/${Log.fileName}').readAsStringSync(),
      contains('ERROR Opening the database failed'),
    );
  });
}
