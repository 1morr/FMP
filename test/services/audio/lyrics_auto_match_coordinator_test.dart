import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/services/audio/lyrics_auto_match_coordinator.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:fmp/services/lyrics/title_parser.dart';
import 'package:isar_community/isar.dart';

import '../../support/isar_test_harness.dart';

/// `LyricsAutoMatchCoordinator` 是 Phase 4 步驟 D 從 `AudioController` 抽出來的
/// 第二個副作用協作者。
///
/// 它負責的是「何時比對、要不要比對、以及哪一次比對的結果還算數」；怎麼比對是
/// `LyricsAutoMatchService` 的事。所以這裡完全不驗歌詞內容，只驗閘門與代際。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsAutoMatchCoordinator', () {
    late Directory tempDir;
    late Isar isar;
    late SettingsRepository settingsRepository;
    late _RecordingLyricsAutoMatchService service;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lyrics_coordinator_');
      isar = await Isar.open(
        [SettingsSchema, LyricsMatchSchema],
        directory: tempDir.path,
        name: 'lyrics_coordinator_test',
      );
      settingsRepository = SettingsRepository(isar);
      await settingsRepository.update((s) => s.autoMatchLyrics = true);
      service = _RecordingLyricsAutoMatchService(isar);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    LyricsAutoMatchCoordinator build() => LyricsAutoMatchCoordinator(
          service: service,
          settingsRepository: settingsRepository,
        );

    test('does not block the caller', () async {
      final coordinator = build();
      final gate = service.enqueuePending();

      coordinator.onTrackStarted(_track('a'));

      // 還卡在 gate 上，但呼叫早就回來了。
      expect(service.calls, isEmpty);
      await service.waitForCallCount(1);
      gate.complete();
    });

    test('skips the service entirely when the setting is off', () async {
      await settingsRepository.update((s) => s.autoMatchLyrics = false);
      final coordinator = build();

      coordinator.onTrackStarted(_track('a'));
      await pumpEventQueue();

      expect(service.calls, isEmpty);
    });

    test('drops the source priority entries the user disabled', () async {
      await settingsRepository.update((s) {
        s.lyricsSourcePriorityList = ['netease', 'qqmusic', 'lrclib'];
        s.disabledLyricsSourcesSet = {'qqmusic'};
      });
      final coordinator = build();

      coordinator.onTrackStarted(_track('a'));
      await service.waitForCallCount(1);

      expect(service.enabledSourceCalls.single, ['netease', 'lrclib']);
    });

    test('a stale match cannot clear the state of a newer one', () async {
      final coordinator = build();
      final states = <bool>[];
      coordinator.onStateChanged = states.add;

      final firstGate = service.enqueuePending();
      final secondGate = service.enqueuePending();

      coordinator.onTrackStarted(_track('a'));
      await service.waitForCallCount(1);
      coordinator.onTrackStarted(_track('b'));
      await service.waitForCallCount(2);

      // 舊的先回來。它不可以把「正在比對」關掉 —— 新的還在跑。
      firstGate.complete();
      await pumpEventQueue();
      expect(states.last, isTrue);

      secondGate.complete();
      await pumpEventQueue();
      expect(states.last, isFalse);
    });

    test('stops reporting after dispose', () async {
      final coordinator = build();
      final states = <bool>[];
      coordinator.onStateChanged = states.add;

      final gate = service.enqueuePending();
      coordinator.onTrackStarted(_track('a'));
      await service.waitForCallCount(1);
      expect(states, [true]);

      coordinator.dispose();
      gate.complete();
      await pumpEventQueue();

      // dispose 之後那次比對回來，不能再碰已經沒人在聽的 UI。
      expect(states, [true]);
    });

    test('does nothing when the database is not available', () async {
      final coordinator = LyricsAutoMatchCoordinator(service: service);

      coordinator.onTrackStarted(_track('a'));
      await pumpEventQueue();

      expect(service.calls, isEmpty);
    });
  });
}

/// 只記錄呼叫並讓測試控制回傳時機，不做任何真的網路查詢。
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
  final List<List<String>?> enabledSourceCalls = [];
  final List<Completer<void>> _pending = [];
  final List<_CountWaiter> _waiters = [];

  Completer<void> enqueuePending() {
    final completer = Completer<void>();
    _pending.add(completer);
    return completer;
  }

  Future<void> waitForCallCount(int count) {
    if (calls.length >= count) return Future.value();
    final completer = Completer<void>();
    _waiters.add(_CountWaiter(count, completer));
    return completer.future;
  }

  @override
  Future<bool> tryAutoMatch(
    Track track, {
    List<String>? enabledSources,
    bool? allowPlainLyricsAutoMatch,
  }) async {
    calls.add(track);
    enabledSourceCalls.add(enabledSources);
    for (final waiter in List<_CountWaiter>.from(_waiters)) {
      if (calls.length >= waiter.target && !waiter.completer.isCompleted) {
        waiter.completer.complete();
        _waiters.remove(waiter);
      }
    }
    if (_pending.isEmpty) return false;
    await _pending.removeAt(0).future;
    return true;
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

class _CountWaiter {
  _CountWaiter(this.target, this.completer);
  final int target;
  final Completer<void> completer;
}

Track _track(String sourceId) => Track()
  ..sourceId = sourceId
  ..sourceType = SourceIds.youtube
  ..title = 'Track $sourceId';
