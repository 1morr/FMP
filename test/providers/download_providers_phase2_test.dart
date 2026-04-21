import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/download_task.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:fmp/providers/download/download_providers.dart' as download_providers;
import 'package:fmp/providers/repository_providers.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('download providers phase 2 cleanup', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test('download track provider reuses shared repository provider instance', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      final sharedRepository = harness.container.read(trackRepositoryProvider);
      final downloadedTrackRepository = harness.container.read(
        download_providers.trackRepositoryProvider,
      );

      expect(
        identical(downloadedTrackRepository, sharedRepository),
        isTrue,
      );
    });
  });
}

class _Harness {
  _Harness({
    required this.container,
    required this.isar,
    required this.tempDir,
  });

  final ProviderContainer container;
  final Isar isar;
  final Directory tempDir;

  Future<void> dispose() async {
    container.dispose();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'download_providers_phase2_test_',
  );
  final isar = await Isar.open(
    [
      TrackSchema,
      PlaylistSchema,
      PlayQueueSchema,
      SettingsSchema,
      DownloadTaskSchema,
      PlayHistorySchema,
    ],
    directory: tempDir.path,
    name: 'download_providers_phase2_test',
  );

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => isar),
    ],
  );

  return _Harness(
    container: container,
    isar: isar,
    tempDir: tempDir,
  );
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
  final packageConfig =
      jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
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
