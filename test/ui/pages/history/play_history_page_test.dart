import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_history.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_player_selectors.dart';
import 'package:fmp/providers/library/play_history_provider.dart';
import 'package:fmp/ui/handlers/track_action_handler.dart';
import 'package:fmp/ui/pages/history/play_history_page.dart';

void main() {
  group('history page shared track actions', () {
    test('play next and add to queue use the shared handler', () async {
      final audio = _FakeTrackActionAudioController()
        ..addNextResult = true
        ..addToQueueResult = true;
      final sink = _FakeTrackActionFeedbackSink();
      final handler = TrackActionHandler(
        audioController: audio,
        feedbackSink: sink,
      );
      final track = _buildTrack();

      await handler.handle(
        parseTrackAction(playNextTrackActionId),
        track: track,
        isLoggedIn: true,
        onAddToPlaylist: () async => fail('playlist should not be called'),
        onMatchLyrics: () async => fail('lyrics should not be called'),
        onAddToRemote: () async => fail('remote should not be called'),
      );
      await handler.handle(
        parseTrackAction(addToQueueTrackActionId),
        track: track,
        isLoggedIn: true,
        onAddToPlaylist: () async => fail('playlist should not be called'),
        onMatchLyrics: () async => fail('lyrics should not be called'),
        onAddToRemote: () async => fail('remote should not be called'),
      );

      expect(audio.addNextCalls.single.sourceId, 'history-track');
      expect(audio.addToQueueCalls.single.sourceId, 'history-track');
      expect(sink.addedToNext, 1);
      expect(sink.addedToQueue, 1);
    });

    test(
      'playlist and lyrics actions delegate through shared handler',
      () async {
        final audio = _FakeTrackActionAudioController();
        final sink = _FakeTrackActionFeedbackSink();
        final handler = TrackActionHandler(
          audioController: audio,
          feedbackSink: sink,
        );
        var playlistCalls = 0;
        var lyricsCalls = 0;
        final track = _buildTrack();

        await handler.handle(
          parseTrackAction(addToPlaylistTrackActionId),
          track: track,
          isLoggedIn: true,
          onAddToPlaylist: () async => playlistCalls++,
          onMatchLyrics: () async => lyricsCalls++,
          onAddToRemote: () async => fail('remote should not be called'),
        );
        await handler.handle(
          parseTrackAction(matchLyricsTrackActionId),
          track: track,
          isLoggedIn: true,
          onAddToPlaylist: () async => playlistCalls++,
          onMatchLyrics: () async => lyricsCalls++,
          onAddToRemote: () async => fail('remote should not be called'),
        );

        expect(playlistCalls, 1);
        expect(lyricsCalls, 1);
        expect(audio.playTemporaryCalls, isEmpty);
        expect(audio.addNextCalls, isEmpty);
        expect(audio.addToQueueCalls, isEmpty);
      },
    );

    test('delete actions stay local to the history page', () {
      expect(tryParseTrackAction('delete'), isNull);
      expect(tryParseTrackAction('delete_all'), isNull);
    });
  });

  group('history timeline rows', () {
    test(
      'buildHistoryTimelineRows keeps date order and skips collapsed tracks',
      () {
        final newerDate = DateTime(2026, 4, 20);
        final olderDate = DateTime(2026, 4, 19);
        final newerFirst = _buildHistory(id: 1, playedAt: newerDate);
        final newerSecond = _buildHistory(id: 2, playedAt: newerDate);
        final older = _buildHistory(id: 3, playedAt: olderDate);

        final expandedRows = buildHistoryTimelineRows({
          olderDate: [older],
          newerDate: [newerFirst, newerSecond],
        }, {});
        final collapsedRows = buildHistoryTimelineRows(
          {
            olderDate: [older],
            newerDate: [newerFirst, newerSecond],
          },
          {newerDate},
        );

        expect(expandedRows, hasLength(5));
        expect((expandedRows[0] as HistoryDateHeaderRow).date, newerDate);
        expect((expandedRows[1] as HistoryTrackRow).history.id, 1);
        expect((expandedRows[2] as HistoryTrackRow).history.id, 2);
        expect((expandedRows[3] as HistoryDateHeaderRow).date, olderDate);
        expect((expandedRows[4] as HistoryTrackRow).history.id, 3);

        expect(collapsedRows, hasLength(3));
        expect((collapsedRows[0] as HistoryDateHeaderRow).date, newerDate);
        expect((collapsedRows[1] as HistoryDateHeaderRow).date, olderDate);
        expect((collapsedRows[2] as HistoryTrackRow).history.id, 3);
      },
    );
  });

  group('history timeline list', () {
    // 500 筆、分在 5 天。展開成一整串 widget 的寫法在這個量級就會卡住捲動，
    // 而它不會有任何錯誤 —— 只是慢，所以要數實際建出來的列。
    final days = [
      for (var day = 0; day < 5; day++) DateTime(2026, 4, 20 - day),
    ];
    final grouped = {
      for (final (index, date) in days.indexed)
        date: [
          for (var i = 0; i < 100; i++)
            _buildHistory(
              id: index * 100 + i + 1,
              playedAt: date.add(Duration(minutes: 100 - i)),
            ),
        ],
    };

    Future<void> pumpHistoryPage(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      LocaleSettings.setLocale(AppLocale.en);

      await tester.pumpWidget(
        TranslationProvider(
          child: ProviderScope(
            overrides: [
              playHistoryPageProvider.overrideWith(_IdlePlayHistoryPage.new),
              groupedPlayHistoryProvider.overrideWith(
                (ref) => AsyncValue.data(grouped),
              ),
              playHistoryStatsProvider.overrideWith(
                (ref) async => const PlayHistoryStats(
                  totalCount: 500,
                  todayCount: 100,
                  weekCount: 500,
                  totalDurationMs: 0,
                  todayDurationMs: 0,
                  weekDurationMs: 0,
                ),
              ),
              currentTrackProvider.overrideWith((ref) => null),
              registeredSourceTypesProvider.overrideWith(
                (ref) => SourceIds.values,
              ),
            ],
            child: const MaterialApp(home: PlayHistoryPage()),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('only the rows near the viewport are built', (tester) async {
      await pumpHistoryPage(tester);

      final builtTrackRows = find
          .byWidgetPredicate(
            (widget) =>
                _keyValue(widget)?.startsWith('history-track-') ?? false,
          )
          .evaluate()
          .length;

      expect(builtTrackRows, greaterThan(0));
      expect(builtTrackRows, lessThan(60));
    });

    testWidgets('every registered source has a filter chip', (tester) async {
      await pumpHistoryPage(tester);

      // 以前只寫了 Bilibili 與 YouTube 兩個 chip，網易雲的紀錄篩不出來。
      for (final name in ['All', 'Bilibili', 'YouTube', 'NetEase']) {
        expect(find.widgetWithText(ChoiceChip, name), findsOneWidget);
      }
    });

    testWidgets('rows are keyed by stable date and history ids', (
      tester,
    ) async {
      await pumpHistoryPage(tester);

      expect(
        find.byKey(ValueKey('history-date-${days.first.toIso8601String()}')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('history-track-1')), findsOneWidget);
    });
  });
}

String? _keyValue(Widget widget) {
  final key = widget.key;
  return key is ValueKey<String> ? key.value : null;
}

/// 不呼叫 `super.build()`：真的那個會去拿播放歷史的 repository。
class _IdlePlayHistoryPage extends PlayHistoryPageNotifier {
  @override
  PlayHistoryPageState build() => const PlayHistoryPageState();
}

Track _buildTrack() {
  return Track()
    ..sourceId = 'history-track'
    ..sourceType = SourceIds.youtube
    ..title = 'History Track';
}

PlayHistory _buildHistory({required int id, required DateTime playedAt}) {
  return PlayHistory()
    ..id = id
    ..sourceId = 'history-track-$id'
    ..sourceType = SourceIds.youtube
    ..title = 'History Track $id'
    ..playedAt = playedAt;
}

class _FakeTrackActionFeedbackSink implements TrackActionFeedbackSink {
  int addedToNext = 0;
  int addedToQueue = 0;
  int loginPrompts = 0;

  @override
  void showAddedToNext() {
    addedToNext++;
  }

  @override
  void showAddedToQueue() {
    addedToQueue++;
  }

  @override
  void showPleaseLogin() {
    loginPrompts++;
  }
}

class _FakeTrackActionAudioController implements TrackActionAudioController {
  bool addNextResult = false;
  bool addToQueueResult = false;
  final List<Track> playTemporaryCalls = [];
  final List<Track> addNextCalls = [];
  final List<Track> addToQueueCalls = [];

  @override
  Future<bool> addNext(Track track) async {
    addNextCalls.add(track);
    return addNextResult;
  }

  @override
  Future<bool> addToQueue(Track track) async {
    addToQueueCalls.add(track);
    return addToQueueResult;
  }

  @override
  Future<void> playTemporary(Track track) async {
    playTemporaryCalls.add(track);
  }
}
