import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_title_parse_cache.dart';
import 'package:fmp/data/repositories/lyrics_title_parse_cache_repository.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsTitleParseCacheRepository', () {
    late Directory tempDir;
    late Isar isar;
    late LyricsTitleParseCacheRepository repo;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lyrics_ai_cache_');
      isar = await Isar.open(
        [LyricsTitleParseCacheSchema],
        directory: tempDir.path,
        name: 'lyrics_ai_cache_test',
      );
      repo = LyricsTitleParseCacheRepository(isar);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('saves and returns reusable cache for unchanged metadata', () async {
      await repo.save(
        trackUniqueKey: 'youtube:abc',
        sourceType: 'youtube',
        originalTitle: '【MV】YOASOBI「アイドル」Official Music Video',
        originalArtist: 'YOASOBI',
        durationMs: 213000,
        parsedTrackName: 'アイドル',
        parsedArtistName: 'YOASOBI',
        alternativeTrackNames: const ['Idol'],
        alternativeArtistNames: const [],
        confidence: 0.92,
        provider: 'openai-compatible',
        model: 'test-model',
      );

      final cached = await repo.getReusable(
        trackUniqueKey: 'youtube:abc',
        originalTitle: '【MV】YOASOBI「アイドル」Official Music Video',
        originalArtist: 'YOASOBI',
        durationMs: 214000,
      );

      expect(cached, isNotNull);
      expect(cached!.parsedTrackName, 'アイドル');
      expect(cached.alternativeTrackNames, ['Idol']);
    });

    test('returns null when title changes', () async {
      await repo.save(
        trackUniqueKey: 'youtube:abc',
        sourceType: 'youtube',
        originalTitle: 'Old title',
        originalArtist: 'Singer',
        durationMs: 180000,
        parsedTrackName: 'Song',
        parsedArtistName: 'Singer',
        alternativeTrackNames: const [],
        alternativeArtistNames: const [],
        confidence: 0.8,
        provider: 'openai-compatible',
        model: 'test-model',
      );

      final cached = await repo.getReusable(
        trackUniqueKey: 'youtube:abc',
        originalTitle: 'New title',
        originalArtist: 'Singer',
        durationMs: 180000,
      );

      expect(cached, isNull);
    });

    test('returns null when duration differs by more than 2 seconds', () async {
      await repo.save(
        trackUniqueKey: 'youtube:abc',
        sourceType: 'youtube',
        originalTitle: 'Song title',
        originalArtist: 'Singer',
        durationMs: 180000,
        parsedTrackName: 'Song',
        parsedArtistName: 'Singer',
        alternativeTrackNames: const [],
        alternativeArtistNames: const [],
        confidence: 0.8,
        provider: 'openai-compatible',
        model: 'test-model',
      );

      final cached = await repo.getReusable(
        trackUniqueKey: 'youtube:abc',
        originalTitle: 'Song title',
        originalArtist: 'Singer',
        durationMs: 183001,
      );

      expect(cached, isNull);
    });

    test('clear deletes all cache rows', () async {
      await repo.save(
        trackUniqueKey: 'youtube:abc',
        sourceType: 'youtube',
        originalTitle: 'Song title',
        originalArtist: 'Singer',
        durationMs: 180000,
        parsedTrackName: 'Song',
        parsedArtistName: 'Singer',
        alternativeTrackNames: const [],
        alternativeArtistNames: const [],
        confidence: 0.8,
        provider: 'openai-compatible',
        model: 'test-model',
      );

      await repo.clear();

      expect(await isar.lyricsTitleParseCaches.count(), 0);
    });
  });
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
