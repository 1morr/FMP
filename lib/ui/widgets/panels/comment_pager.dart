import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/ui_constants.dart';
import '../../../data/models/video_detail.dart';

/// 评论分页组件（手动翻页 + 可选自动翻页 + 动画）。
///
/// 全屏播放器資訊彈窗與桌面 Detail Panel 共用；面板透過 [autoScroll]
/// 啟用 10 秒自動翻頁（僅在評論區可見時翻頁）。
class CommentPager extends StatefulWidget {
  final List<VideoComment> comments;

  /// 標題文字（呼叫方負責 i18n）。
  final String title;

  /// 是否啟用自動翻頁（每 10 秒，僅在可見時）。
  final bool autoScroll;

  const CommentPager({
    super.key,
    required this.comments,
    required this.title,
    this.autoScroll = false,
  });

  @override
  State<CommentPager> createState() => _CommentPagerState();
}

class _CommentPagerState extends State<CommentPager> {
  int _currentIndex = 0;
  Timer? _autoScrollTimer;
  bool _isForward = true; // 动画方向
  final GlobalKey _containerKey = GlobalKey();

  List<VideoComment> get _commentsToShow =>
      widget.comments.take(AppConstants.commentsPreviewCount).toList();

  bool get _hasPrevious => _currentIndex > 0;
  bool get _hasNext => _currentIndex < _commentsToShow.length - 1;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(CommentPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当评论列表变化时（切换歌曲），重置到第一条
    if (oldWidget.comments != widget.comments) {
      setState(() {
        _currentIndex = 0;
        _isForward = true;
      });
      _resetAutoScroll();
    } else if (oldWidget.autoScroll != widget.autoScroll) {
      _resetAutoScroll();
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  /// 检查评论区域是否有足够的可见部分（标题+部分内容）
  bool _isVisible() {
    final renderObject = _containerKey.currentContext?.findRenderObject();
    if (renderObject == null || renderObject is! RenderBox) return false;

    final box = renderObject;
    if (!box.hasSize) return false;

    final position = box.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // 评论区顶部要在屏幕内，且至少有120像素可见（标题栏+评论卡片第一行）
    const minVisibleHeight = 120.0;
    final visibleTop = position.dy.clamp(0.0, screenSize.height);
    final visibleBottom =
        (position.dy + box.size.height).clamp(0.0, screenSize.height);
    final visibleHeight = visibleBottom - visibleTop;

    return visibleHeight >= minVisibleHeight && position.dy < screenSize.height;
  }

  void _startAutoScroll() {
    if (!widget.autoScroll) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) return;
      // 只有当评论区在可视范围内时才自动翻页
      if (_isVisible()) {
        _goToNext(wrap: true);
      }
    });
  }

  void _resetAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _startAutoScroll();
  }

  void _goToPrevious() {
    if (_hasPrevious) {
      setState(() {
        _isForward = false;
        _currentIndex--;
      });
      _resetAutoScroll();
    }
  }

  void _goToNext({bool wrap = false}) {
    setState(() {
      _isForward = true;
      if (_hasNext) {
        _currentIndex++;
      } else if (wrap && _commentsToShow.length > 1) {
        _currentIndex = 0;
      }
    });
    if (!wrap) _resetAutoScroll();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final comments = _commentsToShow;

    if (comments.isEmpty) return const SizedBox.shrink();

    final currentComment = comments[_currentIndex];

    return Column(
      key: _containerKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Row(
          children: [
            Icon(
              Icons.format_quote_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 翻页按钮（小圆形）
            if (comments.length > 1) ...[
              _buildSmallNavButton(
                icon: Icons.chevron_left_rounded,
                onPressed: _hasPrevious ? _goToPrevious : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${_currentIndex + 1}/${comments.length}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _buildSmallNavButton(
                icon: Icons.chevron_right_rounded,
                onPressed: _hasNext ? () => _goToNext() : null,
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),

        // 评论内容（带动画）
        ClipRect(
          child: AnimatedSwitcher(
            duration: AnimationDurations.normal,
            transitionBuilder: (child, animation) {
              final offsetAnimation = Tween<Offset>(
                begin: Offset(_isForward ? 1.0 : -1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ));
              return SlideTransition(
                position: offsetAnimation,
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            child: Container(
              key: ValueKey(_currentIndex),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: AppRadius.borderRadiusLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentComment.content,
                    style: textTheme.bodyMedium?.copyWith(
                      height: 1.6,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.thumb_up_outlined,
                        size: 14,
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        currentComment.formattedLikeCount,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        currentComment.memberName,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSmallNavButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onPressed != null;

    return Material(
      color: isEnabled
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: AppRadius.borderRadiusLg,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.borderRadiusLg,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            icon,
            size: 16,
            color: isEnabled
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
