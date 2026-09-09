import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/services/radio/radio_controller.dart';
import 'package:fmp/services/radio/radio_refresh_service.dart';
import 'package:fmp/services/radio/radio_source.dart';
import 'package:isar_community/isar.dart';

import '../../support/fakes/fake_audio_service.dart';
import '../../support/isar_test_harness.dart';
import '../../support/pump_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeIsarForTests();
    RadioRefreshService.instance = RadioRefreshService(
      radioSource: _FakeRadioSource(const {}),
      refreshInterval: const Duration(days: 1),
    );
  });

  tearDownAll(() {
    RadioRefreshService.instance.dispose();
  });

  group('RadioController account import flow', () {
    test('loads medal wall candidates through the controller', () async {
      final harness = await createHarness(
        medalWallItems: const [
          MedalWallItem(
            roomId: '101',
            name: 'Alpha',
            uid: 1,
            liveStatus: 1,
            link: 'https://live.bilibili.com/101',
          ),
          MedalWallItem(
            roomId: '202',
            name: 'Beta',
            uid: 2,
            liveStatus: 0,
            link: 'https://live.bilibili.com/202',
          ),
        ],
      );
      addTearDown(harness.dispose);

      final items = await harness.controller.loadAccountImportCandidates();

      expect(items.map((item) => item.roomId), ['101', '202']);
      expect(items.where((item) => item.isLive).map((item) => item.name), [
        'Alpha',
      ]);
      expect(items.every((item) => !item.isImported), isTrue);
    });

    test(
      'marks already imported candidates even before radio state finishes loading',
      () async {
        final harness = await createHarness(
          medalWallItems: const [
            MedalWallItem(
              roomId: '101',
              name: 'Existing room',
              uid: 1,
              liveStatus: 1,
              link: 'https://live.bilibili.com/101',
            ),
            MedalWallItem(
              roomId: '202',
              name: 'New room',
              uid: 2,
              liveStatus: 0,
              link: 'https://live.bilibili.com/202',
            ),
          ],
          initialStations: [
            _buildStation(sourceId: '101', title: 'Existing imported room'),
          ],
          initialLoadDelay: const Duration(milliseconds: 200),
          waitForInitialLoad: false,
        );
        addTearDown(harness.dispose);

        expect(harness.controller.state.stations, isEmpty);

        final items = await harness.controller.loadAccountImportCandidates();
        final importedCandidate = items.firstWhere(
          (item) => item.roomId == '101',
        );
        final newCandidate = items.firstWhere((item) => item.roomId == '202');

        expect(importedCandidate.isImported, isTrue);
        expect(newCandidate.isImported, isFalse);
      },
    );

    test(
      'imports only unique stations and applies sequential ordering',
      () async {
        final harness = await createHarness(
          initialStations: [
            _buildStation(sourceId: '101', title: 'Existing', sortOrder: 4),
          ],
          sourceStationsByUrl: {
            'https://live.bilibili.com/101': _buildStation(
              sourceId: '101',
              title: 'Existing duplicate',
            ),
            'https://live.bilibili.com/202': _buildStation(
              sourceId: '202',
              title: 'Imported 202',
            ),
          },
        );
        addTearDown(harness.dispose);

        final progress = <String>[];
        final result = await harness.controller.importAccountStations(const [
          'https://live.bilibili.com/101',
          'https://live.bilibili.com/202',
          'https://live.bilibili.com/202',
        ], onProgress: (completed, total) => progress.add('$completed/$total'));

        await pumpUntil(
          () => harness.controller.state.stations.length == 2,
          reason: 'watch-driven radio state should reflect the saved import',
        );

        final savedStations = await harness.repository.getAll();
        expect(result.successCount, 1);
        expect(result.failureCount, 2);
        expect(savedStations.map((station) => station.sourceId), [
          '101',
          '202',
        ]);
        expect(savedStations.map((station) => station.sortOrder), [4, 5]);
        expect(progress, ['1/3', '2/3', '3/3']);
      },
    );
  });
}

class RadioControllerImportHarness {
  RadioControllerImportHarness({
    required this.controller,
    required this.repository,
    required this.isar,
    required this.tempDir,
    required this.container,
  });

  final RadioController controller;
  final RadioRepository repository;
  final Isar isar;
  final Directory tempDir;
  final ProviderContainer container;

  Future<void> dispose() async {
    container.dispose();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }
}

Future<RadioControllerImportHarness> createHarness({
  List<MedalWallItem> medalWallItems = const [],
  List<RadioStation> initialStations = const [],
  Map<String, RadioStation> sourceStationsByUrl = const {},
  Duration initialLoadDelay = Duration.zero,
  bool waitForInitialLoad = true,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'radio_controller_phase2_import_test_',
  );
  final isar = await Isar.open(
    [RadioStationSchema],
    directory: tempDir.path,
    name: 'radio_controller_phase2_import_test',
  );
  final repository = RadioRepository(isar);
  if (initialStations.isNotEmpty) await repository.saveAll(initialStations);

  // `RadioController` 以前吃四個位置參數；`Notifier.new` 不吃，相依全部從
  // container 進去。`initialLoadDelay` 留在建構子上，由 override 帶進去。
  final container = ProviderContainer(
    overrides: [
      bilibiliAccountServiceProvider.overrideWithValue(
        _FakeBilibiliAccountService(isar: isar, medalWallItems: medalWallItems),
      ),
      radioRepositoryProvider.overrideWith((ref) => repository),
      radioSourceProvider.overrideWith(
        (ref) => _FakeRadioSource(sourceStationsByUrl),
      ),
      audioServiceProvider.overrideWith((ref) => FakeAudioService()),
      radioControllerProvider.overrideWith(
        () => RadioController(initialLoadDelay: initialLoadDelay),
      ),
    ],
  );
  final controller = container.read(radioControllerProvider.notifier);

  final harness = RadioControllerImportHarness(
    controller: controller,
    repository: repository,
    isar: isar,
    tempDir: tempDir,
    container: container,
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));
  if (waitForInitialLoad) {
    await pumpUntil(
      () => controller.state.stations.length == initialStations.length,
      reason: 'controller should load initial radio state',
    );
  }
  return harness;
}

class _FakeBilibiliAccountService extends BilibiliAccountService {
  _FakeBilibiliAccountService({
    required super.isar,
    required this.medalWallItems,
  });

  final List<MedalWallItem> medalWallItems;

  @override
  Future<List<MedalWallItem>> fetchMedalWall() async => medalWallItems;
}

class _FakeRadioSource extends RadioSource {
  _FakeRadioSource(this.sourceStationsByUrl);

  final Map<String, RadioStation> sourceStationsByUrl;

  @override
  ParseResult? parseUrl(String url) {
    final station = sourceStationsByUrl[url];
    if (station == null) return null;
    return ParseResult(sourceId: station.sourceId, normalizedUrl: station.url);
  }

  @override
  Future<RadioStation> createStationFromUrl(String url) async {
    final station = sourceStationsByUrl[url];
    if (station == null) throw Exception('Missing fake station for $url');
    return _buildStation(
      sourceId: station.sourceId,
      title: station.title,
      sortOrder: station.sortOrder,
    );
  }
}

RadioStation _buildStation({
  required String sourceId,
  required String title,
  int sortOrder = 0,
}) {
  return RadioStation()
    ..url = 'https://live.bilibili.com/$sourceId'
    ..sourceType = SourceIds.bilibili
    ..sourceId = sourceId
    ..title = title
    ..sortOrder = sortOrder;
}
