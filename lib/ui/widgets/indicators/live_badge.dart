import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../i18n/strings.g.dart';

enum _LiveBadgeVariant { dot, text, compact }

/// 直播中標記。
///
/// [LiveBadge.dot] 為紅點（surface 描邊 + 紅色光暈），用於封面右上角；
/// [LiveBadge.text] 為紅底 LIVE 文字標籤，用於大圖場景；
/// [LiveBadge.compact] 為更小的文字標籤（列表項內嵌，如帳號電台導入）。
class LiveBadge extends StatelessWidget {
  /// 紅點變體。[size] 由封面尺寸推導，見 [dotSizeForCover]。
  const LiveBadge.dot({super.key, this.size = 16})
      : label = null,
        _variant = _LiveBadgeVariant.dot;

  /// LIVE 文字標籤變體（走 i18n）。
  const LiveBadge.text({super.key})
      : size = 0,
        label = null,
        _variant = _LiveBadgeVariant.text;

  /// 緊湊 LIVE 文字標籤：padding 6/1、radius xs、字級 10 w600。
  ///
  /// [label] 預設為 t.radio.live，可傳入情境化文案（如 t.account.liveStatus）。
  const LiveBadge.compact({super.key, this.label})
      : size = 0,
        _variant = _LiveBadgeVariant.compact;

  /// 紅點直徑（dot 變體專用）。
  final double size;

  /// 文字標籤覆寫（compact 變體專用）。
  final String? label;

  final _LiveBadgeVariant _variant;

  /// 依封面邊長推導紅點直徑（100 -> 14）。
  static double dotSizeForCover(double coverSize) => coverSize * 0.14;

  /// 紅點相對封面右上角的建議偏移（top/right 相同）。
  static double dotOffset(double dotSize) => dotSize * 0.25;

  @override
  Widget build(BuildContext context) {
    switch (_variant) {
      case _LiveBadgeVariant.text:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Text(
            t.radio.live,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case _LiveBadgeVariant.compact:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: AppRadius.borderRadiusXs,
          ),
          child: Text(
            label ?? t.radio.live,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case _LiveBadgeVariant.dot:
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(
              color: colorScheme.surface,
              width: size * 0.125,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.5),
                blurRadius: size * 0.25,
                spreadRadius: 1,
              ),
            ],
          ),
        );
    }
  }
}
