import 'dart:async';
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
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/services/import/import_service.dart';
import 'package:fmp/services/library/playlist_mutation_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImportService phase 4 dispatch', () {
    late Directory tempDir;
    late Isar isar;
    late PlaylistRepository playlistRepository;
    late TrackRepository trackRepository;
    late _FakeSourceManager sourceManager;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'import_service_phase4_',
      );
      isar = await Isar.open(
        [PlaylistSchema, TrackSchema],
        directory: tempDir.path,
        name: 'import_service_phase4_test',
      );
      playlistRepository = PlaylistRepository(isar);
      trackRepository = TrackRepository(isar);
      sourceManager = _FakeSourceManager();
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'importFromUrl routes regular youtube playlist URLs through parser path for YouTubeSource instances',
        () async {
      final source = _FakeYouTubeSource();
      sourceManager.detectedSource = source;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: _FakeSourceAuthContext(),
      );

      await expectLater(
        () => service.importFromUrl(
          'https://www.youtube.com/playlist?list=PL123',
        ),
        throwsA(isA<_ParseSentinel>()),
      );

      expect(source.parsePlaylistCallCount, 1);
      expect(source.lastParseAuthHeaders, isNull);
    });

    test('importFromUrl passes auth headers to playlist parser when enabled',
        () async {
      final source = _FakeGenericSource(SourceType.youtube);
      sourceManager.detectedSource = source;
      final authContext = _FakeSourceAuthContext()
        ..playlistImportHeaders = const {
          'Cookie':
              'SAPISID=sapisid; __Secure-1PSID=1psid; __Secure-3PSID=3psid',
          'Authorization': 'Bearer youtube-auth',
        };
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: authContext,
      );

      await expectLater(
        () => service.importFromUrl(
          'https://www.youtube.com/playlist?list=PL123',
          useAuth: true,
        ),
        throwsA(isA<_ParseSentinel>()),
      );

      expect(source.lastParseAuthHeaders, {
        'Cookie': 'SAPISID=sapisid; __Secure-1PSID=1psid; __Secure-3PSID=3psid',
        'Authorization': 'Bearer youtube-auth',
      });
    });

    test('importFromUrl leaves auth headers null when auth is disabled',
        () async {
      final source = _FakeGenericSource(SourceType.netease);
      sourceManager.detectedSource = source;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: _FakeSourceAuthContext()
          ..playlistImportHeaders = const {'Cookie': 'MUSIC_U=music-u'},
      );

      await expectLater(
        () => service.importFromUrl('https://music.163.com/playlist?id=42'),
        throwsA(isA<_ParseSentinel>()),
      );

      expect(source.lastParseAuthHeaders, isNull);
    });

    test('importFromUrl keeps RD-list non-youtube URLs on parser path',
        () async {
      final source = _FakeGenericSource(SourceType.netease);
      final mixSource = _FakeYouTubeSource()
        ..mixInfo = const MixPlaylistInfo(
          title: 'Wrong Mix',
          playlistId: 'RDdvgZkm1xWPE',
          seedVideoId: 'dvgZkm1xWPE',
        );
      sourceManager.detectedSource = source;
      sourceManager.dynamicPlaylistSourceOverride = mixSource;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: _FakeSourceAuthContext(),
      );

      await expectLater(
        () => service.importFromUrl(
          'https://music.163.com/playlist?id=42&list=RDdvgZkm1xWPE',
        ),
        throwsA(isA<_ParseSentinel>()),
      );

      expect(sourceManager.dynamicPlaylistLookupCount, 1);
      expect(source.lastParseAuthHeaders, isNull);
      expect(mixSource.lastMixInfoUrl, isNull);
    });

    test('importFromUrl normalizes mix shorthand before YouTube Mix import',
        () async {
      final source = _FakeYouTubeSource();
      sourceManager.detectedSource = source;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: _FakeSourceAuthContext(),
      );

      await expectLater(
        () => service.importFromUrl(' MIX:dvgZkm1xWPE '),
        throwsA(isA<_MixImportSentinel>()),
      );

      expect(sourceManager.lastDetectedUrl,
          'https://www.youtube.com/watch?v=dvgZkm1xWPE&list=RDdvgZkm1xWPE');
      expect(source.lastMixInfoUrl,
          'https://www.youtube.com/watch?v=dvgZkm1xWPE&list=RDdvgZkm1xWPE');
      expect(sourceManager.dynamicPlaylistLookupCount, 1);
    });

    test('importFromUrl stores normalized sourceUrl for shorthand Mix playlist',
        () async {
      final source = _FakeYouTubeSource()
        ..mixInfo = const MixPlaylistInfo(
          title: 'Mix',
          playlistId: 'RDdvgZkm1xWPE',
          seedVideoId: 'dvgZkm1xWPE',
          coverUrl: 'https://img.example/cover.jpg',
        );
      sourceManager.detectedSource = source;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: _FakeSourceAuthContext(),
      );

      final result = await service.importFromUrl('mix:dvgZkm1xWPE');

      expect(result.playlist.isMix, isTrue);
      expect(result.playlist.mixPlaylistId, 'RDdvgZkm1xWPE');
      expect(result.playlist.mixSeedVideoId, 'dvgZkm1xWPE');
      expect(result.playlist.sourceUrl,
          'https://www.youtube.com/watch?v=dvgZkm1xWPE&list=RDdvgZkm1xWPE');
      expect(result.addedCount, 0);
      expect(sourceManager.dynamicPlaylistLookupCount, 1);
    });

    test('importFromUrl reports cancellation after mutation instead of success',
        () async {
      final source = _PlaylistSource(
        title: 'Cancellation Playlist',
        tracks: [_track('cancel-track', 'Cancel Track')],
      );
      sourceManager.detectedSource = source;
      late ImportService service;
      final mutationService = _CancellingMutationService(
        isar: isar,
        onAfterMutation: () => service.cancelImport(),
      );
      service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        mutationService: mutationService,
        sourceAuthContext: _FakeSourceAuthContext(),
      );

      await expectLater(
        () => service.importFromUrl('https://example.com/playlist/cancel'),
        throwsA(isA<ImportException>()),
      );
      await service.cleanupCancelledImport();

      expect(await playlistRepository.getAll(), isEmpty);
      expect(await trackRepository.getAll(), isEmpty);
    });

    test(
        'importFromUrl reports cancellation after cover update instead of success',
        () async {
      final source = _PlaylistSource(
        title: 'Cover Cancellation Playlist',
        tracks: [_track('cover-cancel-track', 'Cover Cancel Track')],
      );
      sourceManager.detectedSource = source;
      final blockingTrackRepository = _BlockingTrackRepository(isar);
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: blockingTrackRepository,
        isar: isar,
        sourceAuthContext: _FakeSourceAuthContext(),
      );

      final importFuture = service.importFromUrl(
        'https://example.com/playlist/cover-cancel',
      );
      await blockingTrackRepository.coverLookupStarted.future;
      service.cancelImport();
      blockingTrackRepository.completeCoverLookup();

      await expectLater(importFuture, throwsA(isA<ImportException>()));
      await service.cleanupCancelledImport();

      expect(await playlistRepository.getAll(), isEmpty);
      expect(await trackRepository.getAll(), isEmpty);
    });

    test('importFromUrl reports cancellation after final save without success',
        () async {
      final source = _PlaylistSource(
        title: 'Final Save Cancellation Playlist',
        tracks: [_track('final-save-cancel-track', 'Final Save Cancel Track')],
      );
      sourceManager.detectedSource = source;
      late ImportService service;
      final cancellingPlaylistRepository = _CancellingPlaylistRepository(
        isar,
        onAfterFinalSave: () => service.cancelImport(),
      );
      service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: cancellingPlaylistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: _FakeSourceAuthContext(),
      );
      final progressStatuses = <ImportStatus>[];
      final progressSubscription = service.progressStream.listen(
        (progress) => progressStatuses.add(progress.status),
      );
      addTearDown(() async {
        await progressSubscription.cancel();
        service.dispose();
      });

      await expectLater(
        () => service.importFromUrl('https://example.com/playlist/final-save'),
        throwsA(isA<ImportException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await service.cleanupCancelledImport();

      expect(progressStatuses, isNot(contains(ImportStatus.completed)));
      expect(await cancellingPlaylistRepository.getAll(), isEmpty);
      expect(await trackRepository.getAll(), isEmpty);
    });

    test('importFromUrl counts metadata-only existing tracks as skipped',
        () async {
      String? audioUrl;
      final source = _DynamicPlaylistSource(
        title: 'Metadata Playlist',
        buildTracks: () => [
          _track('metadata-track', 'Metadata Track')..audioUrl = audioUrl,
        ],
      );
      sourceManager.detectedSource = source;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: _FakeSourceAuthContext(),
      );

      final first = await service.importFromUrl(
        'https://example.com/playlist/metadata',
      );
      audioUrl = 'https://audio.example/metadata.m4a';
      final second = await service.importFromUrl(
        'https://example.com/playlist/metadata',
      );
      final savedTrack = await trackRepository.getBySourceId(
        'metadata-track',
        SourceType.youtube,
      );

      expect(first.addedCount, 1);
      expect(first.skippedCount, 0);
      expect(second.addedCount, 0);
      expect(second.skippedCount, 1);
      expect(second.playlist.trackIds, hasLength(1));
      expect(savedTrack!.audioUrl, audioUrl);
    });

    test('importFromUrl updates auth refresh metadata on existing playlist',
        () async {
      final source = _PlaylistSource(
        title: 'Existing Import Playlist',
        tracks: [_track('existing-import-track', 'Existing Import Track')],
        description: 'Updated remote description',
        ownerName: 'Remote Owner',
        ownerUserId: 'remote-owner-id',
      );
      sourceManager.detectedSource = source;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: _FakeSourceAuthContext(),
      );
      final existing = Playlist()
        ..name = 'User Chosen Name'
        ..description = 'Old local description'
        ..sourceUrl = 'https://example.com/playlist/existing'
        ..importSourceType = SourceType.youtube
        ..ownerName = 'Old Owner'
        ..ownerUserId = 'old-owner-id'
        ..useAuthForRefresh = false
        ..refreshIntervalHours = 24
        ..notifyOnUpdate = true
        ..createdAt = DateTime.now();
      existing.id = await playlistRepository.save(existing);

      final result = await service.importFromUrl(
        'https://example.com/playlist/existing',
        customName: 'Ignored Custom Name',
        refreshIntervalHours: 6,
        notifyOnUpdate: false,
        useAuth: true,
      );

      final savedPlaylist = await playlistRepository.getById(existing.id);
      expect(result.playlist.id, existing.id);
      expect(savedPlaylist!.name, 'User Chosen Name');
      expect(savedPlaylist.description, 'Old local description');
      expect(savedPlaylist.ownerName, 'Remote Owner');
      expect(savedPlaylist.ownerUserId, 'remote-owner-id');
      expect(savedPlaylist.useAuthForRefresh, isTrue);
      expect(savedPlaylist.refreshIntervalHours, 6);
      expect(savedPlaylist.notifyOnUpdate, isFalse);
      expect(savedPlaylist.importSourceType, SourceType.youtube);
    });

    test('import multi-page expansion reuses import auth headers', () async {
      final source = _PagedPlaylistSource(SourceType.bilibili);
      sourceManager.detectedSource = source;
      final authContext = _FakeSourceAuthContext()
        ..playlistImportHeaders = const {'Cookie': 'SESSDATA=import'};
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        sourceAuthContext: authContext,
      );

      await service.importFromUrl(
        'https://www.bilibili.com/list/watchlater',
        useAuth: true,
      );

      expect(source.lastParseAuthHeaders, {'Cookie': 'SESSDATA=import'});
      expect(source.lastPageAuthHeaders, {'Cookie': 'SESSDATA=import'});
    });
  });
}

class _FakeSourceManager extends SourceManager {
  _FakeSourceManager() : super(sources: const []);

  PlaylistParsingSource? detectedSource;
  DynamicPlaylistSource? dynamicPlaylistSourceOverride;
  int dynamicPlaylistLookupCount = 0;
  String? lastDetectedUrl;

  @override
  PlaylistParsingSource? playlistParsingSourceForUrl(String url) {
    lastDetectedUrl = url;
    return detectedSource;
  }

  @override
  DynamicPlaylistSource? dynamicPlaylistSourceForUrl(String url) {
    dynamicPlaylistLookupCount++;
    final Object? source = dynamicPlaylistSourceOverride ?? detectedSource;
    if (source is! DynamicPlaylistSource) return null;
    return source.isDynamicPlaylistUrl(url) ? source : null;
  }

  @override
  PagedVideoSource? pagedVideoSource(SourceType type) {
    final source = detectedSource;
    if (source == null || source.sourceType != type) return null;
    final Object candidate = source;
    return candidate is PagedVideoSource ? candidate : null;
  }

  @override
  void dispose() {}
}

class _FakeGenericSource implements PlaylistParsingSource {
  _FakeGenericSource(this._sourceType);

  final SourceType _sourceType;
  Map<String, String>? lastParseAuthHeaders;

  @override
  SourceType get sourceType => _sourceType;

  @override
  bool isPlaylistUrl(String url) => true;

  @override
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1,
      int pageSize = 20,
      Map<String, String>? authHeaders}) async {
    lastParseAuthHeaders = authHeaders;
    throw _ParseSentinel();
  }
}

class _FakeYouTubeSource extends YouTubeSource {
  _FakeYouTubeSource();

  int parsePlaylistCallCount = 0;
  Map<String, String>? lastParseAuthHeaders;
  String? lastMixInfoUrl;
  MixPlaylistInfo? mixInfo;

  @override
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1,
      int pageSize = 20,
      Map<String, String>? authHeaders}) async {
    parsePlaylistCallCount++;
    lastParseAuthHeaders = authHeaders;
    throw _ParseSentinel();
  }

  @override
  Future<MixPlaylistInfo> getMixPlaylistInfo(String url) async {
    lastMixInfoUrl = url;
    final info = mixInfo;
    if (info == null) throw _MixImportSentinel();
    return info;
  }
}

class _PlaylistSource implements PlaylistParsingSource {
  _PlaylistSource({
    required this.title,
    required List<Track> tracks,
    this.description,
    this.ownerName,
    this.ownerUserId,
  }) : _tracks = tracks;

  final String title;
  final List<Track> _tracks;
  final String? description;
  final String? ownerName;
  final String? ownerUserId;
  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  bool isPlaylistUrl(String url) => true;

  @override
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1,
      int pageSize = 20,
      Map<String, String>? authHeaders}) async {
    return PlaylistParseResult(
      title: title,
      tracks: _tracks,
      totalCount: _tracks.length,
      sourceUrl: playlistUrl,
      description: description,
      ownerName: ownerName,
      ownerUserId: ownerUserId,
    );
  }
}

class _PagedPlaylistSource implements PlaylistParsingSource, PagedVideoSource {
  _PagedPlaylistSource(this._sourceType);

  final SourceType _sourceType;
  Map<String, String>? lastParseAuthHeaders;
  Map<String, String>? lastPageAuthHeaders;

  @override
  SourceType get sourceType => _sourceType;

  @override
  bool isPlaylistUrl(String url) => true;

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) async {
    lastParseAuthHeaders = authHeaders;
    return PlaylistParseResult(
      title: 'Paged playlist',
      tracks: [
        Track()
          ..sourceId = 'BV-paged'
          ..sourceType = sourceType
          ..title = 'Paged video'
          ..pageCount = 2,
      ],
      totalCount: 1,
      sourceUrl: playlistUrl,
    );
  }

  @override
  Future<List<VideoPage>> getVideoPages(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) async {
    lastPageAuthHeaders = authHeaders;
    return const [
      VideoPage(cid: 101, page: 1, part: 'Page 1', duration: 60),
      VideoPage(cid: 102, page: 2, part: 'Page 2', duration: 70),
    ];
  }
}

class _DynamicPlaylistSource implements PlaylistParsingSource {
  _DynamicPlaylistSource({
    required this.title,
    required this.buildTracks,
  });

  final String title;
  final List<Track> Function() buildTracks;
  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  bool isPlaylistUrl(String url) => true;

  @override
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1,
      int pageSize = 20,
      Map<String, String>? authHeaders}) async {
    final tracks = buildTracks();
    return PlaylistParseResult(
      title: title,
      tracks: tracks,
      totalCount: tracks.length,
      sourceUrl: playlistUrl,
    );
  }
}

class _BlockingTrackRepository extends TrackRepository {
  _BlockingTrackRepository(super.isar);

  final coverLookupStarted = Completer<void>();
  final _coverLookupCompleter = Completer<void>();

  void completeCoverLookup() {
    if (!_coverLookupCompleter.isCompleted) {
      _coverLookupCompleter.complete();
    }
  }

  @override
  Future<Track?> getById(int id) async {
    if (!coverLookupStarted.isCompleted) {
      coverLookupStarted.complete();
      await _coverLookupCompleter.future;
    }
    return super.getById(id);
  }
}

class _CancellingPlaylistRepository extends PlaylistRepository {
  _CancellingPlaylistRepository(
    super.isar, {
    required this.onAfterFinalSave,
  });

  final void Function() onAfterFinalSave;
  var _saveCount = 0;

  @override
  Future<int> save(Playlist playlist) async {
    final id = await super.save(playlist);
    _saveCount++;
    if (_saveCount == 2) {
      onAfterFinalSave();
    }
    return id;
  }
}

class _CancellingMutationService extends PlaylistMutationService {
  _CancellingMutationService({
    required super.isar,
    required this.onAfterMutation,
  });

  final void Function() onAfterMutation;

  @override
  Future<PlaylistMutationResult> addTracks(
      int playlistId, List<Track> tracks) async {
    final result = await super.addTracks(playlistId, tracks);
    onAfterMutation();
    return result;
  }
}

Track _track(String sourceId, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = title
    ..thumbnailUrl = 'https://example.com/$sourceId.jpg'
    ..createdAt = DateTime.now();
}

class _MixImportSentinel implements Exception {}

class _ParseSentinel implements Exception {}

class _FakeSourceAuthContext implements SourceAuthContext {
  Map<String, String>? playlistImportHeaders;
  Map<String, String>? playlistRefreshHeaders;
  Map<String, String>? playHeaders;

  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async {
    return playHeaders;
  }

  @override
  Future<Map<String, String>?> playlistImportAuth(
    SourceType sourceType, {
    required bool useAuth,
  }) async {
    return useAuth ? playlistImportHeaders : null;
  }

  @override
  Future<Map<String, String>?> playlistRefreshAuth(
    SourceType sourceType, {
    required bool useAuthForRefresh,
  }) async {
    return useAuthForRefresh ? playlistRefreshHeaders : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
