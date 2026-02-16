import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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

  /// 长按回调（播放器页面用于切回封面）
  final VoidCallback? onLongPress;

  /// 是否显示 offset 调整控件
  final bool showOffsetControls;

  const LyricsDisplay({
    super.key,
    this.compact = false,
    this.onLongPress,
    this.showOffsetControls = false,
  });

  @override
  ConsumerState<LyricsDisplay> createState() => _LyricsDisplayState();
}

class _LyricsDisplayState extends ConsumerState<LyricsDisplay> {
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();

  /// 当前高亮行索引（用于检测变化，避免重复滚动）
  int _currentLineIndex = -1;

  /// 用户是否正在手动滚动
  bool _userScrolling = false;

  /// 是否是首次构建（用于判断是否需要初始滚动）
  bool _isFirstBuild = true;

  /// 缓存：代表行的参考宽度（歌词变化时重算）
  double? _cachedRefWidth;
  int _cachedLineCount = -1;
  String _cachedFirstLine = '';

  /// 字号范围
  static const double _minFontSize = 14.0;
  static const double _maxFontSize = 30.0;
  static const double _subFontRatio = 0.65;
  static const double _refFontSize = 20.0;

  /// bold 相对 normal 的宽度安全系数（避免 bold 当前行溢出）
  static const double _boldSafetyFactor = 0.95;

  /// 计算用于字号基准的代表行宽度（结果缓存，歌词不变时不重算）
  ///
  /// 使用中位数行宽：约一半的行刚好单行显示，较长的行自动换行。
  /// 不受少数异常长行（版权声明等）影响，也不受整体歌词偏长影响。
  void _ensureRefWidth(List<LyricsLine> lines, BuildContext context) {
    final firstLine = lines.isNotEmpty ? lines.first.text : '';
    if (_cachedRefWidth != null &&
        _cachedLineCount == lines.length &&
        _cachedFirstLine == firstLine) {
      return;
    }

    final textDirection = Directionality.of(context);
    final widths = <double>[];

    for (final line in lines) {
      if (line.text.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: line.text,
          style: const TextStyle(
              fontSize: _refFontSize, fontWeight: FontWeight.bold),
        ),
        maxLines: 1,
        textDirection: textDirection,
      )..layout();
      widths.add(painter.width);
      painter.dispose();
    }

    if (widths.isEmpty) {
      _cachedRefWidth = 0;
      _cachedLineCount = lines.length;
      _cachedFirstLine = firstLine;
      return;
    }

    widths.sort();
    // 中位数
    final medianIndex = widths.length ~/ 2;
    _cachedRefWidth = widths[medianIndex];
    _cachedLineCount = lines.length;
    _cachedFirstLine = firstLine;
  }

  /// 根据可用宽度计算最优字号
  ///
  /// 字体渲染宽度与字号近似线性关系，直接用比例计算，O(1)。
  /// 基于中位数行宽：多数行单行显示，较长行自动换行。
  ({double main, double sub}) _getFontSizes(
    ParsedLyrics lyrics,
    double availableWidth,
    BuildContext context,
  ) {
    _ensureRefWidth(lyrics.lines, context);

    if (_cachedRefWidth == null || _cachedRefWidth! <= 0) {
      final sub =
          (_maxFontSize * _subFontRatio).clamp(_minFontSize, _maxFontSize);
      return (main: _maxFontSize, sub: sub);
    }

    final safeWidth = availableWidth * _boldSafetyFactor;
    final mainSize =
        (_refFontSize * (safeWidth / _cachedRefWidth!)).clamp(
      _minFontSize,
      _maxFontSize,
    );

    final subSize =
        (mainSize * _subFontRatio).clamp(_minFontSize, _maxFontSize);
    return (main: mainSize, sub: subSize);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lyricsContent = ref.watch(currentLyricsContentProvider);
    final parsedLyrics = ref.watch(parsedLyricsProvider);
    final match = ref.watch(currentLyricsMatchProvider).valueOrNull;

    final isAutoMatching = ref.watch(lyricsAutoMatchingProvider);

    // 歌词内容加载中
    if (lyricsContent.isLoading) {
      return _buildCentered(
        child: const CircularProgressIndicator(),
      );
    }

    // 无匹配：自动匹配进行中显示加载动画，否则显示无歌词
    if (match == null) {
      if (isAutoMatching) {
        return _buildCentered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                t.lyrics.autoMatching,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      }
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
    final currentTrack = playerState.currentTrack;

    // 计算当前行
    final newIndex = LrcParser.findCurrentLineIndex(
      lyrics.lines,
      position,
      offsetMs,
    );

    // 首次构建时立即滚动到当前行
    if (_isFirstBuild && newIndex >= 0) {
      _isFirstBuild = false;
      _currentLineIndex = newIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLine(newIndex, immediate: true);
      });
    }
    // 只在行变化时触发滚动
    else if (newIndex != _currentLineIndex) {
      _currentLineIndex = newIndex;
      if (!_userScrolling && newIndex >= 0) {
        _scrollToLine(newIndex);
      }
    }

    final hPad = widget.compact ? 12.0 : 24.0;

    return GestureDetector(
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          // Offset adjustment controls (only show when enabled)
          if (widget.showOffsetControls && currentTrack != null)
            _OffsetAdjustmentBar(
              trackUniqueKey: currentTrack.uniqueKey,
              currentOffsetMs: offsetMs,
              compact: widget.compact,
            ),
          // Lyrics list
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth - hPad * 2;
                final fontSizes = _getFontSizes(lyrics, availableWidth, context);

                return NotificationListener<ScrollNotification>(
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
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    padding: EdgeInsets.symmetric(
                      vertical: widget.compact ? 16 : 80,
                      horizontal: hPad,
                    ),
                    itemCount: lyrics.lines.length,
                    itemBuilder: (context, index) {
                      final line = lyrics.lines[index];
                      final isCurrent = index == _currentLineIndex;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _LyricsLineWidget(
                          key: ValueKey(index),
                          text: line.text,
                          subText: line.subText,
                          isCurrent: isCurrent,
                          mainFontSize: fontSizes.main,
                          subFontSize: fontSizes.sub,
                          colorScheme: colorScheme,
                          onTap: () => _seekToLyricsLine(line, offsetMs),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
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
      onLongPress: widget.onLongPress,
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
      onLongPress: widget.onLongPress,
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
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Center(child: child),
    );
  }

  /// 点击歌词行跳转到对应时间点
  ///
  /// offset 公式：adjustedMs = position + offsetMs
  /// 所以 position = timestamp - offsetMs
  void _seekToLyricsLine(LyricsLine line, int offsetMs) {
    final targetMs = line.timestamp.inMilliseconds - offsetMs;
    final targetPosition = Duration(milliseconds: targetMs.clamp(0, double.maxFinite.toInt()));
    ref.read(audioControllerProvider.notifier).seekTo(targetPosition);
  }

  /// 平滑滚动到指定行（居中对齐）
  void _scrollToLine(int index, {bool immediate = false}) {
    if (!_itemScrollController.isAttached) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScrollController.isAttached) return;

      if (immediate) {
        _itemScrollController.jumpTo(
          index: index,
          alignment: 0.35,
        );
      } else {
        _itemScrollController.scrollTo(
          index: index,
          alignment: 0.35,
          duration: AnimationDurations.normal,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }
}

/// 单行歌词组件（支持原文 + 附加文本）
class _LyricsLineWidget extends StatelessWidget {
  final String text;
  final String? subText;
  final bool isCurrent;
  final double mainFontSize;
  final double subFontSize;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  const _LyricsLineWidget({
    super.key,
    required this.text,
    this.subText,
    required this.isCurrent,
    required this.mainFontSize,
    required this.subFontSize,
    required this.colorScheme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 当前行和非当前行使用相同字号，仅通过颜色和粗细区分
    final mainStyle = isCurrent
        ? TextStyle(
            color: colorScheme.primary,
            fontSize: mainFontSize,
            fontWeight: FontWeight.bold,
            height: 1.4,
          )
        : TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.4),
            fontSize: mainFontSize,
            fontWeight: FontWeight.normal,
            height: 1.4,
          );

    final hasSubText = subText != null && subText!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: AnimationDurations.medium,
            style: mainStyle,
            child: Text(
              text,
              textAlign: TextAlign.center,
            ),
          ),
          if (hasSubText)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: AnimatedDefaultTextStyle(
                duration: AnimationDurations.medium,
                style: TextStyle(
                  color: isCurrent
                      ? colorScheme.primary.withValues(alpha: 0.7)
                      : colorScheme.onSurface.withValues(alpha: 0.25),
                  fontSize: subFontSize,
                  fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
                  height: 1.4,
                ),
                child: Text(
                  subText!,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 歌词偏移调整控制栏
class _OffsetAdjustmentBar extends ConsumerWidget {
  final String trackUniqueKey;
  final int currentOffsetMs;
  final bool compact;

  const _OffsetAdjustmentBar({
    required this.trackUniqueKey,
    required this.currentOffsetMs,
    required this.compact,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 16,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Label
          Text(
            t.lyrics.offset,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: compact ? 12 : 13,
            ),
          ),
          const SizedBox(width: 8),
          // Current offset display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: AppRadius.borderRadiusXs,
            ),
            child: Text(
              _formatOffset(currentOffsetMs),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 12 : 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Adjustment buttons
          _buildOffsetButton(
            context,
            ref,
            icon: Icons.fast_rewind,
            deltaMs: -1000,
            label: '-1s',
            compact: compact,
          ),
          _buildOffsetButton(
            context,
            ref,
            icon: Icons.remove,
            deltaMs: -500,
            label: '-0.5s',
            compact: compact,
          ),
          _buildOffsetButton(
            context,
            ref,
            icon: Icons.remove_circle_outline,
            deltaMs: -100,
            label: '-0.1s',
            compact: compact,
          ),
          const SizedBox(width: 4),
          // Reset button
          _buildResetButton(context, ref, compact),
          const SizedBox(width: 4),
          _buildOffsetButton(
            context,
            ref,
            icon: Icons.add_circle_outline,
            deltaMs: 100,
            label: '+0.1s',
            compact: compact,
          ),
          _buildOffsetButton(
            context,
            ref,
            icon: Icons.add,
            deltaMs: 500,
            label: '+0.5s',
            compact: compact,
          ),
          _buildOffsetButton(
            context,
            ref,
            icon: Icons.fast_forward,
            deltaMs: 1000,
            label: '+1s',
            compact: compact,
          ),
        ],
      ),
    );
  }

  Widget _buildOffsetButton(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required int deltaMs,
    required String label,
    required bool compact,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => _adjustOffset(ref, deltaMs),
        borderRadius: AppRadius.borderRadiusXs,
        child: Container(
          padding: EdgeInsets.all(compact ? 4 : 6),
          child: Icon(
            icon,
            size: compact ? 16 : 18,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildResetButton(BuildContext context, WidgetRef ref, bool compact) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: t.lyrics.resetOffset,
      child: InkWell(
        onTap: currentOffsetMs != 0 ? () => _resetOffset(ref) : null,
        borderRadius: AppRadius.borderRadiusXs,
        child: Container(
          padding: EdgeInsets.all(compact ? 4 : 6),
          child: Icon(
            Icons.refresh,
            size: compact ? 16 : 18,
            color: currentOffsetMs != 0
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  String _formatOffset(int offsetMs) {
    if (offsetMs == 0) return '0.0s';
    final seconds = offsetMs / 1000;
    return '${seconds >= 0 ? '+' : ''}${seconds.toStringAsFixed(1)}s';
  }

  Future<void> _adjustOffset(WidgetRef ref, int deltaMs) async {
    final newOffsetMs = currentOffsetMs + deltaMs;
    await ref
        .read(lyricsSearchProvider.notifier)
        .updateOffset(trackUniqueKey, newOffsetMs);
  }

  Future<void> _resetOffset(WidgetRef ref) async {
    await ref
        .read(lyricsSearchProvider.notifier)
        .updateOffset(trackUniqueKey, 0);
  }
}
