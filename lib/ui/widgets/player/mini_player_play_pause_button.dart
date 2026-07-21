import 'package:flutter/material.dart';

/// 迷你播放器播放/暫停鈕，音樂/電台迷你播放器共用。
///
/// 兩個迷你播放器原本各自維護一份逐字相同的實作（僅回呼不同：音樂為
/// togglePlayPause，電台為 pause/resume 分支）；抽出為單一元件以保證
/// 樣式一致。固定 40x40；[isLoading] 為真時顯示 20x20、strokeWidth 2 的
/// CircularProgressIndicator，否則依 [isPlaying] 顯示 28px 播放/暫停圖示。
/// [enabled] 為假時按鈕停用。
class MiniPlayerPlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool enabled;

  const MiniPlayerPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.isLoading,
    required this.onPressed,
    required this.tooltip,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 使用固定尺寸的 SizedBox 包裝，確保載入和正常狀態下大小一致。
    return SizedBox(
      width: 40,
      height: 40,
      child: isLoading
          ? Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: colorScheme.primary,
                  strokeWidth: 2,
                ),
              ),
            )
          : IconButton(
              padding: EdgeInsets.zero,
              tooltip: tooltip,
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                size: 28,
              ),
              onPressed: enabled ? onPressed : null,
            ),
    );
  }
}
