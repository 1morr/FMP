import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:fmp/services/lyrics/title_parser.dart';
import 'package:isar_community/isar.dart';

import '../../support/audio_controller_harness.dart';
import '../../support/fakes/count_waiters.dart';
import '../../support/fakes/fake_audio_service.dart';
import '../../support/fakes/fake_source_auth_context.dart';
import '../../support/isar_test_harness.dart';
import '../../support/now_playing.dart';

/// 自動比對存歌詞用的鍵，必須跟播放頁歌詞欄讀的鍵是同一個。
///
/// 歌詞欄一路從 `state.currentTrack.uniqueKey` 往下查，而 `uniqueKey` 含 `cid`
/// —— Bilibili 的 `cid` 又是串流解析時才寫進 track 的。播放請求走的是
/// `Track.copy()`，所以那個回寫只會落在副本上；把請求前的原件交給自動比對，
/// 比對結果就會存在少一段 cid 的鍵底下，歌詞欄永遠查不到（issue #113）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioController lyrics auto-match track identity', () {
    late Directory tempDir;
    late Isar isar;
    late ToastService toastService;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'audio_controller_lyrics_auto_match_track_',
      );
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema, LyricsMatchSchema],
        directory: tempDir.path,
        name: 'audio_controller_lyrics_auto_match_track_test',
      );
      toastService = ToastService();
    });

    tearDown(() async {
      toastService.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test(
      'auto-match receives the resolved track, so its key carries the cid',
      () async {
        final queueRepository = QueueRepository(isar);
        final trackRepository = TrackRepository(isar);
        final settingsRepository = SettingsRepository(isar);
        final queuePersistenceManager = QueuePersistenceManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        );
        final streamResolutionService = DefaultStreamResolutionService(
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
          sourceManager: _CidSourceManager(),
          sourceAuthContext: FakeSourceAuthContext(),
        );
        addTearDown(streamResolutionService.dispose);
        final lyricsService = _RecordingLyricsAutoMatchService(isar);

        final controller = buildTestAudioController(
          audioService: FakeAudioService(),
          queueManager: QueueManager(
            queueRepository: queueRepository,
            trackRepository: trackRepository,
            queuePersistenceManager: queuePersistenceManager,
          ),
          audioStreamManager: AudioStreamManager(
            streamResolutionService: streamResolutionService,
            sourceAuthContext: FakeSourceAuthContext(),
          ),
          toastService: toastService,
          nowPlayingPublisher: testNowPlayingPublisher(),
          settingsRepository: settingsRepository,
          lyricsAutoMatchService: lyricsService,
        );

        final settings = await settingsRepository.get();
        settings.autoMatchLyrics = true;
        await settingsRepository.save(settings);
        await controller.initialize();

        // 起播前這首還沒有 cid —— 它要等串流解析才拿得到。
        final track = Track()
          ..sourceType = SourceIds.bilibili
          ..sourceId = 'BV1cY41117NG'
          ..title = 'Lemon'
          ..artist = 'Tester';
        expect(track.cid, isNull);

        await controller.playTrack(track);
        await lyricsService.waitForCallCount(1);

        final playingKey = controller.state.currentTrack!.uniqueKey;
        expect(playingKey, 'bilibili:BV1cY41117NG:$_resolvedCid');
        expect(lyricsService.calls.single.uniqueKey, playingKey);
      },
    );
  });
}

const int _resolvedCid = 965303764;

class _CidSourceManager extends SourceManager {
  _CidSourceManager() : super(sources: const []);

  final _source = _CidAudioStreamSource();

  @override
  AudioStreamSource? audioStreamSource(String type) => _source;

  @override
  void dispose() {}
}

/// 模仿 Bilibili：串流結果帶回 `cid`，`_applyStreamResult` 會就地寫進 track。
class _CidAudioStreamSource implements AudioStreamSource {
  @override
  String get sourceType => SourceIds.bilibili;

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    return AudioStreamResult(
      url: 'https://example.com/${request.sourceId}.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
      cid: request.cid ?? _resolvedCid,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async => null;
}

class _RecordingLyricsAutoMatchService extends LyricsAutoMatchService {
  _RecordingLyricsAutoMatchService(Isar isar)
    : super(
        lrclib: LrclibSource(),
        netease: NeteaseSource(),
        qqmusic: QQMusicSource(),
        repo: LyricsRepository(isar),
        cache: LyricsCacheService(),
        parser: _PassThroughTitleParser(),
      );

  final List<Track> calls = [];
  late final _waiters = CountWaiters(() => calls.length);

  Future<void> waitForCallCount(int count) => _waiters.waitFor(count);

  @override
  Future<bool> tryAutoMatch(
    Track track, {
    List<String>? enabledSources,
    bool? allowPlainLyricsAutoMatch,
  }) async {
    calls.add(track);
    _waiters.notify();
    return false;
  }
}

class _PassThroughTitleParser implements TitleParser {
  @override
  ParsedTitle parse(String title, {String? uploader}) {
    return ParsedTitle(
      trackName: title,
      artistName: uploader,
      cleanedTitle: title,
    );
  }
}
