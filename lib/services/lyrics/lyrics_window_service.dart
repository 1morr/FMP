import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

import '../lyrics/lrc_parser.dart';

/// 桌面歌词弹出窗口管理服务
///
/// 负责创建、管理歌词子窗口，以及主窗口与子窗口之间的数据同步。
/// 子窗口运行独立 Flutter engine，通过 WindowMethodChannel 通信。
class LyricsWindowService {
  LyricsWindowService._();
  static final instance = LyricsWindowService._();

  /// 子窗口控制器（null 表示窗口未打开）
  WindowController? _controller;

  /// 窗口变化监听
  StreamSubscription<void>? _windowChangeSub;

  /// 子窗口 channel 是否已就绪
  bool _channelReady = false;

  /// 窗口是否已打开
  bool get isOpen => _controller != null;

  /// 通信 channel（unidirectional：子窗口注册 handler，主窗口 invoke）
  static const _channel = WindowMethodChannel(
    'lyrics_sync',
    mode: ChannelMode.unidirectional,
  );

  /// 打开歌词窗口（如果已打开则聚焦）
  Future<void> open() async {
    if (!Platform.isWindows) return;

    if (_controller != null) {
      try {
        await _controller!.show();
        return;
      } catch (_) {
        _controller = null;
        _channelReady = false;
      }
    }

    _controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: false,
        arguments: jsonEncode({'window_type': 'lyrics'}),
      ),
    );
    _channelReady = false;

    // 监听窗口列表变化，检测子窗口关闭
    _windowChangeSub?.cancel();
    _windowChangeSub = onWindowsChanged.listen((_) {
      _checkWindowClosed();
    });

    // 等待子窗口 channel 就绪（轮询，最多 3 秒）
    await _waitForChannelReady();
  }

  /// 轮询等待子窗口 channel 注册完成
  Future<void> _waitForChannelReady() async {
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_controller == null) return; // 窗口已关闭
      try {
        await _channel.invokeMethod('ping', '');
        _channelReady = true;
        debugPrint('LyricsWindowService: channel ready after ${(i + 1) * 100}ms');
        return;
      } catch (_) {
        // 子窗口还没注册，继续等
      }
    }
    debugPrint('LyricsWindowService: channel ready timeout');
  }

  /// 关闭歌词窗口
  Future<void> close() async {
    if (_controller == null) return;
    try {
      if (_channelReady) {
        await _channel.invokeMethod('close', '');
      }
    } catch (_) {}
    _controller = null;
    _channelReady = false;
    _windowChangeSub?.cancel();
    _windowChangeSub = null;
  }

  /// 同步歌词数据到子窗口（全量，歌词内容变化时调用）
  Future<void> syncLyrics({
    required ParsedLyrics? lyrics,
    required int currentLineIndex,
    required int offsetMs,
    required String? trackTitle,
    required String? trackArtist,
  }) async {
    if (_controller == null || !_channelReady) return;

    try {
      final lyricsData = lyrics?.lines.map((line) => {
        'timestamp': line.timestamp.inMilliseconds,
        'text': line.text,
        'subText': line.subText,
      }).toList();

      await _channel.invokeMethod(
        'updateLyrics',
        jsonEncode({
          'lines': lyricsData,
          'isSynced': lyrics?.isSynced ?? false,
          'currentLineIndex': currentLineIndex,
          'offsetMs': offsetMs,
          'trackTitle': trackTitle,
          'trackArtist': trackArtist,
        }),
      );
    } catch (e) {
      debugPrint('LyricsWindowService: sync error: $e');
      _channelReady = false;
    }
  }

  /// 仅同步当前行索引（高频调用，轻量数据）
  Future<void> syncPosition(int currentLineIndex) async {
    if (_controller == null || !_channelReady) return;

    try {
      await _channel.invokeMethod(
        'updatePosition',
        jsonEncode({'currentLineIndex': currentLineIndex}),
      );
    } catch (e) {
      debugPrint('LyricsWindowService: position sync error: $e');
      _channelReady = false;
    }
  }

  /// 检查窗口是否已被用户关闭
  Future<void> _checkWindowClosed() async {
    if (_controller == null) return;
    try {
      final controllers = await WindowController.getAll();
      final stillExists = controllers.any(
        (c) => c.windowId == _controller!.windowId,
      );
      if (!stillExists) {
        _controller = null;
        _channelReady = false;
        _windowChangeSub?.cancel();
        _windowChangeSub = null;
      }
    } catch (_) {
      _controller = null;
      _channelReady = false;
      _windowChangeSub?.cancel();
      _windowChangeSub = null;
    }
  }
}
