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
