import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:isar_community/isar.dart';
import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeIsarForTests();
  });

  test('getBySourceIdentities keeps source type and nullable cid distinct',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'track_repository_batch_identity_test_',
    );
    final isar = await Isar.open(
      [TrackSchema],
      directory: tempDir.path,
      name: 'track_repository_batch_identity_test',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final repo = TrackRepository(isar);

    final youtubeNull =
        await repo.save(_track('same', SourceType.youtube, 'YT'));
    final youtubeCid = await repo.save(
      _track('same', SourceType.youtube, 'YT P2')..cid = 22,
    );
    final bilibiliNull = await repo.save(
      _track('same', SourceType.bilibili, 'BV'),
    );

    final result = await repo.getBySourceIdentities([
      TrackSourceIdentity.fromTrack(youtubeNull),
      TrackSourceIdentity.fromTrack(youtubeCid),
      TrackSourceIdentity.fromTrack(bilibiliNull),
    ]);

    expect(
        result[TrackSourceIdentity.fromTrack(youtubeNull)]?.id, youtubeNull.id);
    expect(
        result[TrackSourceIdentity.fromTrack(youtubeCid)]?.id, youtubeCid.id);
    expect(result[TrackSourceIdentity.fromTrack(bilibiliNull)]?.id,
        bilibiliNull.id);
  });

  test('cleanupInvalidDownloadPaths preserves playlist names', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'track_repository_cleanup_playlist_name_test_',
    );
    final isar = await Isar.open(
      [TrackSchema],
      directory: tempDir.path,
      name: 'track_repository_cleanup_playlist_name_test',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final repo = TrackRepository(isar);
    final validFile = File('${tempDir.path}/valid.m4a');
    await validFile.writeAsString('audio');

    final track = await repo.save(
      _track('cleanup-track', SourceType.youtube, 'Cleanup Track')
        ..playlistInfo = [
          PlaylistDownloadInfo()
            ..playlistId = 1
            ..playlistName = 'Valid Playlist'
            ..downloadPath = validFile.path,
          PlaylistDownloadInfo()
            ..playlistId = 2
            ..playlistName = 'Missing Playlist'
            ..downloadPath = '${tempDir.path}/missing.m4a',
        ],
    );

    final cleanedCount = await repo.cleanupInvalidDownloadPaths();

    expect(cleanedCount, 1);
    final refreshed = await repo.getById(track.id);
    expect(refreshed, isNotNull);
    expect(
      refreshed!.playlistInfo.map(
        (info) => (
          playlistId: info.playlistId,
          playlistName: info.playlistName,
          hasDownloadPath: info.downloadPath.isNotEmpty,
        ),
      ),
      [
        (
          playlistId: 1,
          playlistName: 'Valid Playlist',
          hasDownloadPath: true,
        ),
        (
          playlistId: 2,
          playlistName: 'Missing Playlist',
          hasDownloadPath: false,
        ),
      ],
    );
  });
}

Track _track(String sourceId, SourceType sourceType, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = title
    ..createdAt = DateTime.now();
}
