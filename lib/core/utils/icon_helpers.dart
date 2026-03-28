import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../data/models/track.dart';

/// 根据音量值获取对应的图标
IconData getVolumeIcon(double volume) {
  if (volume <= 0) return Icons.volume_off;
  if (volume < 0.5) return Icons.volume_down;
  return Icons.volume_up;
}

/// 根据导入源类型获取对应的平台图标
IconData getImportSourceIcon(SourceType? sourceType) {
  return switch (sourceType) {
    SourceType.bilibili => SimpleIcons.bilibili,
    SourceType.youtube => SimpleIcons.youtube,
    SourceType.netease => SimpleIcons.neteasecloudmusic,
    null => Icons.link,
  };
}
