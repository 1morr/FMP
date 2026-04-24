import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/services/download/download_path_manager.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadPathManager settings updates', () {
    late Directory tempDir;
    late Isar isar;
    late SettingsRepository settingsRepository;
    late DownloadPathManager manager;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('download_path_manager_');
      isar = await Isar.open(
        [SettingsSchema],
        directory: tempDir.path,
        name: 'download_path_manager_test',
      );
      settingsRepository = SettingsRepository(isar);
      manager = DownloadPathManager(settingsRepository);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveDownloadPath preserves unrelated settings', () async {
      final settings = await settingsRepository.get();
      settings.audioQualityLevelIndex = 2;
      settings.useNeteaseAuthForPlay = false;
      await settingsRepository.save(settings);

      await manager.saveDownloadPath('/tmp/fmp-downloads');

      final updated = await settingsRepository.get();
      expect(updated.customDownloadDir, '/tmp/fmp-downloads');
      expect(updated.audioQualityLevelIndex, 2);
      expect(updated.useNeteaseAuthForPlay, isFalse);
    });

    test('clearDownloadPath preserves unrelated settings', () async {
      final settings = await settingsRepository.get();
      settings.customDownloadDir = '/tmp/fmp-downloads';
      settings.audioQualityLevelIndex = 1;
      settings.useNeteaseAuthForPlay = false;
      await settingsRepository.save(settings);

      await manager.clearDownloadPath();

      final updated = await settingsRepository.get();
      expect(updated.customDownloadDir, isNull);
      expect(updated.audioQualityLevelIndex, 1);
      expect(updated.useNeteaseAuthForPlay, isFalse);
    });
  });
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
