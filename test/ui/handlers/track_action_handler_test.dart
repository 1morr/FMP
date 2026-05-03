import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/ui/handlers/track_action_handler.dart';

void main() {
  group('TrackActionHandler', () {
    test('playNext delegates to audio controller and reports success',
        () async {
      final audio = FakeTrackActionAudioController()..addNextResult = true;
      final sink = FakeTrackActionFeedbackSink();
      final handler = TrackActionHandler(
        audioController: audio,
        feedbackSink: sink,
      );
      final track = buildTrack(sourceId: 'track-1', title: 'Track 1');

      await handler.handle(
        TrackAction.playNext,
        track: track,
        isLoggedIn: true,
        onAddToPlaylist: () async {},
        onMatchLyrics: () async {},
        onAddToRemote: () async {},
      );

      expect(audio.addNextCalls.single.sourceId, 'track-1');
      expect(sink.successMessages.single, contains('added'));
    });

    test('addToRemote requests login feedback when logged out', () async {
      final audio = FakeTrackActionAudioController();
      final sink = FakeTrackActionFeedbackSink();
      var remoteCalls = 0;
      final handler = TrackActionHandler(
        audioController: audio,
        feedbackSink: sink,
      );
      final track = buildTrack(sourceId: 'track-2', title: 'Track 2');

      await handler.handle(
        TrackAction.addToRemote,
        track: track,
        isLoggedIn: false,
        onAddToPlaylist: () async {},
        onMatchLyrics: () async {},
        onAddToRemote: () async {
          remoteCalls++;
        },
      );

      expect(remoteCalls, 0);
      expect(sink.loginPrompts, 1);
    });

    test('track actions expose stable menu ids', () {
      expect(TrackAction.play.menuId, playTrackActionId);
      expect(TrackAction.playNext.menuId, playNextTrackActionId);
      expect(TrackAction.addToQueue.menuId, addToQueueTrackActionId);
      expect(TrackAction.addToPlaylist.menuId, addToPlaylistTrackActionId);
      expect(TrackAction.matchLyrics.menuId, matchLyricsTrackActionId);
      expect(TrackAction.addToRemote.menuId, addToRemoteTrackActionId);
    });

    test('multi addToQueue delegates each selected track and reports count',
        () async {
      final audio = FakeTrackActionAudioController()..addToQueueResult = true;
      final sink = FakeMultiTrackActionFeedbackSink();
      final handler = MultiTrackActionHandler(
        audioController: audio,
        feedbackSink: sink,
      );
      final tracks = [
        buildTrack(sourceId: 'track-1', title: 'Track 1'),
        buildTrack(sourceId: 'track-2', title: 'Track 2'),
      ];

      await handler.handle(
        TrackAction.addToQueue,
        tracks: tracks,
        isLoggedIn: (_) => true,
        onAddToPlaylist: () async {},
        onAddToRemote: (_) async {},
      );

      expect(audio.addToQueueCalls.map((track) => track.sourceId), [
        'track-1',
        'track-2',
      ]);
      expect(sink.addedToQueueCounts, [2]);
    });

    test('multi playNext adds tracks in reverse to preserve visible order',
        () async {
      final audio = FakeTrackActionAudioController()..addNextResult = true;
      final sink = FakeMultiTrackActionFeedbackSink();
      final handler = MultiTrackActionHandler(
        audioController: audio,
        feedbackSink: sink,
      );
      final tracks = [
        buildTrack(sourceId: 'track-1', title: 'Track 1'),
        buildTrack(sourceId: 'track-2', title: 'Track 2'),
      ];

      await handler.handle(
        TrackAction.playNext,
        tracks: tracks,
        isLoggedIn: (_) => true,
        onAddToPlaylist: () async {},
        onAddToRemote: (_) async {},
      );

      expect(audio.addNextCalls.map((track) => track.sourceId), [
        'track-2',
        'track-1',
      ]);
      expect(sink.addedToNextCounts, [2]);
    });

    test(
        'multi addToRemote filters logged-out platforms and reports skipped platforms',
        () async {
      final audio = FakeTrackActionAudioController();
      final sink = FakeMultiTrackActionFeedbackSink();
      final handler = MultiTrackActionHandler(
        audioController: audio,
        feedbackSink: sink,
      );
      final bilibiliTrack = buildTrack(sourceId: 'track-1', title: 'Track 1')
        ..sourceType = SourceType.bilibili;
      final youtubeTrack = buildTrack(sourceId: 'track-2', title: 'Track 2')
        ..sourceType = SourceType.youtube;
      var remoteTracks = <Track>[];

      await handler.handle(
        TrackAction.addToRemote,
        tracks: [bilibiliTrack, youtubeTrack],
        isLoggedIn: (sourceType) => sourceType == SourceType.bilibili,
        onAddToPlaylist: () async {},
        onAddToRemote: (tracks) async {
          remoteTracks = tracks;
        },
      );

      expect(remoteTracks, [bilibiliTrack]);
      expect(
        sink.skippedPlatformMessages.single,
        contains(SourceType.youtube.displayName),
      );
    });
  });
}

Track buildTrack({
  required String sourceId,
  required String title,
}) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.bilibili
    ..title = title;
}

class FakeTrackActionAudioController implements TrackActionAudioController {
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

class FakeTrackActionFeedbackSink implements TrackActionFeedbackSink {
  final List<String> successMessages = [];
  int loginPrompts = 0;

  @override
  void showAddedToNext() {
    successMessages.add('added to next');
  }

  @override
  void showAddedToQueue() {
    successMessages.add('added to queue');
  }

  @override
  void showPleaseLogin() {
    loginPrompts++;
  }
}

class FakeMultiTrackActionFeedbackSink implements MultiTrackActionFeedbackSink {
  final List<int> addedToNextCounts = [];
  final List<int> addedToQueueCounts = [];
  final List<String> skippedPlatformMessages = [];
  int loginPrompts = 0;

  @override
  void showAddedToNext(int count) {
    addedToNextCounts.add(count);
  }

  @override
  void showAddedToQueue(int count) {
    addedToQueueCounts.add(count);
  }

  @override
  void showPleaseLogin() {
    loginPrompts++;
  }

  @override
  void showSkippedNotLoggedIn(Set<String> platforms) {
    skippedPlatformMessages.add(platforms.join('、'));
  }
}
