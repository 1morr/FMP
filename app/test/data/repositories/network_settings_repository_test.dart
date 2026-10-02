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
