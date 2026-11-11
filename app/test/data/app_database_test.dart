import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database.dart';

/// 新版的 drift 資料庫：開在 `platform/` 給的檔案上（plan §1.3）。
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('fmp_db_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('opens an empty database file at schema version 1', () async {
    final db = AppDatabase.open(File('${dir.path}/fmp.sqlite'));
    addTearDown(db.close);

    expect(await db.storedSchemaVersion(), 1);
  });

  test('reopens an existing database file', () async {
    final file = File('${dir.path}/fmp.sqlite');
    final first = AppDatabase.open(file);
    await first.storedSchemaVersion();
    await first.close();

    final second = AppDatabase.open(file);
    addTearDown(second.close);

    expect(await second.storedSchemaVersion(), 1);
  });
}
