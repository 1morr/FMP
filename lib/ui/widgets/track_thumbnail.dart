import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/image_loading_service.dart';
import '../../data/models/track.dart';
import '../../providers/download/file_exists_cache.dart';
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

    // 使用 .select() 只在本 track 的封面路径结果变化时重建
    // 避免全局 fileExistsCacheProvider 任何变化都触发所有缩略图重建
    final coverPaths = track.hasAnyDownload
        ? track.allDownloadPaths
            .map((p) => '${Directory(p).parent.path}/cover.jpg')
            .toList()
        : <String>[];

    final localCoverPath = ref.watch(
      fileExistsCacheProvider.select((cacheSet) {
        for (final path in coverPaths) {
          if (cacheSet.contains(path)) return path;
        }
        return null;
      }),
    );

    // 对未缓存的路径触发异步检查
    if (localCoverPath == null && coverPaths.isNotEmpty) {
      ref.read(fileExistsCacheProvider.notifier).getFirstExisting(coverPaths);
    }

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
            _buildImage(colorScheme, localCoverPath, ref),
            if (showPlayingIndicator && isPlaying)
              _buildPlayingOverlay(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(
      ColorScheme colorScheme, String? localCoverPath, WidgetRef ref) {
    final placeholder = _buildPlaceholder(colorScheme);

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
/// - 高清模式（用于背景图片）
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

  /// 是否使用高清图片（用于背景等大尺寸显示）
  /// 设为 true 时会请求 480px 分辨率的图片
  final bool highResolution;

  const TrackCover({
    super.key,
    this.track,
    this.networkUrl,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 16,
    this.showLoadingIndicator = true,
    this.highResolution = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    // 使用 .select() 只在本 track 的封面路径结果变化时重建
    final coverPaths = (track != null && track!.hasAnyDownload)
        ? track!.allDownloadPaths
            .map((p) => '${Directory(p).parent.path}/cover.jpg')
            .toList()
        : <String>[];

    final localCoverPath = ref.watch(
      fileExistsCacheProvider.select((cacheSet) {
        for (final path in coverPaths) {
          if (cacheSet.contains(path)) return path;
        }
        return null;
      }),
    );

    if (localCoverPath == null && coverPaths.isNotEmpty) {
      ref.read(fileExistsCacheProvider.notifier).getFirstExisting(coverPaths);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          color: colorScheme.surfaceContainerHighest,
          child: _buildImage(colorScheme, localCoverPath),
        ),
      ),
    );
  }

  Widget _buildImage(ColorScheme colorScheme, String? localCoverPath) {
    final placeholder = _buildPlaceholder(colorScheme);

    return ImageLoadingService.loadImage(
      localPath: localCoverPath,
      networkUrl: networkUrl ?? track?.thumbnailUrl,
      placeholder: placeholder,
      fit: BoxFit.cover,
      showLoadingIndicator: showLoadingIndicator,
      targetDisplaySize: highResolution ? 480.0 : 320.0,
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
