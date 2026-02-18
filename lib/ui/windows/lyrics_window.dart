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
  String displayOriginal = '只显示原文';
  String displayPreferTranslated = '优先显示翻译';
  String displayPreferRomaji = '优先显示罗马音';
  String transparentMode = '透明模式';
  String normalMode = '普通模式';
  String singleLine = '单行模式';
  String fullLyrics = '全部歌词模式';

  void updateFrom(Map<String, dynamic> map) {
    waitingLyrics = map['waitingLyrics'] as String? ?? waitingLyrics;
    unpin = map['unpin'] as String? ?? unpin;
    pin = map['pin'] as String? ?? pin;
    offsetAdjust = map['offsetAdjust'] as String? ?? offsetAdjust;
    close = map['close'] as String? ?? close;
    offset = map['offset'] as String? ?? offset;
    reset = map['reset'] as String? ?? reset;
    displayOriginal = map['displayOriginal'] as String? ?? displayOriginal;
    displayPreferTranslated =
        map['displayPreferTranslated'] as String? ?? displayPreferTranslated;
    displayPreferRomaji =
        map['displayPreferRomaji'] as String? ?? displayPreferRomaji;
    transparentMode = map['transparentMode'] as String? ?? transparentMode;
    normalMode = map['normalMode'] as String? ?? normalMode;
    singleLine = map['singleLine'] as String? ?? singleLine;
    fullLyrics = map['fullLyrics'] as String? ?? fullLyrics;
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
    // ExcludeSemantics 包裹整个 MaterialApp，防止子窗口中
    // Tooltip Overlay 等组件触发 AXTree 错误
    return ExcludeSemantics(
      child: MaterialApp(
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
      ),
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
  int _displayModeIndex = 0; // 0=original, 1=preferTranslated, 2=preferRomaji
  bool _transparentMode = false;
  bool _singleLineMode = false;
  bool _isHovering = false;

  /// 用户是否正在手动滚动
  bool _userScrolling = false;
  Timer? _scrollResumeTimer;
  bool _programmaticScrolling = false;

  /// 缓存：代表行的参考宽度（歌词变化时重算）
  double? _cachedRefWidth;
  int _cachedLineCount = -1;
  String _cachedFirstLine = '';

  static const double _minFontSize = 14.0;
  static const double _maxFontSize = 30.0;
  static const double _subFontRatio = 0.65;
  static const double _refFontSize = 20.0;
  static const double _boldSafetyFactor = 0.95;

  /// 透明模式下的描边文字阴影
  static const _strokeShadows = [
    Shadow(offset: Offset(-1.5, -1.5), blurRadius: 3, color: Colors.black),
    Shadow(offset: Offset(1.5, -1.5), blurRadius: 3, color: Colors.black),
    Shadow(offset: Offset(1.5, 1.5), blurRadius: 3, color: Colors.black),
    Shadow(offset: Offset(-1.5, 1.5), blurRadius: 3, color: Colors.black),
  ];

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
        case 'updateLyricsDisplayMode':
          _handleUpdateLyricsDisplayMode(call.arguments as String);
          return 'ok';
        case 'close':
          await windowManager.close();
          return 'ok';
        default:
          return null;
      }
    });
  }

  // ─── Channel handlers ───

  void _handleUpdateTheme(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final themeModeIndex = data['themeMode'] as int? ?? 2;
    final primaryColorValue = data['primaryColor'] as int?;
    final fontFamily = data['fontFamily'] as String?;
    final stringsMap = data['strings'] as Map<String, dynamic>?;

    final appState = context.findAncestorStateOfType<_LyricsWindowAppState>();
    appState?.updateTheme(
      themeMode: ThemeMode.values[themeModeIndex.clamp(0, 2)],
      primaryColor:
          primaryColorValue != null ? Color(primaryColorValue) : null,
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

  void _handleUpdateLyricsDisplayMode(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final modeIndex = data['modeIndex'] as int? ?? 0;
    if (_displayModeIndex != modeIndex) {
      setState(() => _displayModeIndex = modeIndex);
    }
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
          }).toList() ??
          [];
      _isSynced = data['isSynced'] as bool? ?? false;
      _currentLineIndex = data['currentLineIndex'] as int? ?? -1;
      _offsetMs = data['offsetMs'] as int? ?? 0;
      _trackTitle = data['trackTitle'] as String?;
      _trackArtist = data['trackArtist'] as String?;
      _trackUniqueKey = data['trackUniqueKey'] as String?;
    });

    _userScrolling = false;
    _scrollResumeTimer?.cancel();
    _cachedRefWidth = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToCurrentLine(jump: true);
    });
  }

  void _handleUpdatePosition(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final newIndex = data['currentLineIndex'] as int? ?? -1;

    if (newIndex != _currentLineIndex) {
      setState(() => _currentLineIndex = newIndex);
      if (!_userScrolling) _scrollToCurrentLine();
    }
  }

  // ─── Commands to main window ───

  void _sendPlayPause() {
    try { _channel.invokeMethod('playPause', ''); } catch (_) {}
  }

  void _sendNext() {
    try { _channel.invokeMethod('next', ''); } catch (_) {}
  }

  void _sendPrevious() {
    try { _channel.invokeMethod('previous', ''); } catch (_) {}
  }

  void _requestHide() {
    try {
      _channel.invokeMethod('requestHide', '');
    } catch (_) {
      windowManager.close();
    }
  }

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
    setState(() => _offsetMs = newOffsetMs);
  }

  void _resetOffset() {
    if (_trackUniqueKey == null) return;
    try {
      _channel.invokeMethod(
        'resetOffset',
        jsonEncode({'trackUniqueKey': _trackUniqueKey}),
      );
    } catch (_) {}
    setState(() => _offsetMs = 0);
  }

  // ─── Actions ───

  void _cycleLyricsDisplayMode() {
    final nextIndex = (_displayModeIndex + 1) % 3;
    setState(() => _displayModeIndex = nextIndex);
    try {
      _channel.invokeMethod(
        'changeLyricsDisplayMode',
        jsonEncode({'modeIndex': nextIndex}),
      );
    } catch (_) {}
  }

  Future<void> _toggleTransparentMode() async {
    final newMode = !_transparentMode;
    final brightness = Theme.of(context).brightness;
    setState(() {
      _transparentMode = newMode;
      if (!newMode) _isHovering = false;
    });
    if (newMode) {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setBackgroundColor(Colors.transparent);
    } else {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setHasShadow(true);
      final bgColor = brightness == Brightness.dark
          ? const Color(0xFF1C1B1F)
          : const Color(0xFFFFFBFE);
      await windowManager.setBackgroundColor(bgColor);
    }
  }

  // ─── Scroll ───

  void _scrollToCurrentLine({bool jump = false}) {
    if (!_isSynced || _currentLineIndex < 0 || _lines.isEmpty) return;
    if (!_scrollController.isAttached) return;

    if (jump) {
      _scrollController.jumpTo(index: _currentLineIndex, alignment: 0.35);
    } else {
      _programmaticScrolling = true;
      _scrollController
          .scrollTo(
            index: _currentLineIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: 0.35,
          )
          .then((_) => _programmaticScrolling = false);
    }
  }

  // ─── Font size calculation ───

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
    } else {
      widths.sort();
      _cachedRefWidth = widths[widths.length ~/ 2];
    }
    _cachedLineCount = _lines.length;
    _cachedFirstLine = firstLine;
  }

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

  // ─── Helpers ───

  _LyricsWindowStrings get _strings {
    final appState = context.findAncestorStateOfType<_LyricsWindowAppState>();
    return appState?.strings ?? _LyricsWindowStrings();
  }

  IconData get _displayModeIcon {
    switch (_displayModeIndex) {
      case 1: return Icons.translate;
      case 2: return Icons.abc;
      default: return Icons.title;
    }
  }

  String get _displayModeTooltip {
    switch (_displayModeIndex) {
      case 1: return _strings.displayPreferTranslated;
      case 2: return _strings.displayPreferRomaji;
      default: return _strings.displayOriginal;
    }
  }

  String _formatOffset(int offsetMs) {
    if (offsetMs == 0) return '0.0s';
    final seconds = offsetMs / 1000;
    return '${seconds >= 0 ? '+' : ''}${seconds.toStringAsFixed(1)}s';
  }

  Widget _buildContent() {
    if (_lines.isEmpty) return _buildEmpty();
    if (_singleLineMode) return _buildSingleLine();
    return _buildLyricsList();
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    if (_transparentMode) {
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.only(top: _isHovering ? 48 : 0),
                  child: _buildContent(),
                ),
              ),
              // 标题栏始终在树中，通过透明度 + IgnorePointer 控制显隐
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_isHovering,
                  child: AnimatedOpacity(
                    opacity: _isHovering ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: _buildTitleBar(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          _buildTitleBar(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    final t = _transparentMode;
    final colorScheme = Theme.of(context).colorScheme;

    // 透明模式：白色系文字 + 半透明深色背景
    // 普通模式：跟随主题
    final iconColor = t ? Colors.white70 : colorScheme.onSurfaceVariant;
    final titleColor = t ? Colors.white : colorScheme.onSurface;
    final subtitleColor = t ? Colors.white70 : colorScheme.onSurfaceVariant;
    final activeColor = t ? Colors.amber : colorScheme.primary;
    final bgColor = t ? Colors.black.withValues(alpha: 0.85) : null;
    final borderColor = t
        ? Colors.white12
        : colorScheme.outlineVariant.withValues(alpha: 0.3);

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        padding: const EdgeInsets.only(left: 16, right: 4, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Row(
          children: [
            Icon(Icons.lyrics_outlined, size: 18, color: iconColor),
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
                      color: titleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_trackArtist != null)
                    Text(
                      _trackArtist!,
                      style: TextStyle(fontSize: 11, color: subtitleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // 播放控制
            _titleBarButton(Icons.skip_previous_rounded, 18, _sendPrevious,
                color: iconColor),
            _titleBarButton(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              20,
              _sendPlayPause,
              color: titleColor,
            ),
            _titleBarButton(Icons.skip_next_rounded, 18, _sendNext,
                color: iconColor),
            const SizedBox(width: 4),
            // 歌词显示模式
            _titleBarButton(
              _displayModeIcon,
              16,
              _cycleLyricsDisplayMode,
              color: iconColor,
              tooltip: _displayModeTooltip,
            ),
            // 单行/全部歌词切换
            _titleBarButton(
              _singleLineMode ? Icons.view_headline : Icons.short_text,
              16,
              () => setState(() => _singleLineMode = !_singleLineMode),
              color: _singleLineMode ? activeColor : iconColor,
              tooltip: _singleLineMode ? _strings.fullLyrics : _strings.singleLine,
            ),
            // 透明模式切换
            _titleBarButton(
              t ? Icons.opacity : Icons.format_color_fill,
              16,
              _toggleTransparentMode,
              color: t ? activeColor : iconColor,
              tooltip: t ? _strings.normalMode : _strings.transparentMode,
            ),
            // 置顶
            _titleBarButton(
              _alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
              16,
              () async {
                setState(() => _alwaysOnTop = !_alwaysOnTop);
                await windowManager.setAlwaysOnTop(_alwaysOnTop);
              },
              color: _alwaysOnTop ? activeColor : iconColor,
              tooltip: _alwaysOnTop ? _strings.unpin : _strings.pin,
            ),
            // Offset 调整
            if (_isSynced && _lines.isNotEmpty)
              _titleBarButton(
                Icons.timer_outlined,
                16,
                () => setState(
                    () => _showOffsetControls = !_showOffsetControls),
                color: _showOffsetControls ? activeColor : iconColor,
                tooltip: _strings.offsetAdjust,
              ),
            // 关闭
            _titleBarButton(Icons.close, 16, _requestHide,
                color: iconColor, tooltip: _strings.close),
          ],
        ),
      ),
    );
  }

  Widget _titleBarButton(
    IconData icon,
    double size,
    VoidCallback onPressed, {
    Color? color,
    String? tooltip,
  }) {
    return IconButton(
      icon: Icon(icon, size: size, color: color),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }

  Widget _buildEmpty() {
    final t = _transparentMode;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 48,
            color: t
                ? Colors.white.withValues(alpha: 0.4)
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            shadows: t ? _strokeShadows : null,
          ),
          const SizedBox(height: 12),
          Text(
            _strings.waitingLyrics,
            style: TextStyle(
              fontSize: 14,
              color: t ? Colors.white70 : colorScheme.onSurfaceVariant,
              shadows: t ? _strokeShadows : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleLine() {
    final t = _transparentMode;
    final colorScheme = Theme.of(context).colorScheme;

    // 获取当前行文本
    String mainText = '';
    String? subText;
    if (_currentLineIndex >= 0 && _currentLineIndex < _lines.length) {
      final line = _lines[_currentLineIndex];
      mainText = line.text;
      subText = line.subText;
    }
    if (mainText.isEmpty) {
      mainText = _trackTitle ?? '';
    }

    final mainColor = t ? Colors.white : colorScheme.onSurface;
    final subColor = t
        ? Colors.white.withValues(alpha: 0.7)
        : colorScheme.onSurface.withValues(alpha: 0.6);
    final hasSubText = subText != null && subText.isNotEmpty;

    return GestureDetector(
      onTap: _isSynced && _currentLineIndex >= 0
          ? () => _seekToLine(_currentLineIndex)
          : null,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth - 32;
          final maxH = constraints.maxHeight - 24;
          if (maxW <= 0 || maxH <= 0) return const SizedBox.shrink();

          // 用参考字号测量主文本宽度，然后按比例算出填满宽度的字号
          const refSize = 100.0;
          final td = Directionality.of(context);
          final mainPainter = TextPainter(
            text: TextSpan(
              text: mainText,
              style: const TextStyle(
                  fontSize: refSize, fontWeight: FontWeight.bold),
            ),
            maxLines: 1,
            textDirection: td,
          )..layout();
          final mainTextW = mainPainter.width;
          mainPainter.dispose();

          // 按宽度算出的字号
          double mainFontSize = mainTextW > 0
              ? (refSize * maxW / mainTextW)
              : refSize;

          // 按高度限制：主文本行高约 1.3，副文本约 0.7 倍主文本
          final totalLineH = hasSubText ? 1.3 + 0.7 * 0.9 : 1.3;
          final maxByHeight = maxH / totalLineH;
          mainFontSize = mainFontSize.clamp(12.0, maxByHeight);

          final subFontSize = mainFontSize * 0.7;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mainText,
                    style: TextStyle(
                      fontSize: mainFontSize,
                      fontWeight: FontWeight.bold,
                      color: mainColor,
                      height: 1.3,
                      shadows: t ? _strokeShadows : null,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                  if (hasSubText)
                    Text(
                      subText!,
                      style: TextStyle(
                        fontSize: subFontSize,
                        fontWeight: FontWeight.w500,
                        color: subColor,
                        height: 1.3,
                        shadows: t ? _strokeShadows : null,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLyricsList() {
    if (!_isSynced) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - 32;
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

    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth - 32;
              final fontSizes = _getFontSizes(availableWidth, context);

              return NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (_programmaticScrolling) return false;
                  if (notification is ScrollStartNotification) {
                    _scrollResumeTimer?.cancel();
                    _userScrolling = true;
                  } else if (notification is ScrollEndNotification) {
                    _scrollResumeTimer?.cancel();
                    _scrollResumeTimer =
                        Timer(const Duration(seconds: 3), () {
                      if (mounted) _userScrolling = false;
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
        if (_showOffsetControls)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _transparentMode
                ? IgnorePointer(
                    ignoring: !_isHovering,
                    child: AnimatedOpacity(
                      opacity: _isHovering ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: _buildOffsetBar(),
                    ),
                  )
                : _buildOffsetBar(),
          ),
      ],
    );
  }

  Widget _buildLyricsLine(
      int index, bool isCurrent, ({double main, double sub}) fontSizes) {
    final line = _lines[index];
    final t = _transparentMode;
    final colorScheme = Theme.of(context).colorScheme;

    final mainColor = t
        ? (isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.5))
        : (isCurrent
            ? colorScheme.onSurface
            : colorScheme.onSurface.withValues(alpha: 0.4));
    final subColor = t
        ? (isCurrent
            ? Colors.white.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.4))
        : (isCurrent
            ? colorScheme.onSurface.withValues(alpha: 0.7)
            : colorScheme.onSurface.withValues(alpha: 0.3));

    return GestureDetector(
      onTap:
          _isSynced && line.timestamp != null ? () => _seekToLine(index) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: fontSizes.main,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: mainColor,
                height: 1.4,
                shadows: t ? _strokeShadows : null,
              ),
              child: Text(line.text, textAlign: TextAlign.center),
            ),
            if (line.subText != null && line.subText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: fontSizes.sub,
                    fontWeight:
                        isCurrent ? FontWeight.w500 : FontWeight.normal,
                    color: subColor,
                    height: 1.3,
                    shadows: t ? _strokeShadows : null,
                  ),
                  child:
                      Text(line.subText!, textAlign: TextAlign.center),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffsetBar() {
    final t = _transparentMode;
    final colorScheme = Theme.of(context).colorScheme;

    final labelColor = t ? Colors.white70 : colorScheme.onSurfaceVariant;
    final valueColor = t ? Colors.white : colorScheme.onSurface;
    final btnColor = t ? Colors.white : colorScheme.onSurface;
    final bgColor =
        t ? Colors.black.withValues(alpha: 0.85) : Theme.of(context).scaffoldBackgroundColor;
    final borderColor = t
        ? Colors.white12
        : colorScheme.outlineVariant.withValues(alpha: 0.3);
    final chipBg = t
        ? Colors.white.withValues(alpha: 0.15)
        : colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_strings.offset,
                style: TextStyle(fontSize: 12, color: labelColor)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatOffset(_offsetMs),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: valueColor),
              ),
            ),
            const SizedBox(width: 12),
            _offsetButton(Icons.fast_rewind, -1000, btnColor),
            _offsetButton(Icons.remove, -500, btnColor),
            _offsetButton(Icons.remove_circle_outline, -100, btnColor),
            const SizedBox(width: 4),
            InkWell(
              onTap: _offsetMs != 0 ? _resetOffset : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.refresh,
                  size: 16,
                  color: _offsetMs != 0
                      ? btnColor
                      : btnColor.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _offsetButton(Icons.add_circle_outline, 100, btnColor),
            _offsetButton(Icons.add, 500, btnColor),
            _offsetButton(Icons.fast_forward, 1000, btnColor),
          ],
        ),
      ),
    );
  }

  Widget _offsetButton(IconData icon, int deltaMs, Color color) {
    return InkWell(
      onTap: () => _adjustOffset(deltaMs),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
