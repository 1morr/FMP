import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/providers/account_provider.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/services/radio/radio_controller.dart';
import 'package:fmp/services/radio/radio_refresh_service.dart';
import 'package:fmp/services/radio/radio_source.dart';
import 'package:isar/isar.dart';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Isar.initializeIsarCore(
      libraries: {Abi.current(): await _resolveIsarLibraryPath()},
    );
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
      expect(items.where((item) => item.isLive).map((item) => item.name), ['Alpha']);
    });

    test('imports only unique stations and applies sequential ordering', () async {
      final harness = await createHarness(
        initialStations: [_buildStation(sourceId: '101', title: 'Existing', sortOrder: 4)],
        sourceStationsByUrl: {
          'https://live.bilibili.com/101': _buildStation(sourceId: '101', title: 'Existing duplicate'),
          'https://live.bilibili.com/202': _buildStation(sourceId: '202', title: 'Imported 202'),
        },
      );
      addTearDown(harness.dispose);

      final progress = <String>[];
      final result = await harness.controller.importAccountStations(
        const [
          'https://live.bilibili.com/101',
          'https://live.bilibili.com/202',
          'https://live.bilibili.com/202',
        ],
        onProgress: (completed, total) => progress.add('$completed/$total'),
      );

      await harness.pumpUntil(
        () => harness.controller.state.stations.length == 2,
        reason: 'watch-driven radio state should reflect the saved import',
      );

      final savedStations = await harness.repository.getAll();
      expect(result.successCount, 1);
      expect(result.failureCount, 2);
      expect(savedStations.map((station) => station.sourceId), ['101', '202']);
      expect(savedStations.map((station) => station.sortOrder), [4, 5]);
      expect(progress, ['1/3', '2/3', '3/3']);
    });
  });
}

class RadioControllerImportHarness {
  RadioControllerImportHarness({required this.controller, required this.repository, required this.isar, required this.tempDir});

  final RadioController controller;
  final RadioRepository repository;
  final Isar isar;
  final Directory tempDir;

  Future<void> pumpUntil(bool Function() condition, {required String reason, Duration timeout = const Duration(seconds: 2)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (!condition()) fail(reason);
  }

  Future<void> dispose() async {
    controller.dispose();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }
}

Future<RadioControllerImportHarness> createHarness({
  List<MedalWallItem> medalWallItems = const [],
  List<RadioStation> initialStations = const [],
  Map<String, RadioStation> sourceStationsByUrl = const {},
}) async {
  final tempDir = await Directory.systemTemp.createTemp('radio_controller_phase2_import_test_');
  final isar = await Isar.open([RadioStationSchema], directory: tempDir.path, name: 'radio_controller_phase2_import_test');
  final repository = RadioRepository(isar);
  if (initialStations.isNotEmpty) await repository.saveAll(initialStations);

  final controller = RadioController(
    _FakeRef(_FakeBilibiliAccountService(isar: isar, medalWallItems: medalWallItems)),
    repository,
    _FakeRadioSource(sourceStationsByUrl),
    FakeAudioService(),
  );

  final harness = RadioControllerImportHarness(controller: controller, repository: repository, isar: isar, tempDir: tempDir);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await harness.pumpUntil(() => controller.state.stations.length == initialStations.length, reason: 'controller should load initial radio state');
  return harness;
}

class _FakeRef implements Ref {
  _FakeRef(this.accountService);

  final BilibiliAccountService accountService;

  @override
  T read<T>(ProviderListenable<T> provider) {
    if (provider == bilibiliAccountServiceProvider) return accountService as T;
    throw UnimplementedError('Unexpected provider: $provider');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBilibiliAccountService extends BilibiliAccountService {
  _FakeBilibiliAccountService({required super.isar, required this.medalWallItems});

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
    return _buildStation(sourceId: station.sourceId, title: station.title, sortOrder: station.sortOrder);
  }
}

RadioStation _buildStation({required String sourceId, required String title, int sortOrder = 0}) {
  return RadioStation()
    ..url = 'https://live.bilibili.com/$sourceId'
    ..sourceType = SourceType.bilibili
    ..sourceId = sourceId
    ..title = title
    ..sortOrder = sortOrder;
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfig = jsonDecode(await File('${Directory.current.path}/.dart_tool/package_config.json').readAsString()) as Map<String, dynamic>;
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
