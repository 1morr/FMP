import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Isar.initializeIsarCore(
      libraries: {Abi.current(): await _resolveIsarLibraryPath()},
    );
  });

  test('getBySourceIdentities keeps source type and nullable cid distinct',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'track_repository_batch_identity_test_',
    );
    final isar = await Isar.open(
      [TrackSchema],
      directory: tempDir.path,
      name: 'track_repository_batch_identity_test',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final repo = TrackRepository(isar);

    final youtubeNull =
        await repo.save(_track('same', SourceType.youtube, 'YT'));
    final youtubeCid = await repo.save(
      _track('same', SourceType.youtube, 'YT P2')..cid = 22,
    );
    final bilibiliNull = await repo.save(
      _track('same', SourceType.bilibili, 'BV'),
    );

    final result = await repo.getBySourceIdentities([
      TrackSourceIdentity.fromTrack(youtubeNull),
      TrackSourceIdentity.fromTrack(youtubeCid),
      TrackSourceIdentity.fromTrack(bilibiliNull),
    ]);

    expect(
        result[TrackSourceIdentity.fromTrack(youtubeNull)]?.id, youtubeNull.id);
    expect(
        result[TrackSourceIdentity.fromTrack(youtubeCid)]?.id, youtubeCid.id);
    expect(result[TrackSourceIdentity.fromTrack(bilibiliNull)]?.id,
        bilibiliNull.id);
  });
}

Track _track(String sourceId, SourceType sourceType, String title) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = sourceType
    ..title = title
    ..createdAt = DateTime.now();
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
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
