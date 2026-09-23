import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:isar_community/isar.dart';

import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Isar isar;
  late TrackRepository repo;

  setUpAll(() async {
    await initializeIsarForTests();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'track_repository_orphan_cleanup_test_',
    );
    isar = await Isar.open(
      [TrackSchema, LyricsMatchSchema],
      directory: tempDir.path,
      name: 'track_repository_orphan_cleanup_test',
    );
    repo = TrackRepository(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('an orphan track goes, its lyrics match stays', () async {
    final orphan = await repo.save(_track('orphan'));
    final queued = await repo.save(_track('queued'));
    final inPlaylist = await repo.save(
      _track('in-playlist')
        ..playlistInfo = [
          PlaylistDownloadInfo()
            ..playlistId = 7
            ..playlistName = 'Favourites',
        ],
    );
    await isar.writeTxn(
      () => isar.lyricsMatchs.put(
        LyricsMatch()
          ..trackUniqueKey = orphan.uniqueKey
          ..lyricsSource = 'netease'
          ..externalId = '42'
          ..offsetMs = -300,
      ),
    );

    final deleted = await repo.deleteOrphanTracks(excludeTrackIds: [queued.id]);

    expect(deleted, 1);
    expect(await repo.getById(orphan.id), isNull);
    expect(await repo.getById(queued.id), isNotNull);
    expect(await repo.getById(inPlaylist.id), isNotNull);
    // 使用者手動挑的歌詞版本與校正的偏移：同一首歌下次播起來還要用得到。
    final match = await isar.lyricsMatchs
        .where()
        .trackUniqueKeyEqualTo(orphan.uniqueKey)
        .findFirst();
    expect(match?.offsetMs, -300);
  });
}

Track _track(String sourceId) => Track()
  ..sourceId = sourceId
  ..sourceType = SourceIds.bilibili
  ..title = sourceId;
