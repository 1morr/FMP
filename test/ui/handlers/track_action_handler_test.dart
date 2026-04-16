import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/ui/handlers/track_action_handler.dart';

void main() {
  group('TrackActionHandler', () {
    test('playNext delegates to audio controller and reports success', () async {
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
