import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/extensions/track_extensions.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/icon_helpers.dart';
import '../../../data/models/play_queue.dart';
import '../../../data/models/track.dart';
import '../../../data/models/video_detail.dart';
import '../../../providers/download/file_exists_cache.dart';
import '../../../providers/download/download_providers.dart';
import '../../../providers/track_detail_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/platform/url_launcher_service.dart';
import '../../widgets/track_thumbnail.dart';

/// 播放器页面（全屏）
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  /// 是否为桌面平台
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 是否正在拖动进度条
  bool _isDragging = false;

  /// 拖动时的临时进度值
  double _dragProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('正在播放'),
        actions: [
          // 桌面端音量控制（紧凑版）
          if (isDesktop)
            _buildCompactVolumeControl(context, playerState, controller, colorScheme),
          // 更多选项（包含信息、倍速）
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            offset: const Offset(0, 48), // 向下偏移，与子菜单位置一致
            onSelected: (value) async {
              if (value == 'info') {
                // 延迟显示弹窗，等主菜单关闭后再显示
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (!context.mounted) return;
                  _showTrackInfoDialog(context, colorScheme);
                });
              } else if (value == 'speed') {
                // 延迟显示子菜单，等主菜单关闭后再显示
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (!context.mounted) return;
                  _showSpeedMenu(context, controller, playerState.speed, colorScheme);
                });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 12),
                    const Text('信息'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'speed',
                child: Row(
                  children: [
                    const Icon(Icons.speed, size: 20),
                    const SizedBox(width: 12),
                    Text('${playerState.speed}x'),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),

            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 封面图
            Expanded(
              flex: 3,
              child: _buildCoverArt(context, playerState, colorScheme),
            ),
            const SizedBox(height: 32),

            // 歌曲信息
            _buildTrackInfo(context, playerState, colorScheme),
            const SizedBox(height: 32),

            // 进度条
            _buildProgressBar(context, playerState, controller, colorScheme),
            const SizedBox(height: 24),

            // 播放控制
            _buildPlaybackControls(context, playerState, controller, colorScheme),
          ],
        ),
      ),
    );
  }

  /// 封面图
  Widget _buildCoverArt(
    BuildContext context,
    PlayerState state,
    ColorScheme colorScheme,
  ) {
    final track = state.currentTrack;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: track != null
            ? TrackCover(
                track: track,
                aspectRatio: 1,
                borderRadius: 0, // Container 已有圆角
              )
            : Center(
                child: Icon(
                  Icons.music_note,
                  size: 120,
                  color: colorScheme.primary,
                ),
              ),
      ),
    );
  }

  /// 歌曲信息
  Widget _buildTrackInfo(
    BuildContext context,
    PlayerState state,
    ColorScheme colorScheme,
  ) {
    final track = state.currentTrack;

    return Column(
      children: [
        Text(
          track?.title ?? '暂无播放',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          track?.artist ?? '选择一首歌曲开始播放',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// 进度条
  Widget _buildProgressBar(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    // 显示的进度：拖动时显示拖动进度，否则显示实际播放进度
    final displayProgress = _isDragging ? _dragProgress : state.progress.clamp(0.0, 1.0);

    // 显示的位置：拖动时根据拖动进度计算，否则显示实际位置
    final displayPosition = _isDragging && state.duration != null
        ? Duration(milliseconds: (state.duration!.inMilliseconds * _dragProgress).round())
        : state.position;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: displayProgress,
            onChangeStart: (value) {
              setState(() {
                _isDragging = true;
                _dragProgress = value;
              });
            },
            onChanged: (value) {
              // 拖动过程中只更新本地状态，不触发 seek
              setState(() => _dragProgress = value);
            },
            onChangeEnd: (value) {
              // 拖动结束时才触发 seek
              controller.seekToProgress(value);
              setState(() => _isDragging = false);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DurationFormatter.formatMs(displayPosition.inMilliseconds),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                DurationFormatter.formatMs((state.duration ?? Duration.zero).inMilliseconds),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 播放控制按钮
  Widget _buildPlaybackControls(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 顺序/乱序按钮（Mix 模式下禁用）
        IconButton(
          icon: Icon(state.isShuffleEnabled ? Icons.shuffle : Icons.arrow_forward),
          color: state.isShuffleEnabled ? colorScheme.primary : null,
          onPressed: state.isMixMode ? null : () => controller.toggleShuffle(),
          tooltip: state.isMixMode 
              ? 'Mix 模式不支持隨機播放' 
              : (state.isShuffleEnabled ? '随机播放' : '顺序播放'),
        ),

        // 上一首
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 40,
          onPressed: state.canPlayPrevious ? () => controller.previous() : null,
        ),

        // 播放/暂停
        _buildPlayPauseButton(context, state, controller, colorScheme),

        // 下一首
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 40,
          onPressed: state.canPlayNext ? () => controller.next() : null,
        ),

        // 循环模式按钮
        IconButton(
          icon: Icon(_getLoopModeIcon(state.loopMode)),
          color: state.loopMode != LoopMode.none ? colorScheme.primary : null,
          onPressed: () => controller.cycleLoopMode(),
          tooltip: _getLoopModeTooltip(state.loopMode),
        ),
      ],
    );
  }

  /// 播放/暂停按钮
  Widget _buildPlayPauseButton(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    const double buttonSize = 80;

    if (state.isBuffering || state.isLoading) {
      return SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: FilledButton(
          onPressed: null,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            minimumSize: const Size(buttonSize, buttonSize),
            maximumSize: const Size(buttonSize, buttonSize),
            padding: EdgeInsets.zero,
          ),
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: colorScheme.onPrimary,
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: FilledButton(
        onPressed: state.hasCurrentTrack
            ? () => controller.togglePlayPause()
            : null,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          minimumSize: const Size(buttonSize, buttonSize),
          maximumSize: const Size(buttonSize, buttonSize),
          padding: EdgeInsets.zero,
        ),
        child: Icon(
          state.isPlaying ? Icons.pause : Icons.play_arrow,
          size: 40,
        ),
      ),
    );
  }

  /// 显示倍速选择菜单
  void _showSpeedMenu(
    BuildContext context,
    AudioController controller,
    double currentSpeed,
    ColorScheme colorScheme,
  ) {
    // 获取屏幕尺寸，将菜单定位在右上角
    final screenSize = MediaQuery.of(context).size;
    final position = RelativeRect.fromLTRB(
      screenSize.width - 150, // 距离左边
      kToolbarHeight + MediaQuery.of(context).padding.top, // 距离顶部
      8, // 距离右边
      0,
    );

    showMenu<double>(
      context: context,
      position: position,
      items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) => PopupMenuItem(
        value: speed,
        child: Row(
          children: [
            if (currentSpeed == speed)
              Icon(Icons.check, size: 18, color: colorScheme.primary)
            else
              const SizedBox(width: 18),
            const SizedBox(width: 8),
            Text('${speed}x'),
          ],
        ),
      )).toList(),
    ).then((value) {
      if (value != null) {
        controller.setSpeed(value);
      }
    });
  }

  /// 紧凑音量控制（AppBar用，仅桌面端）
  Widget _buildCompactVolumeControl(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 音量图标按钮
        IconButton(
          icon: Icon(getVolumeIcon(state.volume), size: 20),
          visualDensity: VisualDensity.compact,
          tooltip: state.volume > 0 ? '静音' : '取消静音',
          onPressed: () => controller.toggleMute(),
        ),
        // 音量滑块
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.surfaceContainerHighest,
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: state.volume,
              min: 0.0,
              max: 1.0,
              onChanged: (value) => controller.setVolume(value),
            ),
          ),
        ),
      ],
    );
  }

  /// 获取循环模式图标
  IconData _getLoopModeIcon(LoopMode mode) => switch (mode) {
    LoopMode.none || LoopMode.all => Icons.repeat,
    LoopMode.one => Icons.repeat_one,
  };

  /// 获取循环模式提示
  String _getLoopModeTooltip(LoopMode mode) => switch (mode) {
    LoopMode.none => '不循环',
    LoopMode.all => '列表循环',
    LoopMode.one => '单曲循环',
  };

  /// 显示视频信息弹窗
  void _showTrackInfoDialog(BuildContext context, ColorScheme colorScheme) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _TrackInfoDialog(),
    );
  }
}

/// 视频信息弹窗
class _TrackInfoDialog extends ConsumerWidget {
  const _TrackInfoDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailState = ref.watch(trackDetailProvider);
    final playerState = ref.watch(audioControllerProvider);
    final currentTrack = playerState.currentTrack;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Watch 文件存在缓存和下载基础目录
    ref.watch(fileExistsCacheProvider);
    final cache = ref.read(fileExistsCacheProvider.notifier);
    final baseDirAsync = ref.watch(downloadBaseDirProvider);
    final baseDir = baseDirAsync.valueOrNull;

    final isYouTube = currentTrack?.sourceType == SourceType.youtube;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖动手柄
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '视频信息',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 内容区域
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: detailState.detail != null
                  ? _DetailContent(
                      detail: detailState.detail!,
                      isYouTube: isYouTube,
                      track: currentTrack,
                      cache: cache,
                      baseDir: baseDir,
                    )
                  : detailState.isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _BasicInfoContent(track: currentTrack),
            ),
          ),
        ],
      ),
    );
  }
}

/// 详情内容（有 VideoDetail 数据）
class _DetailContent extends StatelessWidget {
  final VideoDetail detail;
  final bool isYouTube;
  final Track? track;
  final FileExistsCache cache;
  final String? baseDir;

  const _DetailContent({
    required this.detail,
    required this.isYouTube,
    required this.track,
    required this.cache,
    required this.baseDir,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题（点击跳转到视频页面）
        GestureDetector(
          onTap: track != null
              ? () => UrlLauncherService.instance.openVideo(track!)
              : null,
          child: Text(
            detail.title,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        const SizedBox(height: 16),

        // UP主信息（点击跳转到频道/空间）
        GestureDetector(
          onTap: track != null
              ? () => UrlLauncherService.instance.openChannel(track!)
              : null,
          child: Row(
            children: [
              // 头像
              ImageLoadingService.loadAvatar(
                localPath: track?.getLocalAvatarPath(cache, baseDir: baseDir),
                networkUrl: detail.ownerFace.isNotEmpty ? detail.ownerFace : null,
                size: 40,
              ),
              const SizedBox(width: 12),
              // UP主名称
              Expanded(
                child: Text(
                  detail.ownerName,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 统计数据
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildStatItem(
              context,
              Icons.play_arrow_rounded,
              detail.formattedViewCount,
            ),
            _buildStatItem(
              context,
              Icons.thumb_up_rounded,
              detail.formattedLikeCount,
            ),
            // YouTube 不显示收藏数
            if (!isYouTube)
              _buildStatItem(
                context,
                Icons.star_rounded,
                detail.formattedFavoriteCount,
              ),
            _buildStatItem(
              context,
              Icons.calendar_today_outlined,
              detail.formattedPublishDate,
            ),
            _buildStatItem(
              context,
              Icons.schedule_outlined,
              detail.formattedDuration,
            ),
          ],
        ),

        // 简介（支持展开/收起）
        if (detail.description.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _DescriptionSection(description: detail.description),
        ],

        // 热门评论（带翻页）
        if (detail.hotComments.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          _CommentPager(comments: detail.hotComments),
        ],

        const SizedBox(height: 20),
      ],
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
          size: 16,
          color: colorScheme.primary.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 评论分页组件（手动翻页 + 动画）
class _CommentPager extends StatefulWidget {
  final List<VideoComment> comments;

  const _CommentPager({required this.comments});

  @override
  State<_CommentPager> createState() => _CommentPagerState();
}

class _CommentPagerState extends State<_CommentPager> {
  int _currentIndex = 0;
  bool _isForward = true;
  final GlobalKey _containerKey = GlobalKey();

  List<VideoComment> get _commentsToShow => widget.comments.take(3).toList();

  bool get _hasPrevious => _currentIndex > 0;
  bool get _hasNext => _currentIndex < _commentsToShow.length - 1;

  @override
  void didUpdateWidget(_CommentPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comments != widget.comments) {
      setState(() {
        _currentIndex = 0;
        _isForward = true;
      });
    }
  }

  void _goToPrevious() {
    if (_hasPrevious) {
      setState(() {
        _isForward = false;
        _currentIndex--;
      });
    }
  }

  void _goToNext() {
    setState(() {
      _isForward = true;
      if (_hasNext) {
        _currentIndex++;
      }
    });
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
                '热门评论',
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

/// 基础信息（没有 VideoDetail 数据）
class _BasicInfoContent extends StatelessWidget {
  final Track? track;

  const _BasicInfoContent({required this.track});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (track == null) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无播放信息',
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text(
          track!.title,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 8),

        // 作者
        Row(
          children: [
            Icon(
              Icons.person_outline,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                track!.artist ?? '未知作者',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // 时长
        Row(
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              DurationFormatter.formatMs(track!.durationMs ?? 0),
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // 提示信息
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '详细信息加载中...',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
      ],
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
      ],
    );
  }
}
