import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 播放頁的毛玻璃面板（ADR 0024 §決定 1）：約 66% 的 `surface` 加一般模糊，沒有折射。
///
/// 系統開了高對比時改成不透明的 `surface`、不做模糊：Flutter 3.47.5 的
/// `AccessibilityFeatures` 沒有「減少透明度」，目前只偵測得到高對比
/// （`MediaQuery.highContrastOf`）。
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final radius = BorderRadius.circular(AppTokens.of(context).radius.large);
    if (MediaQuery.highContrastOf(context)) {
      return Material(
        color: surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppLayout.playerGlassBlur,
          sigmaY: AppLayout.playerGlassBlur,
        ),
        child: Material(
          color: surface.withValues(alpha: AppLayout.playerGlassOpacity),
          child: child,
        ),
      ),
    );
  }
}
