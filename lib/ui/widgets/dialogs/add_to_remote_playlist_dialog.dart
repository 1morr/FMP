import 'package:flutter/material.dart';

import '../../../data/models/track.dart';
import 'add_to_bilibili_playlist_dialog.dart';
import 'add_to_netease_playlist_dialog.dart';
import 'add_to_youtube_playlist_dialog.dart';

Future<bool> showAddToRemotePlaylistDialog({
  required BuildContext context,
  required Track track,
}) async {
  return showAddToRemotePlaylistDialogMulti(context: context, tracks: [track]);
}

Future<bool> showAddToRemotePlaylistDialogMulti({
  required BuildContext context,
  required List<Track> tracks,
}) async {
  if (tracks.isEmpty) return false;

  final bilibiliTracks =
      tracks.where((t) => t.sourceType == SourceType.bilibili).toList();
  final youtubeTracks =
      tracks.where((t) => t.sourceType == SourceType.youtube).toList();
  final neteaseTracks =
      tracks.where((t) => t.sourceType == SourceType.netease).toList();

  // 提前捕獲 navigator，避免調用方 widget dispose 後 context 失效
  final navigator = Navigator.of(context);
  final overlay = navigator.overlay;

  bool anySuccess = false;

  if (bilibiliTracks.isNotEmpty && overlay != null && overlay.mounted) {
    final result = await showAddToBilibiliPlaylistDialog(
      context: overlay.context,
      tracks: bilibiliTracks,
    );
    if (result) anySuccess = true;
  }

  if (youtubeTracks.isNotEmpty && overlay != null && overlay.mounted) {
    final result = await showAddToYouTubePlaylistDialog(
        context: overlay.context, tracks: youtubeTracks);
    if (result) anySuccess = true;
  }

  if (neteaseTracks.isNotEmpty && overlay != null && overlay.mounted) {
    final result = await showAddToNeteasePlaylistDialog(
        context: overlay.context, tracks: neteaseTracks);
    if (result) anySuccess = true;
  }

  return anySuccess;
}
