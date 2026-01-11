import 'package:flutter/material.dart';

/// 根据音量值获取对应的图标
IconData getVolumeIcon(double volume) {
  if (volume <= 0) return Icons.volume_off;
  if (volume < 0.5) return Icons.volume_down;
  return Icons.volume_up;
}
