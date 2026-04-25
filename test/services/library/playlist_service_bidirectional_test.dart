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

    test('duplicatePlaylist adds reverse playlistInfo to copied tracks',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final original = Playlist()
        ..name = 'Original'
        ..createdAt = DateTime.now();
      original.id = await harness.playlists.save(original);
      final track = await harness.tracks.save(Track()
        ..sourceId = 'yt-dup'
        ..sourceType = SourceType.youtube
        ..title = 'Duplicate Me'
        ..createdAt = DateTime.now());
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
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
