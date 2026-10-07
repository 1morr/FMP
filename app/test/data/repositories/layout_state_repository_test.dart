import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/domain/player_tab.dart';

import '../../support/memory_database.dart';

void main() {
  test('reads everything unset before anything is written', () async {
    final repository = LayoutStateRepository(memoryDatabase());

    expect(await repository.read(), LayoutState.empty);
  });

  test('reads back what was written', () async {
    final repository = LayoutStateRepository(memoryDatabase());

    await repository.write(playerTab: PlayerTab.queue);

    expect(
      await repository.read(),
      const LayoutState(playerTab: PlayerTab.queue),
    );
  });

  test('a write with nothing given keeps the value', () async {
    final repository = LayoutStateRepository(memoryDatabase());
    await repository.write(playerTab: PlayerTab.lyrics);

    await repository.write();

    expect(
      await repository.read(),
      const LayoutState(playerTab: PlayerTab.lyrics),
    );
  });

  test('stored format: the tabs are written as fixed strings', () async {
    final database = memoryDatabase();
    final repository = LayoutStateRepository(database);
    final stored = <String?>[];
    for (final tab in PlayerTab.values) {
      await repository.write(playerTab: tab);
      final row = await database
          .customSelect('SELECT player_tab FROM layout_state')
          .getSingle();
      stored.add(row.read<String?>('player_tab'));
    }

    expect(stored, ['lyrics', 'queue', 'details']);
  });

  test('a tab the database does not know fails loudly', () async {
    final database = memoryDatabase();
    final repository = LayoutStateRepository(database);
    await database.customStatement(
      "INSERT INTO layout_state (id, player_tab) VALUES (1, 'bogus')",
    );

    await expectLater(repository.read(), throwsFormatException);
  });

  test('watch emits the current value and every write', () async {
    final repository = LayoutStateRepository(memoryDatabase());
    final events = StreamIterator(repository.watch());
    addTearDown(events.cancel);

    expect(await events.moveNext(), isTrue);
    expect(events.current, LayoutState.empty);

    await repository.write(playerTab: PlayerTab.details);
    expect(await events.moveNext(), isTrue);
    expect(events.current, const LayoutState(playerTab: PlayerTab.details));
  });

  test('reads back the panel fields', () async {
    final repository = LayoutStateRepository(memoryDatabase());

    await repository.write(panelExpanded: false, panelWidth: 380.5);

    expect(
      await repository.read(),
      const LayoutState(panelExpanded: false, panelWidth: 380.5),
    );
  });

  test('a write only changes the fields it is given', () async {
    final repository = LayoutStateRepository(memoryDatabase());
    await repository.write(
      playerTab: PlayerTab.queue,
      panelExpanded: true,
      panelWidth: 400,
    );

    await repository.write(panelWidth: 500);
    expect(
      await repository.read(),
      const LayoutState(
        playerTab: PlayerTab.queue,
        panelExpanded: true,
        panelWidth: 500,
      ),
    );

    await repository.write(panelExpanded: false);
    await repository.write(playerTab: PlayerTab.details);
    expect(
      await repository.read(),
      const LayoutState(
        playerTab: PlayerTab.details,
        panelExpanded: false,
        panelWidth: 500,
      ),
    );
  });

  test(
    'stored format: the panel is a boolean and a real number of dp',
    () async {
      final database = memoryDatabase();
      final repository = LayoutStateRepository(database);

      await repository.write(panelExpanded: false, panelWidth: 412);
      final row = await database
          .customSelect('SELECT panel_expanded, panel_width FROM layout_state')
          .getSingle();

      expect(row.read<int>('panel_expanded'), 0);
      expect(row.read<double>('panel_width'), 412.0);
    },
  );

  test('watch emits a panel write', () async {
    final repository = LayoutStateRepository(memoryDatabase());
    final events = StreamIterator(repository.watch());
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);

    await repository.write(panelWidth: 360);

    expect(await events.moveNext(), isTrue);
    expect(events.current, const LayoutState(panelWidth: 360));
  });
}
