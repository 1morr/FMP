import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/download_task.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/download_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:fmp/providers/download/download_providers.dart';
import 'package:fmp/services/download/download_path_utils.dart';
import 'package:fmp/services/download/download_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadService phase 1 cleanup', () {
    late Directory tempDir;
    late Isar isar;
    late DownloadRepository downloadRepository;
    late TrackRepository trackRepository;
    late SettingsRepository settingsRepository;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('download_phase1_test_');
      isar = await Isar.open(
        [TrackSchema, DownloadTaskSchema, SettingsSchema, AccountSchema],
        directory: tempDir.path,
        name: 'download_service_phase1_test',
      );
      downloadRepository = DownloadRepository(isar);
      trackRepository = TrackRepository(isar);
      settingsRepository = SettingsRepository(isar);
      final settings = await settingsRepository.get();
      settings.maxConcurrentDownloads = 1;
      await settingsRepository.save(settings);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('pauseTask clears buffered progress before a flush runs', () async {
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: SourceManager(),
      );
      final task = await downloadRepository.saveTask(_task(trackId: 11));
      final events = <DownloadProgressEvent>[];
      final sub = service.progressStream.listen(events.add);

      service.debugRecordProgressUpdateForTesting(task.id, task.trackId, 0.4, 40, 100);
      await service.pauseTask(task.id);
      service.debugFlushPendingProgressUpdatesForTesting();
      await pumpEventQueue();

      expect(service.debugPendingProgressCount, 0);
      expect(events, isEmpty);

      await sub.cancel();
      service.dispose();
    });

    test('cancelTask clears buffered progress before a flush runs', () async {
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: SourceManager(),
      );
      final task = await downloadRepository.saveTask(_task(trackId: 22));
      final events = <DownloadProgressEvent>[];
      final sub = service.progressStream.listen(events.add);

      service.debugRecordProgressUpdateForTesting(task.id, task.trackId, 0.7, 70, 100);
      await service.cancelTask(task.id);
      service.debugFlushPendingProgressUpdatesForTesting();
      await pumpEventQueue();

      expect(service.debugPendingProgressCount, 0);
      expect(events, isEmpty);
      expect(await downloadRepository.getTaskById(task.id), isNull);

      await sub.cancel();
      service.dispose();
    });

    test('pending progress buffering enforces a hard cap', () {
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: SourceManager(),
      );
      final limit = service.debugPendingProgressLimit;
      final overflow = 5;

      for (var i = 1; i <= limit + overflow; i++) {
        service.debugRecordProgressUpdateForTesting(i, i, i / 100, i, 100);
      }

      expect(service.debugPendingProgressCount, limit);
      service.dispose();
    });

    test('external cleanup and final cleanup do not double-decrement active downloads', () async {
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: SourceManager(),
      );
      final task = await downloadRepository.saveTask(_task(trackId: 33));

      service.debugRegisterLegacyActiveDownloadForTesting(task.id);
      expect(service.debugActiveDownloads, 1);

      await service.pauseTask(task.id);
      service.debugFinalizeTaskCleanupForTesting(task.id);

      expect(service.debugActiveDownloads, 0);
      service.dispose();
    });

    test('dispose is idempotent', () {
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: SourceManager(),
      );

      service.dispose();

      expect(service.dispose, returnsNormally);
    });

    test('pausing unrelated task while another is active does not stale-abort its later start', () async {
      final baseDir = await Directory.systemTemp.createTemp('download_stale_setup_abort_');
      addTearDown(() async {
        for (var i = 0; i < 100; i++) {
          if (!await baseDir.exists()) return;
          try {
            await baseDir.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      });

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSub = server.listen((request) async {
        try {
          request.response.headers.contentType = ContentType.binary;
          request.response.contentLength = 1024 * 1024;
          for (var i = 0; i < 64; i++) {
            request.response.add(Uint8List(16 * 1024));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await request.response.close();
        } catch (_) {
          // Client disconnected during cleanup.
        }
      });
      addTearDown(() async {
        await serverSub.cancel();
        await server.close(force: true);
      });

      final settings = await settingsRepository.get();
      settings.customDownloadDir = baseDir.path;
      await settingsRepository.save(settings);

      final track1 = Track()
        ..sourceId = 'yt-active'
        ..sourceType = SourceType.youtube
        ..title = 'Active Task'
        ..artist = 'Test Artist'
        ..createdAt = DateTime.now();
      final track2 = Track()
        ..sourceId = 'yt-resume-after-pause'
        ..sourceType = SourceType.youtube
        ..title = 'Resume After Pause'
        ..artist = 'Test Artist'
        ..createdAt = DateTime.now();
      await trackRepository.save(track1);
      await trackRepository.save(track2);

      final playlist = Playlist()..name = 'Phase1';
      final task1 = await downloadRepository.saveTask(
        DownloadTask()
          ..trackId = track1.id
          ..playlistId = playlist.id
          ..playlistName = playlist.name
          ..status = DownloadStatus.downloading
          ..createdAt = DateTime.now(),
      );
      final task2 = await downloadRepository.saveTask(
        DownloadTask()
          ..trackId = track2.id
          ..playlistId = playlist.id
          ..playlistName = playlist.name
          ..status = DownloadStatus.pending
          ..createdAt = DateTime.now(),
      );

      final audioUrl = 'http://${server.address.address}:${server.port}/audio.m4a';
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: _SingleSourceManager(_StaticAudioSource(audioUrl)),
      );

      final firstStart = service.debugStartDownloadForTesting(task1);
      await service.debugWaitForTaskToBecomeActiveForTesting(task1.id);

      await service.pauseTask(task2.id);
      final pausedTask = await downloadRepository.getTaskById(task2.id);
      expect(pausedTask?.status, DownloadStatus.paused);

      await service.resumeTask(task2.id);
      final resumedTask = await downloadRepository.getTaskById(task2.id);
      expect(resumedTask, isNotNull);

      final secondStart = service.debugStartDownloadForTesting(resumedTask!);
      await service.debugWaitForTaskToBecomeActiveForTesting(task2.id);

      await service.pauseTask(task2.id);
      await service.pauseTask(task1.id);
      await secondStart;
      await firstStart;
      await _waitUntil(() async => service.debugActiveDownloads == 0);

      service.dispose();
    });

    test('cancel during setup window prevents download start before isolate registration', () async {
      final baseDir = await Directory.systemTemp.createTemp('download_setup_cancel_');
      addTearDown(() async {
        for (var i = 0; i < 100; i++) {
          if (!await baseDir.exists()) return;
          try {
            await baseDir.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      });

      final settings = await settingsRepository.get();
      settings.customDownloadDir = baseDir.path;
      await settingsRepository.save(settings);

      final track = Track()
        ..sourceId = 'yt-setup-cancel'
        ..sourceType = SourceType.youtube
        ..title = 'Setup Cancel Race'
        ..artist = 'Test Artist'
        ..createdAt = DateTime.now();
      await trackRepository.save(track);

      final playlist = Playlist()..name = 'Phase1';
      final task = await downloadRepository.saveTask(
        DownloadTask()
          ..trackId = track.id
          ..playlistId = playlist.id
          ..playlistName = playlist.name
          ..status = DownloadStatus.downloading
          ..createdAt = DateTime.now(),
      );

      final sourceManager = _SingleSourceManager(
        _BlockingAudioSource('http://127.0.0.1:1/audio.m4a'),
      );
      final blockedSource = sourceManager.getSource(SourceType.youtube)! as _BlockingAudioSource;
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
      );
      final completionEvents = <DownloadCompletionEvent>[];
      final failureEvents = <DownloadFailureEvent>[];
      final completionSub = service.completionStream.listen(completionEvents.add);
      final failureSub = service.failureStream.listen(failureEvents.add);

      final downloadFuture = service.debugStartDownloadForTesting(task);
      await blockedSource.waitUntilRequested();
      await service.cancelTask(task.id);
      blockedSource.release();
      await downloadFuture;

      final savePath = DownloadPathUtils.computeDownloadPath(
        baseDir: baseDir.path,
        playlistName: playlist.name,
        track: track,
      );
      expect(completionEvents, isEmpty);
      expect(failureEvents, isEmpty);
      expect(await downloadRepository.getTaskById(task.id), isNull);
      expect(await File(savePath).exists(), isFalse);
      expect(await File('$savePath.downloading').exists(), isFalse);
      final savedTrack = await trackRepository.getById(track.id);
      expect(savedTrack?.hasAnyDownload, isFalse);

      await completionSub.cancel();
      await failureSub.cancel();
      service.dispose();
    });

    test('dispose during download does not finalize partial work after receive loop ends', () async {
      final baseDir = await Directory.systemTemp.createTemp('download_dispose_midflight_');
      addTearDown(() async {
        for (var i = 0; i < 100; i++) {
          if (!await baseDir.exists()) return;
          try {
            await baseDir.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      });

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSub = server.listen((request) async {
        try {
          request.response.headers.contentType = ContentType.binary;
          request.response.contentLength = 1024 * 1024;
          for (var i = 0; i < 64; i++) {
            request.response.add(Uint8List(16 * 1024));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await request.response.close();
        } catch (_) {
          // Client disconnected during disposal.
        }
      });
      addTearDown(() async {
        await serverSub.cancel();
        await server.close(force: true);
      });

      final settings = await settingsRepository.get();
      settings.customDownloadDir = baseDir.path;
      await settingsRepository.save(settings);

      final track = Track()
        ..sourceId = 'yt-dispose'
        ..sourceType = SourceType.youtube
        ..title = 'Dispose Race'
        ..artist = 'Test Artist'
        ..createdAt = DateTime.now();
      await trackRepository.save(track);

      final playlist = Playlist()..name = 'Phase1';
      final task = await downloadRepository.saveTask(
        DownloadTask()
          ..trackId = track.id
          ..playlistId = playlist.id
          ..playlistName = playlist.name
          ..status = DownloadStatus.downloading
          ..createdAt = DateTime.now(),
      );

      final audioUrl = 'http://${server.address.address}:${server.port}/audio.m4a';
      final sourceManager = _SingleSourceManager(_StaticAudioSource(audioUrl));
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
      );
      final completionEvents = <DownloadCompletionEvent>[];
      final failureEvents = <DownloadFailureEvent>[];
      final completionSub = service.completionStream.listen(completionEvents.add);
      final failureSub = service.failureStream.listen(failureEvents.add);

      final downloadFuture = service.debugStartDownloadForTesting(task);
      await service.debugWaitForTaskToBecomeActiveForTesting(task.id);

      final savePath = DownloadPathUtils.computeDownloadPath(
        baseDir: baseDir.path,
        playlistName: playlist.name,
        track: track,
      );
      final tempFile = File('$savePath.downloading');
      await _waitUntil(() async => await tempFile.exists() && await tempFile.length() > 0);

      service.dispose();
      await _waitUntil(() async => service.debugActiveDownloads == 0);
      await downloadFuture;

      expect(completionEvents, isEmpty);
      expect(failureEvents, isEmpty);
      expect(await File(savePath).exists(), isFalse);
      final savedTask = await downloadRepository.getTaskById(task.id);
      expect(savedTask?.status, DownloadStatus.downloading);
      final savedTrack = await trackRepository.getById(track.id);
      expect(savedTrack?.hasAnyDownload, isFalse);

      await completionSub.cancel();
      await failureSub.cancel();
    });

    test('resume restarts cleanly when server ignores Range and returns 200 OK', () async {
      final baseDir = await Directory.systemTemp.createTemp('download_resume_http200_');
      addTearDown(() async {
        for (var i = 0; i < 100; i++) {
          if (!await baseDir.exists()) return;
          try {
            await baseDir.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      });

      final settings = await settingsRepository.get();
      settings.customDownloadDir = baseDir.path;
      await settingsRepository.save(settings);

      final fullBytes = Uint8List.fromList([10, 20, 30, 40, 50, 60]);
      final partialBytes = Uint8List.fromList(fullBytes.take(2).toList());
      String? requestedRange;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSub = server.listen((request) async {
        requestedRange = request.headers.value(HttpHeaders.rangeHeader);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.binary;
        request.response.contentLength = fullBytes.length;
        request.response.add(fullBytes);
        await request.response.close();
      });
      addTearDown(() async {
        await serverSub.cancel();
        await server.close(force: true);
      });

      final track = Track()
        ..sourceId = 'yt-resume-http200'
        ..sourceType = SourceType.youtube
        ..title = 'Resume HTTP 200'
        ..artist = 'Test Artist'
        ..createdAt = DateTime.now();
      final savedTrack = await trackRepository.save(track);

      final playlist = Playlist()..name = 'Phase1';
      final savePath = DownloadPathUtils.computeDownloadPath(
        baseDir: baseDir.path,
        playlistName: playlist.name,
        track: savedTrack,
      );
      final tempPath = '$savePath.downloading';
      await Directory(tempPath).parent.create(recursive: true);
      await File(tempPath).writeAsBytes(partialBytes, flush: true);

      final task = await downloadRepository.saveTask(
        DownloadTask()
          ..trackId = savedTrack.id
          ..playlistId = playlist.id
          ..playlistName = playlist.name
          ..status = DownloadStatus.downloading
          ..tempFilePath = tempPath
          ..downloadedBytes = partialBytes.length
          ..createdAt = DateTime.now(),
      );

      final audioUrl = 'http://${server.address.address}:${server.port}/audio.m4a';
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: _SingleSourceManager(_StaticAudioSource(audioUrl)),
      );

      await service.debugStartDownloadForTesting(task);
      await _waitUntil(() async => service.debugActiveDownloads == 0);

      expect(requestedRange, 'bytes=${partialBytes.length}-');
      expect(await File(savePath).readAsBytes(), fullBytes);
      expect(await File(tempPath).exists(), isFalse);
      final updatedTask = await downloadRepository.getTaskById(task.id);
      expect(updatedTask?.status, DownloadStatus.completed);

      service.dispose();
    });

    test('download start uses source-provided expiry instead of defaulting to one hour', () async {
      final baseDir = await Directory.systemTemp.createTemp('download_netease_expiry_');
      addTearDown(() async {
        for (var i = 0; i < 100; i++) {
          if (!await baseDir.exists()) return;
          try {
            await baseDir.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      });

      final settings = await settingsRepository.get();
      settings.customDownloadDir = baseDir.path;
      await settingsRepository.save(settings);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSub = server.listen((request) async {
        request.response.headers.contentType = ContentType.binary;
        request.response.contentLength = 4;
        request.response.add(Uint8List.fromList([1, 2, 3, 4]));
        await request.response.close();
      });
      addTearDown(() async {
        await serverSub.cancel();
        await server.close(force: true);
      });

      final track = Track()
        ..sourceId = 'netease-expiry'
        ..sourceType = SourceType.netease
        ..title = 'Netease Expiry'
        ..artist = 'Test Artist'
        ..createdAt = DateTime.now();
      final savedTrack = await trackRepository.save(track);

      final playlist = Playlist()..name = 'Phase1';
      final task = await downloadRepository.saveTask(
        DownloadTask()
          ..trackId = savedTrack.id
          ..playlistId = playlist.id
          ..playlistName = playlist.name
          ..status = DownloadStatus.downloading
          ..createdAt = DateTime.now(),
      );

      final audioUrl = 'http://${server.address.address}:${server.port}/audio.mp3';
      final service = DownloadService(
        downloadRepository: downloadRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: _SingleSourceManager(
          _StaticAudioSource(
            audioUrl,
            sourceTypeOverride: SourceType.netease,
            streamExpiry: const Duration(minutes: 16),
          ),
        ),
      );

      final before = DateTime.now();
      await service.debugStartDownloadForTesting(task);
      await _waitUntil(() async => service.debugActiveDownloads == 0);

      final updatedTrack = await trackRepository.getById(savedTrack.id);
      expect(updatedTrack, isNotNull);
      final remaining = updatedTrack!.audioUrlExpiry!.difference(before);
      expect(remaining, greaterThanOrEqualTo(const Duration(minutes: 15)));
      expect(remaining, lessThanOrEqualTo(const Duration(minutes: 16, seconds: 5)));

      service.dispose();
    });

    test('provider disposal keeps a late-initializing service inert', () async {
      final delayedRepository = _DelayedDownloadRepository(isar);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) => isar),
          downloadRepositoryProvider.overrideWith((ref) => delayedRepository),
        ],
      );
      final service = container.read(downloadServiceProvider);

      container.dispose();
      delayedRepository.allowInitialize();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(service.debugHasSchedulerTimer, isFalse);
      expect(service.debugHasProgressTimer, isFalse);
      expect(service.dispose, returnsNormally);
    });
  });
}

DownloadTask _task({required int trackId}) => DownloadTask()
  ..trackId = trackId
  ..status = DownloadStatus.downloading
  ..createdAt = DateTime.now();

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile = File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig = jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> || package['name'] != 'isar_flutter_libs') continue;
    final packageDir = Directory(packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath());
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}

class _DelayedDownloadRepository extends DownloadRepository {
  _DelayedDownloadRepository(super.isar);

  final Completer<void> _initializeGate = Completer<void>();

  void allowInitialize() {
    if (!_initializeGate.isCompleted) _initializeGate.complete();
  }

  @override
  Future<int> clearCompletedAndErrorTasks() async {
    await _initializeGate.future;
    return super.clearCompletedAndErrorTasks();
  }
}

class _SingleSourceManager extends SourceManager {
  _SingleSourceManager(this._source);

  final BaseSource _source;

  @override
  BaseSource? getSource(SourceType type) {
    if (type == _source.sourceType) return _source;
    return null;
  }

  @override
  void dispose() {
    _source.dispose();
  }
}

class _StaticAudioSource extends BaseSource {
  _StaticAudioSource(
    this.audioUrl, {
    this.sourceTypeOverride = SourceType.youtube,
    this.streamExpiry,
  });

  final String audioUrl;
  final SourceType sourceTypeOverride;
  final Duration? streamExpiry;

  @override
  SourceType get sourceType => sourceTypeOverride;

  @override
  String? parseId(String url) => null;

  @override
  bool isValidId(String id) => true;

  @override
  Future<Track> getTrackInfo(String sourceId, {Map<String, String>? authHeaders}) {
    throw UnimplementedError();
  }

  @override
  Future<AudioStreamResult> getAudioStream(
    String sourceId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    return AudioStreamResult(
      url: audioUrl,
      streamType: StreamType.audioOnly,
      expiry: streamExpiry,
    );
  }

  @override
  Future<Track> refreshAudioUrl(Track track, {Map<String, String>? authHeaders}) {
    throw UnimplementedError();
  }

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) {
    throw UnimplementedError();
  }

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
  bool isPlaylistUrl(String url) => false;

  @override
  Future<bool> checkAvailability(String sourceId) async => true;
}

class _BlockingAudioSource extends _StaticAudioSource {
  _BlockingAudioSource(super.audioUrl);

  final Completer<void> _requested = Completer<void>();
  final Completer<void> _release = Completer<void>();

  Future<void> waitUntilRequested() => _requested.future;

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<AudioStreamResult> getAudioStream(
    String sourceId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    if (!_requested.isCompleted) {
      _requested.complete();
    }
    await _release.future;
    return super.getAudioStream(
      sourceId,
      config: config,
      authHeaders: authHeaders,
    );
  }
}

Future<void> _waitUntil(Future<bool> Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Condition was not met in time');
}
