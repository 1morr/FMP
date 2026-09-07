import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:isar_community/isar.dart';

import '../../support/audio_controller_harness.dart';
import '../../support/fakes/fake_audio_service.dart';
import '../../support/isar_test_harness.dart';
import '../../support/now_playing.dart';

/// 桌面輸出裝置的記憶（issue #42）。
///
/// 分兩半：選裝置時寫進 `Settings`，以及裝置清單第一次到齊時把記住的那個
/// 套回去。兩半都是 `AudioController` 的職責，`FmpAudioService` 只負責照做。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const speakers = FmpAudioDevice(
    name: 'wasapi/{aaaa}',
    description: 'Speakers (Realtek)',
  );
  const headphones = FmpAudioDevice(
    name: 'wasapi/{bbbb}',
    description: 'Headphones (USB DAC)',
  );

  group('preferred audio device', () {
    late Directory tempDir;
    late Isar isar;
    late SettingsRepository settingsRepository;
    late FakeAudioService audioService;
    late DefaultStreamResolutionService streamResolutionService;
    late AudioController controller;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audio_device_pref_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'audio_device_preference_test',
      );

      final queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      settingsRepository = SettingsRepository(isar);
      final sourceManager = _FakeSourceManager();
      final queuePersistenceManager = QueuePersistenceManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
      );
      streamResolutionService = DefaultStreamResolutionService(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
        sourceAuthContext: _FakeSourceAuthContext(),
      );
      audioService = FakeAudioService();
      controller = buildTestAudioController(
        audioService: audioService,
        queueManager: QueueManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          queuePersistenceManager: queuePersistenceManager,
        ),
        audioStreamManager: AudioStreamManager(
          streamResolutionService: streamResolutionService,
          sourceAuthContext: _FakeSourceAuthContext(),
        ),
        toastService: ToastService(),
        nowPlayingPublisher: testNowPlayingPublisher(),
        settingsRepository: settingsRepository,
      );
      await controller.initialize();
    });

    tearDown(() async {
      streamResolutionService.dispose();
      await audioService.dispose();
      if (isar.isOpen) await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<Settings> storedSettings() => settingsRepository.get();

    test('choosing a device stores its name and description', () async {
      await controller.setAudioDevice(headphones);

      final settings = await storedSettings();
      expect(settings.preferredAudioDeviceId, headphones.name);
      expect(settings.preferredAudioDeviceName, headphones.description);
      expect(audioService.audioDevice?.name, headphones.name);
    });

    test('going back to auto clears the stored device', () async {
      await controller.setAudioDevice(headphones);
      expect((await storedSettings()).preferredAudioDeviceId, headphones.name);

      await controller.setAudioDeviceAuto();

      final settings = await storedSettings();
      expect(settings.preferredAudioDeviceId, isNull);
      expect(settings.preferredAudioDeviceName, isNull);
      expect(audioService.audioDevice, isNull);
    });

    test('a remembered device is reapplied when the list arrives', () async {
      await controller.setAudioDevice(headphones);
      await controller.setAudioDeviceAuto();
      // 直接改設定，模擬「上一次執行選了耳機」而不是這次選的。
      await settingsRepository.update((s) {
        s.preferredAudioDeviceId = headphones.name;
        s.preferredAudioDeviceName = headphones.description;
      });

      audioService.emitAudioDevices([speakers, headphones]);
      await pumpEventQueue();

      expect(audioService.audioDevice?.name, headphones.name);
    });

    test('an unplugged device leaves both the output and the setting alone',
        () async {
      await settingsRepository.update((s) {
        s.preferredAudioDeviceId = headphones.name;
        s.preferredAudioDeviceName = headphones.description;
      });

      audioService.emitAudioDevices([speakers]);
      await pumpEventQueue();

      // 沒有切走，也沒有把設定清掉 —— 使用者把耳機插回來時還會想要它。
      expect(audioService.audioDevice, isNull);
      final settings = await storedSettings();
      expect(settings.preferredAudioDeviceId, headphones.name);
    });

    test('restore runs once so a later manual choice is not clobbered',
        () async {
      await settingsRepository.update((s) {
        s.preferredAudioDeviceId = headphones.name;
        s.preferredAudioDeviceName = headphones.description;
      });

      audioService.emitAudioDevices([speakers, headphones]);
      await pumpEventQueue();
      expect(audioService.audioDevice?.name, headphones.name);

      await controller.setAudioDevice(speakers);
      // 插拔會讓裝置清單反覆重送，那不該把使用者剛選的蓋回去。
      audioService.emitAudioDevices([speakers, headphones]);
      await pumpEventQueue();

      expect(audioService.audioDevice?.name, speakers.name);
    });

    test('no stored device means the output is left untouched', () async {
      audioService.emitAudioDevices([speakers, headphones]);
      await pumpEventQueue();

      expect(audioService.audioDevice, isNull);
    });
  });
}

class _FakeSourceManager extends SourceManager {
  _FakeSourceManager() : super(sources: const []);

  @override
  AudioStreamSource? audioStreamSource(String type) => null;

  @override
  void dispose() {}
}

class _FakeSourceAuthContext implements SourceAuthContext {
  @override
  Future<Map<String, String>?> authForPlay(String sourceType) async => null;

  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    return PlaybackNetworkRequest(
      url: url,
      headers: SourceHttpPolicy.mediaHeaders(track.sourceType),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
