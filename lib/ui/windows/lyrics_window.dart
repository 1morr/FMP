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
  String? _trackTitle;
  String? _trackArtist;
  bool _alwaysOnTop = true;

  final _scrollController = ItemScrollController();
  final _positionsListener = ItemPositionsListener.create();

  static const _channel = WindowMethodChannel(
    'lyrics_sync',
    mode: ChannelMode.unidirectional,
  );

  @override
  void initState() {
    super.initState();
    _setupChannel();
    _initWindow();
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
      _trackTitle = data['trackTitle'] as String?;
      _trackArtist = data['trackArtist'] as String?;
    });

    _scrollToCurrentLine();
  }

  void _handleUpdatePosition(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final newIndex = data['currentLineIndex'] as int? ?? -1;

    if (newIndex != _currentLineIndex) {
      setState(() {
        _currentLineIndex = newIndex;
      });
      _scrollToCurrentLine();
    }
  }

  void _scrollToCurrentLine() {
    if (!_isSynced || _currentLineIndex < 0 || _lines.isEmpty) return;
    if (!_scrollController.isAttached) return;

    _scrollController.scrollTo(
      index: _currentLineIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.35,
    );
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
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        itemCount: _lines.length,
        itemBuilder: (context, index) => _buildLyricsLine(index, false),
      );
    }

    // 同步歌词：使用 ScrollablePositionedList
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 检测用户手动滚动（非程序化滚动）
        return false;
      },
      child: ScrollablePositionedList.builder(
        itemScrollController: _scrollController,
        itemPositionsListener: _positionsListener,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        itemCount: _lines.length,
        itemBuilder: (context, index) {
          final isCurrent = index == _currentLineIndex;
          return _buildLyricsLine(index, isCurrent);
        },
      ),
    );
  }

  Widget _buildLyricsLine(int index, bool isCurrent) {
    final line = _lines[index];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 主歌词
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: isCurrent ? 20 : 16,
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
              padding: const EdgeInsets.only(top: 2),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: isCurrent ? 14 : 12,
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
    );
  }
}
