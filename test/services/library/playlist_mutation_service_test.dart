import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/services/library/playlist_mutation_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaylistMutationService', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test('addTracks creates tracks and writes both membership sides', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final playlist = await _createPlaylist(harness, 'Canonical Add');

      final result = await harness.mutations.addTracks(
        playlist.id,
        [_track('a', 'A'), _track('b', 'B')],
      );

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final savedTracks = await harness.tracks.getBySourceIds(['a', 'b']);
      expect(result.playlistId, playlist.id);
      expect(result.addedCount, 2);
      expect(result.skippedCount, 0);
      expect(result.removedCount, 0);
      expect(result.coverChanged, isTrue);
      expect(
        savedPlaylist!.trackIds,
        savedTracks.map((track) => track.id).toList(),
      );
      for (final track in savedTracks) {
        expect(track.belongsToPlaylist(playlist.id), isTrue);
        expect(track.playlistInfo.single.playlistName, 'Canonical Add');
      }
    });

    test('addTracks counts existing unlinked library track as added', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final playlist = await _createPlaylist(harness, 'Existing Library Add');
      final track =
          await harness.tracks.save(_track('existing-unlinked', 'Existing'));

      final result = await harness.mutations.addTracks(playlist.id, [track]);

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final savedTrack = await harness.tracks.getById(track.id);
      expect(result.addedCount, 1);
      expect(result.repairedCount, 0);
      expect(savedPlaylist!.trackIds, [track.id]);
      expect(
        savedTrack!.playlistInfo
            .where((info) => info.playlistId == playlist.id),
        hasLength(1),
      );
    });

    test('addTracks preserves download path from duplicate playlistInfo',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final playlist = await _createPlaylist(harness, 'Duplicate Info');
      final track = _track('duplicate-info', 'Duplicate Info')
        ..playlistInfo = [
          PlaylistDownloadInfo()
            ..playlistId = playlist.id
            ..playlistName = playlist.name,
          PlaylistDownloadInfo()
            ..playlistId = playlist.id
            ..playlistName = playlist.name
            ..downloadPath = '/downloads/duplicate-info.mp3',
        ];
      final savedTrack = await harness.tracks.save(track);
      playlist.trackIds = [savedTrack.id];
      await harness.playlists.save(playlist);

      await harness.mutations.addTracks(playlist.id, [savedTrack]);

      final repairedTrack = await harness.tracks.getById(savedTrack.id);
      final matchingInfos = repairedTrack!.playlistInfo
          .where((info) => info.playlistId == playlist.id)
          .toList();
      expect(matchingInfos, hasLength(1));
      expect(
          matchingInfos.single.downloadPath, '/downloads/duplicate-info.mp3');
    });

    test('addTracks keeps null-cid tracks distinct from cid tracks', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final playlist = await _createPlaylist(harness, 'Cid Distinct');
      final cidTrack = await harness.tracks.save(
        _track('same-source', 'CID Track')..cid = 123,
      );

      await harness.mutations.addTracks(
        playlist.id,
        [_track('same-source', 'Null CID Track')],
      );

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final savedTracks = await harness.tracks.getBySourceIds(['same-source']);
      final nullCidTrack =
          savedTracks.singleWhere((track) => track.cid == null);
      expect(savedTracks, hasLength(2));
      expect(savedPlaylist!.trackIds, [nullCidTrack.id]);
      expect(nullCidTrack.belongsToPlaylist(playlist.id), isTrue);
      expect(
        (await harness.tracks.getById(cidTrack.id))!.belongsToPlaylist(
          playlist.id,
        ),
        isFalse,
      );
    });

    test('addTracks repairs missing playlist or track side without duplicates',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final playlist = await _createPlaylist(harness, 'Repair');
      final track = await harness.tracks.save(_track('repair', 'Repair'));
      playlist.trackIds = [track.id];
      await harness.playlists.save(playlist);

      final result = await harness.mutations.addTracks(playlist.id, [track]);

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final savedTrack = await harness.tracks.getById(track.id);
      expect(result.addedCount, 0);
      expect(result.repairedCount, 1);
      expect(savedPlaylist!.trackIds, [track.id]);
      expect(
        savedTrack!.playlistInfo
            .where((info) => info.playlistId == playlist.id),
        hasLength(1),
      );
    });

    test('removeTracks removes playlist side and deletes only orphan tracks',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final first = await _createPlaylist(harness, 'Remove First');
      final second = await _createPlaylist(harness, 'Remove Second');
      final orphan =
          await harness.tracks.save(_track('remove-orphan', 'Orphan'));
      final shared =
          await harness.tracks.save(_track('remove-shared', 'Shared'));
      final kept = await harness.tracks.save(_track('remove-kept', 'Kept'));
      await harness.mutations.addTracks(first.id, [orphan, shared, kept]);
      await harness.mutations.addTrack(second.id, shared);

      final result = await harness.mutations.removeTracks(
        first.id,
        [orphan.id, shared.id],
      );

      final savedFirst = await harness.playlists.getById(first.id);
      final savedShared = await harness.tracks.getById(shared.id);
      expect(savedFirst!.trackIds, [kept.id]);
      expect(savedFirst.coverUrl, 'https://example.com/remove-kept.jpg');
      expect(await harness.tracks.getById(orphan.id), isNull);
      expect(savedShared!.belongsToPlaylist(first.id), isFalse);
      expect(savedShared.belongsToPlaylist(second.id), isTrue);
      expect(result.removedTrackIds, unorderedEquals([orphan.id, shared.id]));
      expect(result.deletedTrackIds, [orphan.id]);
      expect(result.updatedTrackIds, [shared.id]);
      expect(result.playlistChanged, isTrue);
      expect(result.coverChanged, isTrue);
    });

    test('removeTracks cleans stale reverse-only membership', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final playlist = await _createPlaylist(harness, 'Stale Reverse');
      final track = _track('stale-reverse', 'Stale Reverse')
        ..addToPlaylist(playlist.id, playlistName: playlist.name);
      final savedTrack = await harness.tracks.save(track);

      final result = await harness.mutations.removeTracks(
        playlist.id,
        [savedTrack.id],
      );

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      expect(savedPlaylist!.trackIds, isEmpty);
      expect(await harness.tracks.getById(savedTrack.id), isNull);
      expect(result.removedTrackIds, [savedTrack.id]);
      expect(result.deletedTrackIds, [savedTrack.id]);
      expect(result.updatedTrackIds, isEmpty);
      expect(result.playlistChanged, isFalse);
      expect(result.coverChanged, isFalse);
    });

    test('reorderTracks stores requested order and reports cover changes',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final playlist = await _createPlaylist(harness, 'Reorder');
      final first = await harness.tracks.save(_track('reorder-first', 'First'));
      final second =
          await harness.tracks.save(_track('reorder-second', 'Second'));
      final third = await harness.tracks.save(_track('reorder-third', 'Third'));
      await harness.mutations.addTracks(playlist.id, [first, second, third]);

      final result = await harness.mutations.reorderTracks(
        playlist.id,
        [third.id, first.id, second.id],
      );

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      expect(savedPlaylist!.trackIds, [third.id, first.id, second.id]);
      expect(savedPlaylist.coverUrl, 'https://example.com/reorder-third.jpg');
      expect(result.playlistChanged, isTrue);
      expect(result.coverChanged, isTrue);
    });

    test('deletePlaylist removes playlist and cleans reverse associations',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final first = await _createPlaylist(harness, 'Delete First');
      final second = await _createPlaylist(harness, 'Delete Second');
      final orphan =
          await harness.tracks.save(_track('delete-orphan', 'Orphan'));
      final shared =
          await harness.tracks.save(_track('delete-shared', 'Shared'));
      await harness.mutations.addTracks(first.id, [orphan, shared]);
      await harness.mutations.addTrack(second.id, shared);

      final result = await harness.mutations.deletePlaylist(first.id);

      final savedShared = await harness.tracks.getById(shared.id);
      expect(await harness.playlists.getById(first.id), isNull);
      expect(await harness.tracks.getById(orphan.id), isNull);
      expect(savedShared!.belongsToPlaylist(first.id), isFalse);
      expect(savedShared.belongsToPlaylist(second.id), isTrue);
      expect(result.deletedTrackIds, [orphan.id]);
      expect(result.updatedTrackIds, [shared.id]);
      expect(result.playlistChanged, isTrue);
    });

    test('deletePlaylist cleans stale reverse-only membership', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final playlist = await _createPlaylist(harness, 'Delete Stale Reverse');
      final track = _track('delete-stale-reverse', 'Delete Stale Reverse')
        ..addToPlaylist(playlist.id, playlistName: playlist.name);
      final savedTrack = await harness.tracks.save(track);

      final result = await harness.mutations.deletePlaylist(playlist.id);

      expect(await harness.playlists.getById(playlist.id), isNull);
      expect(await harness.tracks.getById(savedTrack.id), isNull);
      expect(result.removedTrackIds, [savedTrack.id]);
      expect(result.deletedTrackIds, [savedTrack.id]);
      expect(result.updatedTrackIds, isEmpty);
      expect(result.playlistChanged, isTrue);
    });

    test('duplicatePlaylist creates new playlist and reverse membership',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final original = await _createPlaylist(harness, 'Original Duplicate');
      original
        ..description = 'Original description'
        ..coverUrl = 'https://example.com/custom-cover.jpg'
        ..hasCustomCover = true;
      await harness.playlists.save(original);
      final first =
          await harness.tracks.save(_track('duplicate-first', 'First'));
      final second =
          await harness.tracks.save(_track('duplicate-second', 'Second'));
      await harness.mutations.addTracks(original.id, [first, second]);
      final copy = Playlist()
        ..name = 'Duplicate Copy'
        ..sortOrder = 42
        ..createdAt = DateTime.now();

      final result = await harness.mutations.duplicatePlaylist(
        original.id,
        copy,
      );

      final savedCopy = await harness.playlists.getById(result.id);
      final copiedFirst = await harness.tracks.getById(first.id);
      final copiedSecond = await harness.tracks.getById(second.id);
      expect(savedCopy, isNotNull);
      expect(savedCopy!.id, isNot(original.id));
      expect(savedCopy.name, 'Duplicate Copy');
      expect(savedCopy.description, 'Original description');
      expect(savedCopy.coverUrl, 'https://example.com/custom-cover.jpg');
      expect(savedCopy.hasCustomCover, isTrue);
      expect(savedCopy.trackIds, [first.id, second.id]);
      expect(copiedFirst!.belongsToPlaylist(result.id), isTrue);
      expect(copiedSecond!.belongsToPlaylist(result.id), isTrue);
      expect(
        copiedFirst.playlistInfo
            .singleWhere((info) => info.playlistId == result.id)
            .playlistName,
        'Duplicate Copy',
      );
    });
  });
}

class _Harness {
  _Harness(this.isar)
      : playlists = PlaylistRepository(isar),
        tracks = TrackRepository(isar) {
    mutations = PlaylistMutationService(isar: isar);
  }

  final Isar isar;
  final PlaylistRepository playlists;
  final TrackRepository tracks;
  late final PlaylistMutationService mutations;

  Future<void> dispose() async {
    final dir = Directory(isar.directory!);
    await isar.close(deleteFromDisk: true);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'playlist_mutation_service_test_',
  );
  final isar = await Isar.open(
    [PlaylistSchema, TrackSchema, SettingsSchema],
    directory: tempDir.path,
    name: 'playlist_mutation_service_test',
  );
  return _Harness(isar);
}

Future<Playlist> _createPlaylist(_Harness harness, String name) async {
  final playlist = Playlist()
    ..name = name
    ..createdAt = DateTime.now();
  playlist.id = await harness.playlists.save(playlist);
  return playlist;
}

Track _track(String sourceId, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = title
    ..thumbnailUrl = 'https://example.com/$sourceId.jpg'
    ..createdAt = DateTime.now();
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
