import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:fmp/providers/library_invalidation_coordinator.dart';
import 'package:fmp/providers/playlist_provider.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('playlist provider phase 2 invalidation rules', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test(
      'playlist list stays watch-driven while allPlaylists still needs explicit invalidation',
      () async {
        final harness = await createPlaylistPhase2Harness();
        addTearDown(harness.dispose);

        expect(await harness.readAllPlaylists(), isEmpty);

        final notifier = harness.container.read(playlistListProvider.notifier);
        final createdPlaylist =
            await notifier.createPlaylist(name: 'Phase 2 Playlist');
        expect(createdPlaylist, isNotNull);
        final playlist = createdPlaylist!;

        await harness.pumpUntil(
          () =>
              harness.container.read(playlistListProvider).playlists.length ==
              1,
          reason:
              'playlistListProvider should reflect playlist creation via Isar watch',
        );

        final allPlaylistsBeforeAdd = await harness.readAllPlaylists();
        expect(allPlaylistsBeforeAdd.single.trackCount, 0);

        await harness.container
            .read(playlistServiceProvider)
            .addTracksToPlaylist(
          playlist.id,
          [_buildTrack(sourceId: 'watch-track', title: 'Watch Track')],
        );

        await harness.pumpUntil(
          () =>
              harness.container
                  .read(playlistListProvider)
                  .playlists
                  .single
                  .trackCount ==
              1,
          reason:
              'playlistListProvider should update without manual invalidation',
        );

        final staleAllPlaylists = await harness.readAllPlaylists();
        expect(
          staleAllPlaylists.single.trackCount,
          0,
          reason: 'allPlaylistsProvider is a cached FutureProvider snapshot',
        );

        harness.container
            .read(libraryInvalidationCoordinatorProvider)
            .playlistChanged(playlist.id);

        final refreshedAllPlaylists = await harness.readAllPlaylists();
        expect(refreshedAllPlaylists.single.trackCount, 1);
      },
    );

    test(
      'playlist detail addTrack refreshes skipped duplicate back to canonical rows',
      () async {
        final harness = await createPlaylistPhase2Harness();
        addTearDown(harness.dispose);

        final playlist = await harness.container
            .read(playlistListProvider.notifier)
            .createPlaylist(name: 'Duplicate Add Playlist');
        expect(playlist, isNotNull);

        await harness.container
            .read(playlistServiceProvider)
            .addTrackToPlaylist(
              playlist!.id,
              _buildTrack(sourceId: 'duplicate-track', title: 'Original Track'),
            );

        await harness.pumpUntil(
          () {
            final detail =
                harness.container.read(playlistDetailProvider(playlist.id));
            return !detail.isLoading && detail.tracks.length == 1;
          },
          reason: 'playlistDetailProvider should load the canonical track row',
        );

        final success = await harness.container
            .read(playlistDetailProvider(playlist.id).notifier)
            .addTrack(
              _buildTrack(
                  sourceId: 'duplicate-track', title: 'Duplicate Track'),
            );

        expect(success, isTrue);
        final detail =
            harness.container.read(playlistDetailProvider(playlist.id));
        expect(
          detail.tracks.map((track) => track.sourceId),
          ['duplicate-track'],
          reason:
              'skipped duplicate add should not leave optimistic duplicate row',
        );
        expect(detail.totalTrackCount, 1);
      },
    );

    test('playlist detail refreshes after playlist metadata update', () async {
      final harness = await createPlaylistPhase2Harness();
      addTearDown(harness.dispose);

      final notifier = harness.container.read(playlistListProvider.notifier);
      final createdPlaylist = await notifier.createPlaylist(
        name: 'Original Playlist',
        description: 'Original description',
      );
      expect(createdPlaylist, isNotNull);
      final playlist = createdPlaylist!;

      await harness.pumpUntil(
        () {
          final detail =
              harness.container.read(playlistDetailProvider(playlist.id));
          return !detail.isLoading &&
              detail.playlist?.name == 'Original Playlist';
        },
        reason: 'playlistDetailProvider should finish its initial load',
      );

      final result = await notifier.updatePlaylist(
        playlistId: playlist.id,
        description: 'Updated description',
      );
      expect(result, isNotNull);

      await harness.pumpUntil(
        () {
          final detail =
              harness.container.read(playlistDetailProvider(playlist.id));
          return !detail.isLoading &&
              detail.playlist?.name == 'Original Playlist' &&
              detail.playlist?.description == 'Updated description';
        },
        reason: 'playlistDetailProvider should reload after metadata update',
      );
    });

    test('add-to-playlist removal path does not create tracks', () {
      final source = File(
        'lib/ui/widgets/dialogs/add_to_playlist_dialog.dart',
      ).readAsStringSync();
      final removeLoopStart = source.indexOf('// 先处理移除');
      final addLoopStart = source.indexOf('// 再处理添加');
      expect(removeLoopStart, isNonNegative);
      expect(addLoopStart, greaterThan(removeLoopStart));
      final removeSection = source.substring(removeLoopStart, addLoopStart);

      expect(removeSection, contains('removeTracksFromPlaylist'));
      expect(removeSection, isNot(contains('getOrCreate')));
      expect(removeSection, isNot(contains('removeTrackFromPlaylist')));
    });
  });
}

class PlaylistPhase2Harness {
  PlaylistPhase2Harness({
    required this.container,
    required this.isar,
    required this.tempDir,
  });

  final ProviderContainer container;
  final Isar isar;
  final Directory tempDir;

  Future<List<Playlist>> readAllPlaylists({bool forceRefresh = false}) async {
    if (forceRefresh) {
      container.invalidate(allPlaylistsProvider);
    }
    return container.read(allPlaylistsProvider.future);
  }

  Future<void> pumpUntil(
    bool Function() condition, {
    required String reason,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (!condition()) {
      fail(reason);
    }
  }

  Future<void> dispose() async {
    container.dispose();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<PlaylistPhase2Harness> createPlaylistPhase2Harness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'playlist_provider_phase2_test_',
  );
  final isar = await Isar.open(
    [TrackSchema, PlaylistSchema, PlayQueueSchema, SettingsSchema],
    directory: tempDir.path,
    name: 'playlist_provider_phase2_test',
  );

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => isar),
    ],
  );

  return PlaylistPhase2Harness(
    container: container,
    isar: isar,
    tempDir: tempDir,
  );
}

Track _buildTrack({required String sourceId, required String title}) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = title
    ..artist = 'Phase 2 Artist'
    ..durationMs = 180000
    ..thumbnailUrl = 'https://example.com/$sourceId.jpg';
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
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
