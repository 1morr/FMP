import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/data/repositories/lyrics_title_parse_cache_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/providers/audio_settings_provider.dart';
import 'package:fmp/providers/lyrics_provider.dart';
import 'package:fmp/providers/repository_providers.dart';
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

  test('lyricsAutoMatchServiceProvider uses persisted plain lyrics setting',
      () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final settings = Settings()..allowPlainLyricsAutoMatch = true;
    final lyricsRepo = _FakeLyricsRepository();
    final netease = _FakeNeteaseSource()
      ..searchResults = [
        _lyricsResult(
          id: 'plain-lyrics',
          syncedLyrics: null,
          plainLyrics: 'plain line',
        ),
      ];

    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWith(
          (ref) => _FakeSettingsRepository(settings),
        ),
        lyricsRepositoryProvider.overrideWith((ref) => lyricsRepo),
        lyricsTitleParseCacheRepositoryProvider.overrideWith(
          (ref) => _FakeLyricsTitleParseCacheRepository(),
        ),
        lyricsCacheServiceProvider.overrideWith((ref) => _RecordingLyricsCache()),
        titleParserProvider.overrideWith((ref) => _FakeTitleParser()),
        neteaseSourceProvider.overrideWith((ref) => netease),
        qqmusicSourceProvider.overrideWith((ref) => _FakeQQMusicSource()),
        lrclibSourceProvider.overrideWith((ref) => _FakeLrclibSource()),
      ],
    );
    addTearDown(container.dispose);

    final service = await _readServiceAfterSettingsLoad(container);
    final matched = await service.tryAutoMatch(
      _track('provider-plain'),
      enabledSources: const ['netease'],
    );

    expect(matched, isTrue);
    expect(lyricsRepo.saved?.externalId, 'plain-lyrics');
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = 'Song Name'
    ..durationMs = 180000;
}

Future<LyricsAutoMatchService> _readServiceAfterSettingsLoad(
  ProviderContainer container,
) async {
  while (container.read(audioSettingsProvider).isLoading) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(container.read(audioSettingsProvider).allowPlainLyricsAutoMatch, isTrue);
  return container.read(lyricsAutoMatchServiceProvider);
}

LyricsResult _lyricsResult({
  required String id,
  String? syncedLyrics = '[00:01.00]line',
  String? plainLyrics,
}) {
  return LyricsResult(
    id: id,
    trackName: 'Song Name',
    artistName: 'Singer',
    albumName: 'Album',
    duration: 180,
    instrumental: false,
    syncedLyrics: syncedLyrics,
    plainLyrics: plainLyrics,
    source: 'netease',
  );
}

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository(this.settings) : super(_FakeIsar());

  final Settings settings;

  @override
  Future<Settings> get() async => settings;
}

class _FakeLyricsRepository extends LyricsRepository {
  _FakeLyricsRepository() : super(_FakeIsar());

  LyricsMatch? saved;

  @override
  Future<LyricsMatch?> getByTrackKey(String trackUniqueKey) async => saved;

  @override
  Future<void> save(LyricsMatch match) async {
    saved = match;
  }
}

class _FakeLyricsTitleParseCacheRepository
    extends LyricsTitleParseCacheRepository {
  _FakeLyricsTitleParseCacheRepository() : super(_FakeIsar());
}

class _RecordingLyricsCache extends LyricsCacheService {
  @override
  Future<void> put(String trackUniqueKey, LyricsResult result) async {}
}

class _FakeTitleParser implements TitleParser {
  @override
  ParsedTitle parse(String title, {String? uploader}) {
    return const ParsedTitle(
      trackName: 'Song Name',
      artistName: null,
      cleanedTitle: 'Song Name',
    );
  }
}

class _FakeNeteaseSource extends NeteaseSource {
  List<LyricsResult> searchResults = [];

  @override
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    return searchResults;
  }
}

class _FakeQQMusicSource extends QQMusicSource {}

class _FakeLrclibSource extends LrclibSource {}

class _FakeIsar extends Fake implements Isar {}
