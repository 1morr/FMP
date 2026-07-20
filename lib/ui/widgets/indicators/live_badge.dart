import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../i18n/strings.g.dart';

/// 直播中標記。
///
/// [LiveBadge.dot] 為紅點（surface 描邊 + 紅色光暈），用於封面右上角；
/// [LiveBadge.text] 為紅底 LIVE 文字標籤，用於大圖場景。
class LiveBadge extends StatelessWidget {
  /// 紅點變體。[size] 由封面尺寸推導，見 [dotSizeForCover]。
  const LiveBadge.dot({super.key, this.size = 16}) : _isText = false;

  /// LIVE 文字標籤變體（走 i18n）。
  const LiveBadge.text({super.key})
      : size = 0,
        _isText = true;

  /// 紅點直徑（dot 變體專用）。
  final double size;

  final bool _isText;

  /// 依封面邊長推導紅點直徑（100 -> 14）。
  static double dotSizeForCover(double coverSize) => coverSize * 0.14;

  /// 紅點相對封面右上角的建議偏移（top/right 相同）。
  static double dotOffset(double dotSize) => dotSize * 0.25;

  @override
  Widget build(BuildContext context) {
    if (_isText) {
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
    }

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
