import 'package:flutter/material.dart';
import '../../../core/constants/ui_constants.dart';

/// 底部弹窗顶部的共享拖曳把手（40x4）。
/// 统一两个先前漂移的样式为单一 token 化规格。
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key, this.margin});

  /// 把手外边距，默认 top:12 bottom:8（对话/表单 sheet 规格）。
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: margin ?? const EdgeInsets.only(top: 12, bottom: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: AppRadius.borderRadiusXs,
        ),
      ),
    );
  }
}
