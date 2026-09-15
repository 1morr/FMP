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

/// 圖片檔位：每一檔是該場景 box 的**邏輯高度上限（dp）**。
///
/// 這些值用於選擇 CDN 縮圖候選和快取縮放邊界。UI 圖片和下載的 metadata
/// 圖片共用這些語義檔位，避免顯示與落盤圖片使用不同的畫質規則。
///
/// ## 為什麼是「高度」而不是邊長
///
/// Bilibili / YouTube 的封面是 16:9，而封面框多半是正方形，配 `BoxFit.cover`
/// 時來源只有**高**能用：`@200w` 只有 113px 高，`maxresdefault` 只有 720px
/// 高。所以檔位要表達的是「box 有多高」，換算成來源寬的 ×16/9 由
/// `ThumbnailUrlUtils` 負責（issue #107）。
///
/// box 不是正方形時取較大的那一邊仍然安全：`BoxFit.cover` 對 16:9 來源總是
/// 按高對齊，較寬的 box 只是多要一點高。
///
/// ## 這裡是 dp，DPR 在使用端才乘
///
/// 這些值**不含** DPR。URL 檔位與磁碟快取邊界都由
/// `ThumbnailUrlUtils.neededSourceHeight(檔位, DPR)` 算出（DPR 量化到 0.5，
/// 收斂跨裝置的快取鍵），記憶體解碼尺寸用全精度 DPR。2026-09 之前這些值把
/// 一個假設的 DPR 2.666 寫死在常數裡，於是實際 DPR 是多少都選同一檔，高 DPI
/// 螢幕上的封面一律被放大（issue #107）。
///
/// 已知不足：[medium] 取 120，而首頁最近播放卡片在寬版佈局最大到 128dp 高
/// （卡片寬 140 × 1.25 減去文字區）。在同時是寬版佈局又是 DPR 3 的裝置上差
/// 7%。拉到 140 會讓每張首頁卡片從 `@640w` 跳到 `@1280w`，為了 7% 付三倍流量
/// 不划算 —— 手機上卡片寬度被 clamp 在 100dp，根本到不了 128dp。
class ImageTargetSizes {
  ImageTargetSizes._();

  /// 下載 metadata 的頭像圖（最大約 30dp）。
  /// UI 頭像使用 [thumbnail] 檔，見 AvatarImage。
  static const double low = 32.0;

  /// 列表小圖：UI 頭像（約 32–48dp）、列表縮圖（約 32–48dp）與
  /// 電台 compact 小圖（56dp）。
  static const double thumbnail = 56.0;

  /// 中等卡片：首頁最近播放卡片封面（約 78–128dp 高）、電台圓形卡片
  /// （100dp）、歌單 compact 預覽。
  static const double medium = 120.0;

  /// 大卡片（約 200dp）。
  ///
  /// 播放器模糊背景**不**在這一檔：它吃的是整個視窗而不是一張卡片，
  /// 走 [highest]，見 `TrackCoverVariant.backdrop`。
  static const double high = 200.0;

  /// Detail Panel、全螢幕詳情對話框等大型封面（約 360–460dp）。
  static const double fullscreen = 460.0;

  /// 主封面、全螢幕封面與播放器模糊背景（最大顯示約 480dp；播放器封面框
  /// 上限見 `AppLayout.playerCoverMax`）。
  ///
  /// 和 [fullscreen] 在三個源上都會選到同一個 URL 檔位（各源上限：Bilibili
  /// 1280w、NetEase 800、YouTube 720 高）；兩檔分開只影響解碼尺寸。
  static const double highest = 480.0;
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
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

/// REC.709 亮度灰阶 ColorFilter，由 [kGrayscaleColorMatrix] 派生。
///
/// 调用端写 `ColorFiltered(colorFilter: kGrayscaleColorFilter, ...)`。
const ColorFilter kGrayscaleColorFilter = ColorFilter.matrix(
  kGrayscaleColorMatrix,
);
