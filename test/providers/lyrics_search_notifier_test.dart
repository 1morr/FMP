import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/providers/lyrics_provider.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/lyrics_result.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsSearchNotifier', () {
    late Directory tempDir;
    late Isar isar;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'lyrics_search_notifier_',
      );
      isar = await Isar.open(
        [LyricsMatchSchema],
        directory: tempDir.path,
        name: 'lyrics_search_notifier_test',
      );
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('single-source filters do not query disabled lyrics sources',
        () async {
      final netease = _FakeNeteaseSource()
        ..results = [_lyricsResult(id: 'netease-1', source: 'netease')];
      final notifier = LyricsSearchNotifier(
        _FakeLrclibSource(),
        netease,
        _FakeQQMusicSource(),
        LyricsRepository(isar),
        LyricsCacheService(),
        disabledSources: const {'netease'},
      );

      notifier.setFilter(LyricsSourceFilter.netease);
      await notifier.search(query: 'Song Name');

      expect(netease.searchCalls, isEmpty);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.results, isEmpty);
      expect(notifier.state.error, isNull);
    });
  });
}

LyricsResult _lyricsResult({
  required String id,
  required String source,
}) {
  return LyricsResult(
    id: id,
    trackName: 'Song Name',
    artistName: 'Singer',
    albumName: 'Album',
    duration: 180,
    instrumental: false,
    syncedLyrics: '[00:01.00]line',
    source: source,
  );
}

class _FakeNeteaseSource extends NeteaseSource {
  final List<String> searchCalls = [];
  List<LyricsResult> results = [];

  @override
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    searchCalls
        .add(query ?? [trackName, artistName].whereType<String>().join(' '));
    return results;
  }
}

class _FakeQQMusicSource extends QQMusicSource {
  @override
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    return [];
  }
}

class _FakeLrclibSource extends LrclibSource {
  @override
  Future<List<LyricsResult>> search({
    String? q,
    String? trackName,
    String? artistName,
  }) async {
    return [];
  }
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
