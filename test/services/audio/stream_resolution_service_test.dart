import 'dart:convert';
import 'dart:ffi';
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
import 'package:isar/isar.dart';

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
    await Isar.initializeIsarCore(
      libraries: {Abi.current(): await _resolveIsarLibraryPath()},
    );
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
