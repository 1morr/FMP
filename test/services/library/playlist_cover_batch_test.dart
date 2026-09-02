import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/services/library/playlist_service.dart';
import 'package:isar_community/isar.dart';
import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeIsarForTests();
  });

  test(
      'getPlaylistCoverDataForPlaylists resolves first-track covers in one batch',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'playlist_cover_batch_test_',
    );
    final isar = await Isar.open(
      [PlaylistSchema, TrackSchema, SettingsSchema],
      directory: tempDir.path,
      name: 'playlist_cover_batch_test',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final playlistRepo = PlaylistRepository(isar);
    final trackRepo = TrackRepository(isar);
    final service = PlaylistService(
      playlistRepository: playlistRepo,
      trackRepository: trackRepo,
      settingsRepository: SettingsRepository(isar),
      isar: isar,
    );
    final firstTrack = await trackRepo.save(_track('first'));
    final secondTrack = await trackRepo.save(_track('second'));
    final firstPlaylist = Playlist()
      ..name = 'First'
      ..trackIds = [firstTrack.id]
      ..createdAt = DateTime.now();
    final secondPlaylist = Playlist()
      ..name = 'Second'
      ..trackIds = [secondTrack.id]
      ..createdAt = DateTime.now();
    firstPlaylist.id = await playlistRepo.save(firstPlaylist);
    secondPlaylist.id = await playlistRepo.save(secondPlaylist);

    final covers = await service.getPlaylistCoverDataForPlaylists([
      firstPlaylist,
      secondPlaylist,
    ]);

    expect(
        covers[firstPlaylist.id]!.networkUrl, 'https://example.com/first.jpg');
    expect(covers[secondPlaylist.id]!.networkUrl,
        'https://example.com/second.jpg');
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = sourceId
    ..thumbnailUrl = 'https://example.com/$sourceId.jpg'
    ..createdAt = DateTime.now();
}
