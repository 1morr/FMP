import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/import/import_service.dart';
import 'package:fmp/services/library/playlist_mutation_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImportService refresh partial pruning policy', () {
    late Directory tempDir;
    late Isar isar;
    late PlaylistRepository playlistRepository;
    late _FakeRefreshSource source;
    late _FakeSourceManager sourceManager;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'import_service_refresh_partial_',
      );
      isar = await Isar.open(
        [PlaylistSchema, TrackSchema],
        directory: tempDir.path,
        name: 'import_service_refresh_partial_test',
      );
      playlistRepository = PlaylistRepository(isar);
      source = _FakeRefreshSource();
      sourceManager = _FakeSourceManager(source);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reports pruning skipped when mutation reports a persistence error',
        () async {
      final trackRepository = TrackRepository(isar);
      final playlist = await _createImportedPlaylist(
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        tracks: [
          _track('keep', 'Keep'),
          _track('stale', 'Stale'),
        ],
      );
      source.result = PlaylistParseResult(
        title: 'Remote playlist',
        tracks: [_track('keep', 'Keep'), _track('broken', 'Broken')],
        totalCount: 2,
        sourceUrl: playlist.sourceUrl!,
      );
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        mutationService: _ReportingRefreshFailureMutationService(isar: isar),
      );

      final result = await service.refreshPlaylist(playlist.id);

      expect(result.pruningSkipped, isTrue);
      expect(result.removedCount, 0);
      expect(result.errors, isNotEmpty);
      final refreshed = await playlistRepository.getById(playlist.id);
      expect(refreshed!.trackIds, playlist.trackIds);
      expect(
        await trackRepository.getBySourceId('stale', SourceType.youtube),
        isNotNull,
      );
    });

    test('persists refreshed owner metadata after remote refresh', () async {
      final trackRepository = TrackRepository(isar);
      final playlist = await _createImportedPlaylist(
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        tracks: [
          _track('keep', 'Keep'),
        ],
      );
      source.result = PlaylistParseResult(
        title: 'Remote playlist',
        tracks: [_track('keep', 'Keep')],
        totalCount: 1,
        sourceUrl: playlist.sourceUrl!,
        ownerName: 'Refreshed Owner',
        ownerUserId: 'owner-123',
      );
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
      );

      await service.refreshPlaylist(playlist.id);

      final refreshed = await playlistRepository.getById(playlist.id);
      expect(refreshed!.ownerName, 'Refreshed Owner');
      expect(refreshed.ownerUserId, 'owner-123');
    });

    test('keeps existing owner metadata when refresh omits owner fields',
        () async {
      final trackRepository = TrackRepository(isar);
      final playlist = await _createImportedPlaylist(
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        tracks: [
          _track('keep', 'Keep'),
        ],
      );
      playlist
        ..ownerName = 'Existing Owner'
        ..ownerUserId = 'existing-owner-id';
      await playlistRepository.save(playlist);
      source.result = PlaylistParseResult(
        title: 'Remote playlist',
        tracks: [_track('keep', 'Keep')],
        totalCount: 1,
        sourceUrl: playlist.sourceUrl!,
      );
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
      );

      await service.refreshPlaylist(playlist.id);

      final refreshed = await playlistRepository.getById(playlist.id);
      expect(refreshed!.ownerName, 'Existing Owner');
      expect(refreshed.ownerUserId, 'existing-owner-id');
    });

    test('does not append tracks when mutation reports a persistence error',
        () async {
      final trackRepository = TrackRepository(isar);
      final playlist = await _createImportedPlaylist(
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        tracks: [
          _track('keep', 'Keep'),
        ],
      );
      final existingTrack = await TrackRepository(isar).save(
        _track('existing', 'Existing'),
      );
      source.result = PlaylistParseResult(
        title: 'Remote playlist',
        tracks: [
          _track('keep', 'Keep'),
          _track('existing', 'Existing'),
        ],
        totalCount: 2,
        sourceUrl: playlist.sourceUrl!,
      );
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        mutationService: _ReportingRefreshFailureMutationService(isar: isar),
      );

      final result = await service.refreshPlaylist(playlist.id);

      expect(result.pruningSkipped, isTrue);
      expect(result.removedCount, 0);
      expect(result.errors, isNotEmpty);
      final refreshed = await playlistRepository.getById(playlist.id);
      expect(refreshed!.trackIds, isNot(contains(existingTrack.id)));
      expect(refreshed.trackIds, playlist.trackIds);
    });

    test('skips pruning when source result is smaller than reported total',
        () async {
      final trackRepository = TrackRepository(isar);
      final playlist = await _createImportedPlaylist(
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        tracks: [
          _track('keep', 'Keep'),
          _track('stale', 'Stale'),
        ],
      );
      source.result = PlaylistParseResult(
        title: 'Remote playlist',
        tracks: [_track('keep', 'Keep')],
        totalCount: 2,
        sourceUrl: playlist.sourceUrl!,
      );
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
      );

      final result = await service.refreshPlaylist(playlist.id);

      expect(result.pruningSkipped, isTrue);
      expect(result.removedCount, 0);
      expect(result.errors, isEmpty);
      final refreshed = await playlistRepository.getById(playlist.id);
      expect(refreshed!.trackIds, playlist.trackIds);
      expect(await trackRepository.getBySourceId('stale', SourceType.youtube),
          isNotNull);
    });

    test('skips pruning when Bilibili parsed item count is partial', () async {
      final trackRepository = TrackRepository(isar);
      final bilibiliSource = _FakeBilibiliRefreshSource(
        tracks: [_track('BV1234567890', 'Multi-page', SourceType.bilibili, 2)],
        totalCount: 2,
      );
      sourceManager = _FakeSourceManager(bilibiliSource);
      final playlist = await _createImportedPlaylist(
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        sourceType: SourceType.bilibili,
        tracks: [
          _track('BV1234567890', 'Page 1', SourceType.bilibili)
            ..cid = 101
            ..pageNum = 1,
          _track('BVstale0000', 'Stale', SourceType.bilibili),
        ],
      );
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
      );

      final result = await service.refreshPlaylist(playlist.id);

      expect(result.pruningSkipped, isTrue);
      expect(result.removedCount, 0);
      expect(result.errors, isEmpty);
      final refreshed = await playlistRepository.getById(playlist.id);
      expect(refreshed!.trackIds, containsAll(playlist.trackIds));
      expect(
          await trackRepository.getBySourceId(
              'BVstale0000', SourceType.bilibili),
          isNotNull);
    });

    test('skips pruning when Bilibili multipage expansion falls back',
        () async {
      final trackRepository = TrackRepository(isar);
      final bilibiliSource = _FakeBilibiliRefreshSource(
        failVideoPages: true,
        tracks: [_track('BV1234567890', 'Multi-page', SourceType.bilibili, 2)],
        totalCount: 1,
      );
      sourceManager = _FakeSourceManager(bilibiliSource);
      final playlist = await _createImportedPlaylist(
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        sourceType: SourceType.bilibili,
        tracks: [
          _track('BV1234567890', 'Multi-page', SourceType.bilibili, 2),
          _track('BVstale0000', 'Stale', SourceType.bilibili),
        ],
      );
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
      );

      final result = await service.refreshPlaylist(playlist.id);

      expect(result.pruningSkipped, isTrue);
      expect(result.removedCount, 0);
      expect(result.errors, isEmpty);
      final refreshed = await playlistRepository.getById(playlist.id);
      expect(refreshed!.trackIds, playlist.trackIds);
      expect(
          await trackRepository.getBySourceId(
              'BVstale0000', SourceType.bilibili),
          isNotNull);
    });
  });
}

class _ReportingRefreshFailureMutationService extends PlaylistMutationService {
  _ReportingRefreshFailureMutationService({required super.isar});

  @override
  Future<PlaylistMutationResult> replaceTracksFromRemoteRefresh(
    int playlistId,
    List<Track> refreshedTracks,
    RemoteRefreshMutationPolicy policy,
  ) async {
    return PlaylistMutationResult(
      playlistId: playlistId,
      affectedPlaylistIds: [playlistId],
      errors: [StateError('simulated save failure')],
      pruningSkipped: true,
    );
  }
}

class _FakeSourceManager extends SourceManager {
  _FakeSourceManager(this.source) : super(sources: const []);

  final PlaylistParsingSource source;

  @override
  PlaylistParsingSource? playlistParsingSourceForUrl(String url) => source;

  @override
  PagedVideoSource? pagedVideoSource(SourceType type) {
    final Object candidate = source;
    if (type == source.sourceType && candidate is PagedVideoSource) {
      return candidate;
    }
    return null;
  }

  @override
  void dispose() {}
}

class _FakeRefreshSource implements PlaylistParsingSource {
  PlaylistParseResult? result;

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  bool isPlaylistUrl(String url) => true;

  @override
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1,
      int pageSize = 20,
      Map<String, String>? authHeaders}) async {
    final current = result;
    if (current == null) throw StateError('No fake playlist result configured');
    return current;
  }
}

class _FakeBilibiliRefreshSource extends BilibiliSource {
  _FakeBilibiliRefreshSource({
    required this.tracks,
    required this.totalCount,
    this.failVideoPages = false,
  });

  final List<Track> tracks;
  final int totalCount;
  final bool failVideoPages;

  @override
  SourceType get sourceType => SourceType.bilibili;

  @override
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1,
      int pageSize = 20,
      Map<String, String>? authHeaders}) async {
    return PlaylistParseResult(
      title: 'Remote Bilibili playlist',
      tracks: tracks,
      totalCount: totalCount,
      sourceUrl: playlistUrl,
    );
  }

  @override
  Future<List<VideoPage>> getVideoPages(String bvid,
      {Map<String, String>? authHeaders}) async {
    if (failVideoPages) {
      throw StateError('simulated page expansion failure');
    }
    return const [
      VideoPage(cid: 101, page: 1, part: 'Page 1', duration: 60),
      VideoPage(cid: 102, page: 2, part: 'Page 2', duration: 70),
    ];
  }
}

Future<Playlist> _createImportedPlaylist({
  required PlaylistRepository playlistRepository,
  required TrackRepository trackRepository,
  required List<Track> tracks,
  SourceType sourceType = SourceType.youtube,
}) async {
  final playlist = Playlist()
    ..name = 'Imported playlist'
    ..sourceUrl = 'https://example.test/playlist'
    ..importSourceType = sourceType
    ..createdAt = DateTime.now();
  playlist.id = await playlistRepository.save(playlist);

  final trackIds = <int>[];
  for (final track in tracks) {
    track.addToPlaylist(playlist.id, playlistName: playlist.name);
    final saved = await trackRepository.save(track);
    trackIds.add(saved.id);
  }
  playlist.trackIds = trackIds;
  await playlistRepository.save(playlist);
  return playlist;
}

Track _track(
  String sourceId,
  String title, [
  SourceType sourceType = SourceType.youtube,
  int? pageCount,
]) =>
    Track()
      ..sourceId = sourceId
      ..sourceType = sourceType
      ..title = title
      ..artist = 'Artist'
      ..pageCount = pageCount;

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
