import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';

/// 电台/直播封面显示场景。
enum RadioCoverVariant {
  /// 播放器模糊背景，使用高画质图片源减少全屏模糊后的色带和条纹。
  backdrop,

  /// 迷你播放器、搜索列表等小图。
  compact,

  /// 首页和电台列表卡片。
  card,

  /// 电台播放器、Detail Panel 等大图场景。
  hero,
}

extension RadioCoverVariantTarget on RadioCoverVariant {
  double get targetDisplaySize {
    switch (this) {
      case RadioCoverVariant.backdrop:
        return ImageTargetSizes.high;
      case RadioCoverVariant.compact:
        return ImageTargetSizes.medium;
      case RadioCoverVariant.card:
        return ImageTargetSizes.high;
      case RadioCoverVariant.hero:
        return ImageTargetSizes.highest;
    }
  }
}

/// 统一电台/直播封面组件。
///
/// 调用方只选择语义场景，不直接选择图片源尺寸。
class RadioCoverImage extends StatelessWidget {
  final String? networkUrl;
  final RadioCoverVariant variant;
  final Widget? placeholder;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool showLoadingIndicator;
  final Map<String, String>? headers;

  const RadioCoverImage({
    super.key,
    this.networkUrl,
    this.variant = RadioCoverVariant.compact,
    this.placeholder,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.showLoadingIndicator = false,
    this.headers,
  });

  @override
  Widget build(BuildContext context) {
    return ImageLoadingService.loadImage(
      networkUrl: networkUrl,
      placeholder: placeholder ?? const ImagePlaceholder(icon: Icons.radio),
      fit: fit,
      width: width,
      height: height,
      targetDisplaySize: variant.targetDisplaySize,
      headers: headers,
      showLoadingIndicator: showLoadingIndicator,
    );
  }

  static List<ImageProvider> imageProviderCandidates({
    required BuildContext context,
    String? networkUrl,
    double? width,
    double? height,
    RadioCoverVariant variant = RadioCoverVariant.compact,
    Map<String, String>? headers,
  }) {
    return ImageLoadingService.imageProviderCandidates(
      context: context,
      networkUrl: networkUrl,
      width: width,
      height: height,
      targetDisplaySize: variant.targetDisplaySize,
      headers: headers,
    );
  }

  static Future<ImageProvider?> precacheImageCandidates({
    required BuildContext context,
    String? networkUrl,
    RadioCoverVariant variant = RadioCoverVariant.compact,
    Map<String, String>? headers,
  }) {
    return ImageLoadingService.precacheImageCandidates(
      context: context,
      networkUrl: networkUrl,
      targetDisplaySize: variant.targetDisplaySize,
      headers: headers,
    );
  }
}
