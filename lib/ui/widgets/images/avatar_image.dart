import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';

/// 统一头像组件。
///
/// 头像固定使用最低图片源档位；调用方只负责提供头像来源和显示尺寸。
class AvatarImage extends StatelessWidget {
  final String? localPath;
  final String? networkUrl;
  final double size;

  const AvatarImage({
    super.key,
    this.localPath,
    this.networkUrl,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return ImageLoadingService.loadAvatar(
      localPath: localPath,
      networkUrl: networkUrl,
      size: size,
      targetDisplaySize: ImageTargetSizes.low,
    );
  }
}
