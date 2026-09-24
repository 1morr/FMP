import 'package:flutter/material.dart';

import 'package:fmp/data/models/track.dart';
import 'package:fmp/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart';
import 'package:fmp/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart';
import 'package:fmp/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart';

Future<bool> showAddToRemotePlaylistDialog({
  required BuildContext context,
  required Track track,
}) async {
  return showAddToRemotePlaylistDialogMulti(context: context, tracks: [track]);
}

typedef _RemotePlaylistDialog =
    Future<bool> Function({
      required BuildContext context,
      required List<Track> tracks,
    });

/// 每個音源自己的遠端歌單對話框，依這個順序逐一顯示。沒有對話框的音源，
/// 它的曲目就不會被加到任何遠端歌單。
const Map<String, _RemotePlaylistDialog> _dialogsBySource = {
  SourceIds.bilibili: showAddToBilibiliPlaylistDialog,
  SourceIds.youtube: showAddToYouTubePlaylistDialog,
  SourceIds.netease: showAddToNeteasePlaylistDialog,
};

Future<bool> showAddToRemotePlaylistDialogMulti({
  required BuildContext context,
  required List<Track> tracks,
}) async {
  if (tracks.isEmpty) return false;

  // 提前捕獲 navigator，避免調用方 widget dispose 後 context 失效
  final navigator = Navigator.of(context);
  final overlay = navigator.overlay;

  bool anySuccess = false;

  for (final MapEntry(key: sourceType, value: showDialog)
      in _dialogsBySource.entries) {
    final sourceTracks = tracks
        .where((t) => t.sourceType == sourceType)
        .toList();
    if (sourceTracks.isEmpty || overlay == null || !overlay.mounted) continue;
    final result = await showDialog(
      context: overlay.context,
      tracks: sourceTracks,
    );
    if (result) anySuccess = true;
  }

  return anySuccess;
}
