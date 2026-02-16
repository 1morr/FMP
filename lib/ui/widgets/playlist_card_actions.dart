import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/toast_service.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../services/audio/audio_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../data/sources/source_provider.dart';
import '../../i18n/strings.g.dart';

/// PlaylistCard 共享操作工具类
class PlaylistCardActions {
  /// 添加歌单所有歌曲到队列
  static Future<void> addAllToQueue(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final service = ref.read(playlistServiceProvider);
    final result = await service.getPlaylistWithTracks(playlist.id);

    if (result == null || result.tracks.isEmpty) {
      if (context.mounted) {
        ToastService.warning(context, t.library.main.playlistEmpty);
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final added = await controller.addAllToQueue(result.tracks);

    if (added && context.mounted) {
      ToastService.success(context, t.library.addedToQueue(n: result.tracks.length));
    }
  }

  /// 随机添加歌单所有歌曲到队列
  static Future<void> shuffleAddToQueue(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final service = ref.read(playlistServiceProvider);
    final result = await service.getPlaylistWithTracks(playlist.id);

    if (result == null || result.tracks.isEmpty) {
      if (context.mounted) {
        ToastService.warning(context, t.library.main.playlistEmpty);
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(result.tracks)..shuffle();
    final added = await controller.addAllToQueue(shuffled);

    if (added && context.mounted) {
      ToastService.success(context, t.library.shuffledAddedToQueue(n: result.tracks.length));
    }
  }

  /// 播放 Mix 歌单
  static Future<void> playMix(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    if (playlist.mixPlaylistId == null || playlist.mixSeedVideoId == null) {
      ToastService.error(context, t.library.main.mixInfoIncomplete);
      return;
    }

    try {
      final youtubeSource = ref.read(youtubeSourceProvider);
      final result = await youtubeSource.fetchMixTracks(
        playlistId: playlist.mixPlaylistId!,
        currentVideoId: playlist.mixSeedVideoId!,
      );

      if (result.tracks.isEmpty) {
        if (context.mounted) {
          ToastService.error(context, t.library.main.cannotLoadMix);
        }
        return;
      }

      final controller = ref.read(audioControllerProvider.notifier);
      await controller.playMixPlaylist(
        playlistId: playlist.mixPlaylistId!,
        seedVideoId: playlist.mixSeedVideoId!,
        title: playlist.name,
        tracks: result.tracks,
      );
    } catch (e) {
      if (context.mounted) {
        ToastService.error(context, '${t.library.main.playMixFailed}: $e');
      }
    }
  }
}
