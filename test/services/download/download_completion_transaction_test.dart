import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/download_task.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/download_repository.dart';
import 'package:isar_community/isar.dart';
import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadRepository completion transaction', () {
    setUpAll(() async {
      await initializeIsarForTests();
    });

    test(
      'completeTaskWithDownloadPath updates track and task together',
      () async {
        final harness = await _createHarness();
        addTearDown(harness.dispose);

        final trackId = await harness.isar.writeTxn(() async {
          return harness.isar.tracks.put(
            Track()
              ..sourceId = 'yt-complete'
              ..sourceType = SourceIds.youtube
              ..title = 'Complete Track'
              ..createdAt = DateTime.now(),
          );
        });
        final task = await harness.repository.saveTask(
          DownloadTask()
            ..trackId = trackId
            ..playlistId = 7
            ..playlistName = 'Downloaded Playlist'
            ..savePath = 'C:/Music/FMP/Downloaded Playlist/audio.m4a'
            ..status = DownloadStatus.downloading
            ..createdAt = DateTime.now(),
        );

        await harness.repository.completeTaskWithDownloadPath(
          taskId: task.id,
          savePath: 'C:/Music/FMP/Downloaded Playlist/audio.m4a',
        );

        final updatedTrack = await harness.isar.tracks.get(trackId);
        final updatedTask = await harness.repository.getTaskById(task.id);
        expect(
          updatedTrack!.getDownloadPath(7),
          'C:/Music/FMP/Downloaded Playlist/audio.m4a',
        );
        expect(updatedTask!.status, DownloadStatus.completed);
        expect(updatedTask.completedAt, isNotNull);
      },
    );

    test(
      'completeTaskWithDownloadPath does not complete when track is missing',
      () async {
        final harness = await _createHarness();
        addTearDown(harness.dispose);

        final task = await harness.repository.saveTask(
          DownloadTask()
            ..trackId = 999
            ..status = DownloadStatus.downloading
            ..createdAt = DateTime.now(),
        );

        await expectLater(
          harness.repository.completeTaskWithDownloadPath(
            taskId: task.id,
            savePath: 'C:/Music/FMP/Missing/audio.m4a',
          ),
          throwsStateError,
        );

        final updatedTask = await harness.repository.getTaskById(task.id);
        expect(updatedTask!.status, DownloadStatus.downloading);
      },
    );

    test(
      'completeTaskWithDownloadPath does not update track when task is missing',
      () async {
        final harness = await _createHarness();
        addTearDown(harness.dispose);

        final trackId = await harness.isar.writeTxn(() async {
          return harness.isar.tracks.put(
            Track()
              ..sourceId = 'yt-missing-task'
              ..sourceType = SourceIds.youtube
              ..title = 'Missing Task Track'
              ..createdAt = DateTime.now(),
          );
        });

        await expectLater(
          harness.repository.completeTaskWithDownloadPath(
            taskId: 999,
            savePath: 'C:/Music/FMP/MissingTask/audio.m4a',
          ),
          throwsStateError,
        );

        final updatedTrack = await harness.isar.tracks.get(trackId);
        expect(updatedTrack!.hasAnyDownload, isFalse);
      },
    );
  });
}

class _Harness {
  _Harness(this.isar) : repository = DownloadRepository(isar);

  final Isar isar;
  final DownloadRepository repository;

  Future<void> dispose() async {
    final dir = Directory(isar.directory!);
    await isar.close(deleteFromDisk: true);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'download_completion_transaction_test_',
  );
  final isar = await Isar.open(
    [TrackSchema, DownloadTaskSchema],
    directory: tempDir.path,
    name: 'download_completion_transaction_test',
  );
  return _Harness(isar);
}
