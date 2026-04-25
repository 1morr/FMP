import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4 Task 4 play history repository snapshot', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test('loadHistorySnapshot applies filters and returns latest records first',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seed(
        _history(
          sourceId: 'yt-new',
          sourceType: SourceType.youtube,
          title: 'Focus Track',
          artist: 'Alpha',
          playedAt: DateTime(2026, 4, 20, 18),
        ),
        _history(
          sourceId: 'yt-old',
          sourceType: SourceType.youtube,
          title: 'Focus Track Archive',
          artist: 'Alpha',
          playedAt: DateTime(2026, 4, 19, 9),
        ),
        _history(
          sourceId: 'bili-hit',
          sourceType: SourceType.bilibili,
          title: 'Other Song',
          artist: 'Beta',
          playedAt: DateTime(2026, 4, 20, 12),
        ),
      );

      final records = await harness.repository.loadHistorySnapshot(
        sourceTypes: {SourceType.youtube},
        startDate: DateTime(2026, 4, 20),
        searchKeyword: 'focus',
      );

      expect(records.map((e) => e.sourceId).toList(), ['yt-new']);
    });

    test('queryHistory applies time order pagination without snapshot cap',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final records = List.generate(75, (index) {
        return _history(
          sourceId: 'song-$index',
          sourceType: SourceType.youtube,
          title: 'Song $index',
          playedAt:
              DateTime(2026, 4, 20, 12).subtract(Duration(minutes: index)),
        );
      });
      await harness.seedMany(records);

      final page = await harness.repository.queryHistory(
        offset: 20,
        limit: 10,
      );

      expect(page.map((e) => e.sourceId).toList(),
          List.generate(10, (index) => 'song-${index + 20}'));
    });

    test(
        'getRecentHistoryDistinct scans only enough recent rows for unique tracks',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedMany([
        _history(
          sourceId: 'repeat',
          sourceType: SourceType.youtube,
          title: 'Repeat Latest',
          playedAt: DateTime(2026, 4, 20, 12),
        ),
        _history(
          sourceId: 'repeat',
          sourceType: SourceType.youtube,
          title: 'Repeat Older',
          playedAt: DateTime(2026, 4, 20, 11),
        ),
        _history(
          sourceId: 'unique',
          sourceType: SourceType.youtube,
          title: 'Unique',
          playedAt: DateTime(2026, 4, 20, 10),
        ),
      ]);

      final recent =
          await harness.repository.getRecentHistoryDistinct(limit: 2);

      expect(recent.map((e) => e.sourceId).toList(), ['repeat', 'unique']);
    });
  });
}

class _Harness {
  _Harness({
    required this.repository,
    required this.isar,
    required this.tempDir,
  });

  final PlayHistoryRepository repository;
  final Isar isar;
  final Directory tempDir;

  Future<void> seed(PlayHistory first,
      [PlayHistory? second, PlayHistory? third]) async {
    final records = [
      first,
      if (second != null) second,
      if (third != null) third
    ];
    await seedMany(records);
  }

  Future<void> seedMany(List<PlayHistory> records) async {
    await isar.writeTxn(() async {
      await isar.playHistorys.putAll(records);
    });
  }

  Future<void> dispose() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'play_history_repository_phase4_test_',
  );
  final isar = await Isar.open(
    [PlayHistorySchema],
    directory: tempDir.path,
    name: 'play_history_repository_phase4_test',
  );

  return _Harness(
    repository: PlayHistoryRepository(isar),
    isar: isar,
    tempDir: tempDir,
  );
}

PlayHistory _history({
  required String sourceId,
  required SourceType sourceType,
  required String title,
  String? artist,
  required DateTime playedAt,
}) {
  return PlayHistory()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = title
    ..artist = artist
    ..playedAt = playedAt;
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') {
      continue;
    }
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
