import 'dart:convert';
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
import 'package:fmp/providers/download/download_path_provider.dart';
import 'package:fmp/data/database/repository_providers.dart'
    as repository_providers;
import 'package:fmp/services/download/download_path_maintenance_service.dart';
import 'package:fmp/services/download/download_path_manager.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadPathMaintenanceService', () {
    late Directory tempDir;
    late Isar isar;
    late TrackRepository trackRepository;
    late DownloadRepository downloadRepository;
    late SettingsRepository settingsRepository;
    late DownloadPathManager pathManager;
    late DownloadPathMaintenanceService service;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'download_path_maintenance_test_',
      );
      isar = await Isar.open(
        [TrackSchema, DownloadTaskSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'download_path_maintenance_test',
      );
      trackRepository = TrackRepository(isar);
      downloadRepository = DownloadRepository(isar);
      settingsRepository = SettingsRepository(isar);
      pathManager = DownloadPathManager(settingsRepository);
      // 下載根目錄＝測試用的 temp dir：containment guard 在所有測試裡都是開著
      // 的，而既有案例的檔案本來就都在 tempDir 底下。
      await pathManager.saveDownloadPath(tempDir.path);
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
            repository_providers.trackRepositoryProvider.overrideWith(
              (ref) => trackRepository,
            ),
            repository_providers.settingsRepositoryProvider.overrideWith(
              (ref) => settingsRepository,
            ),
            download_providers.downloadRepositoryProvider.overrideWith(
              (ref) => downloadRepository,
            ),
            download_providers.downloadServiceProvider.overrideWith((ref) {
              throw StateError('downloadServiceProvider should not be read');
            }),
          ],
        );
        addTearDown(container.dispose);

        final providerService = container.read(
          downloadPathMaintenanceServiceProvider,
        );

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
              _info(77, 'Gamma', '${tempDir.path}/gamma/audio.m4a'),
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
        expect(remainingTasks.map((task) => task.status), [
          DownloadStatus.pending,
        ]);
      },
    );

    test(
      'deleteDownloadedTracks clears only the matching multi-page entry by cid',
      () async {
        final pageOneFolder = Directory(
          '${tempDir.path}/Playlist A/video-multi',
        );
        await pageOneFolder.create(recursive: true);
        final pageOneAudioPath = '${pageOneFolder.path}/P01.m4a';
        await File(pageOneAudioPath).writeAsString('audio');
        // 擁有權要證明的出來才刪得掉：沒有配對 metadata 的音檔在外來檔案面前
        // 沒有分辨方法，這一條測的是 cid 配對，不是擁有權。
        await File(
          '${pageOneFolder.path}/metadata_P01.json',
        ).writeAsString(_metadataJson('video-multi'));

        final pageTwoFolder = Directory(
          '${tempDir.path}/Playlist B/video-multi',
        );
        await pageTwoFolder.create(recursive: true);
        final pageTwoAudioPath = '${pageTwoFolder.path}/P02.m4a';
        await File(pageTwoAudioPath).writeAsString('audio');

        final persistedPageOne = await trackRepository.save(
          _track('video-multi')
            ..cid = 101
            ..pageNum = 1
            ..playlistInfo = [_info(1, 'Playlist A', pageOneAudioPath)],
        );
        final persistedPageTwo = await trackRepository.save(
          _track('video-multi')
            ..cid = 202
            ..pageNum = 2
            ..playlistInfo = [_info(2, 'Playlist B', pageTwoAudioPath)],
        );

        final scannedTrack = _track('video-multi')
          ..cid = 101
          ..pageNum = 1
          ..playlistInfo = [_info(0, 'Playlist A', pageOneAudioPath)];

        final result = await service.deleteDownloadedTracks([scannedTrack]);

        expect(result.clearedPathCount, 1);
        expect(result.affectedPlaylistIds, [1]);
        expect(await File(pageOneAudioPath).exists(), isFalse);
        expect(await File(pageTwoAudioPath).exists(), isTrue);

        final refreshedPageOne = await trackRepository.getById(
          persistedPageOne.id,
        );
        final refreshedPageTwo = await trackRepository.getById(
          persistedPageTwo.id,
        );
        expect(refreshedPageOne?.playlistInfo.single.downloadPath, '');
        expect(
          refreshedPageTwo?.playlistInfo.single.downloadPath,
          pageTwoAudioPath,
        );
      },
    );

    test(
      'deleteDownloadedTracks keeps sibling audio files in the same folder',
      () async {
        final folder = Directory('${tempDir.path}/Playlist A/video-multi');
        await folder.create(recursive: true);
        final pageOneAudioPath = '${folder.path}/P01.m4a';
        final pageTwoAudioPath = '${folder.path}/P02.m4a';
        final pageOneMetadataPath = '${folder.path}/metadata_P01.json';
        final pageTwoMetadataPath = '${folder.path}/metadata_P02.json';
        final coverPath = '${folder.path}/cover.jpg';
        final avatarPath = '${folder.path}/avatar.jpg';
        await File(pageOneAudioPath).writeAsString('audio');
        await File(pageTwoAudioPath).writeAsString('audio');
        await File(pageOneMetadataPath).writeAsString('{}');
        await File(pageTwoMetadataPath).writeAsString('{}');
        await File(coverPath).writeAsString('image');
        await File(avatarPath).writeAsString('image');

        final persistedPageOne = await trackRepository.save(
          _track('video-multi')
            ..cid = 101
            ..pageNum = 1
            ..playlistInfo = [_info(1, 'Playlist A', pageOneAudioPath)],
        );
        final persistedPageTwo = await trackRepository.save(
          _track('video-multi')
            ..cid = 202
            ..pageNum = 2
            ..playlistInfo = [_info(1, 'Playlist A', pageTwoAudioPath)],
        );

        final scannedTrack = _track('video-multi')
          ..cid = 101
          ..pageNum = 1
          ..playlistInfo = [_info(0, 'Playlist A', pageOneAudioPath)];

        final result = await service.deleteDownloadedTracks([scannedTrack]);

        expect(result.clearedPathCount, 1);
        expect(result.affectedPlaylistIds, [1]);
        expect(await Directory(folder.path).exists(), isTrue);
        expect(await File(pageOneAudioPath).exists(), isFalse);
        expect(await File(pageOneMetadataPath).exists(), isFalse);
        expect(await File(pageTwoAudioPath).exists(), isTrue);
        expect(await File(pageTwoMetadataPath).exists(), isTrue);
        // P02 還在，封面與頭像就還有人要 —— 這是「無剩餘音檔才刪產物」的閘門。
        expect(await File(coverPath).exists(), isTrue);
        expect(await File(avatarPath).exists(), isTrue);
        expect(result.skippedForeignCount, 0);

        final refreshedPageOne = await trackRepository.getById(
          persistedPageOne.id,
        );
        final refreshedPageTwo = await trackRepository.getById(
          persistedPageTwo.id,
        );
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

        final result = await service.deleteDownloadedCategory(
          '${tempDir.path}/Playlist A',
        );

        expect(result.clearedPathCount, 1);
        expect(result.affectedPlaylistIds, [1]);
        expect(result.skippedForeignCount, 0);
        expect(await Directory('${tempDir.path}/Playlist A').exists(), isFalse);

        final persistedTrack = await trackRepository.getById(savedTrack.id);
        expect(persistedTrack?.playlistInfo.map((info) => info.downloadPath), [
          '',
          keptAudioPath,
        ]);
        expect(persistedTrack?.playlistInfo.map((info) => info.playlistId), [
          1,
          2,
        ]);
      },
    );

    test(
      'deleteDownloadedCategory keeps files FMP cannot prove it wrote',
      () async {
        final categoryPath = '${tempDir.path}/Playlist A';
        final ownedFolderPath = '$categoryPath/video-a';
        final ownedAudioPath = '$ownedFolderPath/audio.m4a';
        final notesPath = '$ownedFolderPath/notes.txt';
        final foreignAudioPath = '$ownedFolderPath/my_song.mp3';
        await _write(ownedAudioPath, 'audio');
        await _write(
          '$ownedFolderPath/metadata.json',
          _metadataJson('video-a'),
        );
        await _write(notesPath, 'notes');
        await _write(foreignAudioPath, 'song');

        final pureFolderPath = '$categoryPath/video-b';
        final pureAudioPath = '$pureFolderPath/audio.m4a';
        await _write(pureAudioPath, 'audio');
        await _write('$pureFolderPath/metadata.json', _metadataJson('video-b'));

        final ownedTrack = await trackRepository.save(
          _track('video-a')
            ..playlistInfo = [_info(1, 'Playlist A', ownedAudioPath)],
        );
        final pureTrack = await trackRepository.save(
          _track('video-b')
            ..playlistInfo = [_info(1, 'Playlist A', pureAudioPath)],
        );

        final result = await service.deleteDownloadedCategory(categoryPath);

        // 認不出擁有權的只有 notes.txt 與 my_song.mp3。
        expect(result.skippedForeignCount, 2);
        // 兩首 FMP 音檔都真的被刪掉，DB 也跟著清。
        expect(result.clearedPathCount, 2);
        expect(result.affectedPlaylistIds, [1]);

        // 純 FMP 的資料夾整間消失。
        expect(await Directory(pureFolderPath).exists(), isFalse);
        // 使用者自己放的檔案還在，所以資料夾與分類都還在。
        expect(_entriesIn(ownedFolderPath), ['my_song.mp3', 'notes.txt']);
        expect(await Directory(categoryPath).exists(), isTrue);

        final persistedOwned = await trackRepository.getById(ownedTrack.id);
        final persistedPure = await trackRepository.getById(pureTrack.id);
        expect(persistedOwned?.playlistInfo.single.downloadPath, '');
        expect(persistedPure?.playlistInfo.single.downloadPath, '');
      },
    );

    test(
      'deleteDownloadedCategory leaves an audio file with no paired metadata',
      () async {
        final folderPath = '${tempDir.path}/Playlist A/video-c';
        final audioPath = '$folderPath/audio.m4a';
        await _write(audioPath, 'audio');

        // 掃描端對沒有 metadata 的 .m4a 會合成 fallback DTO（sourceType 走
        // bilibili），所以使用者自有的 .m4a 真的會出現在分類頁上；這裡讓
        // DB 那一列對得上，刪掉檔案就會被斷言抓到。
        final savedTrack = await trackRepository.save(
          _track('video-c')
            ..sourceType = SourceIds.bilibili
            ..playlistInfo = [_info(3, 'Playlist A', audioPath)],
        );

        final result = await service.deleteDownloadedCategory(
          '${tempDir.path}/Playlist A',
        );

        expect(result.skippedForeignCount, 1);
        expect(result.clearedPathCount, 0);
        expect(result.affectedPlaylistIds, isEmpty);
        expect(await File(audioPath).exists(), isTrue);
        expect(await Directory(folderPath).exists(), isTrue);

        final persisted = await trackRepository.getById(savedTrack.id);
        expect(persisted?.playlistInfo.single.downloadPath, audioPath);
      },
    );

    test(
      'deleteDownloadedTracks deletes the page metadata but keeps user files',
      () async {
        final folderPath = '${tempDir.path}/Playlist A/video-multi';
        final audioPath = '$folderPath/P01.m4a';
        final metadataPath = '$folderPath/metadata_P01.json';
        final notesPath = '$folderPath/notes.txt';
        final coverPath = '$folderPath/cover.jpg';
        final avatarPath = '$folderPath/avatar.jpg';
        await _write(audioPath, 'audio');
        await _write(metadataPath, '{}');
        await _write(notesPath, 'notes');
        await _write(coverPath, 'image');
        await _write(avatarPath, 'image');

        final persisted = await trackRepository.save(
          _track('video-multi')
            ..cid = 101
            ..pageNum = 1
            ..playlistInfo = [_info(1, 'Playlist A', audioPath)],
        );

        final scannedTrack = _track('video-multi')
          ..cid = 101
          ..pageNum = 1
          ..playlistInfo = [_info(0, 'Playlist A', audioPath)];

        final result = await service.deleteDownloadedTracks([scannedTrack]);

        expect(result.clearedPathCount, 1);
        expect(result.affectedPlaylistIds, [1]);
        expect(await File(audioPath).exists(), isFalse);
        expect(await File(metadataPath).exists(), isFalse);
        // 資料夾已經沒有 FMP 音檔，封面與頭像跟著走；notes.txt 不是音檔，
        // 也不是 FMP 寫的，它讓資料夾留下來。
        expect(await File(coverPath).exists(), isFalse);
        expect(await File(avatarPath).exists(), isFalse);
        expect(await File(notesPath).exists(), isTrue);
        expect(await Directory(folderPath).exists(), isTrue);
        expect(result.skippedForeignCount, 1);

        final refreshed = await trackRepository.getById(persisted.id);
        expect(refreshed?.playlistInfo.single.downloadPath, '');
      },
    );

    test(
      'deleteDownloadedTracks keeps a shared metadata.json for sibling pages',
      () async {
        final folderPath = '${tempDir.path}/Playlist A/video-legacy';
        final pageOnePath = '$folderPath/P01.m4a';
        final pageTwoPath = '$folderPath/P02.m4a';
        final sharedMetadataPath = '$folderPath/metadata.json';
        await _write(pageOnePath, 'audio');
        await _write(pageTwoPath, 'audio');
        await _write(sharedMetadataPath, _metadataJson('video-legacy'));

        final persistedPageOne = await trackRepository.save(
          _track('video-legacy')
            ..cid = 101
            ..pageNum = 1
            ..playlistInfo = [_info(1, 'Playlist A', pageOnePath)],
        );
        await trackRepository.save(
          _track('video-legacy')
            ..cid = 202
            ..pageNum = 2
            ..playlistInfo = [_info(1, 'Playlist A', pageTwoPath)],
        );

        final scannedTrack = _track('video-legacy')
          ..cid = 101
          ..pageNum = 1
          ..playlistInfo = [_info(0, 'Playlist A', pageOnePath)];

        final result = await service.deleteDownloadedTracks([scannedTrack]);

        expect(result.clearedPathCount, 1);
        expect(await File(pageOnePath).exists(), isFalse);
        // 舊版佈局的多頁資料夾共用同一個 metadata.json，P02 還在讀它。
        expect(await File(sharedMetadataPath).exists(), isTrue);
        expect(await File(pageTwoPath).exists(), isTrue);
        expect(result.skippedForeignCount, 0);

        final refreshed = await trackRepository.getById(persistedPageOne.id);
        expect(refreshed?.playlistInfo.single.downloadPath, '');
      },
    );

    test(
      'deleteDownloadedTracks keeps the shared metadata of old-style page names',
      () async {
        final folderPath = '${tempDir.path}/Playlist A/video-old';
        final pageOnePath = '$folderPath/P01 - 第一話.m4a';
        final pageTwoPath = '$folderPath/P02 - 第二話.m4a';
        final sharedMetadataPath = '$folderPath/metadata.json';
        await _write(pageOnePath, 'audio');
        await _write(pageTwoPath, 'audio');
        await _write(sharedMetadataPath, _metadataJson('video-old'));

        await trackRepository.save(
          _track('video-old')
            ..cid = 101
            ..pageNum = 1
            ..playlistInfo = [_info(1, 'Playlist A', pageOnePath)],
        );
        await trackRepository.save(
          _track('video-old')
            ..cid = 202
            ..pageNum = 2
            ..playlistInfo = [_info(1, 'Playlist A', pageTwoPath)],
        );

        final scannedTrack = _track('video-old')
          ..cid = 101
          ..pageNum = 1
          ..playlistInfo = [_info(0, 'Playlist A', pageOnePath)];

        await service.deleteDownloadedTracks([scannedTrack]);

        expect(await File(pageOnePath).exists(), isFalse);
        // 舊版檔名配不到專屬 metadata，這一份是兩個分P共用的一一留著。
        expect(await File(sharedMetadataPath).exists(), isTrue);
        expect(await File(pageTwoPath).exists(), isTrue);
      },
    );

    test(
      'deleteDownloadedTracks counts an unproven target path exactly once',
      () async {
        // 目標路徑本身認不出擁有權（沒有配對 metadata 的 .m4a）。它會在迴圈裡
        // 被跳過，之後 `_countUnprovenItems` 掃同一個資料夾時再遇到一次——
        // 兩處都計數就是 2。使用者看到的 warning toast 數字必須是 1。
        final folderPath = '${tempDir.path}/Playlist A/video-unproven';
        final audioPath = '$folderPath/audio.m4a';
        await _write(audioPath, 'audio');

        final savedTrack = await trackRepository.save(
          _track('video-unproven')
            ..playlistInfo = [_info(1, 'Playlist A', audioPath)],
        );

        final scannedTrack = _track('video-unproven')
          ..playlistInfo = [_info(0, 'Playlist A', audioPath)];

        final result = await service.deleteDownloadedTracks([scannedTrack]);

        expect(result.skippedForeignCount, 1);
        expect(result.clearedPathCount, 0);
        expect(await File(audioPath).exists(), isTrue);

        final persisted = await trackRepository.getById(savedTrack.id);
        expect(persisted?.playlistInfo.single.downloadPath, audioPath);
      },
    );

    test(
      'deleteDownloadedCategory refuses a target outside the download base',
      () async {
        // base 換到 tempDir 底下的另一個位置，刪除目標落在 base 之外。
        await pathManager.saveDownloadPath('${tempDir.path}/Music/FMP');

        final folderPath = '${tempDir.path}/Other/video-z';
        final audioPath = '$folderPath/audio.m4a';
        final metadataPath = '$folderPath/metadata.json';
        await _write(audioPath, 'audio');
        await _write(metadataPath, _metadataJson('video-z'));

        final savedTrack = await trackRepository.save(
          _track('video-z')..playlistInfo = [_info(4, 'Other', audioPath)],
        );

        final result = await service.deleteDownloadedCategory(
          '${tempDir.path}/Other',
        );

        expect(result.clearedPathCount, 0);
        expect(result.skippedForeignCount, 0);
        expect(result.affectedPlaylistIds, isEmpty);
        expect(await File(audioPath).exists(), isTrue);
        expect(await File(metadataPath).exists(), isTrue);
        expect(await Directory(folderPath).exists(), isTrue);

        final persisted = await trackRepository.getById(savedTrack.id);
        expect(persisted?.playlistInfo.single.downloadPath, audioPath);
      },
    );

    test(
      'deleteDownloadedTracks skips only the paths outside the download base',
      () async {
        // 清單可能混著一筆過期的 DB 路徑：那一筆跳過，其餘照刪。整體拒絕的話，
        // 合法的下載就刪不掉了。
        await pathManager.saveDownloadPath('${tempDir.path}/Music/FMP');

        final insideFolder = '${tempDir.path}/Music/FMP/Playlist A/video-in';
        final insideAudio = '$insideFolder/audio.m4a';
        await _write(insideAudio, 'audio');
        await _write('$insideFolder/metadata.json', _metadataJson('video-in'));

        final outsideFolder = '${tempDir.path}/Other/video-out';
        final outsideAudio = '$outsideFolder/audio.m4a';
        final outsideMetadata = '$outsideFolder/metadata.json';
        await _write(outsideAudio, 'audio');
        await _write(outsideMetadata, _metadataJson('video-out'));

        final result = await service.deleteDownloadedTracks([
          _track('video-in')
            ..playlistInfo = [_info(0, 'Playlist A', insideAudio)],
          _track('video-out')..playlistInfo = [_info(0, 'Other', outsideAudio)],
        ]);

        expect(await File(insideAudio).exists(), isFalse);
        expect(await File(outsideAudio).exists(), isTrue);
        expect(await File(outsideMetadata).exists(), isTrue);
        expect(result.skippedForeignCount, 1);
      },
    );

    test(
      'deleteDownloadedCategory never touches .downloading temp files',
      () async {
        final folderPath = '${tempDir.path}/Playlist A/video-d';
        final audioPath = '$folderPath/audio.m4a';
        final metadataPath = '$folderPath/metadata.json';
        final tempPath = '$audioPath.downloading';
        await _write(audioPath, 'audio');
        await _write(metadataPath, _metadataJson('video-d'));
        await _write(tempPath, 'partial');

        final result = await service.deleteDownloadedCategory(
          '${tempDir.path}/Playlist A',
        );

        expect(await File(audioPath).exists(), isFalse);
        expect(await File(metadataPath).exists(), isFalse);
        // 暫存檔屬於還在佇列上的可續傳任務，由啟動孤兒掃描處理；它不算外來
        // 檔案，但資料夾因此不空，所以也不會被空目錄刪除帶走。
        expect(await File(tempPath).exists(), isTrue);
        expect(await Directory(folderPath).exists(), isTrue);
        expect(result.skippedForeignCount, 0);
      },
    );
  });
}

Track _track(String sourceId) => Track()
  ..sourceId = sourceId
  ..sourceType = SourceIds.youtube
  ..title = sourceId
  ..artist = 'Artist';

PlaylistDownloadInfo _info(
  int playlistId,
  String playlistName,
  String downloadPath,
) {
  return PlaylistDownloadInfo()
    ..playlistId = playlistId
    ..playlistName = playlistName
    ..downloadPath = downloadPath;
}

/// 建檔（含上層目錄）。
Future<void> _write(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

/// 與 `DownloadScanner` 認得的下載 metadata 同形。
String _metadataJson(String sourceId) => jsonEncode({
  'sourceId': sourceId,
  'sourceType': SourceIds.youtube,
  'title': sourceId,
  'artist': 'Artist',
});

/// 資料夾底下的檔名，排序後。
List<String> _entriesIn(String dirPath) {
  final names = Directory(
    dirPath,
  ).listSync().map((entity) => p.basename(entity.path)).toList();
  names.sort();
  return names;
}
