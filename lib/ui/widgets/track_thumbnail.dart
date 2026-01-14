import 'package:flutter/material.dart';

import '../../core/extensions/track_extensions.dart';
import '../../core/services/image_loading_service.dart';
import '../../data/models/track.dart';
import 'now_playing_indicator.dart';

/// 统一的歌曲封面缩略图组件
///
/// 功能：
/// - 优先显示本地封面（已下载歌曲）
/// - 回退到网络封面
/// - 无封面时显示占位符
/// - 支持播放中指示器覆盖
class TrackThumbnail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
            _buildImage(colorScheme),
            if (showPlayingIndicator && isPlaying)
              _buildPlayingOverlay(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(ColorScheme colorScheme) {
    final placeholder = _buildPlaceholder(colorScheme);

    // 使用 ImageLoadingService 加载图片（集成 LocalImageCache）
    return ImageLoadingService.loadImage(
      localPath: track.localCoverPath,
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
class TrackCover extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          color: colorScheme.surfaceContainerHighest,
          child: _buildImage(colorScheme),
        ),
      ),
    );
  }

  Widget _buildImage(ColorScheme colorScheme) {
    final placeholder = _buildPlaceholder(colorScheme);

    // 使用 ImageLoadingService 加载图片（集成 LocalImageCache）
    return ImageLoadingService.loadImage(
      localPath: track?.localCoverPath,
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
