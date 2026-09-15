import 'package:flutter/material.dart';

import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/core/services/image_loading_service.dart';

/// 统一头像组件。
///
/// 頭像固定使用 thumbnail 檔位（56dp）；實際來源尺寸由 DPR 決定，呼叫方
/// 只負責提供頭像來源和顯示尺寸。
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
      targetDisplaySize: ImageTargetSizes.thumbnail,
    );
  }
}
