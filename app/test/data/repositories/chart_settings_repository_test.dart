import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/chart_settings_repository.dart';

import '../../support/memory_database.dart';
import '../../support/pump_until.dart';

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

  test(
    'setOrder writes 0, 1, 2… in the given order and keeps enabled',
    () async {
      final repository = ChartSettingsRepository(memoryDatabase());
      await repository.setEnabled('a', 'new', enabled: false);

      await repository.setOrder(const [
        (pluginId: 'b', chartId: 'hot'),
        (pluginId: 'a', chartId: 'new'),
        (pluginId: 'a', chartId: 'hot'),
      ]);

      expect(
        await repository.watch().first,
        unorderedEquals(const [
          ChartSetting(pluginId: 'b', chartId: 'hot', sortOrder: 0),
          ChartSetting(
            pluginId: 'a',
            chartId: 'new',
            enabled: false,
            sortOrder: 1,
          ),
          ChartSetting(pluginId: 'a', chartId: 'hot', sortOrder: 2),
        ]),
      );

      // 再排一次：舊的順序整批換掉。
      await repository.setOrder(const [
        (pluginId: 'a', chartId: 'hot'),
        (pluginId: 'a', chartId: 'new'),
        (pluginId: 'b', chartId: 'hot'),
      ]);
      expect(
        {
          for (final setting in await repository.watch().first)
            '${setting.pluginId}/${setting.chartId}': setting.sortOrder,
        },
        {'a/hot': 0, 'a/new': 1, 'b/hot': 2},
      );
    },
  );

  test('setOrder is a single write', () async {
    final database = memoryDatabase();
    final repository = ChartSettingsRepository(database);
    final writes = <Object>[];
    final subscription = database
        .tableUpdates(TableUpdateQuery.onTable(database.chartSettingsTable))
        .listen(writes.add);
    addTearDown(subscription.cancel);

    await repository.setOrder(const [
      (pluginId: 'a', chartId: 'hot'),
      (pluginId: 'a', chartId: 'new'),
      (pluginId: 'b', chartId: 'hot'),
    ]);
    await settle();

    expect(writes, hasLength(1));
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

  test(
    'stored format: enabled is 0 or 1, sort_order an integer, unset is NULL',
    () async {
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

      await repository.setOrder(const [
        (pluginId: 'a', chartId: 'new'),
        (pluginId: 'a', chartId: 'hot'),
      ]);
      final ordered = await database
          .customSelect(
            'SELECT chart_id, enabled, sort_order FROM chart_settings '
            'ORDER BY chart_id',
          )
          .get();
      expect(
        [for (final row in ordered) row.data],
        [
          {'chart_id': 'hot', 'enabled': 0, 'sort_order': 1},
          {'chart_id': 'new', 'enabled': null, 'sort_order': 0},
        ],
      );
    },
  );
}
