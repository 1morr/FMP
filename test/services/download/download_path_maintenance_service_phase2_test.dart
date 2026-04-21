import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/download_task.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/download_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/providers/download/download_providers.dart'
    as download_providers;
import 'package:fmp/providers/download_path_provider.dart';
import 'package:fmp/providers/repository_providers.dart' as repository_providers;
import 'package:fmp/services/download/download_path_maintenance_service.dart';
import 'package:fmp/services/download/download_path_manager.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadPathMaintenanceService phase 2', () {
    late Directory tempDir;
    late Isar isar;
    late TrackRepository trackRepository;
    late DownloadRepository downloadRepository;
    late SettingsRepository settingsRepository;
    late DownloadPathManager pathManager;
    late DownloadPathMaintenanceService service;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'download_path_maintenance_phase2_test_',
      );
      isar = await Isar.open(
        [TrackSchema, DownloadTaskSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'download_path_maintenance_phase2_test',
      );
      trackRepository = TrackRepository(isar);
      downloadRepository = DownloadRepository(isar);
      settingsRepository = SettingsRepository(isar);
      pathManager = DownloadPathManager(settingsRepository);
      service = DownloadPathMaintenanceService(
        trackRepository: trackRepository,
        pathManager: pathManager,
        clearCompletedAndErrorTasks:
            downloadRepository.clearCompletedAndErrorTasks,
      );
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'downloadPathMaintenanceServiceProvider builds without touching downloadServiceProvider',
      () async {
        final container = ProviderContainer(
          overrides: [
            repository_providers.trackRepositoryProvider
                .overrideWith((ref) => trackRepository),
            repository_providers.settingsRepositoryProvider
                .overrideWith((ref) => settingsRepository),
            download_providers.downloadRepositoryProvider
                .overrideWith((ref) => downloadRepository),
            download_providers.downloadServiceProvider.overrideWith((ref) {
              throw StateError('downloadServiceProvider should not be read');
            }),
          ],
        );
        addTearDown(container.dispose);

        final providerService =
            container.read(downloadPathMaintenanceServiceProvider);

        expect(providerService, isA<DownloadPathMaintenanceService>());
      },
    );

    test(
      'changeBasePathAndResetDownloads clears paths and tasks then saves new path',
      () async {
        final trackA = await trackRepository.save(
          _track('source-a')
            ..playlistInfo = [
              _info(11, 'Alpha', '${tempDir.path}/alpha/audio.m4a'),
              _info(12, 'Beta', '${tempDir.path}/beta/audio.m4a'),
            ],
        );
        await trackRepository.save(
          _track('source-b')
            ..playlistInfo = [
              _info(77, 'Gamma', '${tempDir.path}/gamma/audio.m4a')
            ],
        );
        await trackRepository.save(_track('source-c'));

        await downloadRepository.saveTask(
          DownloadTask()
            ..trackId = trackA.id
            ..status = DownloadStatus.completed,
        );
        await downloadRepository.saveTask(
          DownloadTask()
            ..trackId = trackA.id
            ..status = DownloadStatus.failed,
        );
        await downloadRepository.saveTask(
          DownloadTask()
            ..trackId = trackA.id
            ..status = DownloadStatus.pending,
        );

        final result = await service.changeBasePathAndResetDownloads(
          '${tempDir.path}/new-base',
        );

        expect(result.clearedDownloadTrackCount, 2);
        expect(result.clearedTaskCount, 2);
        expect(result.affectedPlaylistIds, [11, 12, 77]);

        final savedA = await trackRepository.getById(trackA.id);
        expect(savedA?.playlistInfo.map((info) => info.downloadPath), ['', '']);
        expect(savedA?.playlistInfo.map((info) => info.playlistId), [11, 12]);

        final settings = await settingsRepository.get();
        expect(settings.customDownloadDir, '${tempDir.path}/new-base');

        final remainingTasks = await downloadRepository.getAllTasks();
        expect(remainingTasks.map((task) => task.status),
            [DownloadStatus.pending]);
      },
    );

    test(
      'deleteDownloadedTracks clears only the matching multi-page entry by cid',
      () async {
        final pageOneFolder = Directory('${tempDir.path}/Playlist A/video-multi');
        await pageOneFolder.create(recursive: true);
        final pageOneAudioPath = '${pageOneFolder.path}/P01.m4a';
        await File(pageOneAudioPath).writeAsString('audio');

        final pageTwoFolder = Directory('${tempDir.path}/Playlist B/video-multi');
        await pageTwoFolder.create(recursive: true);
        final pageTwoAudioPath = '${pageTwoFolder.path}/P02.m4a';
        await File(pageTwoAudioPath).writeAsString('audio');

        final persistedPageOne = await trackRepository.save(
          _track('video-multi')
            ..cid = 101
            ..pageNum = 1
            ..playlistInfo = [
              _info(1, 'Playlist A', pageOneAudioPath),
            ],
        );
        final persistedPageTwo = await trackRepository.save(
          _track('video-multi')
            ..cid = 202
            ..pageNum = 2
            ..playlistInfo = [
              _info(2, 'Playlist B', pageTwoAudioPath),
            ],
        );

        final scannedTrack = _track('video-multi')
          ..cid = 101
          ..pageNum = 1
          ..playlistInfo = [
            _info(0, 'Playlist A', pageOneAudioPath),
          ];

        final result = await service.deleteDownloadedTracks([scannedTrack]);

        expect(result.clearedPathCount, 1);
        expect(result.affectedPlaylistIds, [1]);
        expect(await File(pageOneAudioPath).exists(), isFalse);
        expect(await File(pageTwoAudioPath).exists(), isTrue);

        final refreshedPageOne =
            await trackRepository.getById(persistedPageOne.id);
        final refreshedPageTwo =
            await trackRepository.getById(persistedPageTwo.id);
        expect(refreshedPageOne?.playlistInfo.single.downloadPath, '');
        expect(
          refreshedPageTwo?.playlistInfo.single.downloadPath,
          pageTwoAudioPath,
        );
      },
    );

    test(
      'deleteDownloadedCategory clears only matching persisted paths for deleted files',
      () async {
        final deletedFolder = Directory('${tempDir.path}/Playlist A/video-a');
        await deletedFolder.create(recursive: true);
        final deletedAudioPath = '${deletedFolder.path}/audio.m4a';
        await File(deletedAudioPath).writeAsString('audio');
        await File('${deletedFolder.path}/metadata.json').writeAsString(
          jsonEncode({
            'sourceId': 'video-a',
            'sourceType': 'youtube',
            'title': 'Video A',
            'artist': 'Artist',
          }),
        );

        final keptFolder = Directory('${tempDir.path}/Playlist B/video-a');
        await keptFolder.create(recursive: true);
        final keptAudioPath = '${keptFolder.path}/audio.m4a';
        await File(keptAudioPath).writeAsString('audio');

        final savedTrack = await trackRepository.save(
          _track('video-a')
            ..playlistInfo = [
              _info(1, 'Playlist A', deletedAudioPath),
              _info(2, 'Playlist B', keptAudioPath),
            ],
        );

        final result =
            await service.deleteDownloadedCategory('${tempDir.path}/Playlist A');

        expect(result.clearedPathCount, 1);
        expect(result.affectedPlaylistIds, [1]);
        expect(await Directory('${tempDir.path}/Playlist A').exists(), isFalse);

        final persistedTrack = await trackRepository.getById(savedTrack.id);
        expect(persistedTrack?.playlistInfo.map((info) => info.downloadPath),
            ['', keptAudioPath]);
        expect(persistedTrack?.playlistInfo.map((info) => info.playlistId),
            [1, 2]);
      },
    );
  });
}

Track _track(String sourceId) => Track()
  ..sourceId = sourceId
  ..sourceType = SourceType.youtube
  ..title = sourceId
  ..artist = 'Artist';

PlaylistDownloadInfo _info(
    int playlistId, String playlistName, String downloadPath) {
  return PlaylistDownloadInfo()
    ..playlistId = playlistId
    ..playlistName = playlistName
    ..downloadPath = downloadPath;
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') continue;
    final packageDir = Directory(packageConfigDir.uri
        .resolve(package['rootUri'] as String)
        .toFilePath());
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
