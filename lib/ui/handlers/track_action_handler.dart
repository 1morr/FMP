import '../../data/models/track.dart';
import '../../services/audio/audio_provider.dart';

const playTrackActionId = 'play';
const playNextTrackActionId = 'play_next';
const addToQueueTrackActionId = 'add_to_queue';
const addToPlaylistTrackActionId = 'add_to_playlist';
const matchLyricsTrackActionId = 'matchLyrics';
const addToRemoteTrackActionId = 'add_to_remote';

enum TrackAction {
  play,
  playNext,
  addToQueue,
  addToPlaylist,
  matchLyrics,
  addToRemote,
}

extension TrackActionMenuId on TrackAction {
  String get menuId {
    switch (this) {
      case TrackAction.play:
        return playTrackActionId;
      case TrackAction.playNext:
        return playNextTrackActionId;
      case TrackAction.addToQueue:
        return addToQueueTrackActionId;
      case TrackAction.addToPlaylist:
        return addToPlaylistTrackActionId;
      case TrackAction.matchLyrics:
        return matchLyricsTrackActionId;
      case TrackAction.addToRemote:
        return addToRemoteTrackActionId;
    }
  }
}

TrackAction? tryParseTrackAction(String action) {
  switch (action) {
    case playTrackActionId:
      return TrackAction.play;
    case playNextTrackActionId:
      return TrackAction.playNext;
    case addToQueueTrackActionId:
      return TrackAction.addToQueue;
    case addToPlaylistTrackActionId:
      return TrackAction.addToPlaylist;
    case matchLyricsTrackActionId:
      return TrackAction.matchLyrics;
    case addToRemoteTrackActionId:
      return TrackAction.addToRemote;
  }

  return null;
}

TrackAction parseTrackAction(String action) {
  final parsedAction = tryParseTrackAction(action);
  if (parsedAction != null) {
    return parsedAction;
  }

  throw ArgumentError('Unsupported track action: $action');
}

abstract class TrackActionAudioController {
  Future<void> playTemporary(Track track);
  Future<bool> addNext(Track track);
  Future<bool> addToQueue(Track track);
}

class AudioControllerTrackActionAdapter implements TrackActionAudioController {
  AudioControllerTrackActionAdapter(this._audioController);

  final AudioController _audioController;

  @override
  Future<bool> addNext(Track track) => _audioController.addNext(track);

  @override
  Future<bool> addToQueue(Track track) => _audioController.addToQueue(track);

  @override
  Future<void> playTemporary(Track track) => _audioController.playTemporary(track);
}

abstract class TrackActionFeedbackSink {
  void showAddedToNext();
  void showAddedToQueue();
  void showPleaseLogin();
}

class CallbackTrackActionFeedbackSink implements TrackActionFeedbackSink {
  CallbackTrackActionFeedbackSink({
    required this.onAddedToNext,
    required this.onAddedToQueue,
    required this.onPleaseLogin,
  });

  final void Function() onAddedToNext;
  final void Function() onAddedToQueue;
  final void Function() onPleaseLogin;

  @override
  void showAddedToNext() => onAddedToNext();

  @override
  void showAddedToQueue() => onAddedToQueue();

  @override
  void showPleaseLogin() => onPleaseLogin();
}

class TrackActionHandler {
  TrackActionHandler({
    required TrackActionAudioController audioController,
    required TrackActionFeedbackSink feedbackSink,
  })  : _audioController = audioController,
        _feedbackSink = feedbackSink;

  final TrackActionAudioController _audioController;
  final TrackActionFeedbackSink _feedbackSink;

  Future<void> handle(
    TrackAction action, {
    required Track track,
    required bool isLoggedIn,
    required Future<void> Function() onAddToPlaylist,
    required Future<void> Function() onMatchLyrics,
    required Future<void> Function() onAddToRemote,
  }) async {
    switch (action) {
      case TrackAction.play:
        await _audioController.playTemporary(track);
        return;
      case TrackAction.playNext:
        final added = await _audioController.addNext(track);
        if (added) {
          _feedbackSink.showAddedToNext();
        }
        return;
      case TrackAction.addToQueue:
        final added = await _audioController.addToQueue(track);
        if (added) {
          _feedbackSink.showAddedToQueue();
        }
        return;
      case TrackAction.addToPlaylist:
        await onAddToPlaylist();
        return;
      case TrackAction.matchLyrics:
        await onMatchLyrics();
        return;
      case TrackAction.addToRemote:
        if (!isLoggedIn) {
          _feedbackSink.showPleaseLogin();
          return;
        }
        await onAddToRemote();
        return;
    }
  }
}
