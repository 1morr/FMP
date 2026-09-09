import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/core/services/image_loading_service.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/download/file_exists_cache.dart';
import 'package:fmp/ui/widgets/indicators/now_playing_cover_overlay.dart';

/// 统一的歌曲封面缩略图组件
///
/// 功能：
/// - 优先显示本地封面（已下载歌曲）
/// - 回退到网络封面
/// - 无封面时显示占位符
/// - 支持播放中指示器覆盖
///
/// **列表列的小方塊專用，實際呼叫端都在 32–56dp。** 圖片源固定在
/// [ImageTargetSizes.thumbnail]（160px），48dp 在 DPR 3 需要 144px，還有餘。
/// 卡片級以上的封面走 [TrackCover]，它按 [TrackCoverVariant] 選檔 —— 不要在這
/// 裡按 [size] 分檔，那條分支存在過兩個月，一個呼叫端都沒有。
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
            if (showPlayingIndicator && isPlaying) _buildPlayingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(
    ColorScheme colorScheme,
    String? localCoverPath,
    WidgetRef ref,
  ) {
    final placeholder = _buildPlaceholder(colorScheme);

    return ImageLoadingService.loadImage(
      localPath: localCoverPath,
      networkUrl: track.thumbnailUrl,
      placeholder: placeholder,
      fit: BoxFit.cover,
      width: size,
      height: size,
      targetDisplaySize: ImageTargetSizes.thumbnail,
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

  Widget _buildPlayingOverlay() {
    return NowPlayingCoverOverlay(
      coverSize: size,
      borderRadius: BorderRadius.circular(borderRadius),
    );
  }
}

/// 大封面显示场景。
enum TrackCoverVariant {
  /// 播放器模糊背景，使用高画质图片源减少全屏模糊后的色带和条纹。
  backdrop,

  /// 播放器、Detail Panel 等大图场景。
  ///
  /// 各源可用封面尺寸上限：Bilibili 1280w、NetEase 800、YouTube 720 高
  /// （maxresdefault）。因此 NetEase / YouTube 的播放器封面在高 DPR
  /// 手机上会被 GPU 放大约 1.4–1.6 倍而略软；这是源端尺寸上限，
  /// 图片管线无法再提升，请勿通过调高本档目标尺寸来"修复"。
  hero,
}

extension TrackCoverVariantTarget on TrackCoverVariant {
  double get targetDisplaySize {
    switch (this) {
      case TrackCoverVariant.backdrop:
        return ImageTargetSizes.high;
      case TrackCoverVariant.hero:
        return ImageTargetSizes.highest;
    }
  }
}

/// 大尺寸封面图片组件（用于播放页面等）
///
/// 与 TrackThumbnail 类似，但支持：
/// - 更大的尺寸
/// - 16:9 宽高比
/// - 加载指示器
/// - 语义化图片源尺寸
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

  /// 图片显示场景，用于选择图片源和缓存目标尺寸。
  final TrackCoverVariant variant;

  const TrackCover({
    super.key,
    this.track,
    this.networkUrl,
    this.aspectRatio = 16 / 9,
    this.borderRadius = 16,
    this.showLoadingIndicator = true,
    this.variant = TrackCoverVariant.hero,
  });

  static List<ImageProvider> imageProviderCandidates({
    required BuildContext context,
    String? localPath,
    String? networkUrl,
    double? width,
    double? height,
    TrackCoverVariant variant = TrackCoverVariant.hero,
  }) {
    return ImageLoadingService.imageProviderCandidates(
      context: context,
      localPath: localPath,
      networkUrl: networkUrl,
      width: width,
      height: height,
      targetDisplaySize: variant.targetDisplaySize,
    );
  }

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
      targetDisplaySize: variant.targetDisplaySize,
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(Icons.music_note, size: 48, color: colorScheme.outline),
    );
  }
}
