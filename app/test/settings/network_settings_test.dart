import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/settings/network_settings.dart';

import '../support/memory_database.dart';

void main() {
  ProviderContainer containerFor(
    AppDatabase database, {
    int defaultLimit = 256,
  }) => ProviderContainer.test(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      platformCapabilitiesProvider.overrideWithValue(
        PlatformCapabilities(
          dataDirectory: true,
          singleInstance: false,
          fontFallback: FontFallback.none,
          playback: null,
          networkInterfaces: false,
          cache: CacheSizes(
            defaultLimitMebibytes: defaultLimit,
            memoryImages: 1,
            memoryImageMebibytes: 1,
          ),
        ),
      ),
    ],
  );

  /// 訂閱 [networkProvider]，依序取得它發出的值。
  StreamIterator<Network> networks(ProviderContainer container) {
    final controller = StreamController<Network>();
    container.listen(networkProvider, (_, next) {
      if (next case AsyncData(:final value)) controller.add(value);
    }, fireImmediately: true);
    final iterator = StreamIterator(controller.stream);
    addTearDown(() async {
      await iterator.cancel();
      await controller.close();
    });
    return iterator;
  }

  group('defaults apply only to unset fields (ADR 0011)', () {
    test('a user value survives a change of the program default', () {
      const stored = NetworkSettings(cacheLimitMebibytes: 512);

      for (final defaultLimit in [128, 256]) {
        expect(
          resolveNetwork(
            stored,
            defaultCacheLimitMebibytes: defaultLimit,
          ).cacheLimitMebibytes,
          512,
        );
      }
    });

    test('an unset field follows the new default', () {
      for (final defaultLimit in [128, 256]) {
        expect(
          resolveNetwork(
            NetworkSettings.empty,
            defaultCacheLimitMebibytes: defaultLimit,
          ).cacheLimitMebibytes,
          defaultLimit,
        );
      }
    });

    test('nothing is written for fields the user never set', () async {
      final database = memoryDatabase();
      final events = networks(containerFor(database));
      await events.moveNext();

      expect(
        await database.customSelect('SELECT * FROM network_settings').get(),
        isEmpty,
      );
    });
  });

  group('NetworkNotifier', () {
    test('an unset limit reads as the platform default', () async {
      final events = networks(
        containerFor(memoryDatabase(), defaultLimit: 128),
      );

      expect(await events.moveNext(), isTrue);
      expect(events.current.cacheLimitMebibytes, 128);
      expect(events.current.stored, NetworkSettings.empty);
    });

    test('a limit the user set is read back', () async {
      final container = containerFor(memoryDatabase());
      final events = networks(container);
      await events.moveNext();

      await container.read(networkProvider.notifier).setCacheLimit(1024);

      expect(await events.moveNext(), isTrue);
      expect(events.current.cacheLimitMebibytes, 1024);
      expect(
        events.current.stored,
        const NetworkSettings(cacheLimitMebibytes: 1024),
      );
    });

    test('null clears the limit back to the platform default', () async {
      final database = memoryDatabase();
      final container = containerFor(database);
      final events = networks(container);
      await events.moveNext();
      final notifier = container.read(networkProvider.notifier);
      await notifier.setCacheLimit(512);
      await events.moveNext();

      await notifier.setCacheLimit(null);

      expect(await events.moveNext(), isTrue);
      expect(events.current.cacheLimitMebibytes, 256);
      expect(events.current.stored, NetworkSettings.empty);
      final row = await database
          .customSelect('SELECT cache_limit_mb FROM network_settings')
          .getSingle();
      expect(row.data['cache_limit_mb'], isNull);
    });
  });
}
