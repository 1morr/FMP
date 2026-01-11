import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/track_extensions.dart';
import '../../core/services/image_loading_service.dart';
import '../../data/models/track.dart';
import '../../data/models/video_detail.dart';
import '../../providers/track_detail_provider.dart';
import '../../services/audio/audio_provider.dart';
import 'track_thumbnail.dart';

/// 右侧歌曲详情面板（桌面模式）
class TrackDetailPanel extends ConsumerWidget {
  const TrackDetailPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrack = ref.watch(currentTrackProvider);
    final detailState = ref.watch(trackDetailProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 没有播放歌曲时的空状态
    if (currentTrack == null) {
      return Container(
        color: colorScheme.surfaceContainerLow,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note_outlined,
                size: 72,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                '选择一首歌曲播放',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 加载中
    if (detailState.isLoading && detailState.detail == null) {
      return Container(
        color: colorScheme.surfaceContainerLow,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 错误状态
    if (detailState.error != null && detailState.detail == null) {
      return Container(
        color: colorScheme.surfaceContainerLow,
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '加载失败',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () {
                  ref.read(trackDetailProvider.notifier).refresh();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final detail = detailState.detail;

    // 有详情数据时显示
    return Container(
      color: colorScheme.surfaceContainerLow,
      child: detail != null
          ? _DetailContent(detail: detail)
          : _buildBasicInfo(context, currentTrack),
    );
  }

  Widget _buildBasicInfo(BuildContext context, Track track) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1,
              child: TrackCover(
                track: track,
                aspectRatio: 1,
                borderRadius: 0,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            track.title,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            track.artist ?? '未知作者',
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 详情内容组件
class _DetailContent extends ConsumerWidget {
  final VideoDetail detail;

  const _DetailContent({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final detailState = ref.watch(trackDetailProvider);
    final playerState = ref.watch(audioControllerProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    // 获取下一首歌曲（已考虑 shuffle 模式）
    final nextTrack = playerState.upcomingTracks.isNotEmpty
        ? playerState.upcomingTracks.first
        : null;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 封面
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TrackCover(
                  track: currentTrack,
                  networkUrl: detail.coverUrl,
                  aspectRatio: 16 / 9,
                  borderRadius: 0,
                ),
                // 时长标签
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      detail.formattedDuration,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                // 加载指示器
                if (detailState.isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // 标题
        Text(
          detail.title,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 12),

        // UP主信息
        Row(
          children: [
            _buildAvatar(context, currentTrack, detail),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                detail.ownerName,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              detail.formattedPublishDate,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // 简化的统计数据
        _buildSimpleStats(context),

        // 下一首
        if (nextTrack != null) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _buildNextTrack(context, nextTrack),
        ],

        // 简介
        if (detail.description.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _DescriptionSection(description: detail.description),
        ],

        // 热门评论（放在最下方）
        if (detail.hotComments.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _CommentPager(comments: detail.hotComments),
        ],

        const SizedBox(height: 32),
      ],
    );
  }

  /// 简化的统计数据（只显示播放数、点赞数、收藏数）
  Widget _buildSimpleStats(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatChip(
          context,
          Icons.play_arrow_rounded,
          detail.formattedViewCount,
          iconSize: 26,
          offsetY: 1.2,
        ),
        _buildStatChip(
          context,
          Icons.thumb_up_rounded,
          detail.formattedLikeCount,
        ),
        _buildStatChip(
          context,
          Icons.star_rounded,
          detail.formattedFavoriteCount,
          iconSize: 24,
        ),
      ],
    );
  }

  Widget _buildStatChip(BuildContext context, IconData icon, String value,
      {double iconSize = 18, double offsetY = 0}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: Offset(0, offsetY),
          child: Icon(
            icon,
            size: iconSize,
            color: colorScheme.primary.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// 下一首歌曲显示
  Widget _buildNextTrack(BuildContext context, Track track) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.skip_next_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '下一首',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // 缩略图
            TrackThumbnail(
              track: track,
              size: 56,
              borderRadius: 8,
              showPlayingIndicator: false,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist ?? '未知作者',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建UP主头像（优先使用本地头像）
  Widget _buildAvatar(BuildContext context, Track? track, VideoDetail detail) {
    // 使用 ImageLoadingService 加载头像（集成缓存）
    // 优先级：本地头像 → 网络头像 → 占位符
    return ImageLoadingService.loadAvatar(
      localPath: track?.localAvatarPath,
      networkUrl: detail.ownerFace.isNotEmpty ? detail.ownerFace : null,
      size: 32,
    );
  }
}

/// 简介部分（支持展开/收起）
class _DescriptionSection extends StatefulWidget {
  final String description;

  const _DescriptionSection({required this.description});

  @override
  State<_DescriptionSection> createState() => _DescriptionSectionState();
}

class _DescriptionSectionState extends State<_DescriptionSection> {
  bool _isExpanded = false;
  bool _needsExpansion = false;
  final GlobalKey _textKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfNeedsExpansion();
    });
  }

  @override
  void didUpdateWidget(_DescriptionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.description != widget.description) {
      _isExpanded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkIfNeedsExpansion();
      });
    }
  }

  void _checkIfNeedsExpansion() {
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.description,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.6,
        ),
      ),
      maxLines: 6,
      textDirection: TextDirection.ltr,
    );

    final renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      textPainter.layout(maxWidth: renderBox.size.width);
      setState(() {
        _needsExpansion = textPainter.didExceedMaxLines;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '简介',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            Text(
              widget.description,
              key: _textKey,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
              maxLines: _isExpanded ? null : 6,
              overflow: _isExpanded ? null : TextOverflow.ellipsis,
            ),
            if (_needsExpansion && !_isExpanded)
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isExpanded = true;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.only(left: 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.surfaceContainerLow.withValues(alpha: 0),
                          colorScheme.surfaceContainerLow,
                          colorScheme.surfaceContainerLow,
                        ],
                        stops: const [0.0, 0.3, 1.0],
                      ),
                    ),
                    child: Text(
                      '展开',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_isExpanded && _needsExpansion)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isExpanded = false;
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '收起',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 评论分页组件（手动翻页 + 自动翻页 + 动画）
class _CommentPager extends StatefulWidget {
  final List<VideoComment> comments;

  const _CommentPager({required this.comments});

  @override
  State<_CommentPager> createState() => _CommentPagerState();
}

class _CommentPagerState extends State<_CommentPager> {
  int _currentIndex = 0;
  Timer? _autoScrollTimer;
  bool _isForward = true; // 动画方向
  final GlobalKey _containerKey = GlobalKey();

  List<VideoComment> get _commentsToShow => widget.comments.take(3).toList();

  bool get _hasPrevious => _currentIndex > 0;
  bool get _hasNext => _currentIndex < _commentsToShow.length - 1;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(_CommentPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当评论列表变化时（切换歌曲），重置到第一条
    if (oldWidget.comments != widget.comments) {
      setState(() {
        _currentIndex = 0;
        _isForward = true;
      });
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
    final visibleBottom = (position.dy + box.size.height).clamp(0.0, screenSize.height);
    final visibleHeight = visibleBottom - visibleTop;

    return visibleHeight >= minVisibleHeight && position.dy < screenSize.height;
  }

  void _startAutoScroll() {
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
            Text(
              '热门评论',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // 翻页按钮（小圆形）
            if (comments.length > 1) ...[
              _buildSmallNavButton(
                icon: Icons.chevron_left_rounded,
                onPressed: _hasPrevious ? _goToPrevious : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
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
            duration: const Duration(milliseconds: 300),
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
                borderRadius: BorderRadius.circular(14),
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
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        currentComment.formattedLikeCount,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        currentComment.memberName,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
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
