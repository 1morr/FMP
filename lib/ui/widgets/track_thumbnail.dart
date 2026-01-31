import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/track_extensions.dart';
import '../../core/services/image_loading_service.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../providers/download/file_exists_cache.dart';
import '../../services/library/playlist_service.dart';
import 'now_playing_indicator.dart';

/// 统一的歌曲封面缩略图组件
///
/// 功能：
/// - 优先显示本地封面（已下载歌曲）
/// - 回退到网络封面
/// - 无封面时显示占位符
/// - 支持播放中指示器覆盖
class TrackThumbnail extends ConsumerWidget {
  /// 歌曲数据
  final Track track;

  /// 缩略图尺寸（宽高相等）
  final double size;

  /// 是否显示播放中指示器
  final bool showPlayingIndicator;

  /// 是否正在播放此歌曲
  final bool isPlaying;

  /// 圆角半径
  final double borderRadius;

  /// 占位符图标大小（默认为 size 的一半）
  final double? iconSize;

  const TrackThumbnail({
    super.key,
    required this.track,
    this.size = 48,
    this.showPlayingIndicator = true,
    this.isPlaying = false,
    this.borderRadius = 4,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // Watch 文件存在缓存，以便在缓存更新时重建
    ref.watch(fileExistsCacheProvider);
    final cache = ref.read(fileExistsCacheProvider.notifier);

    return SizedBox(
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: colorScheme.surfaceContainerHighest,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(colorScheme, cache, ref),
            if (showPlayingIndicator && isPlaying)
              _buildPlayingOverlay(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(ColorScheme colorScheme, FileExistsCache cache, WidgetRef ref) {
    final placeholder = _buildPlaceholder(colorScheme);

    // 使用 FileExistsCache 获取本地封面路径（避免同步 IO）
    final localCoverPath = track.getLocalCoverPath(cache);

    // 注意：不再根据封面是否存在来清除下载路径
    // 因为下载音频不一定有封面，这会导致误删刚下载的音频路径
    // 无效路径由应用启动时的 cleanupInvalidDownloadPaths() 统一清理

    return ImageLoadingService.loadImage(
      localPath: localCoverPath,
      networkUrl: track.thumbnailUrl,
      placeholder: placeholder,
      fit: BoxFit.cover,
      width: size,
      height: size,
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.music_note,
        size: iconSize ?? size * 0.5,
        color: colorScheme.outline,
      ),
    );
  }

  Widget _buildPlayingOverlay(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: colorScheme.primary.withValues(alpha: 0.8),
      ),
      child: Center(
        child: NowPlayingIndicator(
          size: size * 0.5,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 大尺寸封面图片组件（用于播放页面等）
///
/// 与 TrackThumbnail 类似，但支持：
/// - 更大的尺寸
/// - 16:9 宽高比
/// - 加载指示器
class TrackCover extends ConsumerWidget {
  /// 歌曲数据
  final Track? track;

  /// 网络封面 URL（优先于 track.thumbnailUrl）
  final String? networkUrl;

  /// 宽高比（默认 16:9）
  final double aspectRatio;

  /// 圆角半径
  final double borderRadius;

  /// 是否显示加载指示器
  final bool showLoadingIndicator;

  const TrackCover({
    super.key,
    this.track,
    this.networkUrl,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 16,
    this.showLoadingIndicator = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // Watch 文件存在缓存，以便在缓存更新时重建
    ref.watch(fileExistsCacheProvider);
    final cache = ref.read(fileExistsCacheProvider.notifier);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          color: colorScheme.surfaceContainerHighest,
          child: _buildImage(colorScheme, cache),
        ),
      ),
    );
  }

  Widget _buildImage(ColorScheme colorScheme, FileExistsCache cache) {
    final placeholder = _buildPlaceholder(colorScheme);

    // 使用 FileExistsCache 获取本地封面路径（避免同步 IO）
    return ImageLoadingService.loadImage(
      localPath: track?.getLocalCoverPath(cache),
      networkUrl: networkUrl ?? track?.thumbnailUrl,
      placeholder: placeholder,
      fit: BoxFit.cover,
      showLoadingIndicator: showLoadingIndicator,
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.music_note,
        size: 48,
        color: colorScheme.outline,
      ),
    );
  }
}

/// 统一的歌单封面缩略图组件
///
/// 功能：
/// - 优先显示本地封面（已下载歌单封面）
/// - 回退到第一首歌的本地/网络封面
/// - 无封面时显示占位符
///
/// 使用示例：
/// ```dart
/// PlaylistThumbnail(
///   playlist: playlist,
///   coverData: coverData, // 从 playlistCoverProvider 获取
///   size: 120,
/// )
/// ```
class PlaylistThumbnail extends ConsumerWidget {
  /// 歌单数据
  final Playlist playlist;

  /// 封面数据（从 playlistCoverProvider 获取）
  final PlaylistCoverData? coverData;

  /// 缩略图尺寸（宽高相等）
  final double size;

  /// 圆角半径
  final double borderRadius;

  /// 占位符图标
  final IconData placeholderIcon;

  /// 占位符图标大小（默认为 size 的一半）
  final double? iconSize;

  const PlaylistThumbnail({
    super.key,
    required this.playlist,
    this.coverData,
    this.size = 48,
    this.borderRadius = 8,
    this.placeholderIcon = Icons.album,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // Watch 文件存在缓存，以便在缓存更新时重建
    ref.watch(fileExistsCacheProvider);
    final cache = ref.read(fileExistsCacheProvider.notifier);

    return SizedBox(
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: colorScheme.surfaceContainerHighest,
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildImage(colorScheme, cache),
      ),
    );
  }

  Widget _buildImage(ColorScheme colorScheme, FileExistsCache cache) {
    final placeholder = _buildPlaceholder(colorScheme);

    // 如果有 coverData，使用它
    if (coverData != null) {
      return ImageLoadingService.loadImage(
        localPath: coverData!.localPath,
        networkUrl: coverData!.networkUrl,
        placeholder: placeholder,
        fit: BoxFit.cover,
        width: size,
        height: size,
      );
    }

    // 否则直接使用 playlist 信息（不包含第一首歌的封面）
    return ImageLoadingService.loadPlaylistCover(
      playlist,
      cache: cache,
      size: size,
      borderRadius: borderRadius,
      placeholderIcon: placeholderIcon,
      placeholderIconSize: iconSize,
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        placeholderIcon,
        size: iconSize ?? size * 0.5,
        color: colorScheme.outline,
      ),
    );
  }
}
