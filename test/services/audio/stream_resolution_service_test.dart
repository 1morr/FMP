import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:isar_community/isar.dart';
import '../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Isar isar;
  late TrackRepository trackRepository;
  late SettingsRepository settingsRepository;
  late _RecordingAudioStreamSource source;
  late SourceManager sourceManager;
  late DefaultStreamResolutionService service;
  late _RecordingSourceAuthContext sourceAuthContext;

  setUpAll(() async {
    await initializeIsarForTests();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stream_resolution_');
    isar = await Isar.open(
      [TrackSchema, SettingsSchema],
      directory: tempDir.path,
      name: 'stream_resolution_test',
    );
    trackRepository = TrackRepository(isar);
    settingsRepository = SettingsRepository(isar);
    source = _RecordingAudioStreamSource();
    sourceManager = SourceManager(sources: [source]);
    sourceAuthContext = _RecordingSourceAuthContext();
    service = DefaultStreamResolutionService(
      trackRepository: trackRepository,
      settingsRepository: settingsRepository,
      sourceManager: sourceManager,
      sourceAuthContext: sourceAuthContext,
    );
  });

  tearDown(() async {
    service.dispose();
    sourceManager.dispose();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('resolvePrimary passes auth headers when auth-for-play is enabled',
      () async {
    final settings = await settingsRepository.get();
    settings.useYoutubeAuthForPlay = true;
    await settingsRepository.save(settings);
    sourceAuthContext.authHeaders = {'Authorization': 'Bearer sentinel'};

    final result = await service.resolvePrimary(
      _track('auth-enabled'),
      purpose: StreamResolutionPurpose.playback,
    );

    expect(result, isA<RemoteStreamResolution>());
    expect(sourceAuthContext.authForPlayRequests, [SourceType.youtube]);
    expect(source.primaryRequests.single.authHeaders, {
      'Authorization': 'Bearer sentinel',
    });
    expect((result as RemoteStreamResolution).authHeaders, {
      'Authorization': 'Bearer sentinel',
    });
  });

  test('resolvePrimary clears missing download paths before local playback',
      () async {
    final missingPath = '${tempDir.path}/missing.m4a';
    final localFile = File('${tempDir.path}/downloaded.m4a');
    await localFile.writeAsString('audio');
    final savedTrack = await trackRepository.save(
      _track('local')
        ..playlistInfo = [
          PlaylistDownloadInfo()
            ..playlistId = 1
            ..playlistName = 'Missing'
            ..downloadPath = missingPath,
          PlaylistDownloadInfo()
            ..playlistId = 2
            ..playlistName = 'Downloaded'
            ..downloadPath = localFile.path,
        ],
    );
    final eventFuture = service.downloadPathsChangedStream.first;

    final result = await service.resolvePrimary(
      savedTrack,
      purpose: StreamResolutionPurpose.playback,
      persist: false,
    );

    expect(result, isA<LocalStreamResolution>());
    expect((result as LocalStreamResolution).path, localFile.path);
    expect(source.primaryRequests, isEmpty);
    final event = await eventFuture;
    expect(event.removedPaths, [missingPath]);
    final persistedTrack = await trackRepository.getById(savedTrack.id);
    expect(persistedTrack!.playlistInfo[0].downloadPath, isEmpty);
    expect(persistedTrack.playlistInfo[1].downloadPath, localFile.path);
  });

  test('download resolution skips local files and resolves a remote stream',
      () async {
    final localFile = File('${tempDir.path}/downloaded.m4a');
    await localFile.writeAsString('audio');
    final savedTrack = await trackRepository.save(
      _track('download')
        ..playlistInfo = [
          PlaylistDownloadInfo()
            ..playlistId = 1
            ..playlistName = 'Downloaded'
            ..downloadPath = localFile.path,
        ],
    );

    final result = await service.resolvePrimary(
      savedTrack,
      purpose: StreamResolutionPurpose.download,
    );

    expect(result, isA<RemoteStreamResolution>());
    expect((result as RemoteStreamResolution).stream.url,
        'https://example.com/download-high.m4a');
    expect(source.primaryRequests.single.sourceId, 'download');
  });

  test('resolvePrimary applies quality fallback and persists source expiry',
      () async {
    source
      ..failingQualities.add(AudioQualityLevel.high)
      ..nextExpiry = const Duration(minutes: 12);
    final before = DateTime.now();
    final savedTrack = await trackRepository.save(
      _track('multi')
        ..cid = 24680
        ..pageNum = 2,
    );

    final result = await service.resolvePrimary(
      savedTrack,
      purpose: StreamResolutionPurpose.playback,
    );
    final after = DateTime.now();

    expect(result, isA<RemoteStreamResolution>());
    expect(source.primaryRequests.map((request) => request.config.qualityLevel),
        [AudioQualityLevel.high, AudioQualityLevel.medium]);
    expect(source.primaryRequests.every((request) => request.cid == 24680),
        isTrue);
    expect(source.primaryRequests.every((request) => request.pageNum == 2),
        isTrue);
    final persistedTrack = await trackRepository.getById(savedTrack.id);
    expect(persistedTrack!.audioUrl, 'https://example.com/multi-medium.m4a');
    expect(
      persistedTrack.audioUrlExpiry!,
      isNot(before.add(const Duration(minutes: 12)).subtract(
            const Duration(seconds: 1),
          )),
    );
    expect(
      persistedTrack.audioUrlExpiry!.isBefore(
        after.add(const Duration(minutes: 12, seconds: 1)),
      ),
      isTrue,
    );
  });

  test('resolvePrimary reuses a still-fresh stream instead of resolving twice',
      () async {
    final track = _track('reuse');

    final first = await service.resolvePrimary(
      track,
      purpose: StreamResolutionPurpose.playback,
    );
    final second = await service.resolvePrimary(
      first.track,
      purpose: StreamResolutionPurpose.playback,
    );

    expect(source.primaryRequests, hasLength(1));
    expect(second, isA<RemoteStreamResolution>());
    final firstStream = (first as RemoteStreamResolution).stream;
    final secondStream = (second as RemoteStreamResolution).stream;
    // 中繼資料必須完整跟著回來，否則播放頁的位元率/編碼會在重用時變空白。
    expect(secondStream.url, firstStream.url);
    expect(secondStream.streamType, firstStream.streamType);
    expect(secondStream.bitrate, firstStream.bitrate);
    expect(secondStream.container, firstStream.container);
    expect(secondStream.codec, firstStream.codec);
  });

  test('resolvePrimary re-resolves when the URL is inside the refresh margin',
      () async {
    source.nextExpiry = const Duration(minutes: 4);
    final track = _track('margin');

    final first = await service.resolvePrimary(
      track,
      purpose: StreamResolutionPurpose.playback,
    );
    await service.resolvePrimary(
      first.track,
      purpose: StreamResolutionPurpose.playback,
    );

    expect(source.primaryRequests, hasLength(2));
  });

  test('resolvePrimary re-resolves after the audio quality setting changes',
      () async {
    final first = await service.resolvePrimary(
      _track('quality'),
      purpose: StreamResolutionPurpose.playback,
    );

    final settings = await settingsRepository.get();
    settings.audioQualityLevel = AudioQualityLevel.low;
    await settingsRepository.save(settings);

    await service.resolvePrimary(
      first.track,
      purpose: StreamResolutionPurpose.playback,
    );

    expect(source.primaryRequests.map((request) => request.config.qualityLevel),
        [AudioQualityLevel.high, AudioQualityLevel.low]);
  });

  test('resolvePrimary re-resolves after the auth headers change', () async {
    sourceAuthContext.authHeaders = {'Cookie': 'session=1'};
    final first = await service.resolvePrimary(
      _track('auth'),
      purpose: StreamResolutionPurpose.playback,
    );

    sourceAuthContext.authHeaders = null;
    await service.resolvePrimary(
      first.track,
      purpose: StreamResolutionPurpose.playback,
    );

    expect(source.primaryRequests, hasLength(2));
  });

  test('invalidateStream forces a fresh resolve after a playback failure',
      () async {
    final first = await service.resolvePrimary(
      _track('invalidate'),
      purpose: StreamResolutionPurpose.playback,
    );

    // 播放失敗的那個 URL 可能還沒過期卻已經被 CDN 擋掉。少了這一步，重試會
    // 一次又一次拿回同一個死 URL。
    service.invalidateStream(first.track);
    await service.resolvePrimary(
      first.track,
      purpose: StreamResolutionPurpose.playback,
    );

    expect(source.primaryRequests, hasLength(2));
  });

  test('resolvePrimary never reuses a stream for a download', () async {
    final first = await service.resolvePrimary(
      _track('download-reuse'),
      purpose: StreamResolutionPurpose.playback,
    );

    await service.resolvePrimary(
      first.track,
      purpose: StreamResolutionPurpose.download,
    );

    expect(source.primaryRequests, hasLength(2));
  });

  test('resolvePrimary does not reuse across pages sharing a sourceId',
      () async {
    final page1 = _track('paged')..pageNum = 1;
    final first = await service.resolvePrimary(
      page1,
      purpose: StreamResolutionPurpose.playback,
      persist: false,
    );

    // 分 P 在 cid 解析出來之前共用同一個 uniqueKey，而這兩頁的 URL 不同。
    // 快取 key 少了 pageNum 就會把 P1 的串流餵給 P2。
    final page2 = _track('paged')
      ..pageNum = 2
      ..audioUrl = first.track.audioUrl
      ..audioUrlExpiry = first.track.audioUrlExpiry;
    await service.resolvePrimary(
      page2,
      purpose: StreamResolutionPurpose.playback,
      persist: false,
    );

    expect(source.primaryRequests, hasLength(2));
    expect(source.primaryRequests.map((request) => request.pageNum), [1, 2]);
  });

  test('resolvePrimary writes a resolved cid back onto the track', () async {
    source.nextCid = 998877;
    final track = _track('cid-writeback');

    final result = await service.resolvePrimary(
      track,
      purpose: StreamResolutionPurpose.playback,
    );

    expect(result.track.cid, 998877);
    final persisted = await trackRepository.getById(result.track.id);
    expect(persisted!.cid, 998877);
  });

  test('resolvePrimary never overwrites a cid the track already has',
      () async {
    source.nextCid = 998877;
    final track = _track('cid-keep')..cid = 12345;

    final result = await service.resolvePrimary(
      track,
      purpose: StreamResolutionPurpose.playback,
    );

    // cid 是分 P 的身分，不是可以被解析結果蓋掉的快取值。
    expect(result.track.cid, 12345);
  });

  test('resolveFallback passes failedUrl and updates track URL', () async {
    final track = _track('fallback')..cid = 13579;

    final result = await service.resolveFallback(
      track,
      purpose: StreamResolutionPurpose.playback,
      failedUrl: 'https://failed.example/audio.m4a',
    );

    expect(result, isNotNull);
    expect(result!.stream.url, 'https://example.com/fallback-medium-alt.m4a');
    expect(source.alternativeRequests.single.failedUrl,
        'https://failed.example/audio.m4a');
    expect(source.alternativeRequests.single.cid, 13579);
    expect(result.track.audioUrl, result.stream.url);
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = sourceId
    ..artist = 'Tester';
}

class _RecordingAudioStreamSource implements AudioStreamSource {
  final primaryRequests = <AudioStreamRequest>[];
  final alternativeRequests = <AudioStreamRequest>[];
  final failingQualities = <AudioQualityLevel>{};
  Duration? nextExpiry;
  int? nextCid;

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    primaryRequests.add(request);
    if (failingQualities.contains(request.config.qualityLevel)) {
      throw const _FakeSourceException(SourceErrorKind.unavailable);
    }
    return AudioStreamResult(
      url:
          'https://example.com/${request.sourceId}-${request.config.qualityLevel.name}.m4a',
      streamType: StreamType.audioOnly,
      expiry: nextExpiry,
      cid: nextCid,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async {
    alternativeRequests.add(request);
    return AudioStreamResult(
      url:
          'https://example.com/${request.sourceId}-${request.config.qualityLevel.name}-alt.m4a',
      streamType: StreamType.audioOnly,
      expiry: nextExpiry,
    );
  }
}

class _RecordingSourceAuthContext implements SourceAuthContext {
  Map<String, String>? authHeaders;
  final authForPlayRequests = <SourceType>[];

  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async {
    authForPlayRequests.add(sourceType);
    return authHeaders;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSourceException extends SourceApiException {
  const _FakeSourceException(this._kind);

  final SourceErrorKind _kind;

  @override
  String get code => 'fake';

  @override
  SourceErrorKind get kind => _kind;

  @override
  String get message => 'fake failure';

  @override
  SourceType get sourceType => SourceType.youtube;
}
