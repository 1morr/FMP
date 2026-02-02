import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/extensions/track_extensions.dart';
import '../../core/services/image_loading_service.dart';
import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import '../../data/models/video_detail.dart';
import '../../providers/download/download_providers.dart';
import '../../providers/download/file_exists_cache.dart';
import '../../providers/track_detail_provider.dart';
import '../../services/audio/audio_provider.dart';
import '../../services/platform/url_launcher_service.dart';
import '../../services/radio/radio_controller.dart';
import '../../data/models/radio_station.dart';
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

    // 检查电台是否正在播放（优先于歌曲信息）
    final radioState = ref.watch(radioControllerProvider);
    if (radioState.hasCurrentStation) {
      return Container(
        color: colorScheme.surfaceContainerLow,
        child: _RadioDetailContent(radioState: radioState),
      );
    }

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
    // Watch 文件存在缓存，以便在缓存更新时重建
    ref.watch(fileExistsCacheProvider);
    final cache = ref.read(fileExistsCacheProvider.notifier);

    // 獲取下載基礎目錄（用於頭像路徑查找）
    final baseDirAsync = ref.watch(downloadBaseDirProvider);
    final baseDir = baseDirAsync.valueOrNull;

    // 获取下一首歌曲（已考虑 shuffle 模式）
    final nextTrack = playerState.upcomingTracks.isNotEmpty
        ? playerState.upcomingTracks.first
        : null;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 封面（可点击打开视频）
        _ClickableCover(
          track: currentTrack,
          detail: detail,
          detailState: detailState,
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

        // UP主信息（头像可点击进入频道）
        Row(
          children: [
            _ClickableAvatar(
              track: currentTrack,
              detail: detail,
              cache: cache,
              baseDir: baseDir,
            ),
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
        _buildSimpleStats(context, currentTrack),

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

        // 热门评论
        if (detail.hotComments.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _CommentPager(comments: detail.hotComments),
        ],

        // 音频信息（放在最下方）
        if (playerState.currentBitrate != null ||
            playerState.currentContainer != null) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _buildAudioInfo(context, playerState),
        ],

        const SizedBox(height: 32),
      ],
    );
  }

  /// 简化的统计数据（播放数、点赞数、收藏数）
  /// YouTube 不显示收藏数（API 无法获取）
  Widget _buildSimpleStats(BuildContext context, Track? track) {
    final isYouTube = track?.sourceType == SourceType.youtube;
    
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
        // YouTube 不显示收藏数
        if (!isYouTube)
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

  /// 音频技术信息
  Widget _buildAudioInfo(BuildContext context, PlayerState playerState) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 格式化码率显示
    String? formatBitrate(int? bitrate) {
      if (bitrate == null) return null;
      if (bitrate >= 1000) {
        return '${(bitrate / 1000).toStringAsFixed(0)} kbps';
      }
      return '$bitrate bps';
    }

    // 格式化流类型显示
    String? formatStreamType(StreamType? type) {
      if (type == null) return null;
      switch (type) {
        case StreamType.audioOnly:
          return '纯音频';
        case StreamType.muxed:
          return '混合流';
        case StreamType.hls:
          return 'HLS';
      }
    }

    final bitrate = formatBitrate(playerState.currentBitrate);
    final container = playerState.currentContainer?.toUpperCase();
    final codec = playerState.currentCodec?.toUpperCase();
    final streamType = formatStreamType(playerState.currentStreamType);

    // 如果没有任何信息，不显示
    if (bitrate == null && container == null && codec == null && streamType == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Row(
          children: [
            Icon(
              Icons.graphic_eq,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '音频信息',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 信息标签
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (bitrate != null)
              _buildAudioChip(context, Icons.speed, bitrate),
            if (container != null)
              _buildAudioChip(context, Icons.folder_outlined, container),
            if (codec != null)
              _buildAudioChip(context, Icons.audiotrack_outlined, codec),
            if (streamType != null)
              _buildAudioChip(context, Icons.stream, streamType),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioChip(BuildContext context, IconData icon, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
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
}

/// 可点击的封面（点击打开视频）
class _ClickableCover extends StatefulWidget {
  final Track? track;
  final VideoDetail detail;
  final TrackDetailState detailState;

  const _ClickableCover({
    required this.track,
    required this.detail,
    required this.detailState,
  });

  @override
  State<_ClickableCover> createState() => _ClickableCoverState();
}

class _ClickableCoverState extends State<_ClickableCover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.track != null
            ? () => UrlLauncherService.instance.openVideo(widget.track!)
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TrackCover(
                  track: widget.track,
                  networkUrl: widget.detail.coverUrl,
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
                      widget.detail.formattedDuration,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                // 加载指示器
                if (widget.detailState.isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                // 悬停时显示的遮罩提示（仅桌面）
                if (!widget.detailState.isLoading)
                  AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
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

/// 可点击的头像（点击进入 UP主/频道）
class _ClickableAvatar extends StatelessWidget {
  final Track? track;
  final VideoDetail detail;
  final FileExistsCache cache;
  final String? baseDir;

  const _ClickableAvatar({
    required this.track,
    required this.detail,
    required this.cache,
    required this.baseDir,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: track != null
            ? () => UrlLauncherService.instance.openChannel(track!)
            : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: ImageLoadingService.loadAvatar(
            localPath: track?.getLocalAvatarPath(cache, baseDir: baseDir),
            networkUrl: detail.ownerFace.isNotEmpty ? detail.ownerFace : null,
            size: 32,
          ),
        ),
      ),
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
        // 简介文本
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
        // 展开/收起按钮 - 固定在右下角
        if (_needsExpansion)
          Align(
            alignment: Alignment.centerRight,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _isExpanded ? '收起' : '展开',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
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
    _autoScrollTimer = Timer.periodic(AppConstants.commentScrollInterval, (timer) {
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

/// 电台详情内容组件
class _RadioDetailContent extends ConsumerWidget {
  final RadioState radioState;

  const _RadioDetailContent({required this.radioState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final station = radioState.currentStation!;
    final radioController = ref.read(radioControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 封面（可点击打开直播间）
        _RadioClickableCover(station: station),

        const SizedBox(height: 20),

        // 标题（可点击跳转到直播间）
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => UrlLauncherService.instance.openBilibiliLive(station.sourceId),
            child: Text(
              station.title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 主播信息（头像可点击进入空间）+ 同步按钮
        if (station.hostName != null)
          Row(
            children: [
              _RadioClickableAvatar(
                hostAvatarUrl: station.hostAvatarUrl,
                hostUid: station.hostUid,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  station.hostName!,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 同步按钮
              _buildSyncButton(radioController, colorScheme),
            ],
          ),

        const SizedBox(height: 16),

        // 统计数据
        _buildSimpleStats(context),

        // 公告
        if (radioState.announcement != null && radioState.announcement!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _RadioExpandableSection(
            icon: Icons.campaign_outlined,
            title: '主播公告',
            content: radioState.announcement!,
          ),
        ],

        // 简介
        if (radioState.description != null && radioState.description!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _RadioExpandableSection(
            icon: Icons.info_outline_rounded,
            title: '简介',
            content: radioState.description!,
          ),
        ],

        // 标签
        if (radioState.tags != null && radioState.tags!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _buildTagsSection(context, radioState.tags!),
        ],

        const SizedBox(height: 32),
      ],
    );
  }

  /// 简化的统计数据
  Widget _buildSimpleStats(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        if (radioState.viewerCount != null)
          _buildStatItem(
            context,
            Icons.visibility_rounded,
            _formatCount(radioState.viewerCount!),
          ),
        if (radioState.isPlaying)
          _buildStatItem(
            context,
            Icons.schedule_outlined,
            _formatDuration(radioState.playDuration),
          ),
        if (radioState.areaName != null)
          _buildStatItem(
            context,
            Icons.category_outlined,
            radioState.areaName!,
          ),
        _buildStatItem(
          context,
          radioState.isPlaying ? Icons.radio_button_checked : Icons.radio_button_off,
          radioState.isPlaying ? '直播中' : '已停止',
        ),
      ],
    );
  }

  /// 同步按钮
  Widget _buildSyncButton(
    RadioController controller,
    ColorScheme colorScheme,
  ) {
    final isDisabled = radioState.isBuffering || radioState.isLoading || !radioState.isPlaying;

    return IconButton(
      onPressed: isDisabled ? null : () => controller.sync(),
      icon: Icon(
        Icons.sync,
        size: 20,
        color: isDisabled
            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
            : colorScheme.primary,
      ),
      tooltip: '同步直播',
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildStatItem(BuildContext context, IconData icon, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color: colorScheme.primary.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTagsSection(BuildContext context, String tags) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tagList = tags.split(',').where((t) => t.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tag, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '标签',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tagList.map((tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              tag.trim(),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }
}

/// 电台可点击封面
class _RadioClickableCover extends StatefulWidget {
  final RadioStation station;

  const _RadioClickableCover({required this.station});

  @override
  State<_RadioClickableCover> createState() => _RadioClickableCoverState();
}

class _RadioClickableCoverState extends State<_RadioClickableCover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => UrlLauncherService.instance.openBilibiliLive(widget.station.sourceId),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封面图片
                widget.station.thumbnailUrl != null
                    ? Image.network(
                        widget.station.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCoverPlaceholder(context),
                      )
                    : _buildCoverPlaceholder(context),
                // LIVE 标签
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // 悬停遮罩
                AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
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

  Widget _buildCoverPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.radio,
          size: 64,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// 电台可点击头像（点击进入主播空间）
class _RadioClickableAvatar extends StatelessWidget {
  final String? hostAvatarUrl;
  final int? hostUid;

  const _RadioClickableAvatar({
    this.hostAvatarUrl,
    this.hostUid,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: hostUid != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: hostUid != null
            ? () => UrlLauncherService.instance.openBilibiliSpace(hostUid!)
            : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: ClipOval(
            child: SizedBox(
              width: 32,
              height: 32,
              child: hostAvatarUrl != null
                  ? Image.network(
                      hostAvatarUrl!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildPlaceholder(context),
                    )
                  : _buildPlaceholder(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.person,
        size: 19,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 电台可展开部分（公告/简介）
class _RadioExpandableSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String content;

  const _RadioExpandableSection({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  State<_RadioExpandableSection> createState() => _RadioExpandableSectionState();
}

class _RadioExpandableSectionState extends State<_RadioExpandableSection> {
  bool _isExpanded = false;
  bool _needsExpansion = false;
  final GlobalKey _textKey = GlobalKey();

  static const int _maxLines = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfNeedsExpansion();
    });
  }

  @override
  void didUpdateWidget(_RadioExpandableSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _isExpanded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkIfNeedsExpansion();
      });
    }
  }

  void _checkIfNeedsExpansion() {
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.content,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.6,
        ),
      ),
      maxLines: _maxLines,
      textDirection: TextDirection.ltr,
    );

    final renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      textPainter.layout(maxWidth: renderBox.size.width);
      if (mounted) {
        setState(() {
          _needsExpansion = textPainter.didExceedMaxLines;
        });
      }
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
            Icon(widget.icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          widget.content,
          key: _textKey,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
          maxLines: _isExpanded ? null : _maxLines,
          overflow: _isExpanded ? null : TextOverflow.ellipsis,
        ),
        if (_needsExpansion)
          Align(
            alignment: Alignment.centerRight,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _isExpanded ? '收起' : '展开',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
