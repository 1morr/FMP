import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';

/// 歌词弹出窗口入口点
///
/// 由 desktop_multi_window 在独立 Flutter engine 中启动。
/// 通过 WindowMethodChannel 接收主窗口推送的歌词数据。
@pragma('vm:entry-point')
void lyricsWindowMain(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LyricsWindowApp());
}

/// 歌词窗口翻译字符串（从主窗口同步）
class _LyricsWindowStrings {
  String waitingLyrics = '等待歌词...';
  String unpin = '取消置顶';
  String pin = '置顶';
  String offsetAdjust = '偏移调整';
  String close = '关闭';
  String offset = '偏移';
  String reset = '重置';

  void updateFrom(Map<String, dynamic> map) {
    waitingLyrics = map['waitingLyrics'] as String? ?? waitingLyrics;
    unpin = map['unpin'] as String? ?? unpin;
    pin = map['pin'] as String? ?? pin;
    offsetAdjust = map['offsetAdjust'] as String? ?? offsetAdjust;
    close = map['close'] as String? ?? close;
    offset = map['offset'] as String? ?? offset;
    reset = map['reset'] as String? ?? reset;
  }
}

class LyricsWindowApp extends StatefulWidget {
  const LyricsWindowApp({super.key});

  @override
  State<LyricsWindowApp> createState() => _LyricsWindowAppState();
}

class _LyricsWindowAppState extends State<LyricsWindowApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  Color? _primaryColor;
  String? _fontFamily;
  final _strings = _LyricsWindowStrings();

  _LyricsWindowStrings get strings => _strings;

  void updateTheme({
    required ThemeMode themeMode,
    Color? primaryColor,
    String? fontFamily,
    Map<String, dynamic>? stringsMap,
  }) {
    setState(() {
      _themeMode = themeMode;
      _primaryColor = primaryColor;
      _fontFamily = fontFamily;
      if (stringsMap != null) {
        _strings.updateFrom(stringsMap);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(
        primaryColor: _primaryColor,
        fontFamily: _fontFamily,
      ),
      darkTheme: AppTheme.darkTheme(
        primaryColor: _primaryColor,
        fontFamily: _fontFamily,
      ),
      themeMode: _themeMode,
      home: const LyricsWindowPage(),
    );
  }
}

/// 歌词行数据（从主窗口反序列化）
class _LyricsLine {
  final Duration? timestamp;
  final String text;
  final String? subText;

  _LyricsLine({this.timestamp, required this.text, this.subText});
}

class LyricsWindowPage extends StatefulWidget {
  const LyricsWindowPage({super.key});

  @override
  State<LyricsWindowPage> createState() => _LyricsWindowPageState();
}

class _LyricsWindowPageState extends State<LyricsWindowPage> {
  List<_LyricsLine> _lines = [];
  bool _isSynced = false;
  int _currentLineIndex = -1;
  int _offsetMs = 0;
  String? _trackTitle;
  String? _trackArtist;
  String? _trackUniqueKey;
  bool _alwaysOnTop = true;
  bool _showOffsetControls = false;
  bool _isPlaying = false;

  /// 用户是否正在手动滚动
  bool _userScrolling = false;

  /// 恢复自动滚动的定时器
  Timer? _scrollResumeTimer;

  /// 是否正在执行程序化滚动（区分用户滚动）
  bool _programmaticScrolling = false;

  /// 缓存：代表行的参考宽度（歌词变化时重算）
  double? _cachedRefWidth;
  int _cachedLineCount = -1;
  String _cachedFirstLine = '';

  /// 字号范围（与 LyricsDisplay 一致）
  static const double _minFontSize = 14.0;
  static const double _maxFontSize = 30.0;
  static const double _subFontRatio = 0.65;
  static const double _refFontSize = 20.0;
  static const double _boldSafetyFactor = 0.95;

  final _scrollController = ItemScrollController();
  final _positionsListener = ItemPositionsListener.create();

  static const _channel = WindowMethodChannel(
    'lyrics_sync',
    mode: ChannelMode.bidirectional,
  );

  @override
  void initState() {
    super.initState();
    _setupChannel();
    _initWindow();
  }

  @override
  void dispose() {
    _scrollResumeTimer?.cancel();
    super.dispose();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    // 设置窗口属性
    await windowManager.setSize(const Size(400, 500));
    await windowManager.setMinimumSize(const Size(280, 300));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  void _setupChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'ping':
          return 'pong';
        case 'updateLyrics':
          _handleUpdateLyrics(call.arguments as String);
          return 'ok';
        case 'updatePosition':
          _handleUpdatePosition(call.arguments as String);
          return 'ok';
        case 'updateTheme':
          _handleUpdateTheme(call.arguments as String);
          return 'ok';
        case 'updatePlaybackState':
          _handleUpdatePlaybackState(call.arguments as String);
          return 'ok';
        case 'close':
          // 真正销毁窗口（仅 app 退出时由 destroy() 调用）
          await windowManager.close();
          return 'ok';
        default:
          return null;
      }
    });
  }

  void _handleUpdateTheme(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final themeModeIndex = data['themeMode'] as int? ?? 2; // default dark
    final primaryColorValue = data['primaryColor'] as int?;
    final fontFamily = data['fontFamily'] as String?;
    final stringsMap = data['strings'] as Map<String, dynamic>?;

    final appState = context.findAncestorStateOfType<_LyricsWindowAppState>();
    appState?.updateTheme(
      themeMode: ThemeMode.values[themeModeIndex.clamp(0, 2)],
      primaryColor: primaryColorValue != null ? Color(primaryColorValue) : null,
      fontFamily: fontFamily,
      stringsMap: stringsMap,
    );
  }

  void _handleUpdatePlaybackState(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final isPlaying = data['isPlaying'] as bool? ?? false;
    if (_isPlaying != isPlaying) {
      setState(() => _isPlaying = isPlaying);
    }
  }

  /// 发送播放控制命令到主窗口
  void _sendPlayPause() {
    try {
      _channel.invokeMethod('playPause', '');
    } catch (_) {}
  }

  void _sendNext() {
    try {
      _channel.invokeMethod('next', '');
    } catch (_) {}
  }

  void _sendPrevious() {
    try {
      _channel.invokeMethod('previous', '');
    } catch (_) {}
  }

  void _handleUpdateLyrics(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final linesData = data['lines'] as List<dynamic>?;

    setState(() {
      _lines = linesData?.map((l) {
        final map = l as Map<String, dynamic>;
        return _LyricsLine(
          timestamp: map['timestamp'] != null
              ? Duration(milliseconds: map['timestamp'] as int)
              : null,
          text: map['text'] as String,
          subText: map['subText'] as String?,
        );
      }).toList() ?? [];
      _isSynced = data['isSynced'] as bool? ?? false;
      _currentLineIndex = data['currentLineIndex'] as int? ?? -1;
      _offsetMs = data['offsetMs'] as int? ?? 0;
      _trackTitle = data['trackTitle'] as String?;
      _trackArtist = data['trackArtist'] as String?;
      _trackUniqueKey = data['trackUniqueKey'] as String?;
    });

    // 全量更新时重置用户滚动状态和字号缓存
    _userScrolling = false;
    _scrollResumeTimer?.cancel();
    _cachedRefWidth = null; // 歌词变化，重算字号
    // 等待帧渲染完成后再滚动（首次打开时列表尚未 attach）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToCurrentLine(jump: true);
    });
  }

  /// 计算代表行的参考宽度（中位数，缓存）
  void _ensureRefWidth(BuildContext context) {
    final firstLine = _lines.isNotEmpty ? _lines.first.text : '';
    if (_cachedRefWidth != null &&
        _cachedLineCount == _lines.length &&
        _cachedFirstLine == firstLine) {
      return;
    }

    final textDirection = Directionality.of(context);
    final widths = <double>[];

    for (final line in _lines) {
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
      _cachedLineCount = _lines.length;
      _cachedFirstLine = firstLine;
      return;
    }

    widths.sort();
    _cachedRefWidth = widths[widths.length ~/ 2];
    _cachedLineCount = _lines.length;
    _cachedFirstLine = firstLine;
  }

  /// 根据可用宽度计算最优字号（与 LyricsDisplay 逻辑一致）
  ({double main, double sub}) _getFontSizes(
      double availableWidth, BuildContext context) {
    _ensureRefWidth(context);

    if (_cachedRefWidth == null || _cachedRefWidth! <= 0) {
      final sub =
          (_maxFontSize * _subFontRatio).clamp(_minFontSize, _maxFontSize);
      return (main: _maxFontSize, sub: sub);
    }

    final safeWidth = availableWidth * _boldSafetyFactor;
    final mainSize = (_refFontSize * (safeWidth / _cachedRefWidth!))
        .clamp(_minFontSize, _maxFontSize);
    final subSize =
        (mainSize * _subFontRatio).clamp(_minFontSize, _maxFontSize);
    return (main: mainSize, sub: subSize);
  }

  void _handleUpdatePosition(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final newIndex = data['currentLineIndex'] as int? ?? -1;

    if (newIndex != _currentLineIndex) {
      setState(() {
        _currentLineIndex = newIndex;
      });
      if (!_userScrolling) {
        _scrollToCurrentLine();
      }
    }
  }

  void _scrollToCurrentLine({bool jump = false}) {
    if (!_isSynced || _currentLineIndex < 0 || _lines.isEmpty) return;
    if (!_scrollController.isAttached) return;

    if (jump) {
      // 立即跳转，无动画（首次打开/歌词全量更新时使用）
      _scrollController.jumpTo(
        index: _currentLineIndex,
        alignment: 0.35,
      );
    } else {
      _programmaticScrolling = true;
      _scrollController.scrollTo(
        index: _currentLineIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      ).then((_) {
        _programmaticScrolling = false;
      });
    }
  }

  /// 请求主窗口隐藏此子窗口（而非销毁，避免 window_manager channel 被置空）
  void _requestHide() {
    try {
      _channel.invokeMethod('requestHide', '');
    } catch (_) {
      // fallback: 如果 channel 不可用，直接关闭
      windowManager.close();
    }
  }

  /// 点击歌词行 → 发送 seekTo 命令到主窗口
  void _seekToLine(int index) {
    if (index < 0 || index >= _lines.length) return;
    final line = _lines[index];
    if (line.timestamp == null) return;

    try {
      _channel.invokeMethod(
        'seekTo',
        jsonEncode({
          'timestampMs': line.timestamp!.inMilliseconds,
          'offsetMs': _offsetMs,
        }),
      );
    } catch (_) {}
  }

  /// 调整 offset → 发送 adjustOffset 命令到主窗口
  void _adjustOffset(int deltaMs) {
    if (_trackUniqueKey == null) return;
    final newOffsetMs = _offsetMs + deltaMs;

    try {
      _channel.invokeMethod(
        'adjustOffset',
        jsonEncode({
          'trackUniqueKey': _trackUniqueKey,
          'newOffsetMs': newOffsetMs,
        }),
      );
    } catch (_) {}

    // 乐观更新本地 offset 显示
    setState(() => _offsetMs = newOffsetMs);
  }

  /// 重置 offset → 发送 resetOffset 命令到主窗口
  void _resetOffset() {
    if (_trackUniqueKey == null) return;

    try {
      _channel.invokeMethod(
        'resetOffset',
        jsonEncode({'trackUniqueKey': _trackUniqueKey}),
      );
    } catch (_) {}

    // 乐观更新本地 offset 显示
    setState(() => _offsetMs = 0);
  }

  /// 获取翻译字符串
  _LyricsWindowStrings get _strings {
    final appState = context.findAncestorStateOfType<_LyricsWindowAppState>();
    return appState?.strings ?? _LyricsWindowStrings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 标题栏（可拖动）
          _buildTitleBar(),
          // 歌词内容
          Expanded(
            child: _lines.isEmpty
                ? _buildEmpty()
                : _buildLyricsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      // 允许拖动窗口
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        padding: const EdgeInsets.only(left: 16, right: 4, top: 6, bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.lyrics_outlined, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _trackTitle ?? 'Lyrics',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_trackArtist != null)
                    Text(
                      _trackArtist!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // 播放控制按钮
            IconButton(
              icon: Icon(Icons.skip_previous_rounded, size: 18, color: colorScheme.onSurfaceVariant),
              onPressed: _sendPrevious,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 20,
                color: colorScheme.onSurface,
              ),
              onPressed: _sendPlayPause,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            IconButton(
              icon: Icon(Icons.skip_next_rounded, size: 18, color: colorScheme.onSurfaceVariant),
              onPressed: _sendNext,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            const SizedBox(width: 4),
            // 置顶切换
            IconButton(
              icon: Icon(
                _alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                size: 16,
                color: _alwaysOnTop
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              onPressed: () async {
                setState(() => _alwaysOnTop = !_alwaysOnTop);
                await windowManager.setAlwaysOnTop(_alwaysOnTop);
              },
              tooltip: _alwaysOnTop ? _strings.unpin : _strings.pin,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            // Offset 调整切换
            if (_isSynced && _lines.isNotEmpty)
              IconButton(
                icon: Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: _showOffsetControls
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  setState(() => _showOffsetControls = !_showOffsetControls);
                },
                tooltip: _strings.offsetAdjust,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            // 关闭按钮（发送 requestHide 到主窗口，隐藏而非销毁）
            IconButton(
              icon: Icon(Icons.close, size: 16, color: colorScheme.onSurfaceVariant),
              onPressed: _requestHide,
              tooltip: _strings.close,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            _strings.waitingLyrics,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsList() {
    // 非同步歌词：简单列表
    if (!_isSynced) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - 32; // 16 * 2 padding
          final fontSizes = _getFontSizes(availableWidth, context);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            itemCount: _lines.length,
            itemBuilder: (context, index) =>
                _buildLyricsLine(index, false, fontSizes),
          );
        },
      );
    }

    // 同步歌词：使用 ScrollablePositionedList + 用户滚动检测
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth - 32;
              final fontSizes = _getFontSizes(availableWidth, context);

              return NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // 忽略程序化滚动
                  if (_programmaticScrolling) return false;

                  if (notification is ScrollStartNotification) {
                    _scrollResumeTimer?.cancel();
                    if (!_userScrolling) {
                      setState(() => _userScrolling = true);
                    }
                  } else if (notification is ScrollEndNotification) {
                    // 用户停止滚动后 3 秒恢复自动滚动
                    _scrollResumeTimer?.cancel();
                    _scrollResumeTimer = Timer(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _userScrolling = false);
                    });
                  }
                  return false;
                },
                child: ScrollablePositionedList.builder(
                  itemScrollController: _scrollController,
                  itemPositionsListener: _positionsListener,
                  padding: EdgeInsets.only(
                    top: _showOffsetControls ? 56 : 20,
                    bottom: 20,
                    left: 16,
                    right: 16,
                  ),
                  itemCount: _lines.length,
                  itemBuilder: (context, index) {
                    final isCurrent = index == _currentLineIndex;
                    return _buildLyricsLine(index, isCurrent, fontSizes);
                  },
                ),
              );
            },
          ),
        ),
        // Offset 调整栏
        if (_showOffsetControls)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildOffsetBar(),
          ),
      ],
    );
  }

  Widget _buildLyricsLine(
      int index, bool isCurrent, ({double main, double sub}) fontSizes) {
    final line = _lines[index];
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _isSynced && line.timestamp != null ? () => _seekToLine(index) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 主歌词
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: fontSizes.main,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.4),
                height: 1.4,
              ),
              child: Text(
                line.text,
                textAlign: TextAlign.center,
              ),
            ),
            // 副歌词（翻译/罗马音）
            if (line.subText != null && line.subText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: fontSizes.sub,
                    fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
                    color: isCurrent
                        ? colorScheme.onSurface.withValues(alpha: 0.7)
                        : colorScheme.onSurface.withValues(alpha: 0.3),
                    height: 1.3,
                  ),
                  child: Text(
                    line.subText!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Offset 调整栏
  Widget _buildOffsetBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Label
            Text(
              _strings.offset,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            // Current offset display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatOffset(_offsetMs),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Adjustment buttons
            _buildOffsetButton(Icons.fast_rewind, -1000, '-1s'),
            _buildOffsetButton(Icons.remove, -500, '-0.5s'),
            _buildOffsetButton(Icons.remove_circle_outline, -100, '-0.1s'),
            const SizedBox(width: 4),
            // Reset button
            Tooltip(
              message: _strings.reset,
              child: InkWell(
                onTap: _offsetMs != 0 ? _resetOffset : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.refresh,
                    size: 16,
                    color: _offsetMs != 0
                        ? colorScheme.onSurface
                        : colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _buildOffsetButton(Icons.add_circle_outline, 100, '+0.1s'),
            _buildOffsetButton(Icons.add, 500, '+0.5s'),
            _buildOffsetButton(Icons.fast_forward, 1000, '+1s'),
          ],
        ),
      ),
    );
  }

  Widget _buildOffsetButton(IconData icon, int deltaMs, String label) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => _adjustOffset(deltaMs),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: colorScheme.onSurface,
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
}
