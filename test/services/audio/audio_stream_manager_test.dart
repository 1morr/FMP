import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/internal/audio_stream_delegate.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioStreamManager Task 2 regression', () {
    late Directory tempDir;
    late Isar isar;
    late TrackRepository trackRepository;
    late SettingsRepository settingsRepository;
    late _FakeSourceManager sourceManager;
    late QueueManager queueManager;
    late AudioStreamDelegate delegate;
    late AudioStreamManager manager;
    late Map<String, String>? delegateAuthHeaders;
    late List<SourceType> authHeaderRequests;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'audio_stream_manager_',
      );
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'audio_stream_manager_test',
      );

      trackRepository = TrackRepository(isar);
      settingsRepository = SettingsRepository(isar);
      sourceManager = _FakeSourceManager();
      delegateAuthHeaders = null;
      authHeaderRequests = [];
      delegate = AudioStreamDelegate(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
        getAuthHeaders: (sourceType) async {
          authHeaderRequests.add(sourceType);
          return delegateAuthHeaders;
        },
      );
      manager = AudioStreamManager(
        delegate: delegate,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
      );
      queueManager = QueueManager(
        queueRepository: QueueRepository(isar),
        trackRepository: trackRepository,
        queuePersistenceManager: QueuePersistenceManager(
          queueRepository: QueueRepository(isar),
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        ),
      );
      await queueManager.initialize();
    });

    tearDown(() async {
      queueManager.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('selectPlayback passes auth headers to stream fetch when auth-for-play is enabled',
        () async {
      final settings = await settingsRepository.get();
      settings.useYoutubeAuthForPlay = true;
      await settingsRepository.save(settings);
      delegateAuthHeaders = {
        'Authorization': 'Bearer sentinel',
      };

      await manager.selectPlayback(
        _track('stream-auth', title: 'Stream Auth'),
      );

      expect(sourceManager.source.audioStreamRequests, ['stream-auth']);
      expect(authHeaderRequests, [SourceType.youtube]);
      expect(sourceManager.source.lastAudioAuthHeaders, {
        'Authorization': 'Bearer sentinel',
      });
    });

    test('selectPlayback skips auth header loading when auth-for-play is disabled',
        () async {
      final settings = await settingsRepository.get();
      settings.useYoutubeAuthForPlay = false;
      await settingsRepository.save(settings);
      delegateAuthHeaders = {
        'Authorization': 'Bearer sentinel',
      };

      await manager.selectPlayback(
        _track('stream-no-auth', title: 'Stream No Auth'),
      );

      expect(sourceManager.source.audioStreamRequests, ['stream-no-auth']);
      expect(authHeaderRequests, isEmpty);
      expect(sourceManager.source.lastAudioAuthHeaders, isNull);
    });

    test(
        'ensureAudioUrl preserves valid download paths and clears only missing ones',
        () async {
      final firstValidFile = File('${tempDir.path}/downloaded-1.m4a');
      final secondValidFile = File('${tempDir.path}/downloaded-2.m4a');
      await firstValidFile.writeAsString('audio-bytes-1');
      await secondValidFile.writeAsString('audio-bytes-2');

      final savedTrack = await trackRepository.save(
        _track('stream-1', title: 'Stream One')
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 1
              ..playlistName = 'Missing Playlist'
              ..downloadPath = '${tempDir.path}/missing-file.m4a',
            PlaylistDownloadInfo()
              ..playlistId = 2
              ..playlistName = 'Downloaded Playlist One'
              ..downloadPath = firstValidFile.path,
            PlaylistDownloadInfo()
              ..playlistId = 3
              ..playlistName = 'Downloaded Playlist Two'
              ..downloadPath = secondValidFile.path,
          ],
      );
      final queueCopy = await trackRepository.getById(savedTrack.id);
      expect(queueCopy, isNotNull);
      expect(queueCopy, isNot(same(savedTrack)));

      final (updatedTrack, localPath) =
          await manager.ensureAudioUrl(savedTrack);

      expect(localPath, firstValidFile.path);
      expect(updatedTrack.audioUrl, isNull);
      expect(updatedTrack.playlistInfo[0].downloadPath, isEmpty);
      expect(updatedTrack.playlistInfo[1].downloadPath, firstValidFile.path);
      expect(updatedTrack.playlistInfo[2].downloadPath, secondValidFile.path);
      expect(queueCopy!.playlistInfo[0].downloadPath, '${tempDir.path}/missing-file.m4a');
      expect(queueCopy.playlistInfo[1].downloadPath, firstValidFile.path);
      expect(queueCopy.playlistInfo[2].downloadPath, secondValidFile.path);
      expect(sourceManager.source.audioStreamRequests, isEmpty);

      final persistedTrack = await trackRepository.getById(savedTrack.id);
      expect(persistedTrack, isNotNull);
      expect(persistedTrack!.playlistInfo[0].downloadPath, isEmpty);
      expect(persistedTrack.playlistInfo[1].downloadPath, firstValidFile.path);
      expect(persistedTrack.playlistInfo[2].downloadPath, secondValidFile.path);
    });

    test(
        'ensureAudioStream leaves queue copy stale until caller explicitly replaces it',
        () async {
      final queuedTrack = await queueManager.playSingle(
        _track('stream-attach', title: 'Stream Attach'),
      );
      final queueCopyBeforeRefresh = queueManager.currentTrack;
      expect(queueCopyBeforeRefresh, isNotNull);
      expect(queueCopyBeforeRefresh, same(queuedTrack));

      final requestTrack = await trackRepository.getById(queuedTrack.id);
      expect(requestTrack, isNotNull);
      expect(requestTrack, isNot(same(queueCopyBeforeRefresh)));

      final (updatedTrack, localPath, streamResult) =
          await manager.ensureAudioStream(requestTrack!);

      expect(localPath, isNull);
      expect(streamResult, isNotNull);
      expect(updatedTrack.audioUrl, isNotNull);
      expect(queueManager.currentTrack, same(queueCopyBeforeRefresh));
      expect(queueManager.currentTrack!.audioUrl, isNull);

      final persistedTrack = await trackRepository.getById(queuedTrack.id);
      expect(persistedTrack, isNotNull);
      expect(persistedTrack!.audioUrl, updatedTrack.audioUrl);

      queueManager.replaceTrack(updatedTrack);

      expect(queueManager.currentTrack, isNotNull);
      expect(queueManager.currentTrack, isNot(same(queueCopyBeforeRefresh)));
      expect(queueManager.currentTrack!.audioUrl, updatedTrack.audioUrl);
    });

    test('prefetchTrack swallows refresh failures', () async {
      sourceManager.source.throwOnRefresh = true;
      final directManager = AudioStreamManager(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
      );

      await expectLater(
        directManager.prefetchTrack(
          _track('stream-prefetch', title: 'Prefetch Failure'),
        ),
        completes,
      );
    });

    test('selectPlayback attaches playback headers for remote streams',
        () async {
      final selection = await manager.selectPlayback(
        _track('stream-headers', title: 'Stream Headers'),
      );

      expect(selection.localPath, isNull);
      expect(selection.url, 'https://example.com/stream-headers.m4a');
      expect(selection.track.audioUrl, selection.url);
      expect(selection.headers, {
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
        'User-Agent': AudioStreamManager.defaultPlaybackUserAgent,
      });
      expect(selection.streamResult, isNotNull);
    });

    test('selectFallbackPlayback assembles fallback selection with headers',
        () async {
      final track = _track('stream-fallback', title: 'Stream Fallback');

      final selection = await manager.selectFallbackPlayback(
        track,
        failedUrl: 'https://failed.example/stream-fallback.m4a',
      );

      expect(selection, isNotNull);
      expect(selection!.localPath, isNull);
      expect(selection.url, 'https://example.com/stream-fallback-fallback.m3u8');
      expect(selection.track, same(track));
      expect(selection.track.audioUrl,
          'https://example.com/stream-fallback-fallback.m3u8');
      expect(selection.track.audioUrlExpiry, isNotNull);
      final fallbackExpiryDelta =
          selection.track.audioUrlExpiry!.difference(DateTime.now());
      expect(
        fallbackExpiryDelta.inMinutes,
        inInclusiveRange(15, 16),
      );
      expect(selection.headers, {
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
        'User-Agent': AudioStreamManager.defaultPlaybackUserAgent,
      });
      expect(selection.streamResult, isNotNull);
      expect(selection.streamResult!.url,
          'https://example.com/stream-fallback-fallback.m3u8');
      expect(selection.streamResult!.streamType, StreamType.audioOnly);
      expect(sourceManager.source.lastFailedUrl,
          'https://failed.example/stream-fallback.m4a');
    });

    test(
        'getAlternativeAudioStream uses configured stream priority for fallback selection',
        () async {
      final settings = await settingsRepository.get();
      settings.youtubeStreamPriority = 'hls,muxed,audioOnly';
      await settingsRepository.save(settings);

      final result = await manager.getAlternativeAudioStream(
        _track('stream-2', title: 'Stream Two'),
        failedUrl: 'https://failed.example/stream-2.m4a',
      );

      expect(result, isNotNull);
      expect(result!.url, 'https://example.com/stream-2-fallback.m3u8');
      expect(result.streamType, StreamType.hls);
      expect(sourceManager.source.lastAlternativeConfig?.streamPriority, [
        StreamType.hls,
        StreamType.muxed,
        StreamType.audioOnly,
      ]);
      expect(sourceManager.source.lastFailedUrl,
          'https://failed.example/stream-2.m4a');
    });
  });
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfig = await _loadPackageConfig();
  final packageDir =
      _resolvePackageDirectory(packageConfig, 'isar_flutter_libs');

  if (Platform.isWindows) {
    return '${packageDir.path}/windows/isar.dll';
  }
  if (Platform.isLinux) {
    return '${packageDir.path}/linux/libisar.so';
  }
  if (Platform.isMacOS) {
    return '${packageDir.path}/macos/libisar.dylib';
  }

  throw UnsupportedError(
      'Unsupported platform for Isar tests: ${Platform.operatingSystem}');
}

Future<Map<String, dynamic>> _loadPackageConfig() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  if (!await packageConfigFile.exists()) {
    throw StateError(
      'Could not find .dart_tool/package_config.json for test package resolution',
    );
  }

  return jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
}

Directory _resolvePackageDirectory(
  Map<String, dynamic> packageConfig,
  String packageName,
) {
  final packages = packageConfig['packages'];
  if (packages is! List) {
    throw StateError('Invalid package_config.json format');
  }

  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');
  for (final package in packages) {
    if (package is! Map<String, dynamic>) continue;
    if (package['name'] != packageName) continue;

    final rootUri = package['rootUri'];
    if (rootUri is! String) break;

    return Directory(packageConfigDir.uri.resolve(rootUri).toFilePath());
  }

  throw StateError('Package not found in package_config.json: $packageName');
}

Track _track(String sourceId, {required String title}) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = title
    ..artist = 'Tester';
}

class _FakeSourceManager extends SourceManager {
  _FakeSourceManager() : super();

  final source = _FakeSource();

  @override
  BaseSource? getSource(SourceType type) => source;

  @override
  void dispose() {}
}

class _FakeSource extends BaseSource {
  AudioStreamConfig? lastAlternativeConfig;
  String? lastFailedUrl;
  final List<String> audioStreamRequests = [];
  Map<String, String>? lastAudioAuthHeaders;
  bool throwOnRefresh = false;

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  Future<bool> checkAvailability(String sourceId) async => true;

  @override
  bool isPlaylistUrl(String url) => false;

  @override
  bool isValidId(String id) => true;

  @override
  String? parseId(String url) => url;

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Track> getTrackInfo(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) async {
    return _track(sourceId, title: sourceId);
  }

  @override
  Future<AudioStreamResult> getAudioStream(
    String sourceId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    audioStreamRequests.add(sourceId);
    lastAudioAuthHeaders = authHeaders;
    return AudioStreamResult(
      url: 'https://example.com/$sourceId.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    String sourceId, {
    String? failedUrl,
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  }) async {
    lastFailedUrl = failedUrl;
    lastAlternativeConfig = config;
    return AudioStreamResult(
      url: 'https://example.com/$sourceId-fallback.m3u8',
      container: 'm3u8',
      codec: 'aac',
      streamType: config.streamPriority.first,
      expiry: const Duration(minutes: 16),
    );
  }

  @override
  Future<Track> refreshAudioUrl(
    Track track, {
    Map<String, String>? authHeaders,
  }) async {
    if (throwOnRefresh) {
      throw StateError('refresh failed for ${track.sourceId}');
    }
    track.audioUrl = 'https://example.com/${track.sourceId}.m4a';
    track.audioUrlExpiry = DateTime.now().add(const Duration(minutes: 30));
    return track;
  }

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    return SearchResult.empty();
  }

  @override
  void dispose() {}
}
