import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/database/database_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  group('database path', () {
    test('stores the Isar database in a dedicated app-named folder', () {
      final documentsPath = p.join('tmp', 'Documents');

      final databasePath = resolveFmpDatabaseDirectoryPathForTesting(
        documentsPath,
      );

      expect(databasePath, p.join(documentsPath, 'FMP'));
      expect(databasePath, isNot(documentsPath));
    });

    test('moves legacy root-level Isar files into the database folder',
        () async {
      final documentsDir = await Directory.systemTemp.createTemp(
        'fmp_database_path_test_',
      );
      addTearDown(() async {
        if (await documentsDir.exists()) {
          await documentsDir.delete(recursive: true);
        }
      });

      final legacyDatabaseFile = File(
        p.join(documentsDir.path, 'fmp_database.isar'),
      );
      final legacyLockFile = File(
        p.join(documentsDir.path, 'fmp_database.isar.lock'),
      );
      await legacyDatabaseFile.writeAsString('legacy-db');
      await legacyLockFile.writeAsString('legacy-lock');

      final databaseDir = await ensureFmpDatabaseDirectoryForTesting(
        documentsDir,
      );

      expect(databaseDir.path, p.join(documentsDir.path, 'FMP'));
      expect(await legacyDatabaseFile.exists(), isFalse);
      expect(await legacyLockFile.exists(), isFalse);
      expect(
        await File(p.join(databaseDir.path, 'fmp_database.isar'))
            .readAsString(),
        'legacy-db',
      );
      expect(
        await File(
          p.join(databaseDir.path, 'fmp_database.isar.lock'),
        ).readAsString(),
        'legacy-lock',
      );
    });

    test('does not overwrite a database file already in the new folder',
        () async {
      final documentsDir = await Directory.systemTemp.createTemp(
        'fmp_database_path_test_',
      );
      addTearDown(() async {
        if (await documentsDir.exists()) {
          await documentsDir.delete(recursive: true);
        }
      });

      final databaseDir = Directory(p.join(documentsDir.path, 'FMP'));
      await databaseDir.create();
      final legacyDatabaseFile = File(
        p.join(documentsDir.path, 'fmp_database.isar'),
      );
      final newDatabaseFile = File(
        p.join(databaseDir.path, 'fmp_database.isar'),
      );
      await legacyDatabaseFile.writeAsString('legacy-db');
      await newDatabaseFile.writeAsString('new-db');

      await ensureFmpDatabaseDirectoryForTesting(documentsDir);

      expect(await legacyDatabaseFile.readAsString(), 'legacy-db');
      expect(await newDatabaseFile.readAsString(), 'new-db');
    });
  });
}
