import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';

/// 可点击的封面（点击打开来源页面，悬停显示遮罩提示）。
///
/// 全屏播放器資訊彈窗與桌面 Detail Panel（音樂 / 電台）共用。封面圖片由
/// 呼叫方建好傳入（TrackCover / RadioCoverImage），此元件不負責圖片載入；
/// 徽章與額外遮罩也以參數傳入。
class ClickableSourceCover extends StatefulWidget {
  /// 封面圖片 widget（由呼叫方建立）。
  final Widget cover;

  /// 點擊開啟來源頁面；null 時不可點擊。
  final VoidCallback? onOpenSource;

  /// 封面寬高比。
  final double aspectRatio;

  /// 右下角徽章（例如時長標籤）。
  final Widget? bottomBadge;

  /// 左上角徽章（例如 LIVE 標籤）。
  final Widget? topBadge;

  /// 是否顯示載入中遮罩（會暫時隱藏懸停遮罩）。
  final bool isLoading;

  /// 額外的全幅遮罩（例如電台未播放遮罩），顯示在封面之上、懸停遮罩之下。
  final Widget? overlay;

  const ClickableSourceCover({
    super.key,
    required this.cover,
    this.onOpenSource,
    this.aspectRatio = 16 / 9,
    this.bottomBadge,
    this.topBadge,
    this.isLoading = false,
    this.overlay,
  });

  @override
  State<ClickableSourceCover> createState() => _ClickableSourceCoverState();
}

class _ClickableSourceCoverState extends State<ClickableSourceCover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onOpenSource != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onOpenSource,
        child: ClipRRect(
          borderRadius: AppRadius.borderRadiusXl,
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.cover,
                if (widget.topBadge != null)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: widget.topBadge!,
                  ),
                if (widget.bottomBadge != null)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: widget.bottomBadge!,
                  ),
                // 加载指示器
                if (widget.isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                if (widget.overlay != null)
                  Positioned.fill(child: widget.overlay!),
                // 悬停时显示的遮罩提示（仅桌面）
                if (!widget.isLoading)
                  AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: AnimationDurations.fast,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: const Center(
                        child: Icon(
                          Icons.open_in_new,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
