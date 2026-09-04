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
IconData getImportSourceIcon(String? sourceType) {
  return switch (sourceType) {
    SourceIds.bilibili => SimpleIcons.bilibili,
    SourceIds.youtube => SimpleIcons.youtube,
    SourceIds.netease => SimpleIcons.neteasecloudmusic,
    // null 代表「沒有匯入來源」（本地建立的歌單）；認不得的 id 代表
    // 「有來源但沒有圖示」。兩者刻意用不同圖示，別合併。
    null => Icons.link,
    _ => Icons.source_outlined,
  };
}
