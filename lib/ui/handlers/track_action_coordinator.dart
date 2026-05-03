import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/toast_service.dart';
import '../../data/models/track.dart';
import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../services/audio/audio_provider.dart';
import '../pages/lyrics/lyrics_search_sheet.dart';
import '../widgets/dialogs/add_to_playlist_dialog.dart';
import '../widgets/dialogs/add_to_remote_playlist_dialog.dart';
import 'track_action_handler.dart';

class TrackActionCoordinator {
  const TrackActionCoordinator._();

  static Future<void> handleSingle({
    required BuildContext context,
    required WidgetRef ref,
    required Track track,
    required String actionId,
  }) async {
    final handler = TrackActionHandler(
      audioController: AudioControllerTrackActionAdapter(
        ref.read(audioControllerProvider.notifier),
      ),
      feedbackSink: CallbackTrackActionFeedbackSink(
        onAddedToNext: () {
          if (context.mounted) {
            ToastService.success(context, t.general.addedToNext);
          }
        },
        onAddedToQueue: () {
          if (context.mounted) {
            ToastService.success(context, t.general.addedToQueue);
          }
        },
        onPleaseLogin: () {
          if (context.mounted) {
            ToastService.show(context, t.remote.pleaseLogin);
          }
        },
      ),
    );

    await handler.handle(
      parseTrackAction(actionId),
      track: track,
      isLoggedIn: ref.read(isLoggedInProvider(track.sourceType)),
      onAddToPlaylist: () async {
        if (context.mounted) {
          await showAddToPlaylistDialog(context: context, track: track);
        }
      },
      onMatchLyrics: () async {
        if (context.mounted) {
          showLyricsSearchSheet(context: context, track: track);
        }
      },
      onAddToRemote: () async {
        if (context.mounted) {
          await showAddToRemotePlaylistDialog(context: context, track: track);
        }
      },
    );
  }

  static Future<void> handleMulti({
    required BuildContext context,
    required WidgetRef ref,
    required List<Track> tracks,
    required String actionId,
  }) async {
    final handler = MultiTrackActionHandler(
      audioController: AudioControllerTrackActionAdapter(
        ref.read(audioControllerProvider.notifier),
      ),
      feedbackSink: CallbackMultiTrackActionFeedbackSink(
        onAddedToNext: (count) {
          if (context.mounted) {
            ToastService.success(
              context,
              t.selectionMode.addedToNext(count: count),
            );
          }
        },
        onAddedToQueue: (count) {
          if (context.mounted) {
            ToastService.success(
              context,
              t.selectionMode.addedToQueue(count: count),
            );
          }
        },
        onPleaseLogin: () {
          if (context.mounted) {
            ToastService.show(context, t.remote.pleaseLogin);
          }
        },
        onSkippedNotLoggedIn: (platforms) {
          if (context.mounted) {
            ToastService.show(
              context,
              t.remote.skippedNotLoggedIn(platforms: platforms.join('、')),
            );
          }
        },
      ),
    );

    await handler.handle(
      parseTrackAction(actionId),
      tracks: tracks,
      isLoggedIn: (sourceType) => ref.read(isLoggedInProvider(sourceType)),
      onAddToPlaylist: () async {
        if (context.mounted) {
          await showAddToPlaylistDialog(context: context, tracks: tracks);
        }
      },
      onAddToRemote: (remoteTracks) async {
        if (context.mounted) {
          await showAddToRemotePlaylistDialogMulti(
            context: context,
            tracks: remoteTracks,
          );
        }
      },
    );
  }
}
