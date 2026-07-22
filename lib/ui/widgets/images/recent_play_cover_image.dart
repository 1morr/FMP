import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';

/// 首页最近播放封面。
///
/// 最近播放卡片在首页以约 140dp 的封面展示，固定使用中等画质档位
/// （140 × 2.666 ≈ 373，取 medium 的 400）。
class RecentPlayCoverImage extends StatelessWidget {
  final String? networkUrl;
  final Widget? placeholder;
  final BoxFit fit;
  final double? width;
  final double? height;

  const RecentPlayCoverImage({
    super.key,
    this.networkUrl,
    this.placeholder,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ImageLoadingService.loadImage(
      networkUrl: networkUrl,
      placeholder: placeholder ?? const ImagePlaceholder.track(),
      fit: fit,
      width: width,
      height: height,
      targetDisplaySize: ImageTargetSizes.medium,
    );
  }
}
