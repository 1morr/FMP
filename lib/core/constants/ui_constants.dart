import 'package:flutter/material.dart';

/// 统一圆角常量
///
/// 用于 BorderRadius.circular() 的标准圆角值。
class AppRadius {
  AppRadius._();

  /// 2dp - 进度条等极小元素
  static const double xs = 2.0;

  /// 4dp - 缩略图、标签、小卡片、小徽章
  static const double sm = 4.0;

  /// 8dp - 输入框、对话框内元素
  static const double md = 8.0;

  /// 12dp - 卡片、对话框、标签徽章
  static const double lg = 12.0;

  /// 16dp - 大卡片、封面图
  static const double xl = 16.0;

  /// 28dp - 导航栏指示器等特殊元素
  static const double pill = 28.0;

  /// 预构建的 BorderRadius 常量（避免重复创建对象）
  static final BorderRadius borderRadiusXs = BorderRadius.circular(xs);
  static final BorderRadius borderRadiusSm = BorderRadius.circular(sm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(md);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(lg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(xl);
  static final BorderRadius borderRadiusPill = BorderRadius.circular(pill);
}

/// 统一动画时长常量
class AnimationDurations {
  AnimationDurations._();

  /// 100ms - 最快动画（淡出、微交互）
  static const Duration fastest = Duration(milliseconds: 100);

  /// 150ms - 快速动画（淡入、列表项切换）
  static const Duration fast = Duration(milliseconds: 150);

  /// 200ms - 标准过渡（布局变化）
  static const Duration medium = Duration(milliseconds: 200);

  /// 300ms - 常规动画（展开/折叠、页面过渡）
  static const Duration normal = Duration(milliseconds: 300);

  /// 500ms - 慢速动画（复杂过渡）
  static const Duration slow = Duration(milliseconds: 500);

  /// 1600ms - 循环动画（播放指示器等）
  static const Duration loop = Duration(milliseconds: 1600);
}

/// UI 尺寸常量
class AppSizes {
  AppSizes._();

  /// 播放器主按钮尺寸 (播放/暂停)
  static const double playerMainButton = 80.0;

  /// 可折叠 AppBar 折叠阈值
  static const double collapseThreshold = 280 - kToolbarHeight;

  /// 侧边面板最小宽度
  static const double sidePanelMinWidth = 280.0;

  /// 侧边面板最大宽度
  static const double sidePanelMaxWidth = 500.0;

  /// 小缩略图尺寸
  static const double thumbnailSmall = 40.0;

  /// 中缩略图尺寸
  static const double thumbnailMedium = 48.0;

  /// 大缩略图尺寸
  static const double thumbnailLarge = 56.0;

  /// 卡片宽高比
  static const double cardAspectRatio = 0.8;
}

/// Toast 时长常量
class ToastDurations {
  ToastDurations._();

  /// 1500ms - 普通消息
  static const Duration short = Duration(milliseconds: 1500);

  /// 3000ms - 错误/警告消息
  static const Duration long = Duration(milliseconds: 3000);
}

/// 防抖时长常量
class DebounceDurations {
  DebounceDurations._();

  /// 300ms - 标准防抖（下载完成事件等）
  static const Duration standard = Duration(milliseconds: 300);

  /// 500ms - 长防抖（图片缓存清理等）
  static const Duration long = Duration(milliseconds: 500);
}
