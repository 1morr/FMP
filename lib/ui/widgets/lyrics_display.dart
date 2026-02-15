import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/ui_constants.dart';
import '../../i18n/strings.g.dart';
import '../../providers/lyrics_provider.dart';
import '../../services/audio/audio_provider.dart';
import '../../services/lyrics/lrc_parser.dart';

/// 歌词滚动显示组件
///
/// 用于播放器页面和 TrackDetailPanel。
/// 自动同步当前播放位置，高亮当前行并平滑滚动。
class LyricsDisplay extends ConsumerStatefulWidget {
  /// 紧凑模式（TrackDetailPanel 使用较小字号）
  final bool compact;

  /// 点击回调（播放器页面用于切回封面）
  final VoidCallback? onTap;

  const LyricsDisplay({
    super.key,
    this.compact = false,
    this.onTap,
  });

  @override
  ConsumerState<LyricsDisplay> createState() => _LyricsDisplayState();
}

class _LyricsDisplayState extends ConsumerState<LyricsDisplay> {
  final _scrollController = ScrollController();

  /// 当前高亮行索引（用于检测变化，避免重复滚动）
  int _currentLineIndex = -1;

  /// 用户是否正在手动滚动
  bool _userScrolling = false;

  /// 固定行高（用于计算滚动位置）
  double get _lineHeight => widget.compact ? 48.0 : 48.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lyricsContent = ref.watch(currentLyricsContentProvider);
    final parsedLyrics = ref.watch(parsedLyricsProvider);
    final match = ref.watch(currentLyricsMatchProvider).valueOrNull;

    // 歌词内容加载中
    if (lyricsContent.isLoading) {
      return _buildCentered(
        child: const CircularProgressIndicator(),
      );
    }

    // 无匹配
    if (match == null) {
      return _buildNoLyrics(context, colorScheme);
    }

    // 加载失败
    if (lyricsContent.hasError) {
      return _buildCentered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              lyricsContent.error.toString(),
              style: TextStyle(color: colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final content = lyricsContent.valueOrNull;

    // 纯音乐
    if (content?.instrumental == true) {
      return _buildCentered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note, size: 48, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              t.lyrics.instrumentalTrack,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // 无歌词内容
    if (parsedLyrics == null || parsedLyrics.isEmpty) {
      return _buildNoLyrics(context, colorScheme);
    }

    // 同步歌词
    if (parsedLyrics.isSynced) {
      return _buildSyncedLyrics(context, colorScheme, parsedLyrics, match.offsetMs);
    }

    // 纯文本歌词
    return _buildPlainLyrics(context, colorScheme, parsedLyrics);
  }

  /// 同步歌词（带时间戳，自动滚动）
  Widget _buildSyncedLyrics(
    BuildContext context,
    ColorScheme colorScheme,
    ParsedLyrics lyrics,
    int offsetMs,
  ) {
    final playerState = ref.watch(audioControllerProvider);
    final position = playerState.position;

    // 计算当前行
    final newIndex = LrcParser.findCurrentLineIndex(
      lyrics.lines,
      position,
      offsetMs,
    );

    // 只在行变化时触发滚动
    if (newIndex != _currentLineIndex) {
      _currentLineIndex = newIndex;
      if (!_userScrolling && newIndex >= 0) {
        _scrollToLine(newIndex, lyrics.lines.length);
      }
    }

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _userScrolling = true;
          } else if (notification is ScrollEndNotification) {
            // 用户停止滚动后 3 秒恢复自动滚动
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _userScrolling = false);
            });
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            vertical: widget.compact ? 16 : 80,
            horizontal: widget.compact ? 12 : 24,
          ),
          itemCount: lyrics.lines.length,
          itemExtent: _lineHeight,
          itemBuilder: (context, index) {
            final line = lyrics.lines[index];
            final isCurrent = index == _currentLineIndex;

            return _LyricsLineWidget(
              key: ValueKey(index),
              text: line.text,
              isCurrent: isCurrent,
              compact: widget.compact,
              colorScheme: colorScheme,
            );
          },
        ),
      ),
    );
  }

  /// 纯文本歌词（无时间戳，简单滚动）
  Widget _buildPlainLyrics(
    BuildContext context,
    ColorScheme colorScheme,
    ParsedLyrics lyrics,
  ) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(
          vertical: widget.compact ? 16 : 40,
          horizontal: widget.compact ? 12 : 24,
        ),
        itemCount: lyrics.lines.length,
        itemBuilder: (context, index) {
          final line = lyrics.lines[index];
          return Padding(
            padding: EdgeInsets.symmetric(vertical: widget.compact ? 4 : 6),
            child: Text(
              line.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                    fontSize: widget.compact ? 17 : 15,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    );
  }

  /// 无歌词状态
  Widget _buildNoLyrics(BuildContext context, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              t.lyrics.noLyricsAvailable,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 居中布局包装
  Widget _buildCentered({required Widget child}) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(child: child),
    );
  }

  /// 平滑滚动到指定行
  void _scrollToLine(int index, int totalLines) {
    if (!_scrollController.hasClients) return;

    // 目标位置：将当前行滚动到视口中间偏上
    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset = (index * _lineHeight) - (viewportHeight / 2) + (_lineHeight / 2);
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        clampedOffset,
        duration: AnimationDurations.normal,
        curve: Curves.easeOutCubic,
      );
    });
  }
}

/// 单行歌词组件
class _LyricsLineWidget extends StatelessWidget {
  final String text;
  final bool isCurrent;
  final bool compact;
  final ColorScheme colorScheme;

  const _LyricsLineWidget({
    super.key,
    required this.text,
    required this.isCurrent,
    required this.compact,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = isCurrent
        ? TextStyle(
            color: colorScheme.primary,
            fontSize: compact ? 20 : 20,
            fontWeight: FontWeight.bold,
            height: 1.3,
          )
        : TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.4),
            fontSize: compact ? 17 : 16,
            fontWeight: FontWeight.normal,
            height: 1.3,
          );

    return AnimatedDefaultTextStyle(
      duration: AnimationDurations.medium,
      style: textStyle,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
