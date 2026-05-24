import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../lyrics/lrc_parser.dart';
import 'lyrics_window_style.dart';

abstract class LyricsWindowControllerHandle {
  String get windowId;
  Future<void> show();
  Future<void> hide();
}

class _DesktopLyricsWindowControllerHandle
    implements LyricsWindowControllerHandle {
  _DesktopLyricsWindowControllerHandle(this._controller);

  final WindowController _controller;

  @override
  String get windowId => _controller.windowId;

  @override
  Future<void> show() => _controller.show();

  @override
  Future<void> hide() => _controller.hide();
}

@visibleForTesting
abstract class LyricsWindowPlatform {
  bool get isWindows;
  Future<LyricsWindowControllerHandle> createWindow(
    WindowConfiguration configuration,
  );
  Future<List<LyricsWindowControllerHandle>> getAllWindows();
  Stream<void> get windowsChanged;
  Future<dynamic> invokeMethod(String method, String arguments);
  Future<void> setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  );
}

class _DesktopLyricsWindowPlatform implements LyricsWindowPlatform {
  const _DesktopLyricsWindowPlatform();

  @override
  bool get isWindows => Platform.isWindows;

  @override
  Future<LyricsWindowControllerHandle> createWindow(
    WindowConfiguration configuration,
  ) async {
    final controller = await WindowController.create(configuration);
    return _DesktopLyricsWindowControllerHandle(controller);
  }

  @override
  Future<List<LyricsWindowControllerHandle>> getAllWindows() async {
    final controllers = await WindowController.getAll();
    return controllers.map(_DesktopLyricsWindowControllerHandle.new).toList();
  }

  @override
  Stream<void> get windowsChanged => onWindowsChanged;

  @override
  Future<dynamic> invokeMethod(String method, String arguments) {
    return LyricsWindowService._channel.invokeMethod(method, arguments);
  }

  @override
  Future<void> setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    return LyricsWindowService._channel.setMethodCallHandler(handler);
  }
}

/// 桌面歌词弹出窗口管理服务
///
/// 负责创建、管理歌词子窗口，以及主窗口与子窗口之间的数据同步。
/// 子窗口运行独立 Flutter engine，通过 WindowMethodChannel 双向通信。
class LyricsWindowService {
  LyricsWindowService._({LyricsWindowPlatform? platform})
      : _platform = platform ?? const _DesktopLyricsWindowPlatform();

  @visibleForTesting
  factory LyricsWindowService.forTesting(LyricsWindowPlatform platform) {
    return LyricsWindowService._(platform: platform);
  }

  static final instance = LyricsWindowService._();

  /// 子窗口控制器（null 表示窗口未创建）
  LyricsWindowControllerHandle? _controller;

  Future<void>? _opening;

  /// 窗口变化监听
  StreamSubscription<void>? _windowChangeSub;

  /// 子窗口 channel 是否已就绪
  bool _channelReady = false;

  /// 窗口是否已隐藏（关闭时隐藏而非销毁，避免 window_manager channel 被置空）
  bool _isHidden = false;

  /// 窗口是否已打开（存在且未隐藏）
  bool get isOpen => _controller != null && !_isHidden;

  /// 通信 channel（bidirectional：主窗口和子窗口互相调用）
  static const _channel = WindowMethodChannel(
    'lyrics_sync',
    mode: ChannelMode.bidirectional,
  );

  final LyricsWindowPlatform _platform;

  /// 回调：子窗口请求 seek 到指定时间点
  /// 参数：(timestampMs, offsetMs) → 目标位置 = timestampMs - offsetMs
  void Function(int timestampMs, int offsetMs)? onSeekTo;

  /// 回调：子窗口请求调整 offset
  /// 参数：(trackUniqueKey, newOffsetMs)
  void Function(String trackUniqueKey, int newOffsetMs)? onAdjustOffset;

  /// 回调：子窗口请求重置 offset
  /// 参数：(trackUniqueKey)
  void Function(String trackUniqueKey)? onResetOffset;

  /// 回调：子窗口请求播放/暂停
  VoidCallback? onPlayPause;

  /// 回调：子窗口请求下一首
  VoidCallback? onNext;

  /// 回调：子窗口请求上一首
  VoidCallback? onPrevious;

  /// 回调：子窗口请求切换歌词显示模式
  /// 参数：(modeIndex) → 0=original, 1=preferTranslated, 2=preferRomaji
  void Function(int modeIndex)? onChangeLyricsDisplayMode;

  /// 回调：子窗口请求更新歌词弹窗样式
  void Function(LyricsWindowStyle style)? onChangeLyricsWindowStyle;

  /// 回调：子窗口请求重置歌词弹窗样式
  VoidCallback? onResetLyricsWindowStyle;

  /// 回调：子窗口被用户关闭时通知（用于刷新 UI 图标状态）
  VoidCallback? onWindowClosed;

  /// 打开歌词窗口（如果已隐藏则恢复显示，如果已打开则聚焦）
  Future<void> open() async {
    if (!_platform.isWindows) return;
    final opening = _opening;
    if (opening != null) {
      if (_controller != null && _isHidden) {
        try {
          await _controller!.show();
          _isHidden = false;
        } catch (_) {}
      }
      return opening;
    }

    final openOperation = _openWindow();
    _opening = openOperation;
    try {
      await openOperation;
    } finally {
      if (identical(_opening, openOperation)) {
        _opening = null;
      }
    }
  }

  Future<void> _openWindow() async {
    // 窗口存在且未隐藏 → 聚焦
    if (_controller != null && !_isHidden) {
      try {
        await _controller!.show();
        return;
      } catch (_) {
        _controller = null;
        _channelReady = false;
        _isHidden = false;
      }
    }

    // 窗口存在但已隐藏 → 恢复显示
    if (_controller != null && _isHidden) {
      try {
        await _controller!.show();
        _isHidden = false;
        return;
      } catch (_) {
        // 窗口已被系统销毁，重新创建
        _controller = null;
        _channelReady = false;
        _isHidden = false;
      }
    }

    // 注册主窗口 handler（处理子窗口发来的命令）
    await _registerMainWindowHandler();

    _controller = await _platform.createWindow(
      WindowConfiguration(
        hiddenAtLaunch: false,
        arguments: jsonEncode({'window_type': 'lyrics'}),
      ),
    );
    _channelReady = false;
    _isHidden = false;

    // 监听窗口列表变化，检测子窗口关闭
    _windowChangeSub?.cancel();
    _windowChangeSub = _platform.windowsChanged.listen((_) {
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
        await _platform.invokeMethod('ping', '');
        _channelReady = true;
        debugPrint(
            'LyricsWindowService: channel ready after ${(i + 1) * 100}ms');
        return;
      } catch (_) {
        // 子窗口还没注册，继续等
      }
    }
    debugPrint('LyricsWindowService: channel ready timeout');
  }

  /// 关闭歌词窗口（隐藏而非销毁，保持 engine 存活）
  Future<void> close() async {
    if (_controller == null || _isHidden) return;
    try {
      await _controller!.hide();
      _isHidden = true;
    } catch (_) {
      // 窗口可能已被系统销毁
      _controller = null;
      _channelReady = false;
      _isHidden = false;
    }
    onWindowClosed?.call();
  }

  /// 真正销毁歌词窗口（仅 app 退出时调用）
  Future<void> destroy() async {
    if (_controller == null) return;
    try {
      if (_channelReady) {
        await _platform.invokeMethod('close', '');
      }
    } catch (_) {}
    _controller = null;
    _channelReady = false;
    _isHidden = false;
    _windowChangeSub?.cancel();
    _windowChangeSub = null;
    await _unregisterMainWindowHandler();
  }

  /// 同步歌词数据到子窗口（全量，歌词内容变化时调用）
  Future<void> syncLyrics({
    required ParsedLyrics? lyrics,
    required int currentLineIndex,
    required int positionMs,
    required int offsetMs,
    required String? trackTitle,
    required String? trackArtist,
    required String? trackUniqueKey,
  }) async {
    if (_controller == null || !_channelReady || _isHidden) return;

    try {
      final lyricsData = lyrics?.lines
          .map((line) => {
                'timestamp': line.timestamp.inMilliseconds,
                'text': line.text,
                'subText': line.subText,
              })
          .toList();

      await _platform.invokeMethod(
        'updateLyrics',
        jsonEncode({
          'lines': lyricsData,
          'isSynced': lyrics?.isSynced ?? false,
          'currentLineIndex': currentLineIndex,
          'positionMs': positionMs,
          'offsetMs': offsetMs,
          'trackTitle': trackTitle,
          'trackArtist': trackArtist,
          'trackUniqueKey': trackUniqueKey,
        }),
      );
    } catch (e) {
      debugPrint('LyricsWindowService: sync error: $e');
      _channelReady = false;
    }
  }

  /// 同步当前行索引与播放位置（高频调用，轻量数据）
  Future<void> syncPosition({
    required int currentLineIndex,
    required int positionMs,
  }) async {
    if (_controller == null || !_channelReady || _isHidden) return;

    try {
      await _platform.invokeMethod(
        'updatePosition',
        jsonEncode({
          'currentLineIndex': currentLineIndex,
          'positionMs': positionMs,
        }),
      );
    } catch (e) {
      debugPrint('LyricsWindowService: position sync error: $e');
      _channelReady = false;
    }
  }

  /// 同步主题/语言/字体配置到子窗口
  Future<void> syncTheme({
    required ThemeMode themeMode,
    required Color? primaryColor,
    required String? fontFamily,
    required LyricsWindowStyle lyricsWindowStyle,
  }) async {
    if (_controller == null || !_channelReady || _isHidden) return;

    // 收集歌词窗口需要的翻译字符串
    final strings = {
      'waitingLyrics': t.lyrics.windowWaitingLyrics,
      'previous': t.tray.previous,
      'play': t.tray.play,
      'pause': t.tray.pause,
      'next': t.tray.next,
      'unpin': t.lyrics.windowUnpin,
      'pin': t.lyrics.windowPin,
      'offsetAdjust': t.lyrics.windowOffsetAdjust,
      'close': t.lyrics.windowClose,
      'offset': t.lyrics.offset,
      'reset': t.lyrics.windowReset,
      'displayOriginal': t.lyrics.displayOriginal,
      'displayPreferTranslated': t.lyrics.displayPreferTranslated,
      'displayPreferRomaji': t.lyrics.displayPreferRomaji,
      'transparentMode': t.lyrics.windowTransparentMode,
      'normalMode': t.lyrics.windowNormalMode,
      'singleLine': t.lyrics.windowSingleLine,
      'fullLyrics': t.lyrics.windowFullLyrics,
      'styleSettings': t.lyrics.windowStyleSettings,
      'textColor': t.lyrics.windowTextColor,
      'secondaryTextColor': t.lyrics.windowSecondaryTextColor,
      'inactiveOpacity': t.lyrics.windowInactiveOpacity,
      'outline': t.lyrics.windowOutline,
      'outlineColor': t.lyrics.windowOutlineColor,
      'outlineWidth': t.lyrics.windowOutlineWidth,
      'shadow': t.lyrics.windowShadow,
      'shadowColor': t.lyrics.windowShadowColor,
      'shadowBlur': t.lyrics.windowShadowBlur,
      'shadowOffsetX': t.lyrics.windowShadowOffsetX,
      'shadowOffsetY': t.lyrics.windowShadowOffsetY,
      'resetStyle': t.lyrics.windowResetStyle,
    };

    try {
      await _platform.invokeMethod(
        'updateTheme',
        jsonEncode({
          'themeMode': themeMode.index,
          'primaryColor': primaryColor?.toARGB32(),
          'fontFamily': fontFamily,
          'lyricsWindowStyle': lyricsWindowStyle.toJson(),
          'strings': strings,
        }),
      );
    } catch (e) {
      debugPrint('LyricsWindowService: theme sync error: $e');
      _channelReady = false;
    }
  }

  /// 同步播放状态到子窗口（isPlaying 变化时调用）
  Future<void> syncPlaybackState({required bool isPlaying}) async {
    if (_controller == null || !_channelReady || _isHidden) return;

    try {
      await _platform.invokeMethod(
        'updatePlaybackState',
        jsonEncode({'isPlaying': isPlaying}),
      );
    } catch (e) {
      debugPrint('LyricsWindowService: playback state sync error: $e');
      _channelReady = false;
    }
  }

  /// 同步歌词显示模式到子窗口
  Future<void> syncLyricsDisplayMode({required int modeIndex}) async {
    if (_controller == null || !_channelReady || _isHidden) return;

    try {
      await _platform.invokeMethod(
        'updateLyricsDisplayMode',
        jsonEncode({'modeIndex': modeIndex}),
      );
    } catch (e) {
      debugPrint('LyricsWindowService: lyrics display mode sync error: $e');
      _channelReady = false;
    }
  }

  /// 检查窗口是否已被用户强制关闭（Alt+F4 等）
  Future<void> _checkWindowClosed() async {
    if (_controller == null) return;
    try {
      final controllers = await _platform.getAllWindows();
      final stillExists = controllers.any(
        (c) => c.windowId == _controller!.windowId,
      );
      if (!stillExists) {
        _controller = null;
        _channelReady = false;
        _isHidden = false;
        _windowChangeSub?.cancel();
        _windowChangeSub = null;
        await _unregisterMainWindowHandler();
        onWindowClosed?.call();
      }
    } catch (_) {
      _controller = null;
      _channelReady = false;
      _isHidden = false;
      _windowChangeSub?.cancel();
      _windowChangeSub = null;
      await _unregisterMainWindowHandler();
      onWindowClosed?.call();
    }
  }

  /// 注册主窗口 handler（处理子窗口发来的 seek/offset/requestHide 命令）
  Future<void> _registerMainWindowHandler() async {
    try {
      await _platform.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'seekTo':
            final data =
                jsonDecode(call.arguments as String) as Map<String, dynamic>;
            final timestampMs = data['timestampMs'] as int;
            final offsetMs = data['offsetMs'] as int;
            onSeekTo?.call(timestampMs, offsetMs);
            return 'ok';
          case 'adjustOffset':
            final data =
                jsonDecode(call.arguments as String) as Map<String, dynamic>;
            final trackUniqueKey = data['trackUniqueKey'] as String;
            final newOffsetMs = data['newOffsetMs'] as int;
            onAdjustOffset?.call(trackUniqueKey, newOffsetMs);
            return 'ok';
          case 'resetOffset':
            final data =
                jsonDecode(call.arguments as String) as Map<String, dynamic>;
            final trackUniqueKey = data['trackUniqueKey'] as String;
            onResetOffset?.call(trackUniqueKey);
            return 'ok';
          case 'playPause':
            onPlayPause?.call();
            return 'ok';
          case 'next':
            onNext?.call();
            return 'ok';
          case 'previous':
            onPrevious?.call();
            return 'ok';
          case 'changeLyricsDisplayMode':
            final data =
                jsonDecode(call.arguments as String) as Map<String, dynamic>;
            final modeIndex = data['modeIndex'] as int;
            onChangeLyricsDisplayMode?.call(modeIndex);
            return 'ok';
          case 'changeLyricsWindowStyle':
            final data =
                jsonDecode(call.arguments as String) as Map<String, dynamic>;
            onChangeLyricsWindowStyle?.call(LyricsWindowStyle.fromJson(data));
            return 'ok';
          case 'resetLyricsWindowStyle':
            onResetLyricsWindowStyle?.call();
            return 'ok';
          case 'requestHide':
            // 子窗口请求隐藏自己（用户点击关闭按钮）
            await close();
            return 'ok';
          default:
            return null;
        }
      });
    } catch (e) {
      debugPrint('LyricsWindowService: register handler error: $e');
    }
  }

  /// 注销主窗口 handler
  Future<void> _unregisterMainWindowHandler() async {
    try {
      await _platform.setMethodCallHandler(null);
    } catch (e) {
      debugPrint('LyricsWindowService: unregister handler error: $e');
    }
  }
}
