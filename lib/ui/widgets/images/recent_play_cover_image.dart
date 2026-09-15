import 'package:flutter/material.dart';

import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/core/services/image_loading_service.dart';

/// 首页最近播放封面。
///
/// 最近播放卡片封面在首頁約 78–128dp 高（卡片寬 100–140dp，扣掉標題區），
/// 固定使用 [ImageTargetSizes.medium] 檔位。
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
