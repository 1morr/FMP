import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../data/models/radio_station.dart';
import '../images/radio_cover_image.dart';
import '../indicators/live_badge.dart';
import '../indicators/now_playing_indicator.dart';

/// 純視覺的圓形電台封面：非直播灰階、直播紅點、播放中/載入中遮罩。
///
/// [size] 為 null 時由父層約束決定（取 maxWidth，呼叫端需給予寬度約束）；
/// 否則使用固定邊長。
class RadioStationCover extends StatelessWidget {
  const RadioStationCover({
    super.key,
    required this.imageUrl,
    required this.isLive,
    required this.isPlaying,
    required this.isLoading,
    this.size,
  });

  final String? imageUrl;
  final bool isLive;
  final bool isPlaying;
  final bool isLoading;

  /// 封面邊長；null 表示由父層約束決定（液態）。
  final double? size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final coverSize = size ?? constraints.maxWidth;
        // 紅點直徑由封面尺寸推導（100 -> 14、液態大圖 -> 約 16）
        final dotSize = LiveBadge.dotSizeForCover(coverSize);
        // 播放中/載入中指示器統一規格：封面邊長 * 0.32、onPrimary 色
        final indicatorSize = coverSize * 0.32;

        return SizedBox(
          width: coverSize,
          height: coverSize,
          child: Stack(
            children: [
              // 封面圖（非直播時灰階）
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: ColorFiltered(
                  colorFilter: isLive
                      ? const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.multiply,
                        )
                      : kGrayscaleColorFilter,
                  child: RadioCoverImage(
                    networkUrl: imageUrl,
                    fit: BoxFit.cover,
                    width: coverSize,
                    height: coverSize,
                    variant: RadioCoverVariant.card,
                  ),
                ),
              ),

              // 正在直播紅點
              if (isLive)
                Positioned(
                  top: LiveBadge.dotOffset(dotSize),
                  right: LiveBadge.dotOffset(dotSize),
                  child: LiveBadge.dot(size: dotSize),
                ),

              // 播放中/載入中遮罩
              if (isPlaying || isLoading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary.withValues(alpha: 0.4),
                    ),
                    child: Center(
                      child: isLoading
                          ? SizedBox(
                              width: indicatorSize,
                              height: indicatorSize,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : NowPlayingIndicator(
                              color: colorScheme.onPrimary,
                              size: indicatorSize,
                              isPlaying: true,
                            ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 完整電台卡片：圓形封面 + 標題（+ 可選主播列）。
///
/// - [coverSize] 為 null 時採液態佈局（封面 = 卡片寬度 - 40，電台頁網格）；
///   否則使用固定封面尺寸（首頁橫向列表傳 100）。
/// - [dense] 為 true 時使用首頁緊湊樣式（bodySmall 置中標題、無封面外距）；
///   false 時為電台頁樣式（titleSmall 標題、封面 20dp 外距）。
/// - [onTap] 為 null 時不包 InkWell（排序模式），此時可透過 [trailing]
///   在卡片右上角疊加拖動把手（見 [RadioStationDragHandle]）。
class RadioStationCard extends StatelessWidget {
  const RadioStationCard({
    super.key,
    required this.station,
    required this.isLive,
    required this.isPlaying,
    required this.isLoading,
    this.onTap,
    this.onLongPress,
    this.coverSize,
    this.showAnchor = false,
    this.dense = false,
    this.trailing,
  });

  final RadioStation station;
  final bool isLive;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 封面邊長；null 表示 LayoutBuilder 液態（maxWidth - 40）。
  final double? coverSize;

  /// 是否顯示主播名列（電台頁 true、首頁 false）。
  final bool showAnchor;

  /// 首頁緊湊樣式：bodySmall 置中標題、封面無外距、間距 6。
  final bool dense;

  /// 疊加在卡片右上角的元件（排序模式傳拖動把手）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        // 液態模式：封面大小 = 卡片寬度 - 水平 padding（20 * 2）
        final effectiveCoverSize = coverSize ?? constraints.maxWidth - 40;

        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // 圓形封面
            Padding(
              padding: dense
                  ? EdgeInsets.zero
                  : const EdgeInsets.only(left: 20, right: 20, top: 20),
              child: RadioStationCover(
                imageUrl: station.thumbnailUrl,
                isLive: isLive,
                isPlaying: isPlaying,
                isLoading: isLoading,
                size: effectiveCoverSize,
              ),
            ),

            SizedBox(height: dense ? 6 : 8),

            // 標題
            Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 8),
              child: Text(
                station.title,
                style:
                    (dense ? textTheme.bodySmall : textTheme.titleSmall)
                        ?.copyWith(
                      fontWeight: isPlaying ? FontWeight.bold : null,
                      color: isLive
                          ? (isPlaying
                              ? colorScheme.primary
                              : colorScheme.onSurface)
                          : colorScheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),

            // 主播名稱
            if (showAnchor && station.hostName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  station.hostName!,
                  style: textTheme.bodySmall?.copyWith(
                    color: isLive
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.outline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        );
      },
    );

    // 排序模式：右上角疊加拖動把手
    if (trailing != null) {
      content = Stack(
        children: [
          content,
          Positioned(right: 4, top: 4, child: trailing!),
        ],
      );
    }

    // onTap == null（排序模式）時不包 InkWell
    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: AppRadius.borderRadiusLg,
        child: content,
      );
    }

    return content;
  }
}

/// 排序模式的拖動把手，作為 [RadioStationCard.trailing] 疊在卡片右上角。
class RadioStationDragHandle extends StatelessWidget {
  const RadioStationDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.7),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Icon(
        Icons.drag_indicator,
        size: 16,
        color: colorScheme.onPrimary,
      ),
    );
  }
}
