import 'audio_playback_types.dart';

class TemporaryPlaybackState {
  const TemporaryPlaybackState({
    required this.mode,
    required this.savedQueueIndex,
    required this.savedPosition,
    required this.savedWasPlaying,
  });

  final PlayMode mode;
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
    required this.shouldClearSavedState,
  });

  final int savedIndex;
  final Duration savedPosition;
  final bool savedWasPlaying;
  final int rewindSeconds;
  final bool shouldClearSavedState;
}

class TemporaryPlayHandler {
  const TemporaryPlayHandler();

  TemporaryPlaybackState enterTemporary({
    required TemporaryPlaybackState current,
    required bool hasQueueTrack,
    required int currentIndex,
    required Duration savedPosition,
    required bool savedWasPlaying,
  }) {
    if (current.mode == PlayMode.temporary) {
      return current;
    }
    if (!hasQueueTrack) {
      return const TemporaryPlaybackState(
        mode: PlayMode.temporary,
        savedQueueIndex: null,
        savedPosition: null,
        savedWasPlaying: null,
      );
    }
    return TemporaryPlaybackState(
      mode: PlayMode.temporary,
      savedQueueIndex: currentIndex,
      savedPosition: savedPosition,
      savedWasPlaying: savedWasPlaying,
    );
  }

  RestorePlaybackPlan? buildRestorePlan({
    required TemporaryPlaybackState state,
    required bool restorePositionEnabled,
    required int tempPlayRewindSeconds,
  }) {
    final savedIndex = state.savedQueueIndex;
    if (savedIndex == null) {
      return null;
    }

    return RestorePlaybackPlan(
      savedIndex: savedIndex,
      savedPosition: restorePositionEnabled
          ? (state.savedPosition ?? Duration.zero)
          : Duration.zero,
      savedWasPlaying: state.savedWasPlaying ?? false,
      rewindSeconds: restorePositionEnabled ? tempPlayRewindSeconds : 0,
      shouldClearSavedState: true,
    );
  }
}
