import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/search_history_repository.dart';

import '../../support/memory_database.dart';

DateTime _at(int minute) => DateTime.utc(2026, 10, 27, 12, minute);

void main() {
  late SearchHistoryRepository repository;
  setUp(() => repository = SearchHistoryRepository(memoryDatabase()));

  Future<void> record(String query, int minute) =>
      withClock(Clock.fixed(_at(minute)), () => repository.record(query));

  Future<List<String>> queries() async => [
    for (final e in await repository.list()) e.query,
  ];

  test('lists the newest first', () async {
    await record('a', 1);
    await record('b', 3);
    await record('c', 2);

    expect(await queries(), ['b', 'c', 'a']);
  });

  test('trims the query and ignores blank ones', () async {
    await record('  lofi \n', 1);
    await record('   ', 2);
    await record('', 3);

    expect(await repository.list(), [
      SearchHistoryEntry(query: 'lofi', searchedAt: _at(1)),
    ]);
  });

  test('searching the same query again only moves it to the top', () async {
    await record('a', 1);
    await record('b', 2);
    await record(' a ', 3);

    expect(await repository.list(), [
      SearchHistoryEntry(query: 'a', searchedAt: _at(3)),
      SearchHistoryEntry(query: 'b', searchedAt: _at(2)),
    ]);
  });

  test('keeps only the newest 50', () async {
    for (var i = 0; i < 55; i++) {
      await record('q$i', i);
    }

    final stored = await queries();
    expect(stored, hasLength(SearchHistoryRepository.limit));
    expect(stored.first, 'q54');
    expect(stored.last, 'q5');
  });

  test('deletes one query or clears everything', () async {
    await record('a', 1);
    await record('b', 2);

    await repository.delete('a');
    expect(await queries(), ['b']);
    await repository.delete('missing');
    expect(await queries(), ['b']);

    await repository.clear();
    expect(await queries(), isEmpty);
  });

  test('watch emits the list again after every change', () async {
    final seen = <List<String>>[];
    final subscription = repository.watch().listen(
      (entries) => seen.add([for (final e in entries) e.query]),
    );
    addTearDown(subscription.cancel);
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    await settle();
    await record('a', 1);
    await settle();
    await record('b', 2);
    await settle();
    await repository.clear();
    await settle();

    expect(seen.first, isEmpty);
    expect(seen, anyElement(orderedEquals(['b', 'a'])));
    expect(seen.last, isEmpty);
  });

  test(
    'stored format: queries are text and times are epoch milliseconds',
    () async {
      final database = memoryDatabase();
      final repository = SearchHistoryRepository(database);
      await withClock(Clock.fixed(_at(1)), () => repository.record(' lofi '));

      final row = await database
          .customSelect('SELECT query, searched_at FROM search_history')
          .getSingle();
      expect(row.data, {
        'query': 'lofi',
        'searched_at': _at(1).millisecondsSinceEpoch,
      });
    },
  );
}
