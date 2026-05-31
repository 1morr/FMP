import 'package:flutter/material.dart';

import '../../core/constants/ui_constants.dart';
import '../../core/services/image_loading_service.dart';

/// 歌单封面显示场景。
enum PlaylistCoverVariant {
  /// 小型预览、弹窗和选择器。
  compact,

  /// 首页和音乐库卡片。
  card,

  /// 歌单详情背景等大图场景。
  hero,
}

extension PlaylistCoverVariantTarget on PlaylistCoverVariant {
  double get targetDisplaySize {
    switch (this) {
      case PlaylistCoverVariant.compact:
        return ImageTargetSizes.medium;
      case PlaylistCoverVariant.card:
        return ImageTargetSizes.high;
      case PlaylistCoverVariant.hero:
        return ImageTargetSizes.highest;
    }
  }
}

/// 统一歌单封面组件。
///
/// 调用方只选择语义场景，不直接选择图片源尺寸。
class PlaylistCoverImage extends StatelessWidget {
  final String? localPath;
  final String? networkUrl;
  final PlaylistCoverVariant variant;
  final Widget? placeholder;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool showLoadingIndicator;

  const PlaylistCoverImage({
    super.key,
    this.localPath,
    this.networkUrl,
    this.variant = PlaylistCoverVariant.compact,
    this.placeholder,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.showLoadingIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
    return ImageLoadingService.loadImage(
      localPath: localPath,
      networkUrl: networkUrl,
      placeholder: placeholder ?? const ImagePlaceholder.playlist(),
      fit: fit,
      width: width,
      height: height,
      targetDisplaySize: variant.targetDisplaySize,
      showLoadingIndicator: showLoadingIndicator,
    );
  }
}
