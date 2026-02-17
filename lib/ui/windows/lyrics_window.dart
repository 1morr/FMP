import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:window_manager/window_manager.dart';

/// 歌词弹出窗口入口点
///
/// 由 desktop_multi_window 在独立 Flutter engine 中启动。
/// 通过 WindowMethodChannel 接收主窗口推送的歌词数据。
@pragma('vm:entry-point')
void lyricsWindowMain(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LyricsWindowApp());
}

class LyricsWindowApp extends StatelessWidget {
  const LyricsWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      ),
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
        case 'close':
          await windowManager.close();
          return 'ok';
        default:
          return null;
      }
    });
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
    _scrollToCurrentLine();
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

  void _scrollToCurrentLine() {
    if (!_isSynced || _currentLineIndex < 0 || _lines.isEmpty) return;
    if (!_scrollController.isAttached) return;

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
    return GestureDetector(
      // 允许拖动窗口
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        padding: const EdgeInsets.only(left: 16, right: 4, top: 6, bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.lyrics_outlined, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _trackTitle ?? 'Lyrics',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_trackArtist != null)
                    Text(
                      _trackArtist!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // 置顶切换
            IconButton(
              icon: Icon(
                _alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                size: 16,
                color: _alwaysOnTop ? Colors.white : Colors.white54,
              ),
              onPressed: () async {
                setState(() => _alwaysOnTop = !_alwaysOnTop);
                await windowManager.setAlwaysOnTop(_alwaysOnTop);
              },
              tooltip: _alwaysOnTop ? '取消置顶' : '置顶',
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
                  color: _showOffsetControls ? Colors.white : Colors.white54,
                ),
                onPressed: () {
                  setState(() => _showOffsetControls = !_showOffsetControls);
                },
                tooltip: '偏移调整',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            // 关闭按钮
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white54),
              onPressed: () => windowManager.close(),
              tooltip: '关闭',
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            '等待歌词...',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.5),
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
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.4),
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
                        ? Colors.white.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.3),
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

  /// Offset 调整栏（简化版，适配弹出窗口暗色主题）
  Widget _buildOffsetBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
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
              '偏移',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 8),
            // Current offset display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatOffset(_offsetMs),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
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
              message: '重置',
              child: InkWell(
                onTap: _offsetMs != 0 ? _resetOffset : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.refresh,
                    size: 16,
                    color: _offsetMs != 0
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.2),
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
            color: Colors.white,
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
