import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dataDirectory;

  setUp(() {
    dataDirectory = Directory.systemTemp.createTempSync('fmp_open_db_');
    // 刪得掉也證明資料庫關閉後檔案沒被佔住（Windows 上開著的檔案刪不掉）。
    addTearDown(() => dataDirectory.deleteSync(recursive: true));
  });

  File databaseFile() => File(p.join(dataDirectory.path, 'fmp.db'));

  test('creates fmp.db in the data directory', () async {
    final database = await openAppDatabase(dataDirectory);
    addTearDown(database.close);

    expect(databaseFile().existsSync(), isTrue);
    final foreignKeys = await database
        .customSelect('PRAGMA foreign_keys')
        .getSingle();
    expect(foreignKeys.data.values.single, 1);
  });

  test('keeps data across reopening', () async {
    final first = await openAppDatabase(dataDirectory);
    await AppearanceSettingsRepository(first)
        .write(themeMode: ThemeModeSetting.dark);
    await first.close();

    final second = await openAppDatabase(dataDirectory);
    addTearDown(second.close);

    expect(
      await AppearanceSettingsRepository(second).read(),
      const AppearanceSettings(themeMode: ThemeModeSetting.dark),
    );
  });

  test('throws while opening when the file is not a database', () async {
    databaseFile().writeAsStringSync('not a database, just some text ' * 100);

    await expectLater(openAppDatabase(dataDirectory), throwsA(anything));
  });
}
