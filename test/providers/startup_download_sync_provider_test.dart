import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:fmp/providers/download/download_providers.dart'
    show downloadedCategoriesProvider;
import 'package:fmp/providers/download/file_exists_cache.dart';
import 'package:fmp/providers/library_invalidation_coordinator.dart';
import 'package:fmp/providers/startup_download_sync_provider.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Isar.initializeIsarCore(
      libraries: {Abi.current(): await _resolveIsarLibraryPath()},
    );
  });

  group('startup download sync', () {
    test('app starts the silent startup download sync provider', () {
      final appSource = File(
        '${Directory.current.path}/lib/app.dart',
      ).readAsStringSync();

      expect(
        appSource,
        contains("import 'providers/startup_download_sync_provider.dart';"),
      );
      expect(appSource, contains('ref.watch(startupDownloadSyncProvider);'));
    });

    test('provider syncs local files silently and refreshes changed state', () {
      final providerFile = File(
        '${Directory.current.path}/lib/providers/startup_download_sync_provider.dart',
      );

      expect(providerFile.existsSync(), isTrue);

      final source = providerFile.readAsStringSync();
      expect(source, contains('final startupDownloadSyncProvider'));
      expect(source, contains('FutureProvider<void>'));
      expect(source, contains('downloadPathSyncServiceProvider'));
      expect(source, contains('syncLocalFiles('));
      expect(source, contains('libraryInvalidationCoordinatorProvider'));
      expect(source, contains('downloadStateChanged('));
      expect(source,
          isNot(contains('ref.invalidate(downloadedCategoriesProvider)')));
      expect(
          source, isNot(contains('ref.invalidate(fileExistsCacheProvider)')));
      expect(source, isNot(contains('playlistListProvider.notifier')));
      expect(source, contains('allPlaylistsProvider.future'));
      expect(source, contains('affectedPlaylistIds:'));
      expect(source, contains('AppLogger.error'));
    });

    test('unconfigured download path is skipped without error logging',
        () async {
      final harness =
          await _createHarness('startup_download_sync_unconfigured');
      addTearDown(harness.dispose);
      AppLogger.clearLogs();

      await harness.container.read(startupDownloadSyncProvider.future);

      final startupLogs = AppLogger.logs
          .where((entry) => entry.tag == 'StartupDownloadSync')
          .toList();
      expect(startupLogs.map((entry) => entry.level), [LogLevel.info]);
      expect(startupLogs.single.message, contains('not configured'));
    });

    test('successful startup sync updates persisted download path and cache',
        () async {
      final downloadStateChanges = <_DownloadStateChange>[];
      final harness = await _createHarness(
        'startup_download_sync_success',
        downloadStateChanges: downloadStateChanges,
      );
      addTearDown(harness.dispose);

      final downloadsDir = Directory(p.join(harness.tempDir.path, 'downloads'));
      final playlistDir = Directory(
        p.join(downloadsDir.path, 'Playlist A', 'video-a'),
      );
      await playlistDir.create(recursive: true);
      final audioPath = p.join(playlistDir.path, 'audio.m4a');
      await File(audioPath).writeAsString('audio');
      await File(p.join(playlistDir.path, 'metadata.json')).writeAsString(
        jsonEncode({
          'sourceId': 'video-a',
          'sourceType': 'youtube',
          'title': 'Video A',
          'artist': 'Artist',
        }),
      );

      final settingsRepo = SettingsRepository(harness.isar);
      await settingsRepo.update((settings) {
        settings.customDownloadDir = downloadsDir.path;
      });

      final trackRepo = TrackRepository(harness.isar);
      final playlist = Playlist()..name = 'Playlist A';
      await harness.isar.writeTxn(() => harness.isar.playlists.put(playlist));
      final savedTrack = await trackRepo.save(
        Track()
          ..sourceId = 'video-a'
          ..sourceType = SourceType.youtube
          ..title = 'Video A'
          ..artist = 'Artist',
      );

      harness.container
          .read(fileExistsCacheProvider.notifier)
          .markAsExisting('/stale/cover.jpg');
      await harness.container.read(downloadedCategoriesProvider.future);

      await harness.container.read(startupDownloadSyncProvider.future);

      final refreshedTrack = await trackRepo.getById(savedTrack.id);
      expect(refreshedTrack?.allDownloadPaths, [audioPath]);
      expect(downloadStateChanges, hasLength(1));
      expect(downloadStateChanges.single.fileExistsChanged, isTrue);
      expect(downloadStateChanges.single.affectedPlaylistIds, [playlist.id]);
      expect(harness.container.read(fileExistsCacheProvider), isEmpty);
      final categories = await harness.container.read(
        downloadedCategoriesProvider.future,
      );
      expect(categories.single.folderName, 'Playlist A');
    });
  });
}

class _Harness {
  _Harness({
    required this.container,
    required this.isar,
    required this.tempDir,
  });

  final ProviderContainer container;
  final Isar isar;
  final Directory tempDir;

  Future<void> dispose() async {
    container.dispose();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _DownloadStateChange {
  const _DownloadStateChange({
    required this.affectedPlaylistIds,
    required this.fileExistsChanged,
  });

  final List<int> affectedPlaylistIds;
  final bool fileExistsChanged;
}

class _RecordingLibraryInvalidationCoordinator
    extends LibraryInvalidationCoordinator {
  _RecordingLibraryInvalidationCoordinator({
    required Ref ref,
    required this.changes,
  }) : super(
          invalidateAllPlaylists: () {},
          invalidatePlaylistDetail: (_) {},
          invalidatePlaylistCover: (_) {},
          invalidateDownloadedCategories: () {
            ref.invalidate(downloadedCategoriesProvider);
          },
          invalidateDownloadedCategoryTracks: (_) {},
          invalidateFileExistsCache: () {
            ref.invalidate(fileExistsCacheProvider);
          },
          refreshLoadedPlaylistDetail: (_) async {},
          startRefreshLoadedPlaylistDetail: (_) {},
          logBackgroundError: (_, __, ___) {},
        );

  final List<_DownloadStateChange> changes;

  @override
  void downloadStateChanged({
    Iterable<String> savePaths = const [],
    Iterable<String> categoryPaths = const [],
    Iterable<int> affectedPlaylistIds = const [],
    bool includeDownloadedCategories = true,
    bool fileExistsChanged = true,
  }) {
    changes.add(
      _DownloadStateChange(
        affectedPlaylistIds: affectedPlaylistIds.toList(),
        fileExistsChanged: fileExistsChanged,
      ),
    );
    super.downloadStateChanged(
      savePaths: savePaths,
      categoryPaths: categoryPaths,
      affectedPlaylistIds: affectedPlaylistIds,
      includeDownloadedCategories: includeDownloadedCategories,
      fileExistsChanged: fileExistsChanged,
    );
  }
}

Future<_Harness> _createHarness(
  String name, {
  List<_DownloadStateChange>? downloadStateChanges,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('${name}_');
  final isar = await Isar.open(
    [
      TrackSchema,
      PlaylistSchema,
      SettingsSchema,
    ],
    directory: tempDir.path,
    name: name,
  );

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => isar),
      if (downloadStateChanges != null)
        libraryInvalidationCoordinatorProvider.overrideWith((ref) {
          return _RecordingLibraryInvalidationCoordinator(
            ref: ref,
            changes: downloadStateChanges,
          );
        }),
    ],
  );

  return _Harness(
    container: container,
    isar: isar,
    tempDir: tempDir,
  );
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') {
      continue;
    }
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
