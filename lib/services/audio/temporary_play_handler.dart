import 'audio_playback_types.dart';

class TemporaryPlaybackState {
  const TemporaryPlaybackState({
    required this.savedQueueIndex,
    required this.savedPosition,
    required this.savedWasPlaying,
  });

  final int? savedQueueIndex;
  final Duration? savedPosition;
  final bool? savedWasPlaying;

  bool get hasSavedState => savedQueueIndex != null;
}

class RestorePlaybackPlan {
  const RestorePlaybackPlan({
    required this.savedIndex,
    required this.savedPosition,
    required this.savedWasPlaying,
    required this.rewindSeconds,
  });

  final int savedIndex;
  final Duration savedPosition;
  final bool savedWasPlaying;
  final int rewindSeconds;
}

class TemporaryPlayHandler {
  const TemporaryPlayHandler();

  TemporaryPlaybackState enterTemporary({
    required PlayMode currentMode,
    required TemporaryPlaybackState currentState,
    required bool hasQueueTrack,
    required int currentIndex,
    required Duration currentPosition,
    required bool currentWasPlaying,
  }) {
    if (currentMode == PlayMode.temporary) {
      return currentState;
    }
    if (!hasQueueTrack) {
      return const TemporaryPlaybackState(
        savedQueueIndex: null,
        savedPosition: null,
        savedWasPlaying: null,
      );
    }
    return TemporaryPlaybackState(
      savedQueueIndex: currentIndex,
      savedPosition: currentPosition,
      savedWasPlaying: currentWasPlaying,
    );
  }

  RestorePlaybackPlan? buildQueueRestorePlan({
    required int? savedQueueIndex,
    required Duration savedPosition,
    required bool savedWasPlaying,
  }) {
    if (savedQueueIndex == null) {
      return null;
    }

    return RestorePlaybackPlan(
      savedIndex: savedQueueIndex,
      savedPosition: savedPosition,
      savedWasPlaying: savedWasPlaying,
      rewindSeconds: 0,
    );
  }

  RestorePlaybackPlan? buildRestorePlan({
    required TemporaryPlaybackState state,
    required bool rememberPosition,
    required int rewindSeconds,
  }) {
    final savedIndex = state.savedQueueIndex;
    if (savedIndex == null) {
      return null;
    }

    return RestorePlaybackPlan(
      savedIndex: savedIndex,
      savedPosition:
          rememberPosition ? (state.savedPosition ?? Duration.zero) : Duration.zero,
      savedWasPlaying: state.savedWasPlaying ?? false,
      rewindSeconds: rememberPosition ? rewindSeconds : 0,
    );
  }
}
