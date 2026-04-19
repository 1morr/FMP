import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/main.dart' as app_main;
import 'package:fmp/providers/account_provider.dart';
import 'package:fmp/providers/lyrics_provider.dart';
import 'package:fmp/providers/repository_providers.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/just_audio_service.dart';
import 'package:fmp/services/audio/media_kit_audio_service.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:fmp/services/lyrics/title_parser.dart';
import 'package:fmp/services/network/connectivity_service.dart';
import 'package:isar/isar.dart';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('audio disposal safety', () {
    late Directory tempDir;
    late Isar isar;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      app_main.audioHandler = FmpAudioHandler();
      app_main.windowsSmtcHandler = WindowsSmtcHandler();

      tempDir = await Directory.systemTemp.createTemp('audio_dispose_test_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'audio_service_dispose_test',
      );

      final settingsRepository = SettingsRepository(isar);
      await settingsRepository.get();
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('provider disposal does not double-dispose owned dependencies',
        () async {
      final audioService = _ThrowOnSecondDisposeAudioService();
      final queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      final settingsRepository = SettingsRepository(isar);
      final queueManager = _ThrowOnSecondDisposeQueueManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        queuePersistenceManager: QueuePersistenceManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        ),
        audioStreamManager: AudioStreamManager(
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
          sourceManager: SourceManager(),
        ),
      );
      final container = _createContainer(
        isar: isar,
        audioService: audioService,
        queueManager: queueManager,
      );

      container.read(audioControllerProvider);
      await pumpEventQueue(times: 5);

      expect(container.dispose, returnsNormally);
      expect(audioService.disposeCallCount, 1);
      expect(queueManager.disposeCallCount, 1);
    });

    test(
        'provider disposal is safe when container is disposed before scheduled initialization runs',
        () async {
      final audioService = _ThrowOnSecondDisposeAudioService();
      final queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      final settingsRepository = SettingsRepository(isar);
      final queueManager = _ThrowOnSecondDisposeQueueManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        queuePersistenceManager: QueuePersistenceManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        ),
        audioStreamManager: AudioStreamManager(
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
          sourceManager: SourceManager(),
        ),
      );
      final container = _createContainer(
        isar: isar,
        audioService: audioService,
        queueManager: queueManager,
      );

      container.read(audioControllerProvider);
      expect(container.dispose, returnsNormally);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(audioService.initializeAfterDisposeCallCount, 0);
      expect(queueManager.initializeAfterDisposeCallCount, 0);
      expect(audioService.disposeCallCount, 1);
      expect(queueManager.disposeCallCount, 1);
    });

    test('just audio dispose is safe before initialization and on repeat calls',
        () async {
      final service = JustAudioService();

      await service.dispose();
      await service.dispose();
    });

    test('media kit dispose is safe before initialization and on repeat calls',
        () async {
      final service = MediaKitAudioService();

      await service.dispose();
      await service.dispose();
    });
  });
}

ProviderContainer _createContainer({
  required Isar isar,
  required _ThrowOnSecondDisposeAudioService audioService,
  required _ThrowOnSecondDisposeQueueManager queueManager,
}) {
  return ProviderContainer(
    overrides: [
      audioServiceProvider.overrideWith((ref) => audioService),
      queueManagerProvider.overrideWith((ref) => queueManager),
      audioStreamManagerProvider.overrideWith(
        (ref) => AudioStreamManager(
          trackRepository: TrackRepository(isar),
          settingsRepository: SettingsRepository(isar),
          sourceManager: SourceManager(),
          neteaseAccountService: ref.read(neteaseAccountServiceProvider),
        ),
      ),
      connectivityProvider.overrideWith((ref) => _TestConnectivityNotifier()),
      settingsRepositoryProvider
          .overrideWith((ref) => SettingsRepository(isar)),
      playHistoryRepositoryProvider.overrideWith(
        (ref) => PlayHistoryRepository(isar),
      ),
      neteaseAccountServiceProvider.overrideWith(
        (ref) => _FakeNeteaseAccountService(isar: isar),
      ),
      lyricsAutoMatchServiceProvider.overrideWith(
        (ref) => LyricsAutoMatchService(
          lrclib: LrclibSource(),
          netease: NeteaseSource(),
          qqmusic: QQMusicSource(),
          repo: LyricsRepository(isar),
          cache: LyricsCacheService(),
          parser: RegexTitleParser(),
        ),
      ),
    ],
  );
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic>) continue;
    if (package['name'] != 'isar_flutter_libs') continue;

    final rootUri = package['rootUri'] as String;
    final packageDir =
        Directory(packageConfigDir.uri.resolve(rootUri).toFilePath());

    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}

class _ThrowOnSecondDisposeAudioService extends FakeAudioService {
  int disposeCallCount = 0;
  int initializeAfterDisposeCallCount = 0;
  bool _disposed = false;

  @override
  Future<void> initialize() {
    if (_disposed) {
      initializeAfterDisposeCallCount++;
      throw StateError('audio service initialized after dispose');
    }
    return super.initialize();
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    disposeCallCount++;
    if (disposeCallCount > 1) {
      throw StateError('audio service disposed more than once');
    }
    return super.dispose();
  }
}

class _ThrowOnSecondDisposeQueueManager extends QueueManager {
  _ThrowOnSecondDisposeQueueManager({
    required super.queueRepository,
    required super.trackRepository,
    required super.queuePersistenceManager,
    required super.audioStreamManager,
  });

  int disposeCallCount = 0;
  int initializeAfterDisposeCallCount = 0;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      initializeAfterDisposeCallCount++;
      throw StateError('queue manager initialized after dispose');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    disposeCallCount++;
    if (disposeCallCount > 1) {
      throw StateError('queue manager disposed more than once');
    }
  }
}

class _TestConnectivityNotifier extends StateNotifier<ConnectivityState>
    with Logging
    implements ConnectivityNotifier {
  _TestConnectivityNotifier() : super(ConnectivityState.initial);

  final _networkRecoveredController = StreamController<void>.broadcast();

  @override
  Stream<void> get onNetworkRecovered => _networkRecoveredController.stream;

  @override
  void dispose() {
    _networkRecoveredController.close();
    super.dispose();
  }
}

class _FakeNeteaseAccountService extends NeteaseAccountService {
  _FakeNeteaseAccountService({required super.isar});
}
