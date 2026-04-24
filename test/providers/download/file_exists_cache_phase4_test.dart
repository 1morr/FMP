import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/download/file_exists_cache.dart';

Future<void> _waitForCondition(bool Function() condition) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > const Duration(seconds: 2)) {
      fail('Timed out waiting for condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('Phase 4 Task 3 file exists cache', () {
    test('file exists cache exposes path-scoped and reactive epoch providers',
        () {
      final source = File(
        '${Directory.current.path}/lib/providers/download/file_exists_cache.dart',
      ).readAsStringSync();

      expect(source, contains('final filePathExistsProvider'));
      expect(source, contains('final fileExistsCacheEpochProvider'));
      expect(source, contains('StateProvider<int>'));
      expect(
        source,
        contains(
          'fileExistsCacheProvider.select((paths) => paths.contains(path))',
        ),
      );
    });

    test('path-scoped selector provider only updates for the watched path', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final values = <bool>[];
      final subscription = container.listen<bool>(
        filePathExistsProvider('/watched/cover.jpg'),
        (_, next) => values.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      container
          .read(fileExistsCacheProvider.notifier)
          .markAsExisting('/other/cover.jpg');

      expect(container.read(filePathExistsProvider('/watched/cover.jpg')),
          isFalse);
      expect(values, [false]);

      container
          .read(fileExistsCacheProvider.notifier)
          .markAsExisting('/watched/cover.jpg');

      expect(
          container.read(filePathExistsProvider('/watched/cover.jpg')), isTrue);
      expect(values, [false, true]);
    });

    test('cache epoch provider updates for synchronous cache mutations', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final values = <int>[];
      final subscription = container.listen<int>(
        fileExistsCacheEpochProvider,
        (_, next) => values.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final cache = container.read(fileExistsCacheProvider.notifier);
      cache.markAsExisting('/watched/cover.jpg');
      cache.remove('/watched/cover.jpg');
      cache.markAsExisting('/watched/cover.jpg');
      cache.clearAll();

      expect(values, [0, 1, 2, 3, 4]);
    });

    test('single-path overflow trimming stays stable for incremental inserts',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final cache = container.read(fileExistsCacheProvider.notifier);
      const watchedPath = '/covers/4999.jpg';

      expect(
        () {
          for (var i = 0; i < 6000; i++) {
            cache.markAsExisting('/covers/$i.jpg');
          }
        },
        returnsNormally,
      );

      final state = container.read(fileExistsCacheProvider);
      expect(state.length, 5000);
      expect(container.read(filePathExistsProvider(watchedPath)), isTrue);
    });

    test('batched preload overflow trims without throwing and caps cache size',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'file_exists_cache_phase4_trim_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cache = container.read(fileExistsCacheProvider.notifier);

      for (var i = 0; i < 5000; i++) {
        cache.markAsExisting('${tempDir.path}/seed_$i.jpg');
      }

      final batchPaths = <String>[];
      for (var i = 0; i < 1001; i++) {
        final path = '${tempDir.path}/batch_$i.jpg';
        await File(path).writeAsString('x');
        batchPaths.add(path);
      }

      await expectLater(
        cache.preloadPaths(batchPaths, batchSize: 1001),
        completes,
      );

      final state = container.read(fileExistsCacheProvider);
      expect(state.length, 5000);
      expect(state.contains(batchPaths.last), isTrue);
    });

    test('cache epoch provider updates for async cache population paths',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'file_exists_cache_phase4_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final existsPath = '${tempDir.path}/exists_cover.jpg';
      final refreshPath = '${tempDir.path}/refresh_cover.jpg';
      final preloadPath = '${tempDir.path}/preload_cover.jpg';
      await File(existsPath).writeAsString('exists');
      await File(refreshPath).writeAsString('refresh');
      await File(preloadPath).writeAsString('preload');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final values = <int>[];
      final subscription = container.listen<int>(
        fileExistsCacheEpochProvider,
        (_, next) => values.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final cache = container.read(fileExistsCacheProvider.notifier);

      expect(cache.exists(existsPath), isFalse);
      await _waitForCondition(
        () => container.read(filePathExistsProvider(existsPath)),
      );
      expect(values, [0, 1]);

      expect(cache.getFirstExisting([refreshPath]), isNull);
      await _waitForCondition(
        () => container.read(filePathExistsProvider(refreshPath)),
      );
      expect(values, [0, 1, 2]);

      await cache.preloadPaths([preloadPath]);
      expect(container.read(filePathExistsProvider(preloadPath)), isTrue);
      expect(values, [0, 1, 2, 3]);
    });

    test('preloadPaths batches uncached unique paths in source', () {
      final source = File(
        '${Directory.current.path}/lib/providers/download/file_exists_cache.dart',
      ).readAsStringSync();

      expect(
        source,
        contains(
          'Future<void> preloadPaths(List<String> paths, {int batchSize = 64}) async',
        ),
      );
      expect(source, contains('paths.toSet().difference(state).toList()'));
      expect(source, contains('Future.wait('));
    });

    test('getFirstExisting schedules one refresh per unresolved path set', () {
      final source = File(
        '${Directory.current.path}/lib/providers/download/file_exists_cache.dart',
      ).readAsStringSync();

      expect(source,
          contains("final Set<String> _pendingRefreshPaths = <String>{};"));
      expect(
          source,
          contains(
              'final pending = uncached.difference(_pendingRefreshPaths);'));
      expect(source, contains('_pendingRefreshPaths.addAll(pending);'));
      expect(source, contains('_pendingRefreshPaths.removeAll(pending);'));
    });

    test(
      'playlist detail page tracks a cached cover-path set and watches the reactive cache epoch provider',
      () {
        final source = File(
          '${Directory.current.path}/lib/ui/pages/library/playlist_detail_page.dart',
        ).readAsStringSync();

        expect(source, contains('_cachedCoverPaths'));
        expect(source, contains('setEquals(coverPaths, _cachedCoverPaths)'));
        expect(source, contains('_lastCacheEpoch'));
        expect(source, contains('fileExistsCacheEpochProvider'));
        expect(source,
            isNot(contains('tracks.length != _lastRefreshedTracksLength')));
        expect(
          source,
          isNot(
            contains(
              'fileExistsCacheProvider.notifier.select((cache) => cache.cacheEpoch)',
            ),
          ),
        );
        expect(
          source,
          isNot(
            contains('ref.read(fileExistsCacheProvider.notifier).cacheEpoch'),
          ),
        );
      },
    );

    test('track detail panel watches the reactive cache epoch provider', () {
      final source = File(
        '${Directory.current.path}/lib/ui/widgets/track_detail_panel.dart',
      ).readAsStringSync();

      expect(source, contains('_lastAvatarCacheEpoch'));
      expect(source, contains('fileExistsCacheEpochProvider'));
      expect(
        source,
        isNot(
            contains('ref.read(fileExistsCacheProvider.notifier).cacheEpoch')),
      );
    });

    test('missing paths are cached to avoid repeated refresh scheduling',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'file_exists_cache_phase4_missing_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cache = container.read(fileExistsCacheProvider.notifier);
      final missingPath = '${tempDir.path}/missing_cover.jpg';

      expect(cache.exists(missingPath), isFalse);
      await _waitForCondition(() => cache.debugMissingPathCount == 1);

      expect(cache.getFirstExisting([missingPath]), isNull);
      expect(cache.pendingRefreshCount, 0);
      expect(cache.exists(missingPath), isFalse);
      expect(cache.debugMissingPathCount, 1);
    });

    test('markAsExisting clears missing cache entry and updates selector', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cache = container.read(fileExistsCacheProvider.notifier);
      const path = '/previously/missing/cover.jpg';

      cache.debugMarkMissingForTesting(path);
      expect(cache.debugMissingPathCount, 1);
      expect(container.read(filePathExistsProvider(path)), isFalse);

      cache.markAsExisting(path);

      expect(cache.debugMissingPathCount, 0);
      expect(container.read(filePathExistsProvider(path)), isTrue);
    });

    test('missing path cache is bounded', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cache = container.read(fileExistsCacheProvider.notifier);

      for (var i = 0; i < 6000; i++) {
        cache.debugMarkMissingForTesting('/missing/$i.jpg');
      }

      expect(cache.debugMissingPathCount, 5000);
    });
  });
}
