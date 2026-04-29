import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/lyrics_title_parse_cache.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/data/repositories/lyrics_title_parse_cache_repository.dart';
import 'package:fmp/services/lyrics/ai_title_parser.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/lyrics_ai_config_service.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/lyrics_result.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:fmp/services/lyrics/title_parser.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsAutoMatchService AI title parsing', () {
    late Directory tempDir;
    late Isar isar;
    late _RecordingLyricsCacheService cache;
    late _FakeTitleParser parser;
    late _FakeAiTitleParser aiParser;
    late _FakeNeteaseSource netease;
    late _FakeQQMusicSource qqmusic;
    late _FakeLrclibSource lrclib;
    late LyricsRepository repo;
    late LyricsTitleParseCacheRepository titleParseCacheRepo;
    late LyricsAiConfig config;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'lyrics_auto_match_ai_title_parser_',
      );
      isar = await Isar.open(
        [LyricsMatchSchema, LyricsTitleParseCacheSchema],
        directory: tempDir.path,
        name: 'lyrics_auto_match_ai_title_parser_test',
      );
      cache = _RecordingLyricsCacheService();
      parser = _FakeTitleParser();
      aiParser = _FakeAiTitleParser();
      netease = _FakeNeteaseSource();
      qqmusic = _FakeQQMusicSource();
      lrclib = _FakeLrclibSource();
      repo = LyricsRepository(isar);
      titleParseCacheRepo = LyricsTitleParseCacheRepository(isar);
      config = _config(mode: LyricsAiTitleParsingMode.fallbackAfterRules);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    LyricsAutoMatchService buildService() {
      return LyricsAutoMatchService(
        lrclib: lrclib,
        netease: netease,
        qqmusic: qqmusic,
        repo: repo,
        cache: cache,
        parser: parser,
        aiTitleParser: aiParser,
        aiConfigLoader: () async => config,
        titleParseCacheRepo: titleParseCacheRepo,
      );
    }

    test('off mode never calls AI after regex match fails', () async {
      config = _config(mode: LyricsAiTitleParsingMode.off);
      aiParser.result = _aiParsed();

      final matched = await buildService().tryAutoMatch(
        _track('off-mode'),
        enabledSources: const ['netease'],
      );

      expect(matched, isFalse);
      expect(netease.searchCalls, ['Regex Song Regex Artist']);
      expect(aiParser.calls, isEmpty);
      expect(await _cachedCount(isar), 0);
    });

    test(
        'fallbackAfterRules calls AI after regex failure, caches parse, and saves match',
        () async {
      aiParser.result = _aiParsed(
        trackName: 'AI Song',
        artistName: 'AI Artist',
      );
      netease.searchResultsByQuery['AI Song AI Artist'] = [
        _lyricsResult(
          id: 'ai-match-1',
          source: 'netease',
          trackName: 'AI Song',
          artistName: 'AI Artist',
        ),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('fallback-match'),
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(netease.searchCalls, [
        'Regex Song Regex Artist',
        'AI Song AI Artist',
      ]);
      expect(aiParser.calls, hasLength(1));
      final cached = await titleParseCacheRepo.getReusable(
        trackUniqueKey: 'youtube:fallback-match',
        originalTitle: 'Video Title',
        originalArtist: 'Uploader',
        durationMs: 180000,
      );
      expect(cached, isNotNull);
      expect(cached!.parsedTrackName, 'AI Song');
      expect(cached.parsedArtistName, 'AI Artist');
      expect(cached.provider, 'openai-compatible');
      expect(cached.model, 'test-model');
      final saved = await repo.getByTrackKey('youtube:fallback-match');
      expect(saved, isNotNull);
      expect(saved!.lyricsSource, 'netease');
      expect(saved.externalId, 'ai-match-1');
      expect(cache.savedKeys, ['youtube:fallback-match']);
    });

    test('fallbackAfterRules reuses cached AI parse without calling AI',
        () async {
      await titleParseCacheRepo.save(
        trackUniqueKey: 'youtube:cached-ai',
        sourceType: SourceType.youtube.name,
        originalTitle: 'Video Title',
        originalArtist: 'Uploader',
        durationMs: 180000,
        parsedTrackName: 'Cached Song',
        parsedArtistName: 'Cached Artist',
        alternativeTrackNames: const [],
        alternativeArtistNames: const [],
        confidence: 0.91,
        provider: 'openai-compatible',
        model: 'test-model',
      );
      netease.searchResultsByQuery['Cached Song Cached Artist'] = [
        _lyricsResult(
          id: 'cached-match',
          source: 'netease',
          trackName: 'Cached Song',
          artistName: 'Cached Artist',
        ),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('cached-ai'),
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(aiParser.calls, isEmpty);
      expect(netease.searchCalls, [
        'Regex Song Regex Artist',
        'Cached Song Cached Artist',
      ]);
      final saved = await repo.getByTrackKey('youtube:cached-ai');
      expect(saved?.externalId, 'cached-match');
    });

    test('alwaysForVideoSources tries AI before regex for YouTube/Bilibili',
        () async {
      config = _config(mode: LyricsAiTitleParsingMode.alwaysForVideoSources);
      aiParser.result =
          _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
      netease.searchResultsByQuery['AI Song AI Artist'] = [
        _lyricsResult(
          id: 'always-ai-match',
          source: 'netease',
          trackName: 'AI Song',
          artistName: 'AI Artist',
        ),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('always-ai')..sourceType = SourceType.bilibili,
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(netease.searchCalls, ['AI Song AI Artist']);
      expect(aiParser.calls, hasLength(1));
      final saved = await repo.getByTrackKey('bilibili:always-ai');
      expect(saved?.externalId, 'always-ai-match');
    });

    test('non-video Netease source does not use AI', () async {
      config = _config(mode: LyricsAiTitleParsingMode.alwaysForVideoSources);
      aiParser.result =
          _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
      final track = _track('netease-no-ai')..sourceType = SourceType.netease;

      final matched = await buildService().tryAutoMatch(
        track,
        enabledSources: const ['netease'],
      );

      expect(matched, isFalse);
      expect(aiParser.calls, isEmpty);
      expect(netease.directFetchCalls, ['netease-no-ai']);
      expect(netease.searchCalls, ['Regex Song Regex Artist']);
    });

    test('valid AI parse is cached even when lyrics matching fails', () async {
      aiParser.result =
          _aiParsed(trackName: 'No Match Song', artistName: 'Nobody');

      final matched = await buildService().tryAutoMatch(
        _track('cache-without-match'),
        enabledSources: const ['netease'],
      );

      expect(matched, isFalse);
      expect(aiParser.calls, hasLength(1));
      final cached = await titleParseCacheRepo.getReusable(
        trackUniqueKey: 'youtube:cache-without-match',
        originalTitle: 'Video Title',
        originalArtist: 'Uploader',
        durationMs: 180000,
      );
      expect(cached, isNotNull);
      expect(cached!.parsedTrackName, 'No Match Song');
      expect(cached.parsedArtistName, 'Nobody');
      expect(await repo.getByTrackKey('youtube:cache-without-match'), isNull);
    });

    test('AI unavailable or invalid falls back without throwing', () async {
      config = _config(mode: LyricsAiTitleParsingMode.alwaysForVideoSources);
      aiParser.result = null;
      netease.searchResultsByQuery['Regex Song Regex Artist'] = [
        _lyricsResult(id: 'regex-fallback', source: 'netease'),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('ai-null-fallback'),
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(aiParser.calls, hasLength(1));
      expect(netease.searchCalls, ['Regex Song Regex Artist']);
      final saved = await repo.getByTrackKey('youtube:ai-null-fallback');
      expect(saved?.externalId, 'regex-fallback');
      expect(await _cachedCount(isar), 0);
    });

    test('AI-derived queries are bounded, deduped, and start with title artist',
        () async {
      aiParser.result = _aiParsed(
        trackName: 'AI Song',
        artistName: 'AI Artist',
        alternativeTrackNames: const [
          'AI Song',
          'Alt Song 1',
          'Alt Song 2',
          'Alt Song 3',
        ],
        alternativeArtistNames: const [
          'AI Artist',
          'Alt Artist 1',
          'Alt Artist 2',
        ],
      );

      final matched = await buildService().tryAutoMatch(
        _track('bounded-queries'),
        enabledSources: const ['netease'],
      );

      expect(matched, isFalse);
      expect(netease.searchCalls.first, 'Regex Song Regex Artist');
      expect(netease.searchCalls.skip(1).take(6), [
        'AI Song AI Artist',
        'AI Song Alt Artist 1',
        'AI Song Alt Artist 2',
        'Alt Song 1 AI Artist',
        'Alt Song 1 Alt Artist 1',
        'Alt Song 1 Alt Artist 2',
      ]);
      expect(netease.searchCalls.length, 7);
    });
  });
}

LyricsAiConfig _config({required LyricsAiTitleParsingMode mode}) {
  return LyricsAiConfig(
    mode: mode,
    endpoint: 'https://example.test/v1',
    apiKey: 'test-key',
    model: 'test-model',
    timeoutSeconds: 3,
  );
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = 'Video Title'
    ..artist = 'Uploader'
    ..durationMs = 180000;
}

LyricsResult _lyricsResult({
  required String id,
  required String source,
  String trackName = 'Regex Song',
  String artistName = 'Regex Artist',
}) {
  return LyricsResult(
    id: id,
    trackName: trackName,
    artistName: artistName,
    albumName: 'Album',
    duration: 180,
    instrumental: false,
    syncedLyrics: '[00:01.00]line',
    source: source,
  );
}

AiParsedTitle _aiParsed({
  String trackName = 'AI Song',
  String? artistName = 'AI Artist',
  List<String> alternativeTrackNames = const [],
  List<String> alternativeArtistNames = const [],
}) {
  return AiParsedTitle(
    trackName: trackName,
    artistName: artistName,
    alternativeTrackNames: alternativeTrackNames,
    alternativeArtistNames: alternativeArtistNames,
    confidence: 0.92,
  );
}

Future<int> _cachedCount(Isar isar) {
  return isar.lyricsTitleParseCaches.count();
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
      trackName: 'Regex Song',
      artistName: 'Regex Artist',
      cleanedTitle: 'Regex Song Regex Artist',
    );
  }
}

class _FakeAiTitleParser extends AiTitleParser {
  final List<({String title, String artist, SourceType sourceType})> calls = [];
  AiParsedTitle? result;

  @override
  Future<AiParsedTitle?> parse({
    required String endpoint,
    required String apiKey,
    required String model,
    required String title,
    required String artist,
    required SourceType sourceType,
    required int? durationMs,
    required int timeoutSeconds,
  }) async {
    calls.add((title: title, artist: artist, sourceType: sourceType));
    return result;
  }
}

class _FakeNeteaseSource extends NeteaseSource {
  final List<String> searchCalls = [];
  final List<String> directFetchCalls = [];
  final Map<String, List<LyricsResult>> searchResultsByQuery = {};
  final Map<String, LyricsResult> directResults = {};

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
    return searchResultsByQuery[effectiveQuery] ?? const [];
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
  final Map<String, List<LyricsResult>> searchResultsByQuery = {};
  final Map<String, LyricsResult> directResults = {};

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
    return searchResultsByQuery[effectiveQuery] ?? const [];
  }

  @override
  Future<LyricsResult?> getLyricsResult(String songmid) async {
    directFetchCalls.add(songmid);
    return directResults[songmid];
  }
}

class _FakeLrclibSource extends LrclibSource {
  final List<String> searchCalls = [];
  final Map<String, List<LyricsResult>> searchResultsByQuery = {};

  @override
  Future<List<LyricsResult>> search({
    String? q,
    String? trackName,
    String? artistName,
  }) async {
    final effectiveQuery =
        [trackName, artistName].whereType<String>().join(' ');
    searchCalls.add(effectiveQuery);
    return searchResultsByQuery[effectiveQuery] ?? const [];
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
