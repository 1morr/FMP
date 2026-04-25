import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/services/library/playlist_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaylistService bidirectional relations', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test('addTrackToPlaylist persists playlist trackIds and track playlistInfo',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final playlist = await _createPlaylist(harness, 'Single Add');
      final track = _newTrack('yt-single', 'Single Add Track');

      await harness.service.addTrackToPlaylist(playlist.id, track);

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final savedTrack = await harness.tracks.getBySourceId(
        'yt-single',
        SourceType.youtube,
      );
      expect(savedPlaylist!.trackIds, [savedTrack!.id]);
      expect(savedTrack.belongsToPlaylist(playlist.id), isTrue);
      expect(
        savedTrack.playlistInfo
            .singleWhere((info) => info.playlistId == playlist.id)
            .playlistName,
        'Single Add',
      );
    });

    test('addTracksToPlaylist persists reverse playlistInfo for all tracks',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final playlist = await _createPlaylist(harness, 'Batch Add');
      final tracks = [
        _newTrack('yt-batch-1', 'Batch Track 1'),
        _newTrack('yt-batch-2', 'Batch Track 2'),
      ];

      await harness.service.addTracksToPlaylist(playlist.id, tracks);

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final savedTracks = await harness.tracks.getBySourceIds([
        'yt-batch-1',
        'yt-batch-2',
      ]);
      expect(savedTracks, hasLength(2));
      expect(savedPlaylist!.trackIds,
          unorderedEquals(savedTracks.map((t) => t.id)));
      for (final track in savedTracks) {
        expect(track.belongsToPlaylist(playlist.id), isTrue);
        expect(
          track.playlistInfo
              .singleWhere((info) => info.playlistId == playlist.id)
              .playlistName,
          'Batch Add',
        );
      }
    });

    test('addTracksToPlaylist dedupes duplicate input tracks', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final playlist = await _createPlaylist(harness, 'Duplicate Input');
      final track = _newTrack('yt-duplicate-input', 'Duplicate Input Track');

      await harness.service.addTracksToPlaylist(playlist.id, [track, track]);

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final savedTrack = await harness.tracks.getBySourceId(
        'yt-duplicate-input',
        SourceType.youtube,
      );
      expect(savedPlaylist!.trackIds, [savedTrack!.id]);
      expect(
        savedTrack.playlistInfo.where((info) => info.playlistId == playlist.id),
        hasLength(1),
      );
    });

    test('addTrackToPlaylist repairs missing playlist trackId side', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final playlist = await _createPlaylist(harness, 'Single Repair');
      final track = _newTrack('yt-single-repair', 'Single Repair Track')
        ..addToPlaylist(playlist.id, playlistName: playlist.name);
      final savedTrack = await harness.tracks.save(track);

      await harness.service.addTrackToPlaylist(playlist.id, savedTrack);

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final reloadedTrack = await harness.tracks.getById(savedTrack.id);
      expect(savedPlaylist!.trackIds, [savedTrack.id]);
      expect(
        reloadedTrack!.playlistInfo
            .where((info) => info.playlistId == playlist.id),
        hasLength(1),
      );
    });

    test('addTracksToPlaylist repairs missing playlist trackId side', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final playlist = await _createPlaylist(harness, 'Batch Repair');
      final track = _newTrack('yt-batch-repair', 'Batch Repair Track')
        ..addToPlaylist(playlist.id, playlistName: playlist.name);
      final savedTrack = await harness.tracks.save(track);

      await harness.service.addTracksToPlaylist(playlist.id, [savedTrack]);

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final reloadedTrack = await harness.tracks.getById(savedTrack.id);
      expect(savedPlaylist!.trackIds, [savedTrack.id]);
      expect(
        reloadedTrack!.playlistInfo
            .where((info) => info.playlistId == playlist.id),
        hasLength(1),
      );
    });

    test('addTrackToPlaylist repairs missing track playlistInfo side',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final playlist = await _createPlaylist(harness, 'Single Reverse Repair');
      final savedTrack = await harness.tracks.save(
        _newTrack('yt-single-reverse-repair', 'Single Reverse Repair Track'),
      );
      playlist.trackIds = [savedTrack.id];
      await harness.playlists.save(playlist);

      await harness.service.addTrackToPlaylist(playlist.id, savedTrack);

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final reloadedTrack = await harness.tracks.getById(savedTrack.id);
      expect(savedPlaylist!.trackIds, [savedTrack.id]);
      expect(
        reloadedTrack!.playlistInfo
            .where((info) => info.playlistId == playlist.id),
        hasLength(1),
      );
    });

    test('addTracksToPlaylist repairs missing track playlistInfo side',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final playlist = await _createPlaylist(harness, 'Batch Reverse Repair');
      final savedTrack = await harness.tracks.save(
        _newTrack('yt-batch-reverse-repair', 'Batch Reverse Repair Track'),
      );
      playlist.trackIds = [savedTrack.id];
      await harness.playlists.save(playlist);

      await harness.service.addTracksToPlaylist(playlist.id, [savedTrack]);

      final savedPlaylist = await harness.playlists.getById(playlist.id);
      final reloadedTrack = await harness.tracks.getById(savedTrack.id);
      expect(savedPlaylist!.trackIds, [savedTrack.id]);
      expect(
        reloadedTrack!.playlistInfo
            .where((info) => info.playlistId == playlist.id),
        hasLength(1),
      );
    });

    test('duplicatePlaylist adds reverse playlistInfo to copied tracks',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final original = await _createPlaylist(harness, 'Original');
      final track = await harness.tracks.save(
        _newTrack('yt-dup', 'Duplicate Me'),
      );
      await harness.service.addTrackToPlaylist(original.id, track);

      final copy = await harness.service.duplicatePlaylist(original.id, 'Copy');

      final copiedTrack = await harness.tracks.getById(track.id);
      expect(copy.trackIds, [track.id]);
      expect(copiedTrack!.belongsToPlaylist(original.id), isTrue);
      expect(copiedTrack.belongsToPlaylist(copy.id), isTrue);
      expect(
        copiedTrack.playlistInfo
            .singleWhere((info) => info.playlistId == copy.id)
            .playlistName,
        'Copy',
      );
    });
  });
}

class _Harness {
  _Harness(this.isar)
      : playlists = PlaylistRepository(isar),
        tracks = TrackRepository(isar),
        settings = SettingsRepository(isar) {
    service = PlaylistService(
      playlistRepository: playlists,
      trackRepository: tracks,
      settingsRepository: settings,
      isar: isar,
    );
  }

  final Isar isar;
  final PlaylistRepository playlists;
  final TrackRepository tracks;
  final SettingsRepository settings;
  late final PlaylistService service;

  Future<void> dispose() async {
    final dir = Directory(isar.directory!);
    await isar.close(deleteFromDisk: true);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'playlist_service_bidirectional_test_',
  );
  final isar = await Isar.open(
    [PlaylistSchema, TrackSchema, SettingsSchema],
    directory: tempDir.path,
    name: 'playlist_service_bidirectional_test',
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

Track _newTrack(String sourceId, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = title
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
