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
import 'package:fmp/services/lyrics/ai_lyrics_selector.dart';
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
    late _FakeAiLyricsSelector aiLyricsSelector;
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
      aiLyricsSelector = _FakeAiLyricsSelector();
      netease = _FakeNeteaseSource();
      qqmusic = _FakeQQMusicSource();
      lrclib = _FakeLrclibSource();
      repo = LyricsRepository(isar);
      titleParseCacheRepo = LyricsTitleParseCacheRepository(isar);
      config = _config(mode: LyricsAiTitleParsingMode.alwaysAi);
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
        aiLyricsSelector: aiLyricsSelector,
        aiConfigLoader: () async => config,
        titleParseCacheRepo: titleParseCacheRepo,
        allowPlainLyricsAutoMatch: false,
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

    test('alwaysAi calls AI before regex, caches parse, and saves match',
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
      final track = _track('fallback-match')..sourceType = SourceType.netease;

      final matched = await buildService().tryAutoMatch(
        track,
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(netease.directFetchCalls, ['fallback-match']);
      expect(netease.searchCalls, ['AI Song AI Artist']);
      expect(aiParser.calls, hasLength(1));
      expect(aiParser.calls.single.title, 'Video Title');
      expect(aiParser.calls.single.uploader, 'Uploader');
      final cached = await titleParseCacheRepo.getReusable(
        trackUniqueKey: 'netease:fallback-match',
      );
      expect(cached, isNotNull);
      expect(cached!.parsedTrackName, 'AI Song');
      expect(cached.parsedArtistName, 'AI Artist');
      expect(cached.provider, 'openai-compatible');
      expect(cached.model, 'test-model');
      final saved = await repo.getByTrackKey('netease:fallback-match');
      expect(saved, isNotNull);
      expect(saved!.lyricsSource, 'netease');
      expect(saved.externalId, 'ai-match-1');
      expect(cache.savedKeys, ['netease:fallback-match']);
    });

    test('alwaysAi reuses cached AI parse without calling AI', () async {
      await titleParseCacheRepo.save(
        trackUniqueKey: 'youtube:cached-ai',
        sourceType: SourceType.youtube.name,
        parsedTrackName: 'Cached Song',
        parsedArtistName: 'Cached Artist',
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
      expect(netease.searchCalls, ['Cached Song Cached Artist']);
      final saved = await repo.getByTrackKey('youtube:cached-ai');
      expect(saved?.externalId, 'cached-match');
    });

    test('low-confidence cached AI artist is ignored for search', () async {
      await titleParseCacheRepo.save(
        trackUniqueKey: 'youtube:cached-low-confidence-artist',
        sourceType: SourceType.youtube.name,
        parsedTrackName: 'Cached Song',
        parsedArtistName: 'Wrong Uploader',
        confidence: 0.79,
        provider: 'openai-compatible',
        model: 'test-model',
      );
      netease.searchResultsByQuery['Cached Song'] = [
        _lyricsResult(
          id: 'cached-title-only-match',
          source: 'netease',
          trackName: 'Cached Song',
          artistName: 'Real Artist',
        ),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('cached-low-confidence-artist'),
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(aiParser.calls, isEmpty);
      expect(netease.searchCalls, ['Cached Song']);
      final saved =
          await repo.getByTrackKey('youtube:cached-low-confidence-artist');
      expect(saved?.externalId, 'cached-title-only-match');
    });

    test(
        'alwaysAi tries AI before regex for any source after direct fetch fails',
        () async {
      config = _config(mode: LyricsAiTitleParsingMode.alwaysAi);
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
      final track = _track('always-ai')..sourceType = SourceType.netease;

      final matched = await buildService().tryAutoMatch(
        track,
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(netease.directFetchCalls, ['always-ai']);
      expect(netease.searchCalls, ['AI Song AI Artist']);
      expect(aiParser.calls, hasLength(1));
      expect(aiParser.calls.single.title, 'Video Title');
      final saved = await repo.getByTrackKey('netease:always-ai');
      expect(saved?.externalId, 'always-ai-match');
    });

    test('netease direct lyrics fetch still runs before always AI', () async {
      config = _config(mode: LyricsAiTitleParsingMode.alwaysAi);
      aiParser.result =
          _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
      netease.directResults['netease-direct'] = _lyricsResult(
        id: 'netease-direct',
        source: 'netease',
      );
      final track = _track('netease-direct')..sourceType = SourceType.netease;

      final matched = await buildService().tryAutoMatch(
        track,
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(aiParser.calls, isEmpty);
      expect(netease.directFetchCalls, ['netease-direct']);
      expect(netease.searchCalls, isEmpty);
      final saved = await repo.getByTrackKey('netease:netease-direct');
      expect(saved?.externalId, 'netease-direct');
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
      );
      expect(cached, isNotNull);
      expect(cached!.parsedTrackName, 'No Match Song');
      expect(cached.parsedArtistName, 'Nobody');
      expect(await repo.getByTrackKey('youtube:cache-without-match'), isNull);
    });

    test(
        'alwaysAi does not fall back to regex when AI parse succeeds but matching fails',
        () async {
      config = _config(mode: LyricsAiTitleParsingMode.alwaysAi);
      aiParser.result =
          _aiParsed(trackName: 'AI No Match', artistName: 'AI Artist');
      netease.searchResultsByQuery['Regex Song Regex Artist'] = [
        _lyricsResult(id: 'regex-should-not-run', source: 'netease'),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('no-regex-after-ai-match-fail'),
        enabledSources: const ['netease'],
      );

      expect(matched, isFalse);
      expect(netease.searchCalls, ['AI No Match AI Artist', 'AI No Match']);
      expect(
        await repo.getByTrackKey('youtube:no-regex-after-ai-match-fail'),
        isNull,
      );
    });

    test('AI unavailable or null falls back without throwing', () async {
      config = _config(mode: LyricsAiTitleParsingMode.alwaysAi);
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

    test('invalid non-null AI parse falls back without saving cache', () async {
      config = _config(mode: LyricsAiTitleParsingMode.alwaysAi);
      aiParser.result = _aiParsed(trackName: '   ', artistName: 'AI Artist');
      netease.searchResultsByQuery['Regex Song Regex Artist'] = [
        _lyricsResult(id: 'invalid-ai-regex-fallback', source: 'netease'),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('invalid-ai-fallback'),
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(aiParser.calls, hasLength(1));
      expect(netease.searchCalls, ['Regex Song Regex Artist']);
      expect(await _cachedCount(isar), 0);
      final saved = await repo.getByTrackKey('youtube:invalid-ai-fallback');
      expect(saved?.externalId, 'invalid-ai-regex-fallback');
    });

    test('invalid cached AI parse is ignored and refreshed', () async {
      await titleParseCacheRepo.save(
        trackUniqueKey: 'youtube:invalid-cache',
        sourceType: SourceType.youtube.name,
        parsedTrackName: '',
        parsedArtistName: 'Cached Artist',
        confidence: 0.95,
        provider: 'openai-compatible',
        model: 'test-model',
      );
      aiParser.result = _aiParsed(
        trackName: 'Fresh AI Song',
        artistName: 'Fresh AI Artist',
      );
      netease.searchResultsByQuery['Fresh AI Song Fresh AI Artist'] = [
        _lyricsResult(
          id: 'fresh-ai-match',
          source: 'netease',
          trackName: 'Fresh AI Song',
          artistName: 'Fresh AI Artist',
        ),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('invalid-cache'),
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(aiParser.calls, hasLength(1));
      final cached = await titleParseCacheRepo.getReusable(
        trackUniqueKey: 'youtube:invalid-cache',
      );
      expect(cached?.parsedTrackName, 'Fresh AI Song');
      final saved = await repo.getByTrackKey('youtube:invalid-cache');
      expect(saved?.externalId, 'fresh-ai-match');
    });

    test('source priority dominates AI query order', () async {
      aiParser.result = _aiParsed(
        trackName: 'AI Song',
        artistName: 'AI Artist',
      );
      qqmusic.searchResultsByQuery['AI Song AI Artist'] = [
        _lyricsResult(
          id: 'qq-first-query-match',
          source: 'qqmusic',
          trackName: 'AI Song',
          artistName: 'AI Artist',
        ),
      ];
      netease.searchResultsByQuery['AI Song'] = [
        _lyricsResult(
          id: 'netease-no-artist-match',
          source: 'netease',
          trackName: 'AI Song',
          artistName: 'Different Artist',
        ),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('source-priority'),
        enabledSources: const ['netease', 'qqmusic'],
      );

      expect(matched, isTrue);
      expect(netease.searchCalls, [
        'AI Song AI Artist',
        'AI Song',
      ]);
      expect(qqmusic.searchCalls, isEmpty);
      final saved = await repo.getByTrackKey('youtube:source-priority');
      expect(saved?.lyricsSource, 'netease');
      expect(saved?.externalId, 'netease-no-artist-match');
    });

    test('low-confidence AI artist is ignored for search', () async {
      aiParser.result = _aiParsed(
        trackName: 'AI Song',
        artistName: null,
        artistConfidence: 0.79,
      );

      final matched = await buildService().tryAutoMatch(
        _track('artist-confidence'),
        enabledSources: const ['netease'],
      );

      expect(matched, isFalse);
      expect(netease.searchCalls, ['AI Song']);
    });

    test('advanced mode saves AI selected high-confidence synced candidate',
        () async {
      config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
      aiParser.result =
          _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
      netease.searchResultsByQuery['AI Song AI Artist'] = [
        _lyricsResult(
          id: 'chosen',
          source: 'netease',
          trackName: 'AI Song',
          artistName: 'AI Artist',
        ),
      ];
      aiLyricsSelector.result = const AiLyricsSelection(
        selectedCandidateId: 'netease:chosen',
        confidence: 0.91,
        reason: 'best synced match',
      );

      final matched = await buildService().tryAutoMatch(
        _track('advanced-selected'),
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(aiLyricsSelector.calls, hasLength(1));
      final call = aiLyricsSelector.calls.single;
      expect(call.candidates.single.candidateId, 'netease:chosen');
      expect(call.candidates.single.hasSyncedLyrics, isTrue);
      expect(call.candidates.single.videoDurationSeconds, 180);
      expect(call.sourcePriority, ['netease']);
      expect(call.allowPlainLyricsAutoMatch, isFalse);
      final saved = await repo.getByTrackKey('youtube:advanced-selected');
      expect(saved?.externalId, 'chosen');
    });

    test('advanced mode filters plain candidates before AI when disabled',
        () async {
      config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
      aiParser.result =
          _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
      netease.searchResultsByQuery['AI Song AI Artist'] = [
        _lyricsResult(
          id: 'plain',
          source: 'netease',
          trackName: 'AI Song',
          artistName: 'AI Artist',
          syncedLyrics: null,
          plainLyrics: 'plain',
        ),
      ];

      final matched = await buildService().tryAutoMatch(
        _track('advanced-filter-plain'),
        enabledSources: const ['netease'],
      );

      expect(matched, isFalse);
      expect(aiLyricsSelector.calls, isEmpty);
    });

    test(
        'advanced mode does not fall back to regex after low confidence selection',
        () async {
      config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
      aiParser.result =
          _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
      netease.searchResultsByQuery['AI Song AI Artist'] = [
        _lyricsResult(
          id: 'candidate',
          source: 'netease',
          trackName: 'AI Song',
          artistName: 'AI Artist',
        ),
      ];
      netease.searchResultsByQuery['Regex Song Regex Artist'] = [
        _lyricsResult(id: 'regex-should-not-run', source: 'netease'),
      ];
      aiLyricsSelector.result = const AiLyricsSelection(
        selectedCandidateId: 'netease:candidate',
        confidence: 0.8,
        reason: 'not enough',
      );

      final matched = await buildService().tryAutoMatch(
        _track('advanced-low-confidence'),
        enabledSources: const ['netease'],
      );

      expect(matched, isFalse);
      expect(netease.searchCalls, isNot(contains('Regex Song Regex Artist')));
      expect(
        await repo.getByTrackKey('youtube:advanced-low-confidence'),
        isNull,
      );
    });

    test('advanced mode falls back to regex when selector returns null',
        () async {
      config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
      aiParser.result =
          _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
      netease.searchResultsByQuery['AI Song AI Artist'] = [
        _lyricsResult(
          id: 'candidate',
          source: 'netease',
          trackName: 'AI Song',
          artistName: 'AI Artist',
        ),
      ];
      netease.searchResultsByQuery['Regex Song Regex Artist'] = [
        _lyricsResult(id: 'regex-fallback', source: 'netease'),
      ];
      aiLyricsSelector.result = null;

      final matched = await buildService().tryAutoMatch(
        _track('advanced-selector-null'),
        enabledSources: const ['netease'],
      );

      expect(matched, isTrue);
      expect(netease.searchCalls, [
        'AI Song AI Artist',
        'AI Song',
        'Regex Song Regex Artist',
      ]);
      final saved = await repo.getByTrackKey('youtube:advanced-selector-null');
      expect(saved?.externalId, 'regex-fallback');
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
  int duration = 180,
  String? syncedLyrics = '[00:01.00]line',
  String? plainLyrics,
}) {
  return LyricsResult(
    id: id,
    trackName: trackName,
    artistName: artistName,
    albumName: 'Album',
    duration: duration,
    instrumental: false,
    syncedLyrics: syncedLyrics,
    plainLyrics: plainLyrics,
    source: source,
  );
}

AiParsedTitle _aiParsed({
  String trackName = 'AI Song',
  String? artistName = 'AI Artist',
  double artistConfidence = 0.92,
}) {
  return AiParsedTitle(
    trackName: trackName,
    artistName: artistName,
    artistConfidence: artistConfidence,
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
  final List<({String title, String? uploader})> calls = [];
  AiParsedTitle? result;

  @override
  Future<AiParsedTitle?> parse({
    required String endpoint,
    required String apiKey,
    required String model,
    required String title,
    String? uploader,
    required int timeoutSeconds,
  }) async {
    calls.add((title: title, uploader: uploader));
    return result;
  }
}

class _FakeAiLyricsSelector extends AiLyricsSelector {
  final List<
      ({
        String endpoint,
        String apiKey,
        String model,
        String title,
        String? uploader,
        int durationSeconds,
        List<String> sourcePriority,
        bool allowPlainLyricsAutoMatch,
        List<AiLyricsCandidate> candidates,
        int timeoutSeconds,
      })> calls = [];
  AiLyricsSelection? result;

  @override
  Future<AiLyricsSelection?> select({
    required String endpoint,
    required String apiKey,
    required String model,
    required String title,
    String? uploader,
    required int durationSeconds,
    required List<String> sourcePriority,
    required bool allowPlainLyricsAutoMatch,
    required List<AiLyricsCandidate> candidates,
    required int timeoutSeconds,
  }) async {
    calls.add((
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      title: title,
      uploader: uploader,
      durationSeconds: durationSeconds,
      sourcePriority: sourcePriority,
      allowPlainLyricsAutoMatch: allowPlainLyricsAutoMatch,
      candidates: candidates,
      timeoutSeconds: timeoutSeconds,
    ));
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
