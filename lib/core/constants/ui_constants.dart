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

  /// 20dp - 底部弹窗顶部圆角
  static const double sheet = 20.0;

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

/// 统一阴影规格
class AppShadows {
  AppShadows._();

  /// Hero 封面（120x120）阴影：colorScheme.shadow alpha 0.3, blur 10, offset (0,5)
  static List<BoxShadow> heroCover(ColorScheme colorScheme) => [
        BoxShadow(
          color: colorScheme.shadow.withValues(alpha: 0.3),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ];
}

/// UI 尺寸常量
class AppSizes {
  AppSizes._();

  /// 播放器主按钮尺寸 (播放/暂停)
  static const double playerMainButton = 80.0;

  /// 可折叠 AppBar 折叠阈值
  static const double collapseThreshold = 280 - kToolbarHeight;

  /// 小缩略图尺寸
  static const double thumbnailSmall = 40.0;

  /// 中缩略图尺寸
  static const double thumbnailMedium = 48.0;

  /// 大缩略图尺寸
  static const double thumbnailLarge = 56.0;

  /// 卡片宽高比
  static const double cardAspectRatio = 0.8;

  /// 底部弹窗最大高度
  static const double maxBottomSheetHeight = 800.0;
}

/// 图片源尺寸目标。
///
/// 这些值用于选择 CDN 缩略图候选和缓存缩放边界，是图片源尺寸提示，
/// 不是 720p 这类视频分辨率。UI 图片和下载的 metadata 图片共用这些
/// 语义档位，避免显示与落盘图片使用不同的画质规则。
///
/// 档位取值按「使用该档位界面的最大逻辑显示尺寸 × 最高支持的 DPR
/// （约 2.666）」留足余量，确保高 DPI 屏幕上解码后的位图不需要再放大。
class ImageTargetSizes {
  ImageTargetSizes._();

  /// 低画质：仅用于下载 metadata 的头像图（最大约 30dp；30 × 2.666 ≈ 80）。
  /// UI 头像使用 [thumbnail] 档，见 AvatarImage。
  static const double low = 80.0;

  /// 缩略图画质：UI 头像（约 32–48dp）、列表小缩略图（约 32–56dp）与
  /// 电台 compact 小图（56 × 2.666 ≈ 149，留余量取 160）。
  static const double thumbnail = 160.0;

  /// 中等画质：中等卡片与大号列表缩略图（约 100–140dp；
  /// 140 × 2.666 ≈ 373，留余量取 400）。
  static const double medium = 400.0;

  /// 高画质：大卡片（约 200dp）与播放器模糊背景
  /// （200 × 2.666 ≈ 533；模糊背景需要更高源尺寸以减少色带，取 720）。
  static const double high = 720.0;

  /// 全屏面板画质：Detail Panel、全屏详情对话框等大型封面
  /// （约 360–460dp；360 × 2.666 ≈ 960，460dp 在 DPR ≤ 2.1 时无需再放大）。
  static const double fullscreen = 960.0;

  /// 最高画质：主封面、全屏封面与 Hero 背景
  /// （最大显示约 480dp；480 × 2.666 ≈ 1280）。
  static const double highest = 1280.0;
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

/// REC.709 亮度灰阶矩阵（单一真相）。
///
/// 用于把封面去饱和为灰阶（例如离线 / 不可用的电台封面）。不要在 UI 檔
/// 逐字重复这 20 个值；消费 [kGrayscaleColorFilter] 即可。此 list 单独
/// 暴露是为了单元测试能锁值。
const List<double> kGrayscaleColorMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];

/// REC.709 亮度灰阶 ColorFilter，由 [kGrayscaleColorMatrix] 派生。
///
/// 调用端写 `ColorFiltered(colorFilter: kGrayscaleColorFilter, ...)`。
const ColorFilter kGrayscaleColorFilter = ColorFilter.matrix(kGrayscaleColorMatrix);
