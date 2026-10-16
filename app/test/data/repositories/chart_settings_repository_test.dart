import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/chart_settings_repository.dart';

import '../../support/memory_database.dart';

void main() {
  test(
    'a chart nobody set has no row, so it reads as enabled upstream',
    () async {
      final repository = ChartSettingsRepository(memoryDatabase());

      expect(await repository.watch().first, isEmpty);
    },
  );

  test('setEnabled creates the row and a later call flips it', () async {
    final repository = ChartSettingsRepository(memoryDatabase());

    await repository.setEnabled('fmp-test', 'hot', enabled: false);
    expect(await repository.watch().first, const [
      ChartSetting(pluginId: 'fmp-test', chartId: 'hot', enabled: false),
    ]);

    await repository.setEnabled('fmp-test', 'hot', enabled: true);
    expect(await repository.watch().first, const [
      ChartSetting(pluginId: 'fmp-test', chartId: 'hot', enabled: true),
    ]);
  });

  test('setEnabled keeps the sort order of the row', () async {
    final database = memoryDatabase();
    final repository = ChartSettingsRepository(database);
    await database.customStatement(
      'INSERT INTO chart_settings (plugin_id, chart_id, sort_order) '
      "VALUES ('fmp-test', 'hot', 3)",
    );

    await repository.setEnabled('fmp-test', 'hot', enabled: false);

    expect(await repository.watch().first, const [
      ChartSetting(
        pluginId: 'fmp-test',
        chartId: 'hot',
        enabled: false,
        sortOrder: 3,
      ),
    ]);
  });

  test('the same chart id under two plugins is two rows', () async {
    final repository = ChartSettingsRepository(memoryDatabase());

    await repository.setEnabled('a', 'hot', enabled: false);
    await repository.setEnabled('b', 'hot', enabled: true);

    expect(
      await repository.watch().first,
      unorderedEquals(const [
        ChartSetting(pluginId: 'a', chartId: 'hot', enabled: false),
        ChartSetting(pluginId: 'b', chartId: 'hot', enabled: true),
      ]),
    );
  });

  test(
    'removePlugin deletes that plugin\'s rows only, and may find none',
    () async {
      final repository = ChartSettingsRepository(memoryDatabase());
      await repository.setEnabled('a', 'hot', enabled: false);
      await repository.setEnabled('a', 'new', enabled: false);
      await repository.setEnabled('b', 'hot', enabled: false);

      await repository.removePlugin('a');
      await repository.removePlugin('nobody');

      expect(await repository.watch().first, const [
        ChartSetting(pluginId: 'b', chartId: 'hot', enabled: false),
      ]);
    },
  );

  test('watch emits the current rows and every write', () async {
    final repository = ChartSettingsRepository(memoryDatabase());
    final events = StreamIterator(repository.watch());
    addTearDown(events.cancel);

    expect(await events.moveNext(), isTrue);
    expect(events.current, isEmpty);

    await repository.setEnabled('a', 'hot', enabled: false);
    expect(await events.moveNext(), isTrue);
    expect(events.current, hasLength(1));
  });

  test('stored format: enabled is 0 or 1, unset is NULL', () async {
    final database = memoryDatabase();
    final repository = ChartSettingsRepository(database);

    await repository.setEnabled('a', 'hot', enabled: false);
    await database.customStatement(
      "INSERT INTO chart_settings (plugin_id, chart_id) VALUES ('a', 'new')",
    );

    final rows = await database
        .customSelect(
          'SELECT chart_id, enabled, sort_order FROM chart_settings '
          'ORDER BY chart_id',
        )
        .get();
    expect(
      [for (final row in rows) row.data],
      [
        {'chart_id': 'hot', 'enabled': 0, 'sort_order': null},
        {'chart_id': 'new', 'enabled': null, 'sort_order': null},
      ],
    );
  });
}
