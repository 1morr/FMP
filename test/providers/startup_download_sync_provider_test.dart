import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/database/database_provider.dart';
import 'package:fmp/data/database/repository_providers.dart'
    show trackRepositoryProvider;
import 'package:fmp/providers/download/download_path_provider.dart';
import 'package:fmp/providers/download/download_providers.dart'
    show downloadedCategoriesProvider;
import 'package:fmp/providers/download/file_exists_cache.dart';
import 'package:fmp/providers/library/library_invalidation_coordinator.dart';
import 'package:fmp/providers/download/startup_download_sync_provider.dart';
import 'package:fmp/services/download/download_path_sync_service.dart';
import 'package:isar_community/isar.dart';
import '../support/isar_test_harness.dart';
import '../support/pump_until.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeIsarForTests();
  });

  group('startup download sync', () {
    test(
      'unconfigured download path syncs the platform default directory',
      () async {
        final harness = await _createHarness(
          'startup_download_sync_unconfigured',
        );
        addTearDown(harness.dispose);

        // 舊版未選目錄時下載到平台預設（桌面是 Documents/FMP）；那些檔案要能
        // 被同步回來，不能因為使用者沒選過目錄就整段跳過。
        final documentsDir = p.join(harness.tempDir.path, 'documents');
        const pathProviderChannel = MethodChannel(
          'plugins.flutter.io/path_provider',
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documentsDir;
          }
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(pathProviderChannel, null),
        );

        final videoDir = Directory(
          p.join(documentsDir, 'FMP', 'Playlist A', 'video-a'),
        );
        await videoDir.create(recursive: true);
        final audioPath = p.join(videoDir.path, 'audio.m4a');
        await File(audioPath).writeAsString('audio');
        await File(p.join(videoDir.path, 'metadata.json')).writeAsString(
          jsonEncode({
            'sourceId': 'video-a',
            'sourceType': 'youtube',
            'title': 'Video A',
            'artist': 'Artist',
          }),
        );

        final trackRepo = TrackRepository(harness.isar);
        final savedTrack = await trackRepo.save(
          Track()
            ..sourceId = 'video-a'
            ..sourceType = SourceIds.youtube
            ..title = 'Video A'
            ..artist = 'Artist',
        );
        AppLogger.clearLogs();

        await harness.container.read(startupDownloadSyncProvider.future);

        final refreshedTrack = await trackRepo.getById(savedTrack.id);
        expect(refreshedTrack?.allDownloadPaths, [audioPath]);
        expect(
          AppLogger.logs.where((entry) => entry.level == LogLevel.error),
          isEmpty,
        );
      },
    );

    test(
      'successful startup sync updates persisted download path and cache',
      () async {
        final downloadStateChanges = <_DownloadStateChange>[];
        final harness = await _createHarness(
          'startup_download_sync_success',
          downloadStateChanges: downloadStateChanges,
        );
        addTearDown(harness.dispose);

        final downloadsDir = Directory(
          p.join(harness.tempDir.path, 'downloads'),
        );
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
            ..sourceType = SourceIds.youtube
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
      },
    );

    test('a sync that changes nothing keeps the file-exists cache', () async {
      final downloadStateChanges = <_DownloadStateChange>[];
      final harness = await _createHarness(
        'startup_download_sync_unchanged',
        downloadStateChanges: downloadStateChanges,
      );
      addTearDown(harness.dispose);

      final downloadsDir = Directory(p.join(harness.tempDir.path, 'downloads'));
      await downloadsDir.create(recursive: true);
      await SettingsRepository(harness.isar).update((settings) {
        settings.customDownloadDir = downloadsDir.path;
      });
      final playlist = Playlist()..name = 'Playlist A';
      await harness.isar.writeTxn(() => harness.isar.playlists.put(playlist));

      harness.container
          .read(fileExistsCacheProvider.notifier)
          .markAsExisting('/kept/cover.jpg');

      await harness.container.read(startupDownloadSyncProvider.future);

      // 沒有任何路徑變動時，已確認存在的檔案仍然存在：清掉快取只會讓每張封面
      // 重新打一次檔案系統。歌單也沒有被影響，不該有任何一個被點名刷新。
      expect(downloadStateChanges, hasLength(1));
      expect(downloadStateChanges.single.fileExistsChanged, isFalse);
      expect(downloadStateChanges.single.affectedPlaylistIds, isEmpty);
      expect(harness.container.read(fileExistsCacheProvider), {
        '/kept/cover.jpg',
      });
    });

    test('a failing sync is logged instead of failing startup', () async {
      final downloadStateChanges = <_DownloadStateChange>[];
      const failure = FileSystemException('scan refused');
      final harness = await _createHarness(
        'startup_download_sync_failure',
        downloadStateChanges: downloadStateChanges,
        overrides: [
          downloadPathSyncServiceProvider.overrideWith(
            (ref) => _FailingDownloadPathSyncService(
              ref.watch(trackRepositoryProvider),
              ref.watch(downloadPathManagerProvider),
              failure,
            ),
          ),
        ],
      );
      addTearDown(harness.dispose);
      AppLogger.clearLogs();

      // app.dart 只 watch 這個 provider、不處理它的錯誤。它自己拋出來的話不只
      // 是一個錯誤狀態：Riverpod 3 會自動重試，於是每次啟動都反覆掃描同一個
      // 失敗的目錄。所以看的是 provider 的狀態，不是 `.future`（重試期間它一直
      // 不會完成）。
      final subscription = harness.container.listen(
        startupDownloadSyncProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      // 重試期間狀態停在 loading、但已經帶著錯誤，所以兩個出口都要等。
      await pumpUntil(() {
        final state = subscription.read();
        return state.hasValue || state.hasError;
      }, reason: 'the startup sync settles');

      final state = subscription.read();
      expect(state.hasError, isFalse, reason: '${state.error}');
      expect(state.hasValue, isTrue);

      expect(
        AppLogger.logs.where(
          (entry) =>
              entry.level == LogLevel.error &&
              entry.error == failure.toString(),
        ),
        hasLength(1),
      );
      expect(downloadStateChanges, isEmpty);
    });

    test(
      'startup sync matches null-cid metadata to DB track by page number',
      () async {
        final harness = await _createHarness('startup_download_sync_null_cid');
        addTearDown(harness.dispose);

        final downloadsDir = Directory(
          p.join(harness.tempDir.path, 'downloads'),
        );
        final playlistDir = Directory(
          p.join(downloadsDir.path, 'Playlist B', 'video-b'),
        );
        await playlistDir.create(recursive: true);
        final audioPath = p.join(playlistDir.path, 'P02.m4a');
        await File(audioPath).writeAsString('audio');
        await File(p.join(playlistDir.path, 'metadata.json')).writeAsString(
          jsonEncode({
            'sourceId': 'video-b',
            'sourceType': 'bilibili',
            'title': 'Video B',
            'artist': 'Artist',
            'pageNum': 1,
          }),
        );

        final settingsRepo = SettingsRepository(harness.isar);
        await settingsRepo.update((settings) {
          settings.customDownloadDir = downloadsDir.path;
        });

        final trackRepo = TrackRepository(harness.isar);
        final savedTrack = await trackRepo.save(
          Track()
            ..sourceId = 'video-b'
            ..sourceType = SourceIds.bilibili
            ..title = 'Video B P2'
            ..artist = 'Artist'
            ..cid = 2002
            ..pageNum = 2,
        );

        await harness.container.read(startupDownloadSyncProvider.future);

        final refreshedTrack = await trackRepo.getById(savedTrack.id);
        expect(refreshedTrack?.allDownloadPaths, [audioPath]);
      },
    );
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

class _FailingDownloadPathSyncService extends DownloadPathSyncService {
  _FailingDownloadPathSyncService(
    super.trackRepo,
    super.pathManager,
    this.failure,
  );

  final Object failure;

  @override
  Future<(int added, int removed)> syncLocalFiles({
    void Function(int current, int total)? onProgress,
  }) async {
    throw failure;
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
         logBackgroundError: (_, _, _) {},
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
  List<Override> overrides = const [],
}) async {
  final tempDir = await Directory.systemTemp.createTemp('${name}_');
  final isar = await Isar.open(
    [TrackSchema, PlaylistSchema, SettingsSchema],
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
      ...overrides,
    ],
  );

  return _Harness(container: container, isar: isar, tempDir: tempDir);
}
