import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/lyrics_result.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:fmp/services/lyrics/title_parser.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsAutoMatchService phase 4', () {
    late Directory tempDir;
    late Isar isar;
    late _RecordingLyricsCacheService cache;
    late _FakeTitleParser parser;
    late _FakeNeteaseSource netease;
    late _FakeQQMusicSource qqmusic;
    late _FakeLrclibSource lrclib;
    late LyricsRepository repo;
    late LyricsAutoMatchService service;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'lyrics_auto_match_phase4_',
      );
      isar = await Isar.open(
        [LyricsMatchSchema],
        directory: tempDir.path,
        name: 'lyrics_auto_match_phase4_test',
      );
      cache = _RecordingLyricsCacheService();
      parser = _FakeTitleParser();
      netease = _FakeNeteaseSource();
      qqmusic = _FakeQQMusicSource();
      lrclib = _FakeLrclibSource();
      repo = LyricsRepository(isar);
      service = LyricsAutoMatchService(
        lrclib: lrclib,
        netease: netease,
        qqmusic: qqmusic,
        repo: repo,
        cache: cache,
        parser: parser,
      );
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('tryAutoMatch short-circuits when a lyrics match already exists',
        () async {
      await repo.save(
        LyricsMatch()
          ..trackUniqueKey = 'youtube:existing'
          ..lyricsSource = 'netease'
          ..externalId = 'existing-lyrics'
          ..offsetMs = 0
          ..matchedAt = DateTime.now(),
      );

      final matched = await service.tryAutoMatch(
        _track('existing'),
        enabledSources: const ['netease', 'qqmusic'],
      );

      expect(matched, isFalse);
      expect(netease.directFetchCalls, isEmpty);
      expect(qqmusic.directFetchCalls, isEmpty);
      expect(netease.searchCalls, isEmpty);
      expect(qqmusic.searchCalls, isEmpty);
      expect(lrclib.searchCalls, isEmpty);
      expect(cache.savedKeys, isEmpty);
    });

    test('tryAutoMatch fetches netease source lyrics directly by sourceId',
        () async {
      netease.directResults['netease-song-1'] = _lyricsResult(
        id: 'netease-song-1',
        source: 'netease',
      );
      final track = _track('netease-song-1')..sourceType = SourceType.netease;

      final matched = await service.tryAutoMatch(
        track,
        enabledSources: const ['qqmusic', 'netease'],
      );

      expect(matched, isTrue);
      expect(netease.directFetchCalls, ['netease-song-1']);
      expect(qqmusic.directFetchCalls, isEmpty);
      expect(qqmusic.searchCalls, isEmpty);
      expect(netease.searchCalls, isEmpty);
      expect(lrclib.searchCalls, isEmpty);
      final saved = await repo.getByTrackKey('netease:netease-song-1');
      expect(saved, isNotNull);
      expect(saved!.lyricsSource, 'netease');
      expect(saved.externalId, 'netease-song-1');
      expect(cache.savedKeys, ['netease:netease-song-1']);
    });

    test('tryAutoMatch fetches imported qqmusic lyrics directly by original ID',
        () async {
      qqmusic.directResults['qq-songmid-1'] = _lyricsResult(
        id: 'qq-songmid-1',
        source: 'qqmusic',
      );
      final track = _track('imported-qq')
        ..originalSongId = 'qq-songmid-1'
        ..originalSource = 'qqmusic';

      final matched = await service.tryAutoMatch(
        track,
        enabledSources: const ['netease', 'qqmusic'],
      );

      expect(matched, isTrue);
      expect(qqmusic.directFetchCalls, ['qq-songmid-1']);
      expect(netease.directFetchCalls, isEmpty);
      expect(netease.searchCalls, isEmpty);
      expect(qqmusic.searchCalls, isEmpty);
      expect(lrclib.searchCalls, isEmpty);
      final saved = await repo.getByTrackKey('youtube:imported-qq');
      expect(saved, isNotNull);
      expect(saved!.lyricsSource, 'qqmusic');
      expect(saved.externalId, 'qq-songmid-1');
      expect(cache.savedKeys, ['youtube:imported-qq']);
    });

    test('tryAutoMatch searches for spotify imports instead of direct fetch',
        () async {
      netease.searchResults = [
        _lyricsResult(id: 'netease-fallback-1', source: 'netease'),
      ];
      final track = _track('spotify-import')
        ..originalSongId = 'spotify-track-1'
        ..originalSource = 'spotify';

      final matched = await service.tryAutoMatch(
        track,
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(netease.directFetchCalls, isEmpty);
      expect(qqmusic.directFetchCalls, isEmpty);
      expect(netease.searchCalls, ['Song Name Singer']);
      expect(qqmusic.searchCalls, isEmpty);
      expect(lrclib.searchCalls, isEmpty);
      final saved = await repo.getByTrackKey('youtube:spotify-import');
      expect(saved, isNotNull);
      expect(saved!.lyricsSource, 'netease');
      expect(saved.externalId, 'netease-fallback-1');
      expect(cache.savedKeys, ['youtube:spotify-import']);
    });

    test('tryAutoMatch respects enabled source ordering before fallback',
        () async {
      qqmusic.searchResults = [
        _lyricsResult(id: 'qq-1', source: 'qqmusic'),
      ];
      netease.searchResults = [
        _lyricsResult(id: 'netease-1', source: 'netease'),
      ];

      final matched = await service.tryAutoMatch(
        _track('track-1'),
        enabledSources: const ['qqmusic', 'netease', 'lrclib'],
      );

      expect(matched, isTrue);
      expect(qqmusic.searchCalls, ['Song Name Singer']);
      expect(netease.searchCalls, isEmpty);
      expect(lrclib.searchCalls, isEmpty);
      final saved = await repo.getByTrackKey('youtube:track-1');
      expect(saved, isNotNull);
      expect(saved!.lyricsSource, 'qqmusic');
      expect(saved.externalId, 'qq-1');
      expect(cache.savedKeys, ['youtube:track-1']);
    });

    test('tryAutoMatch accepts search result within 20 seconds', () async {
      netease.searchResults = [
        _lyricsResult(id: 'netease-20s', source: 'netease', duration: 200),
      ];

      final matched = await service.tryAutoMatch(
        _track('duration-20s'),
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      final saved = await repo.getByTrackKey('youtube:duration-20s');
      expect(saved?.externalId, 'netease-20s');
    });

    test('tryAutoMatch rejects search result beyond 20 seconds', () async {
      netease.searchResults = [
        _lyricsResult(id: 'netease-21s', source: 'netease', duration: 201),
      ];

      final matched = await service.tryAutoMatch(
        _track('duration-21s'),
        enabledSources: const ['netease'],
      );

      expect(matched, isFalse);
      expect(await repo.getByTrackKey('youtube:duration-21s'), isNull);
    });

    test('rejects plain-only lyrics by default', () async {
      netease.searchResults = [
        _lyricsResult(
          id: 'plain-only',
          source: 'netease',
          syncedLyrics: null,
          plainLyrics: 'plain line',
        ),
      ];
      final matched = await service.tryAutoMatch(
        _track('plain-default'),
        enabledSources: const ['netease'],
      );
      expect(matched, isFalse);
      expect(await repo.getByTrackKey('youtube:plain-default'), isNull);
    });

    test('accepts plain-only lyrics when setting allows it', () async {
      service = LyricsAutoMatchService(
        lrclib: lrclib,
        netease: netease,
        qqmusic: qqmusic,
        repo: repo,
        cache: cache,
        parser: parser,
        allowPlainLyricsAutoMatch: true,
      );
      netease.searchResults = [
        _lyricsResult(
          id: 'plain-allowed',
          source: 'netease',
          syncedLyrics: null,
          plainLyrics: 'plain line',
        ),
      ];
      final matched = await service.tryAutoMatch(
        _track('plain-allowed'),
        enabledSources: const ['netease'],
      );
      expect(matched, isTrue);
      final saved = await repo.getByTrackKey('youtube:plain-allowed');
      expect(saved?.externalId, 'plain-allowed');
    });

    test('tryAutoMatch clears in-flight state after completion', () async {
      final gate = _Gate();
      netease.onSearch = () async {
        await gate.future;
        return [_lyricsResult(id: 'netease-2', source: 'netease')];
      };

      final first = service.tryAutoMatch(
        _track('track-2'),
        enabledSources: const ['netease'],
      );
      await netease.waitForSearchCall();

      final duplicateWhileRunning = await service.tryAutoMatch(
        _track('track-2'),
        enabledSources: const ['netease'],
      );
      expect(duplicateWhileRunning, isFalse);

      gate.complete();
      expect(await first, isTrue);

      await repo.delete('youtube:track-2');
      netease.onSearch = () async => [
            _lyricsResult(id: 'netease-3', source: 'netease'),
          ];
      final retrySameTrack = await service.tryAutoMatch(
        _track('track-2'),
        enabledSources: const ['netease'],
      );

      expect(retrySameTrack, isTrue);

      netease.onSearch = () async => [
            _lyricsResult(id: 'netease-4', source: 'netease'),
          ];
      final nextTrack = _track('track-3');
      final second = await service.tryAutoMatch(
        nextTrack,
        enabledSources: const ['netease'],
      );

      expect(second, isTrue);
      expect(netease.searchCalls.length, 3);
      expect(cache.savedKeys,
          ['youtube:track-2', 'youtube:track-2', 'youtube:track-3']);
    });
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = 'Song Name'
    ..artist = 'Singer'
    ..durationMs = 180000;
}

LyricsResult _lyricsResult({
  required String id,
  required String source,
  int duration = 180,
  String? syncedLyrics = '[00:01.00]line',
  String? plainLyrics,
}) {
  return LyricsResult(
    id: id,
    trackName: 'Song Name',
    artistName: 'Singer',
    albumName: 'Album',
    duration: duration,
    instrumental: false,
    syncedLyrics: syncedLyrics,
    plainLyrics: plainLyrics,
    source: source,
  );
}

class _RecordingLyricsCacheService extends LyricsCacheService {
  final List<String> savedKeys = [];

  @override
  Future<void> put(String trackUniqueKey, LyricsResult result) async {
    savedKeys.add(trackUniqueKey);
  }
}

class _FakeTitleParser implements TitleParser {
  @override
  ParsedTitle parse(String title, {String? uploader}) {
    return const ParsedTitle(
      trackName: 'Song Name',
      artistName: 'Singer',
      cleanedTitle: 'Song Name Singer',
    );
  }
}

class _FakeNeteaseSource extends NeteaseSource {
  final List<String> searchCalls = [];
  final List<String> directFetchCalls = [];
  final Completer<void> _searchCalled = Completer<void>();
  List<LyricsResult> searchResults = [];
  Map<String, LyricsResult> directResults = {};
  Future<List<LyricsResult>> Function()? onSearch;

  Future<void> waitForSearchCall() => _searchCalled.future;

  @override
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    final effectiveQuery =
        query ?? [trackName, artistName].whereType<String>().join(' ');
    searchCalls.add(effectiveQuery);
    if (!_searchCalled.isCompleted) {
      _searchCalled.complete();
    }
    return onSearch != null ? await onSearch!() : searchResults;
  }

  @override
  Future<LyricsResult?> getLyricsResult(String songId) async {
    directFetchCalls.add(songId);
    return directResults[songId];
  }
}

class _FakeQQMusicSource extends QQMusicSource {
  final List<String> searchCalls = [];
  final List<String> directFetchCalls = [];
  List<LyricsResult> searchResults = [];
  Map<String, LyricsResult> directResults = {};

  @override
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    final effectiveQuery =
        query ?? [trackName, artistName].whereType<String>().join(' ');
    searchCalls.add(effectiveQuery);
    return searchResults;
  }

  @override
  Future<LyricsResult?> getLyricsResult(String songmid) async {
    directFetchCalls.add(songmid);
    return directResults[songmid];
  }
}

class _FakeLrclibSource extends LrclibSource {
  final List<String> searchCalls = [];

  @override
  Future<List<LyricsResult>> search({
    String? q,
    String? trackName,
    String? artistName,
  }) async {
    searchCalls.add([trackName, artistName].whereType<String>().join(' '));
    return [];
  }
}

class _Gate {
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
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
