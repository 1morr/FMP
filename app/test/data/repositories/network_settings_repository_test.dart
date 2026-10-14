import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';

import '../../support/memory_database.dart';

void main() {
  test('reads all fields unset before anything is written', () async {
    final repository = NetworkSettingsRepository(memoryDatabase());

    expect(await repository.read(), NetworkSettings.empty);
  });

  test('reads back what was written', () async {
    final repository = NetworkSettingsRepository(memoryDatabase());

    await repository.write(cacheLimitMebibytes: 512);

    expect(
      await repository.read(),
      const NetworkSettings(cacheLimitMebibytes: 512),
    );
  });

  test('a write with nothing given keeps the value', () async {
    final repository = NetworkSettingsRepository(memoryDatabase());
    await repository.write(cacheLimitMebibytes: 128);

    await repository.write();

    expect(
      await repository.read(),
      const NetworkSettings(cacheLimitMebibytes: 128),
    );
  });

  group('clear', () {
    test('stores NULL, not a default value', () async {
      final database = memoryDatabase();
      final repository = NetworkSettingsRepository(database);
      await repository.write(cacheLimitMebibytes: 1024);

      await repository.clear(cacheLimitMebibytes: true);

      final row = await database
          .customSelect('SELECT cache_limit_mb FROM network_settings')
          .getSingle();
      expect(row.data, {'cache_limit_mb': null});
      expect(await repository.read(), NetworkSettings.empty);
    });

    test('with nothing named changes nothing', () async {
      final repository = NetworkSettingsRepository(memoryDatabase());
      await repository.write(cacheLimitMebibytes: 256);

      await repository.clear();

      expect(
        await repository.read(),
        const NetworkSettings(cacheLimitMebibytes: 256),
      );
    });

    test('before any write leaves the row unset', () async {
      final repository = NetworkSettingsRepository(memoryDatabase());

      await repository.clear(cacheLimitMebibytes: true);

      expect(await repository.read(), NetworkSettings.empty);
    });
  });

  group('radio status interval', () {
    test('is written and read without touching the cache limit', () async {
      final repository = NetworkSettingsRepository(memoryDatabase());
      await repository.write(cacheLimitMebibytes: 512);

      await repository.write(radioStatusIntervalMinutes: 3);

      expect(
        await repository.read(),
        const NetworkSettings(
          cacheLimitMebibytes: 512,
          radioStatusIntervalMinutes: 3,
        ),
      );
    });

    test('0 (off) is a value, not an unset field', () async {
      final repository = NetworkSettingsRepository(memoryDatabase());

      await repository.write(radioStatusIntervalMinutes: 0);

      expect((await repository.read()).radioStatusIntervalMinutes, 0);
    });

    test('clear stores NULL and leaves the cache limit alone', () async {
      final database = memoryDatabase();
      final repository = NetworkSettingsRepository(database);
      await repository.write(
        cacheLimitMebibytes: 512,
        radioStatusIntervalMinutes: 10,
      );

      await repository.clear(radioStatusIntervalMinutes: true);

      final row = await database
          .customSelect(
            'SELECT cache_limit_mb, radio_status_interval_minutes '
            'FROM network_settings',
          )
          .getSingle();
      expect(row.data, {
        'cache_limit_mb': 512,
        'radio_status_interval_minutes': null,
      });
    });

    test('clearing the cache limit leaves the interval alone', () async {
      final repository = NetworkSettingsRepository(memoryDatabase());
      await repository.write(
        cacheLimitMebibytes: 512,
        radioStatusIntervalMinutes: 10,
      );

      await repository.clear(cacheLimitMebibytes: true);

      expect(
        await repository.read(),
        const NetworkSettings(radioStatusIntervalMinutes: 10),
      );
    });

    test('stored format: a plain number of minutes', () async {
      final database = memoryDatabase();
      await NetworkSettingsRepository(database)
          .write(radioStatusIntervalMinutes: 5);

      final row = await database
          .customSelect(
            'SELECT radio_status_interval_minutes AS v FROM network_settings',
          )
          .getSingle();
      expect(row.data['v'], 5);
    });
  });

  test('watch emits the current value and every write', () async {
    final repository = NetworkSettingsRepository(memoryDatabase());
    final events = StreamIterator(repository.watch());
    addTearDown(events.cancel);

    expect(await events.moveNext(), isTrue);
    expect(events.current, NetworkSettings.empty);

    await repository.write(cacheLimitMebibytes: 256);
    expect(await events.moveNext(), isTrue);
    expect(events.current, const NetworkSettings(cacheLimitMebibytes: 256));
  });

  test('stored format: the limit is a plain number of MiB', () async {
    final database = memoryDatabase();
    final repository = NetworkSettingsRepository(database);

    await repository.write(cacheLimitMebibytes: 512);

    final row = await database
        .customSelect('SELECT id, cache_limit_mb FROM network_settings')
        .getSingle();
    expect(row.data, {'id': 1, 'cache_limit_mb': 512});
  });
}
