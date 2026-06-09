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
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart'
    hide PlaybackNetworkRequest, PlaybackUrlResolution, PlaybackUrlResolver;
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
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
    late DefaultStreamResolutionService streamResolutionService;
    late AudioStreamManager manager;
    late _FakeSourceAuthContext sourceAuthContext;

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
      sourceAuthContext = _FakeSourceAuthContext();
      streamResolutionService = DefaultStreamResolutionService(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
        sourceAuthContext: sourceAuthContext,
      );
      manager = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        sourceAuthContext: sourceAuthContext,
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
      streamResolutionService.dispose();
      queueManager.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('selectPlayback passes SourceAuthContext headers to stream fetch',
        () async {
      sourceAuthContext.authHeaders = {
        'Authorization': 'Bearer sentinel',
      };

      await manager.selectPlayback(
        _track('stream-auth', title: 'Stream Auth'),
      );

      expect(sourceManager.source.audioStreamRequests.map((r) => r.sourceId),
          ['stream-auth']);
      expect(sourceAuthContext.authForPlayRequests, [
        SourceType.youtube,
        SourceType.youtube,
      ]);
      expect(sourceManager.source.lastAudioAuthHeaders, {
        'Authorization': 'Bearer sentinel',
      });
    });

    test(
        'selectPlayback passes null stream auth when SourceAuthContext returns none',
        () async {
      await manager.selectPlayback(
        _track('stream-no-auth', title: 'Stream No Auth'),
      );

      expect(sourceManager.source.audioStreamRequests.map((r) => r.sourceId),
          ['stream-no-auth']);
      expect(sourceAuthContext.authForPlayRequests, [
        SourceType.youtube,
        SourceType.youtube,
      ]);
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
      expect(queueCopy!.playlistInfo[0].downloadPath,
          '${tempDir.path}/missing-file.m4a');
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
        'selectPlayback clears missing download paths even when stream persistence is disabled',
        () async {
      final missingPath = '${tempDir.path}/missing-temporary-play.m4a';
      final savedTrack = await trackRepository.save(
        _track('stream-temporary', title: 'Temporary Stream')
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 1
              ..playlistName = 'Downloaded Playlist'
              ..downloadPath = missingPath,
          ],
      );

      final selection =
          await manager.selectPlayback(savedTrack, persist: false);

      expect(selection.localPath, isNull);
      expect(selection.url, 'https://example.com/stream-temporary.m4a');
      expect(selection.track.audioUrl, selection.url);
      expect(selection.track.playlistInfo.single.downloadPath, isEmpty);
      expect(sourceManager.source.audioStreamRequests.map((r) => r.sourceId),
          ['stream-temporary']);

      final persistedTrack = await trackRepository.getById(savedTrack.id);
      expect(persistedTrack, isNotNull);
      expect(persistedTrack!.playlistInfo.single.downloadPath, isEmpty);
      expect(persistedTrack.audioUrl, isNull);
    });

    test(
        'selectPlayback notifies with removed paths when clearing missing download paths',
        () async {
      final missingPath = '${tempDir.path}/missing-watch-update.m4a';
      final eventFuture = manager.downloadPathsChangedStream.first;
      final savedTrack = await trackRepository.save(
        _track('stream-watch', title: 'Stream Watch')
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 1
              ..playlistName = 'Downloaded Playlist'
              ..downloadPath = missingPath,
          ],
      );

      await manager.selectPlayback(savedTrack, persist: false);

      final event = await eventFuture;
      expect(event.track.id, savedTrack.id);
      expect(event.track.playlistInfo.single.downloadPath, isEmpty);
      expect(event.removedPaths, [missingPath]);
    });

    test('default manager emits removed download paths on its stream',
        () async {
      final missingPath = '${tempDir.path}/missing-manager-stream.m4a';
      final directManager = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        sourceAuthContext: sourceAuthContext,
      );
      addTearDown(directManager.dispose);
      final eventFuture = directManager.downloadPathsChangedStream.first;
      final savedTrack = await trackRepository.save(
        _track('stream-manager-event', title: 'Manager Event')
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 1
              ..playlistName = 'Downloaded Playlist'
              ..downloadPath = missingPath,
          ],
      );

      await directManager.selectPlayback(savedTrack, persist: false);

      final event = await eventFuture;
      expect(event.track.id, savedTrack.id);
      expect(event.removedPaths, [missingPath]);
    });

    test('selectPlayback ignores cleanup notifications after manager disposal',
        () async {
      final missingPath = '${tempDir.path}/missing-after-dispose.m4a';
      final directManager = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        sourceAuthContext: sourceAuthContext,
      );
      final savedTrack = await trackRepository.save(
        _track('stream-disposed-event', title: 'Disposed Event')
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 1
              ..playlistName = 'Downloaded Playlist'
              ..downloadPath = missingPath,
          ],
      );
      directManager.dispose();

      await expectLater(
        directManager.selectPlayback(savedTrack, persist: false),
        completes,
      );
    });

    test('ensureAudioUrl clears missing paths after the first valid local file',
        () async {
      final validFile = File('${tempDir.path}/downloaded-first-valid.m4a');
      await validFile.writeAsString('audio-bytes');
      final trailingMissingPath = '${tempDir.path}/missing-after-valid.m4a';

      final savedTrack = await trackRepository.save(
        _track('stream-valid-first', title: 'Valid First')
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 1
              ..playlistName = 'Downloaded Playlist'
              ..downloadPath = validFile.path,
            PlaylistDownloadInfo()
              ..playlistId = 2
              ..playlistName = 'Deleted Playlist'
              ..downloadPath = trailingMissingPath,
          ],
      );

      final (updatedTrack, localPath) =
          await manager.ensureAudioUrl(savedTrack);

      expect(localPath, validFile.path);
      expect(updatedTrack.playlistInfo[0].downloadPath, validFile.path);
      expect(updatedTrack.playlistInfo[1].downloadPath, isEmpty);
      expect(sourceManager.source.audioStreamRequests, isEmpty);

      final persistedTrack = await trackRepository.getById(savedTrack.id);
      expect(persistedTrack, isNotNull);
      expect(persistedTrack!.playlistInfo[0].downloadPath, validFile.path);
      expect(persistedTrack.playlistInfo[1].downloadPath, isEmpty);
    });

    test(
        'selectPlayback clears matching persisted track for transient downloaded-page tracks',
        () async {
      final missingPath = '${tempDir.path}/missing-scanned-track.m4a';
      final savedTrack = await trackRepository.save(
        _track('stream-scanned', title: 'Persisted Stream')
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 4
              ..playlistName = 'Persisted Playlist'
              ..downloadPath = missingPath,
          ],
      );
      final transientTrack = _track('stream-scanned', title: 'Scanned Stream')
        ..playlistInfo = [
          PlaylistDownloadInfo()
            ..playlistId = 0
            ..downloadPath = missingPath,
        ];

      final selection =
          await manager.selectPlayback(transientTrack, persist: false);

      expect(selection.localPath, isNull);
      expect(selection.url, 'https://example.com/stream-scanned.m4a');
      expect(selection.track.id, savedTrack.id);
      expect(selection.track.playlistInfo.single.downloadPath, isEmpty);

      final persistedTracks = await trackRepository.getAll();
      expect(persistedTracks, hasLength(1));
      expect(persistedTracks.single.id, savedTrack.id);
      expect(persistedTracks.single.playlistInfo.single.downloadPath, isEmpty);
    });

    test('selectPlayback matches persisted track by page when cid is missing',
        () async {
      final firstMissingPath = '${tempDir.path}/missing-ambiguous-first.m4a';
      final secondMissingPath = '${tempDir.path}/missing-ambiguous-second.m4a';
      final firstTrack = await trackRepository.save(
        _track('stream-ambiguous', title: 'Ambiguous First')
          ..cid = 101
          ..pageNum = 1
          ..pageCount = 2
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 1
              ..playlistName = 'First Playlist'
              ..downloadPath = firstMissingPath,
          ],
      );
      final secondTrack = await trackRepository.save(
        _track('stream-ambiguous', title: 'Ambiguous Second')
          ..cid = 202
          ..pageNum = 2
          ..pageCount = 2
          ..playlistInfo = [
            PlaylistDownloadInfo()
              ..playlistId = 2
              ..playlistName = 'Second Playlist'
              ..downloadPath = secondMissingPath,
          ],
      );
      final transientTrack = _track('stream-ambiguous', title: 'Scanned Page')
        ..pageNum = 2
        ..pageCount = 2
        ..playlistInfo = [
          PlaylistDownloadInfo()
            ..playlistId = 0
            ..downloadPath = secondMissingPath,
        ];

      final selection =
          await manager.selectPlayback(transientTrack, persist: false);

      expect(selection.track.id, secondTrack.id);
      expect(selection.track.playlistInfo.single.downloadPath, isEmpty);
      final firstPersisted = await trackRepository.getById(firstTrack.id);
      final secondPersisted = await trackRepository.getById(secondTrack.id);
      expect(
          firstPersisted!.playlistInfo.single.downloadPath, firstMissingPath);
      expect(secondPersisted!.playlistInfo.single.downloadPath, isEmpty);
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
        streamResolutionService: streamResolutionService,
        sourceAuthContext: sourceAuthContext,
      );

      await expectLater(
        directManager.prefetchTrack(
          _track('stream-prefetch', title: 'Prefetch Failure'),
        ),
        completes,
      );
    });

    test('playback headers use shared source media policy', () async {
      final youtube = await manager.getPlaybackHeaders(
        Track()
          ..sourceId = 'yt'
          ..sourceType = SourceType.youtube
          ..title = 'YouTube'
          ..artist = 'Tester',
      );
      final bilibili = await manager.getPlaybackHeaders(
        Track()
          ..sourceId = 'bv'
          ..sourceType = SourceType.bilibili
          ..title = 'Bilibili'
          ..artist = 'Tester',
      );

      expect(youtube, SourceHttpPolicy.mediaHeaders(SourceType.youtube));
      expect(bilibili, SourceHttpPolicy.mediaHeaders(SourceType.bilibili));
      expect(
        AudioStreamManager.defaultPlaybackUserAgent,
        SourceHttpPolicy.mediaUserAgent,
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

    test('selectPlayback stores source-provided stream expiry on the track',
        () async {
      sourceManager.source.nextAudioExpiry = const Duration(minutes: 16);

      final selection = await manager.selectPlayback(
        _track('stream-expiry', title: 'Stream Expiry'),
      );

      expect(selection.localPath, isNull);
      expect(selection.url, 'https://example.com/stream-expiry.m4a');
      expect(selection.track.audioUrl, selection.url);
      expect(selection.track.audioUrlExpiry, isNotNull);
      final expiryDelta =
          selection.track.audioUrlExpiry!.difference(DateTime.now());
      expect(
        expiryDelta.inMinutes,
        inInclusiveRange(15, 16),
      );
    });

    test('selectPlayback falls back to one hour when source omits expiry',
        () async {
      sourceManager.source.nextAudioExpiry = null;

      final selection = await manager.selectPlayback(
        _track('stream-default-expiry', title: 'Stream Default Expiry'),
      );

      expect(selection.track.audioUrlExpiry, isNotNull);
      final expiryDelta =
          selection.track.audioUrlExpiry!.difference(DateTime.now());
      expect(
        expiryDelta.inMinutes,
        inInclusiveRange(59, 60),
      );
    });

    test(
        'selectPlayback falls back from high quality to the next lower quality when source quality is unavailable',
        () async {
      final settings = await settingsRepository.get();
      settings.audioQualityLevel = AudioQualityLevel.high;
      await settingsRepository.save(settings);
      sourceManager.source
        ..encodeQualityInAudioUrl = true
        ..failingAudioQualities.add(AudioQualityLevel.high)
        ..bitrateByQuality[AudioQualityLevel.medium] = 192000;

      final selection = await manager.selectPlayback(
        _track('quality-fallback', title: 'Quality Fallback'),
      );

      expect(selection.url, 'https://example.com/quality-fallback-medium.m4a');
      expect(selection.streamResult?.bitrate, 192000);
      expect(sourceManager.source.audioStreamQualityRequests, [
        AudioQualityLevel.high,
        AudioQualityLevel.medium,
      ]);
    });

    test(
        'selectPlayback does not fall back quality for retryable source errors',
        () async {
      sourceManager.source
        ..failingAudioQualities.add(AudioQualityLevel.high)
        ..failingAudioKind = SourceErrorKind.network;

      await expectLater(
        manager.selectPlayback(
          _track('quality-network-error', title: 'Quality Network Error'),
        ),
        throwsA(isA<_FakeSourceException>()),
      );

      expect(sourceManager.source.audioStreamQualityRequests, [
        AudioQualityLevel.high,
      ]);
    });

    test('selectPlayback preserves Bilibili cid during stream resolution',
        () async {
      final bilibili = _FakeBilibiliSource();
      sourceManager.source = bilibili;
      final track = Track()
        ..sourceId = 'BVmultiPage'
        ..sourceType = SourceType.bilibili
        ..cid = 24680
        ..title = 'Bilibili P2'
        ..artist = 'Tester';

      final selection = await manager.selectPlayback(track);

      expect(selection.url, 'https://example.com/BVmultiPage-24680.m4a');
      expect(
        bilibili.primaryRequests.map((r) => (sourceId: r.sourceId, cid: r.cid)),
        [
          (sourceId: 'BVmultiPage', cid: 24680),
        ],
      );
    });

    test(
        'selectFallbackPlayback preserves Bilibili cid for alternative streams',
        () async {
      final bilibili = _FakeBilibiliSource();
      sourceManager.source = bilibili;
      const failedUrl = 'https://failed.example/bilibili-p2.m4a';
      final track = Track()
        ..sourceId = 'BVmultiPage'
        ..sourceType = SourceType.bilibili
        ..cid = 13579
        ..title = 'Bilibili P2'
        ..artist = 'Tester';

      final selection = await manager.selectFallbackPlayback(
        track,
        failedUrl: failedUrl,
      );

      expect(selection, isNotNull);
      expect(selection!.url,
          'https://example.com/BVmultiPage-13579-medium-alternative.m4a');
      expect(
        bilibili.alternativeRequests.map(
          (r) => (
            sourceId: r.sourceId,
            cid: r.cid,
            failedUrl: r.failedUrl,
            quality: r.config.qualityLevel,
          ),
        ),
        [
          (
            sourceId: 'BVmultiPage',
            cid: 13579,
            failedUrl: failedUrl,
            quality: AudioQualityLevel.medium,
          ),
        ],
      );
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
      expect(
          selection.url, 'https://example.com/stream-fallback-fallback.m3u8');
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
        'selectFallbackPlayback passes SourceAuthContext headers to source alternative streams',
        () async {
      sourceAuthContext.authHeaders = {
        'Authorization': 'Bearer fallback-sentinel',
      };

      final selection = await manager.selectFallbackPlayback(
        _track('stream-fallback-auth', title: 'Stream Fallback Auth'),
        failedUrl: 'https://failed.example/stream-fallback-auth.m4a',
      );

      expect(selection, isNotNull);
      expect(sourceAuthContext.authForPlayRequests, [
        SourceType.youtube,
        SourceType.youtube,
      ]);
      expect(sourceManager.source.lastAlternativeAuthHeaders, {
        'Authorization': 'Bearer fallback-sentinel',
      });
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

    test(
        'selectFallbackPlayback fetches the next lower quality when source alternative stream is unavailable',
        () async {
      final settings = await settingsRepository.get();
      settings.audioQualityLevel = AudioQualityLevel.high;
      await settingsRepository.save(settings);
      sourceManager.source
        ..encodeQualityInAudioUrl = true
        ..returnNullAlternative = true
        ..bitrateByQuality[AudioQualityLevel.medium] = 160000;
      final track =
          _track('handoff-quality-fallback', title: 'Handoff Fallback');

      final selection = await manager.selectFallbackPlayback(
        track,
        failedUrl: 'https://example.com/handoff-quality-fallback-high.m4a',
      );

      expect(selection, isNotNull);
      expect(selection!.url,
          'https://example.com/handoff-quality-fallback-medium.m4a');
      expect(selection.streamResult?.bitrate, 160000);
      expect(sourceManager.source.alternativeQualityRequests, [
        AudioQualityLevel.medium,
      ]);
      expect(sourceManager.source.audioStreamQualityRequests, [
        AudioQualityLevel.medium,
      ]);
    });

    test(
        'selectFallbackPlayback does not return the failed URL from lower-quality primary fallback',
        () async {
      final settings = await settingsRepository.get();
      settings.audioQualityLevel = AudioQualityLevel.high;
      await settingsRepository.save(settings);
      sourceManager.source
        ..returnNullAlternative = true
        ..reuseFailedUrlForPrimaryFallback = true;
      const failedUrl = 'https://example.com/handoff-failed-url-exclusion.m4a';

      final selection = await manager.selectFallbackPlayback(
        _track(
          'handoff-failed-url-exclusion',
          title: 'Handoff Failed URL Exclusion',
        ),
        failedUrl: failedUrl,
      );

      expect(selection, isNull);
      expect(sourceManager.source.audioStreamQualityRequests, [
        AudioQualityLevel.medium,
        AudioQualityLevel.low,
      ]);
    });

    test(
        'playback headers include Netease auth only when SourceAuthContext returns it',
        () async {
      final neteaseContext = _FakeSourceAuthContext();
      final managerWithNetease = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        sourceAuthContext: neteaseContext,
      );
      final track = Track()
        ..sourceId = 'netease-song'
        ..sourceType = SourceType.netease
        ..audioUrl = 'https://m701.music.126.net/netease-song.m4a'
        ..title = 'Netease Song'
        ..artist = 'Tester';

      neteaseContext.authHeaders =
          SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=music-u; __csrf=csrf');
      final enabledHeaders = await managerWithNetease.getPlaybackHeaders(track);
      expect(enabledHeaders?['Cookie'], 'MUSIC_U=music-u; __csrf=csrf');

      neteaseContext.authHeaders = null;
      final disabledHeaders =
          await managerWithNetease.getPlaybackHeaders(track);
      expect(
          disabledHeaders, SourceHttpPolicy.mediaHeaders(SourceType.netease));
      expect(disabledHeaders, isNot(contains('Cookie')));
    });

    test('prepareNetworkPlayback strips Netease auth after off-domain redirect',
        () async {
      final neteaseContext = _FakeSourceAuthContext()
        ..authHeaders =
            SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=music-u; __csrf=csrf')
        ..playbackUrlResolver = (sourceType, url, authHeaders) async {
          expect(sourceType, SourceType.netease);
          expect(url, 'https://m701.music.126.net/netease-song.m4a');
          expect(authHeaders?['Cookie'], 'MUSIC_U=music-u; __csrf=csrf');
          return const PlaybackUrlResolution(
            url: 'https://attacker.example/netease-song.m4a',
            includeCredentials: false,
          );
        };
      final managerWithNetease = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        sourceAuthContext: neteaseContext,
      );

      final prepared = await managerWithNetease.prepareNetworkPlayback(
        Track()
          ..sourceId = 'netease-song'
          ..sourceType = SourceType.netease
          ..title = 'Netease Song'
          ..artist = 'Tester',
        'https://m701.music.126.net/netease-song.m4a',
      );

      expect(prepared.url, 'https://attacker.example/netease-song.m4a');
      expect(prepared.headers, isNot(contains('Cookie')));
      expect(prepared.headers?['Origin'], SourceHttpPolicy.neteaseOrigin);
    });

    test(
        'playback headers delegate auth without leaking non-Netease media auth',
        () async {
      final accountContext = _FakeSourceAuthContext()
        ..headersBySource[SourceType.bilibili] = const {
          'Cookie': 'SESSDATA=bilibili-session',
        }
        ..headersBySource[SourceType.youtube] = const {
          'Cookie': 'SAPISID=youtube-session',
          'Authorization': 'SAPISIDHASH youtube-auth',
        };
      final managerWithAccounts = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        sourceAuthContext: accountContext,
      );

      final bilibiliHeaders = await managerWithAccounts.getPlaybackHeaders(
        Track()
          ..sourceId = 'BVauth'
          ..sourceType = SourceType.bilibili
          ..title = 'Bilibili Auth'
          ..artist = 'Tester',
      );
      final youtubeHeaders = await managerWithAccounts.getPlaybackHeaders(
        Track()
          ..sourceId = 'yt-auth'
          ..sourceType = SourceType.youtube
          ..title = 'YouTube Auth'
          ..artist = 'Tester',
      );

      expect(accountContext.authForPlayRequests, [
        SourceType.bilibili,
        SourceType.youtube,
      ]);
      expect(
          bilibiliHeaders, SourceHttpPolicy.mediaHeaders(SourceType.bilibili));
      expect(youtubeHeaders, SourceHttpPolicy.mediaHeaders(SourceType.youtube));
      expect(bilibiliHeaders, isNot(contains('Cookie')));
      expect(youtubeHeaders, isNot(contains('Cookie')));
      expect(youtubeHeaders, isNot(contains('Authorization')));
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
  _FakeSourceManager() : super(sources: const []);

  dynamic source = _FakeSource();

  @override
  AudioStreamSource? audioStreamSource(SourceType type) =>
      source is AudioStreamSource ? source as AudioStreamSource : null;

  @override
  void dispose() {}
}

class _FakeSource implements AudioStreamSource {
  AudioStreamRequest? lastAlternativeRequest;
  AudioStreamConfig? lastAlternativeConfig;
  String? lastFailedUrl;
  final List<AudioStreamRequest> audioStreamRequests = [];
  final List<AudioQualityLevel> audioStreamQualityRequests = [];
  final List<AudioQualityLevel> alternativeQualityRequests = [];
  Map<String, String>? lastAudioAuthHeaders;
  Map<String, String>? lastAlternativeAuthHeaders;
  bool throwOnRefresh = false;
  Duration? nextAudioExpiry;
  bool encodeQualityInAudioUrl = false;
  bool returnNullAlternative = false;
  bool reuseFailedUrlForPrimaryFallback = false;
  SourceErrorKind failingAudioKind = SourceErrorKind.unavailable;
  final Set<AudioQualityLevel> failingAudioQualities = {};
  final Map<AudioQualityLevel, int> bitrateByQuality = {};

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    audioStreamRequests.add(request);
    audioStreamQualityRequests.add(request.config.qualityLevel);
    lastAudioAuthHeaders = request.authHeaders;
    if (throwOnRefresh) {
      throw StateError('refresh failed for ${request.sourceId}');
    }
    if (failingAudioQualities.contains(request.config.qualityLevel)) {
      throw _FakeSourceException(
        kind: failingAudioKind,
        message: 'quality ${request.config.qualityLevel.name} failed',
      );
    }
    final expiry = nextAudioExpiry;
    nextAudioExpiry = null;
    final qualitySuffix =
        encodeQualityInAudioUrl && !reuseFailedUrlForPrimaryFallback
            ? '-${request.config.qualityLevel.name}'
            : '';
    return AudioStreamResult(
      url: 'https://example.com/${request.sourceId}$qualitySuffix.m4a',
      bitrate: bitrateByQuality[request.config.qualityLevel],
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
      expiry: expiry,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async {
    lastAlternativeRequest = request;
    lastFailedUrl = request.failedUrl;
    lastAlternativeConfig = request.config;
    lastAlternativeAuthHeaders = request.authHeaders;
    alternativeQualityRequests.add(request.config.qualityLevel);
    if (returnNullAlternative) {
      return null;
    }
    return AudioStreamResult(
      url: 'https://example.com/${request.sourceId}-fallback.m3u8',
      container: 'm3u8',
      codec: 'aac',
      streamType: request.config.streamPriority.first,
      expiry: const Duration(minutes: 16),
    );
  }
}

class _FakeBilibiliSource extends BilibiliSource {
  final List<AudioStreamRequest> primaryRequests = [];
  final List<AudioStreamRequest> alternativeRequests = [];

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    primaryRequests.add(request);
    if (request.cid == null) {
      throw StateError('Bilibili request must preserve cid');
    }
    return AudioStreamResult(
      url: 'https://example.com/${request.sourceId}-${request.cid}.m4a',
      streamType: StreamType.audioOnly,
      expiry: const Duration(minutes: 16),
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async {
    alternativeRequests.add(request);
    if (request.cid == null) {
      throw StateError('Bilibili alternative request must preserve cid');
    }
    return AudioStreamResult(
      url:
          'https://example.com/${request.sourceId}-${request.cid}-${request.config.qualityLevel.name}-alternative.m4a',
      streamType: request.config.streamPriority.first,
      expiry: const Duration(minutes: 16),
    );
  }
}

class _FakeSourceAuthContext implements SourceAuthContext {
  final headersBySource = <SourceType, Map<String, String>?>{};
  final authForPlayRequests = <SourceType>[];
  final playbackNetworkRequests = <({SourceType sourceType, String url})>[];
  Map<String, String>? authHeaders;
  PlaybackUrlResolver? playbackUrlResolver;

  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async {
    authForPlayRequests.add(sourceType);
    if (headersBySource.containsKey(sourceType)) {
      return headersBySource[sourceType];
    }
    return authHeaders;
  }

  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    playbackNetworkRequests.add((sourceType: track.sourceType, url: url));
    final headers = await authForPlay(track.sourceType);
    final resolver = playbackUrlResolver ??
        (
          SourceType sourceType,
          String url,
          Map<String, String>? authHeaders,
        ) async {
          return PlaybackUrlResolution(url: url);
        };
    final resolved = await resolver(track.sourceType, url, headers);
    return PlaybackNetworkRequest(
      url: resolved.url,
      headers: SourceHttpPolicy.mediaHeaders(
        track.sourceType,
        authHeaders: headers,
        requestUrl: resolved.url,
        includeCredentials: resolved.includeCredentials,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSourceException extends SourceApiException {
  const _FakeSourceException({
    required this.kind,
    required this.message,
  });

  @override
  final SourceErrorKind kind;

  @override
  final String message;

  @override
  String get code => kind.name;

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  String toString() => 'FakeSourceException($code): $message';
}
