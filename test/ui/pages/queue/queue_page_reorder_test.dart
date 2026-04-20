import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';
import 'package:fmp/ui/pages/queue/queue_page.dart';
import 'package:isar/isar.dart';

import 'package:fmp/providers/playback_settings_provider.dart';

import '../../../support/fakes/fake_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Isar.initializeIsarCore(
      libraries: {ffi.Abi.current(): await _resolveIsarLibraryPath()},
    );
  });

  testWidgets('QueuePage keeps drag reorder available while shuffle is enabled', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_QueuePageHarness.create))!;
    addTearDown(() => tester.runAsync(() => harness.dispose()));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.binding.setSurfaceSize(const Size(400, 900));
    LocaleSettings.setLocale(AppLocale.en);

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            audioControllerProvider.overrideWith((ref) => harness.controller),
            autoScrollToCurrentTrackProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(home: QueuePage()),
        ),
      ),
    );

    await tester.pump();

    expect(_queueOrder(tester), ['Alpha', 'Bravo', 'Charlie']);
    expect(
      find.byWidgetPredicate((widget) => widget is LongPressDraggable<int>),
      findsNWidgets(3),
      reason: 'shuffle mode should still show queue drag affordances',
    );
    expect(
      _queueOrder(tester),
      ['Alpha', 'Bravo', 'Charlie'],
      reason: 'showing drag affordances should not change the rendered queue order',
    );
    expect(harness.controller.moveInQueueCallCount, 0);
  });
}

class _QueuePageHarness {
  _QueuePageHarness({
    required this.isar,
    required this.controller,
  });

  final Isar isar;
  final _QueuePageTestAudioController controller;

  static Future<_QueuePageHarness> create() async {
    final isar = await Isar.open(
      [TrackSchema, PlayQueueSchema, SettingsSchema],
      directory: '${Directory.current.path}/.dart_tool',
      name: 'queue_page_reorder_lockout_test',
    );

    final queueRepository = QueueRepository(isar);
    final trackRepository = TrackRepository(isar);
    final settingsRepository = SettingsRepository(isar);
    final queuePersistenceManager = QueuePersistenceManager(
      queueRepository: queueRepository,
      trackRepository: trackRepository,
      settingsRepository: settingsRepository,
    );
    final audioStreamManager = AudioStreamManager(
      trackRepository: trackRepository,
      settingsRepository: settingsRepository,
      sourceManager: SourceManager(),
    );
    final queueManager = QueueManager(
      queueRepository: queueRepository,
      trackRepository: trackRepository,
      queuePersistenceManager: queuePersistenceManager,
      audioStreamManager: audioStreamManager,
    );

    final controller = _QueuePageTestAudioController(
      queueManager: queueManager,
      audioStreamManager: audioStreamManager,
      queue: [
        _buildTrack(id: 1, sourceId: 'alpha', title: 'Alpha'),
        _buildTrack(id: 2, sourceId: 'bravo', title: 'Bravo'),
        _buildTrack(id: 3, sourceId: 'charlie', title: 'Charlie'),
      ],
    );

    return _QueuePageHarness(isar: isar, controller: controller);
  }

  Future<void> dispose() async {
    controller.dispose();
    await isar.close(deleteFromDisk: true);
  }
}

class _QueuePageTestAudioController extends AudioController {
  _QueuePageTestAudioController({
    required super.queueManager,
    required super.audioStreamManager,
    required List<Track> queue,
  }) : super(
         audioService: FakeAudioService(),
         toastService: ToastService(),
         audioHandler: FmpAudioHandler(),
         windowsSmtcHandler: WindowsSmtcHandler(),
       ) {
    state = PlayerState(
      queue: queue,
      currentIndex: 0,
      queueVersion: 1,
      isShuffleEnabled: true,
    );
  }

  int moveInQueueCallCount = 0;

  @override
  Future<void> moveInQueue(int oldIndex, int newIndex) async {
    moveInQueueCallCount++;
  }
}

Track _buildTrack({
  required int id,
  required String sourceId,
  required String title,
}) {
  return Track()
    ..id = id
    ..sourceId = sourceId
    ..sourceType = SourceType.bilibili
    ..title = title
    ..artist = '$title Artist'
    ..durationMs = 180000;
}

List<String> _queueOrder(WidgetTester tester) {
  final titles = ['Alpha', 'Bravo', 'Charlie'];
  final positions = <String, double>{
    for (final title in titles) title: tester.getTopLeft(find.text(title)).dy,
  };
  final ordered = positions.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return ordered.map((entry) => entry.key).toList();
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
    final packageDir = Directory(packageConfigDir.uri.resolve(rootUri).toFilePath());

    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
