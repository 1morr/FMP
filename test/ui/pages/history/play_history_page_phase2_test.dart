import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/ui/handlers/track_action_handler.dart';
import 'package:fmp/ui/pages/history/play_history_page.dart';

void main() {
  group('history page shared track actions', () {
    test('play next and add to queue keep history feedback callbacks',
        () async {
      final audio = _FakeTrackActionAudioController()
        ..addNextResult = true
        ..addToQueueResult = true;
      var addedToNextToasts = 0;
      var addedToQueueToasts = 0;
      var playlistCalls = 0;
      var lyricsCalls = 0;
      final track = _buildTrack();

      final handledPlayNext = await handleHistorySharedTrackAction(
        action: 'play_next',
        track: track,
        audioController: audio,
        onAddedToNext: () => addedToNextToasts++,
        onAddedToQueue: () => addedToQueueToasts++,
        onAddToPlaylist: () async => playlistCalls++,
        onMatchLyrics: () async => lyricsCalls++,
      );
      final handledAddToQueue = await handleHistorySharedTrackAction(
        action: 'add_to_queue',
        track: track,
        audioController: audio,
        onAddedToNext: () => addedToNextToasts++,
        onAddedToQueue: () => addedToQueueToasts++,
        onAddToPlaylist: () async => playlistCalls++,
        onMatchLyrics: () async => lyricsCalls++,
      );

      expect(handledPlayNext, isTrue);
      expect(handledAddToQueue, isTrue);
      expect(audio.addNextCalls.single.sourceId, 'history-track');
      expect(audio.addToQueueCalls.single.sourceId, 'history-track');
      expect(addedToNextToasts, 1);
      expect(addedToQueueToasts, 1);
      expect(playlistCalls, 0);
      expect(lyricsCalls, 0);
    });

    test('playlist and lyrics actions delegate through shared handler',
        () async {
      final audio = _FakeTrackActionAudioController();
      var playlistCalls = 0;
      var lyricsCalls = 0;
      final track = _buildTrack();

      final handledAddToPlaylist = await handleHistorySharedTrackAction(
        action: 'add_to_playlist',
        track: track,
        audioController: audio,
        onAddedToNext: () {},
        onAddedToQueue: () {},
        onAddToPlaylist: () async => playlistCalls++,
        onMatchLyrics: () async => lyricsCalls++,
      );
      final handledMatchLyrics = await handleHistorySharedTrackAction(
        action: 'matchLyrics',
        track: track,
        audioController: audio,
        onAddedToNext: () {},
        onAddedToQueue: () {},
        onAddToPlaylist: () async => playlistCalls++,
        onMatchLyrics: () async => lyricsCalls++,
      );

      expect(handledAddToPlaylist, isTrue);
      expect(handledMatchLyrics, isTrue);
      expect(playlistCalls, 1);
      expect(lyricsCalls, 1);
      expect(audio.playTemporaryCalls, isEmpty);
      expect(audio.addNextCalls, isEmpty);
      expect(audio.addToQueueCalls, isEmpty);
    });

    test('delete actions stay local to the history page', () async {
      final audio = _FakeTrackActionAudioController();
      final track = _buildTrack();

      final handledDelete = await handleHistorySharedTrackAction(
        action: 'delete',
        track: track,
        audioController: audio,
        onAddedToNext: () => fail('delete should stay local'),
        onAddedToQueue: () => fail('delete should stay local'),
        onAddToPlaylist: () async => fail('delete should stay local'),
        onMatchLyrics: () async => fail('delete should stay local'),
      );
      final handledDeleteAll = await handleHistorySharedTrackAction(
        action: 'delete_all',
        track: track,
        audioController: audio,
        onAddedToNext: () => fail('delete_all should stay local'),
        onAddedToQueue: () => fail('delete_all should stay local'),
        onAddToPlaylist: () async => fail('delete_all should stay local'),
        onMatchLyrics: () async => fail('delete_all should stay local'),
      );

      expect(handledDelete, isFalse);
      expect(handledDeleteAll, isFalse);
      expect(audio.playTemporaryCalls, isEmpty);
      expect(audio.addNextCalls, isEmpty);
      expect(audio.addToQueueCalls, isEmpty);
    });
  });

  group('history page lazy timeline structure', () {
    test('timeline list does not expand grouped histories with spread map', () {
      final source = File('lib/ui/pages/history/play_history_page.dart')
          .readAsStringSync();
      final timelineBody = _methodBody(source, '_buildTimelineList');
      final dateGroupBody = _methodBody(source, '_buildDateHeader');

      expect(timelineBody, contains('ListView.builder'));
      expect(dateGroupBody, isNot(contains('...histories.map')));
      expect(timelineBody, contains('HistoryTimelineRow'));
    });
  });
}

String _methodBody(String source, String name) {
  final match =
      RegExp('(?:^|\\n)\\s*[\\w<>?]+\\s+$name' r'\s*\(').firstMatch(source);
  expect(match, isNotNull, reason: 'method $name should exist');
  final firstBrace = source.indexOf('{', match!.start);
  var depth = 0;
  for (var i = firstBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) return source.substring(firstBrace, i + 1);
  }
  fail('method $name body did not close');
}

Track _buildTrack() {
  return Track()
    ..sourceId = 'history-track'
    ..sourceType = SourceType.youtube
    ..title = 'History Track';
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
