import 'package:flutter/material.dart';

import 'now_playing_indicator.dart';

/// 播放中封面遮罩：primary scrim + onPrimary 動態指示器。
///
/// 指示器尺寸統一為封面邊長 * 0.32（見 radio_station_card 的規格註解）。
/// [scrimAlpha] 預設 0.8（方形歌曲縮圖）；圓形電台封面傳 0.4。
/// [child] 可覆寫中央內容（例如電台封面的載入中進度圈）。
class NowPlayingCoverOverlay extends StatelessWidget {
  /// 封面邊長，用於推導指示器尺寸（coverSize * 0.32）。
  final double coverSize;

  /// primary scrim 不透明度。
  final double scrimAlpha;

  /// 遮罩形狀；圓形電台封面傳 [BoxShape.circle]。
  final BoxShape shape;

  /// 方形遮罩的圓角（shape 為 rectangle 時生效）。
  final BorderRadius? borderRadius;

  /// 中央內容；null 時為 onPrimary 的 [NowPlayingIndicator]。
  final Widget? child;

  const NowPlayingCoverOverlay({
    super.key,
    required this.coverSize,
    this.scrimAlpha = 0.8,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
        color: colorScheme.primary.withValues(alpha: scrimAlpha),
      ),
      child: Center(
        child: child ??
            NowPlayingIndicator(
              size: coverSize * 0.32,
              color: colorScheme.onPrimary,
              isPlaying: true,
            ),
      ),
    );
  }
}
