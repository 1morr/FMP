import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_database.dart';

void main() {
  test('foreign keys are enforced on every connection', () async {
    final database = memoryDatabase();

    final row = await database.customSelect('PRAGMA foreign_keys').getSingle();

    expect(row.data.values.single, 1);
  });

  test('appearance_settings only accepts the single row with id 1', () async {
    final database = memoryDatabase();

    await database.customStatement(
      'INSERT INTO appearance_settings (id) VALUES (1)',
    );
    await expectLater(
      database.customStatement(
        'INSERT INTO appearance_settings (id) VALUES (2)',
      ),
      throwsA(anything),
    );
    final count = await database
        .customSelect('SELECT COUNT(*) AS c FROM appearance_settings')
        .getSingle();
    expect(count.read<int>('c'), 1);
  });
}
