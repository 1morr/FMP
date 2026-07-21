import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';

/// Hero 徽章配置（Mix / 導入 / 已下載等標籤）。
class CollapsingHeroBadge {
  const CollapsingHeroBadge({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
}

/// 共享的可折疊 Hero SliverAppBar。
///
/// 統一歌單詳情頁與已下載分類頁的折疊式應用欄：
/// expandedHeight 280、折疊後圖標色切換（[isCollapsed] 由呼叫端的
/// ScrollController 推導）、black54 ColorFilter 封面背景、
/// transparent -> surface(alpha 0.8) 漸變遮罩、120x120 圓角封面
/// （[AppShadows.heroCover]）、titleLarge 白色粗體標題與徽章 chip。
///
/// 封面與背景由呼叫端以 PlaylistCoverImage + 語意 variant 建構後傳入，
/// 本元件不直接載圖；[backgroundCover] 為 null 時顯示
/// [backgroundPlaceholder]（不套用 ColorFilter）。
class CollapsingHeroSliverAppBar extends StatelessWidget {
  const CollapsingHeroSliverAppBar({
    super.key,
    required this.isCollapsed,
    required this.backgroundPlaceholder,
    required this.cover,
    required this.title,
    this.backgroundCover,
    this.infoRows = const [],
    this.badge,
    this.leadingBuilder,
    this.titleBuilder,
    this.actionsBuilder,
  });

  /// 是否已折疊（呼叫端以 AppSizes.collapseThreshold 推導）。
  final bool isCollapsed;

  /// Hero 背景封面（已套用語意 variant）；非 null 時會疊加
  /// black54 ColorFilter 變暗。
  final Widget? backgroundCover;

  /// 無封面時的背景佔位。
  final Widget backgroundPlaceholder;

  /// 120x120 封面內容。
  final Widget cover;

  /// Hero 標題（titleLarge 白色粗體，最多兩行）。
  final String title;

  /// 標題下方的信息行（呼叫端自帶間距與樣式）。
  final List<Widget> infoRows;

  /// 徽章 chip；null 時不顯示。
  final CollapsingHeroBadge? badge;

  /// 返回/關閉按鈕；接收當前圖標色（展開白色、折疊 onSurface）。
  final Widget Function(BuildContext context, Color iconColor)?
      leadingBuilder;

  /// 折疊欄標題（如多選模式的已選數量）；返回 null 表示無標題。
  final Widget? Function(BuildContext context, Color iconColor)? titleBuilder;

  /// 操作按鈕列；接收當前圖標色。
  final List<Widget> Function(BuildContext context, Color iconColor)?
      actionsBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 根据滚动位置决定图标颜色：展开时白色，收起时使用主题色
    final iconColor = isCollapsed ? colorScheme.onSurface : Colors.white;

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      leading: leadingBuilder?.call(context, iconColor),
      title: titleBuilder?.call(context, iconColor),
      actions: actionsBuilder?.call(context, iconColor),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 封面背景
            if (backgroundCover != null)
              ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Colors.black54,
                  BlendMode.darken,
                ),
                child: backgroundCover!,
              )
            else
              backgroundPlaceholder,

            // 渐变遮罩
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    colorScheme.surface.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),

            // 信息区
            Positioned(
              left: 16,
              right: 16,
              bottom: 70,
              child: Row(
                children: [
                  // 封面
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.borderRadiusMd,
                      boxShadow: AppShadows.heroCover(colorScheme),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: cover,
                  ),
                  const SizedBox(width: 16),

                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        ...infoRows,
                        if (badge != null) ...[
                          const SizedBox(height: 8),
                          _HeroBadgeChip(badge: badge!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero 徽章 chip：圓角膠囊 + 圖標 + labelSmall 文字。
class _HeroBadgeChip extends StatelessWidget {
  const _HeroBadgeChip({required this.badge});

  final CollapsingHeroBadge badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: badge.backgroundColor,
        borderRadius: AppRadius.borderRadiusLg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            badge.icon,
            size: 14,
            color: badge.foregroundColor,
          ),
          const SizedBox(width: 4),
          Text(
            badge.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: badge.foregroundColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
