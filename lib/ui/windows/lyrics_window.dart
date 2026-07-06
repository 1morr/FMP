import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/lyrics/lyrics_window_style.dart';
import '../theme/app_theme.dart';
import '../widgets/lyrics/lyrics_style_dialog.dart';
import '../widgets/lyrics/lyrics_styled_text.dart';
import 'lyrics_display_mode.dart';
import 'lyrics/lyrics_empty_state.dart';
import 'lyrics/lyrics_line_item.dart';
import 'lyrics/lyrics_offset_bar.dart';
import 'lyrics/lyrics_offset_math.dart';
import 'lyrics/lyrics_single_line_view.dart';
import 'lyrics/lyrics_title_bar.dart';
import 'lyrics_text_measurer.dart';

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
  String previous = '上一首';
  String play = '播放';
  String pause = '暂停';
  String next = '下一首';
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
  String styleSettings = '歌词样式';
  String textColor = '歌词颜色';
  String secondaryTextColor = '副歌词颜色';
  String inactiveOpacity = '非当前行透明度';
  String outline = '描边';
  String outlineColor = '描边颜色';
  String outlineWidth = '描边粗细';
  String shadow = '阴影';
  String shadowColor = '阴影颜色';
  String shadowBlur = '阴影模糊';
  String shadowOffsetX = '阴影水平偏移';
  String shadowOffsetY = '阴影垂直偏移';
  String resetStyle = '重置样式';

  void updateFrom(Map<String, dynamic> map) {
    waitingLyrics = map['waitingLyrics'] as String? ?? waitingLyrics;
    previous = map['previous'] as String? ?? previous;
    play = map['play'] as String? ?? play;
    pause = map['pause'] as String? ?? pause;
    next = map['next'] as String? ?? next;
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
    styleSettings = map['styleSettings'] as String? ?? styleSettings;
    textColor = map['textColor'] as String? ?? textColor;
    secondaryTextColor =
        map['secondaryTextColor'] as String? ?? secondaryTextColor;
    inactiveOpacity = map['inactiveOpacity'] as String? ?? inactiveOpacity;
    outline = map['outline'] as String? ?? outline;
    outlineColor = map['outlineColor'] as String? ?? outlineColor;
    outlineWidth = map['outlineWidth'] as String? ?? outlineWidth;
    shadow = map['shadow'] as String? ?? shadow;
    shadowColor = map['shadowColor'] as String? ?? shadowColor;
    shadowBlur = map['shadowBlur'] as String? ?? shadowBlur;
    shadowOffsetX = map['shadowOffsetX'] as String? ?? shadowOffsetX;
    shadowOffsetY = map['shadowOffsetY'] as String? ?? shadowOffsetY;
    resetStyle = map['resetStyle'] as String? ?? resetStyle;
  }

  LyricsStyleDialogStrings toStyleDialogStrings() {
    return LyricsStyleDialogStrings(
      styleSettings: styleSettings,
      textColor: textColor,
      secondaryTextColor: secondaryTextColor,
      inactiveOpacity: inactiveOpacity,
      outline: outline,
      outlineColor: outlineColor,
      outlineWidth: outlineWidth,
      shadow: shadow,
      shadowColor: shadowColor,
      shadowBlur: shadowBlur,
      shadowOffsetX: shadowOffsetX,
      shadowOffsetY: shadowOffsetY,
      resetStyle: resetStyle,
      close: close,
    );
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
  int _positionMs = 0;
  int _offsetMs = 0;
  String? _trackTitle;
  String? _trackArtist;
  String? _trackUniqueKey;
  bool _alwaysOnTop = true;
  bool _showOffsetControls = false;
  bool _isPlaying = false;
  LyricsDisplayMode _displayMode = LyricsDisplayMode.original;
  bool _transparentMode = false;
  bool _singleLineMode = false;
  bool _isHovering = false;
  LyricsWindowStyle _lyricsStyle = LyricsWindowStyle.defaults;
  late final LyricsWindowStyleCommitDebouncer _styleCommitDebouncer;

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

  /// 透明/普通模式切换时保留滚动位置
  final _lyricsListKey = GlobalKey();

  final _scrollController = ItemScrollController();
  final _positionsListener = ItemPositionsListener.create();

  static const _channel = WindowMethodChannel(
    'lyrics_sync',
    mode: ChannelMode.bidirectional,
  );
  @override
  void initState() {
    super.initState();
    _styleCommitDebouncer = LyricsWindowStyleCommitDebouncer(
      commit: _sendLyricsWindowStyle,
    );
    _setupChannel();
    _initWindow();
  }

  @override
  void dispose() {
    _styleCommitDebouncer.flush();
    _styleCommitDebouncer.dispose();
    _scrollResumeTimer?.cancel();
    super.dispose();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(400, 500));
    await windowManager.setMinimumSize(
      const Size(
        LyricsWindowLayout.minWindowWidth,
        LyricsWindowLayout.minWindowHeight,
      ),
    );
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
    final style = LyricsWindowStyle.fromJson(data['lyricsWindowStyle']);

    final appState = context.findAncestorStateOfType<_LyricsWindowAppState>();
    appState?.updateTheme(
      themeMode: ThemeMode.values[themeModeIndex.clamp(0, 2)],
      primaryColor: primaryColorValue != null ? Color(primaryColorValue) : null,
      fontFamily: fontFamily,
      stringsMap: stringsMap,
    );
    if (_lyricsStyle != style) {
      setState(() => _lyricsStyle = style);
    }
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
    final mode = LyricsDisplayMode.fromIndex(data['modeIndex'] as int?);
    if (_displayMode != mode) {
      setState(() => _displayMode = mode);
      // 切换显示模式后滚动到当前播放行
      if (!_singleLineMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToCurrentLine(jump: true);
        });
      }
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
      _positionMs = data['positionMs'] as int? ?? 0;
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
    _positionMs = data['positionMs'] as int? ?? _positionMs;

    if (newIndex != _currentLineIndex) {
      setState(() => _currentLineIndex = newIndex);
      if (!_userScrolling) _scrollToCurrentLine();
    }
  }

  // ─── Commands to main window ───

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
    _updateOffset(_offsetMs + deltaMs);
  }

  void _calibrateOffsetToLine(int index) {
    if (!_isSynced || index < 0 || index >= _lines.length) return;
    final timestamp = _lines[index].timestamp;
    if (timestamp == null) return;
    _updateOffset(
        LyricsOffsetMath.calibrationOffsetForLine(timestamp, _positionMs));
  }

  void _updateOffset(int newOffsetMs) {
    if (_trackUniqueKey == null) return;
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
    final nextMode = _displayMode.next;
    setState(() => _displayMode = nextMode);
    try {
      _channel.invokeMethod(
        'changeLyricsDisplayMode',
        jsonEncode({'modeIndex': nextMode.modeIndex}),
      );
    } catch (_) {}
    // 切换显示模式后滚动到当前播放行
    if (!_singleLineMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentLine(jump: true);
      });
    }
  }

  void _sendLyricsWindowStyle(LyricsWindowStyle style) {
    try {
      _channel.invokeMethod(
        'changeLyricsWindowStyle',
        jsonEncode(style.toJson()),
      );
    } catch (_) {}
  }

  void _updateLyricsWindowStyle(LyricsWindowStyle style) {
    setState(() => _lyricsStyle = style);
    _styleCommitDebouncer.schedule(style);
  }

  void _resetLyricsWindowStyle() {
    _styleCommitDebouncer.cancel();
    setState(() => _lyricsStyle = LyricsWindowStyle.defaults);
    try {
      _channel.invokeMethod('resetLyricsWindowStyle', '');
    } catch (_) {}
  }

  Future<void> _showLyricsStyleDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => LyricsStyleDialog(
        initialStyle: _lyricsStyle,
        strings: _strings.toStyleDialogStrings(),
        onChanged: _updateLyricsWindowStyle,
        onReset: _resetLyricsWindowStyle,
      ),
    );
    _styleCommitDebouncer.flush();
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

    _cachedRefWidth = LyricsTextMeasurer.medianReferenceWidth(
      texts: _lines.map((line) => line.text),
      refFontSize: _refFontSize,
      styleBuilder: (fontSize, weight) => LyricsTextStyles.fromTheme(
        context,
        fontSize: fontSize,
        fontWeight: weight,
      ),
      textDirection: Directionality.of(context),
    );
    _cachedLineCount = _lines.length;
    _cachedFirstLine = firstLine;
  }

  ({double main, double sub}) _getFontSizes(
      double availableWidth, BuildContext context) {
    _ensureRefWidth(context);

    return LyricsTextMeasurer.fontSizesFromReferenceWidth(
      referenceWidth: _cachedRefWidth,
      availableWidth: availableWidth,
      minFontSize: _minFontSize,
      maxFontSize: _maxFontSize,
      refFontSize: _refFontSize,
      subFontRatio: _subFontRatio,
      boldSafetyFactor: _boldSafetyFactor,
    );
  }

  // ─── Helpers ───

  _LyricsWindowStrings get _strings {
    final appState = context.findAncestorStateOfType<_LyricsWindowAppState>();
    return appState?.strings ?? _LyricsWindowStrings();
  }

  IconData get _displayModeIcon => _displayMode.icon;

  String get _displayModeTooltip {
    switch (_displayMode) {
      case LyricsDisplayMode.original:
        return _strings.displayOriginal;
      case LyricsDisplayMode.preferTranslated:
        return _strings.displayPreferTranslated;
      case LyricsDisplayMode.preferRomaji:
        return _strings.displayPreferRomaji;
    }
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
        child: DragToResizeArea(
          resizeEdgeSize: 12,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            color: _isHovering
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.transparent,
            child: Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.only(
                        top: LyricsWindowLayout.contentTopInset(
                          transparentMode: true,
                          titleBarVisible: _isHovering,
                          offsetControlsVisible: _showOffsetControls,
                        ),
                      ),
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
    return LyricsTitleBar(
      title: _trackTitle,
      artist: _trackArtist,
      transparentMode: _transparentMode,
      isPlaying: _isPlaying,
      displayModeIcon: _displayModeIcon,
      displayModeTooltip: _displayModeTooltip,
      singleLineMode: _singleLineMode,
      alwaysOnTop: _alwaysOnTop,
      isSynced: _isSynced,
      hasLines: _lines.isNotEmpty,
      showOffsetControls: _showOffsetControls,
      labels: LyricsTitleBarLabels(
        previous: _strings.previous,
        play: _strings.play,
        pause: _strings.pause,
        next: _strings.next,
        styleSettings: _strings.styleSettings,
        fullLyrics: _strings.fullLyrics,
        singleLine: _strings.singleLine,
        normalMode: _strings.normalMode,
        transparentMode: _strings.transparentMode,
        unpin: _strings.unpin,
        pin: _strings.pin,
        offsetAdjust: _strings.offsetAdjust,
        close: _strings.close,
      ),
      onDragStart: (_) => windowManager.startDragging(),
      onPrevious: _sendPrevious,
      onPlayPause: _sendPlayPause,
      onNext: _sendNext,
      onCycleDisplayMode: _cycleLyricsDisplayMode,
      onShowStyleDialog: _showLyricsStyleDialog,
      onToggleSingleLine: () {
        final wasInSingleLine = _singleLineMode;
        setState(() => _singleLineMode = !_singleLineMode);
        // 从单行切换到多行时，ScrollablePositionedList 刚创建，
        // 需要等下一帧 controller attach 后再滚动
        if (wasInSingleLine) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToCurrentLine(jump: true);
          });
        }
      },
      onToggleTransparent: _toggleTransparentMode,
      onToggleAlwaysOnTop: () async {
        setState(() => _alwaysOnTop = !_alwaysOnTop);
        await windowManager.setAlwaysOnTop(_alwaysOnTop);
      },
      onToggleOffsetControls: () =>
          setState(() => _showOffsetControls = !_showOffsetControls),
      onClose: _requestHide,
    );
  }

  Widget _buildEmpty() {
    return LyricsEmptyState(
      transparentMode: _transparentMode,
      style: _lyricsStyle,
      waitingText: _strings.waitingLyrics,
    );
  }

  Widget _buildSingleLine() {
    // 文字解析（當前行 → 曲名 fallback）留在 State；字級擬合與呈現由 leaf 負責。
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

    return LyricsSingleLineView(
      mainText: mainText,
      subText: subText,
      transparentMode: _transparentMode,
      style: _lyricsStyle,
      isSynced: _isSynced,
      hasCurrentLine: _currentLineIndex >= 0,
      onTap: () => _seekToLine(_currentLineIndex),
      onSecondaryTap: () => _calibrateOffsetToLine(_currentLineIndex),
      boldSafetyFactor: _boldSafetyFactor,
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
                    _scrollResumeTimer = Timer(const Duration(seconds: 3), () {
                      if (mounted) _userScrolling = false;
                    });
                  }
                  return false;
                },
                child: ScrollablePositionedList.builder(
                  key: _lyricsListKey,
                  itemScrollController: _scrollController,
                  itemPositionsListener: _positionsListener,
                  padding: EdgeInsets.only(
                    top: _showOffsetControls
                        ? LyricsWindowLayout.offsetBarHeight
                        : LyricsWindowLayout.defaultContentTopPadding,
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
    return LyricsLineItem(
      text: line.text,
      subText: line.subText,
      isCurrent: isCurrent,
      fontSizes: fontSizes,
      transparentMode: _transparentMode,
      style: _lyricsStyle,
      isSynced: _isSynced,
      hasTimestamp: line.timestamp != null,
      onTap: () => _seekToLine(index),
      onSecondaryTap: () => _calibrateOffsetToLine(index),
    );
  }

  Widget _buildOffsetBar() {
    return LyricsOffsetBar(
      offsetMs: _offsetMs,
      transparentMode: _transparentMode,
      offsetLabel: _strings.offset,
      onAdjust: _adjustOffset,
      onReset: _resetOffset,
    );
  }
}
