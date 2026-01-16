import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/models/track.dart';

/// Windows 桌面特性服务
///
/// 负责管理：
/// - 系统托盘（图标、右键菜单、悬停提示）
/// - 全局快捷键
/// - 窗口管理（最小化到托盘等）
class WindowsDesktopService with TrayListener, WindowListener {
  WindowsDesktopService();

  bool _isInitialized = false;
  bool _isMinimizedToTray = false;

  // 回调函数，由外部设置
  VoidCallback? onPlayPause;
  VoidCallback? onNext;
  VoidCallback? onPrevious;
  VoidCallback? onStop;
  VoidCallback? onShowWindow;
  VoidCallback? onQuit;

  // 当前播放状态（用于更新托盘菜单）
  bool _isPlaying = false;
  Track? _currentTrack;

  /// 初始化 Windows 桌面特性
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (!Platform.isWindows) return;

    await _initTray();
    await _initHotkeys();
    _initWindowListener();

    _isInitialized = true;
    debugPrint('[WindowsDesktopService] Initialized');
  }

  /// 销毁资源
  Future<void> dispose() async {
    if (!Platform.isWindows) return;

    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await hotKeyManager.unregisterAll();
    await trayManager.destroy();

    _isInitialized = false;
  }

  // ============================================================
  // 系统托盘
  // ============================================================

  Future<void> _initTray() async {
    // 设置托盘图标
    await trayManager.setIcon('windows/runner/resources/app_icon.ico');

    // 设置悬停提示
    await trayManager.setToolTip('FMP 音乐播放器');

    // 设置右键菜单
    await _updateTrayMenu();

    // 注册托盘事件监听
    trayManager.addListener(this);
  }

  /// 更新托盘菜单
  Future<void> _updateTrayMenu() async {
    final trackInfo = _currentTrack != null
        ? '${_currentTrack!.title}\n${_currentTrack!.artist ?? "未知艺术家"}'
        : '未在播放';

    final menu = Menu(
      items: [
        MenuItem(
          label: trackInfo,
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          label: _isPlaying ? '暂停' : '播放',
          onClick: (_) => onPlayPause?.call(),
        ),
        MenuItem(
          label: '上一首',
          onClick: (_) => onPrevious?.call(),
        ),
        MenuItem(
          label: '下一首',
          onClick: (_) => onNext?.call(),
        ),
        MenuItem.separator(),
        MenuItem(
          label: '显示窗口',
          onClick: (_) => _showWindow(),
        ),
        MenuItem.separator(),
        MenuItem(
          label: '退出',
          onClick: (_) => _handleQuit(),
        ),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  /// 更新托盘工具提示（显示当前歌曲）
  Future<void> updateTrayTooltip() async {
    if (!Platform.isWindows || !_isInitialized) return;

    String tooltip = 'FMP 音乐播放器';
    if (_currentTrack != null) {
      final artist = _currentTrack!.artist ?? '未知艺术家';
      tooltip = '${_currentTrack!.title}\n$artist';
      if (_isPlaying) {
        tooltip = '▶ $tooltip';
      } else {
        tooltip = '⏸ $tooltip';
      }
    }

    await trayManager.setToolTip(tooltip);
  }

  /// 更新播放状态
  Future<void> updatePlaybackState({
    required bool isPlaying,
    Track? currentTrack,
  }) async {
    if (!Platform.isWindows || !_isInitialized) return;

    _isPlaying = isPlaying;
    _currentTrack = currentTrack;

    await _updateTrayMenu();
    await updateTrayTooltip();
  }

  // TrayListener 回调

  @override
  void onTrayIconMouseDown() {
    // 左键点击托盘图标：显示窗口
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键点击：显示菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() {}

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    // 菜单项点击已通过 MenuItem.onClick 处理
  }

  // ============================================================
  // 全局快捷键
  // ============================================================

  Future<void> _initHotkeys() async {
    try {
      // 播放/暂停: Ctrl + Alt + Space
      await hotKeyManager.register(
        HotKey(
          key: LogicalKeyboardKey.space,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
        ),
        keyDownHandler: (hotKey) {
          debugPrint('[WindowsDesktopService] Hotkey: Play/Pause');
          onPlayPause?.call();
        },
      );

      // 下一首: Ctrl + Alt + Right
      await hotKeyManager.register(
        HotKey(
          key: LogicalKeyboardKey.arrowRight,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
        ),
        keyDownHandler: (hotKey) {
          debugPrint('[WindowsDesktopService] Hotkey: Next');
          onNext?.call();
        },
      );

      // 上一首: Ctrl + Alt + Left
      await hotKeyManager.register(
        HotKey(
          key: LogicalKeyboardKey.arrowLeft,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
        ),
        keyDownHandler: (hotKey) {
          debugPrint('[WindowsDesktopService] Hotkey: Previous');
          onPrevious?.call();
        },
      );

      // 停止: Ctrl + Alt + S
      await hotKeyManager.register(
        HotKey(
          key: LogicalKeyboardKey.keyS,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
          scope: HotKeyScope.system,
        ),
        keyDownHandler: (hotKey) {
          debugPrint('[WindowsDesktopService] Hotkey: Stop');
          onStop?.call();
        },
      );

      debugPrint('[WindowsDesktopService] Hotkeys registered');
    } catch (e) {
      debugPrint('[WindowsDesktopService] Failed to register hotkeys: $e');
    }
  }

  // ============================================================
  // 窗口管理
  // ============================================================

  void _initWindowListener() {
    windowManager.addListener(this);
  }

  /// 显示窗口
  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
    _isMinimizedToTray = false;
    onShowWindow?.call();
  }

  /// 最小化到托盘
  Future<void> minimizeToTray() async {
    if (!Platform.isWindows || !_isInitialized) return;

    await windowManager.hide();
    _isMinimizedToTray = true;
    debugPrint('[WindowsDesktopService] Minimized to tray');
  }

  /// 是否已最小化到托盘
  bool get isMinimizedToTray => _isMinimizedToTray;

  /// 处理退出
  Future<void> _handleQuit() async {
    onQuit?.call();
    // 如果没有设置 onQuit 回调，执行默认退出
    if (onQuit == null) {
      await dispose();
      exit(0);
    }
  }

  // WindowListener 回调

  @override
  void onWindowClose() async {
    // 关闭窗口时最小化到托盘而不是退出
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await minimizeToTray();
    }
  }

  @override
  void onWindowFocus() {}

  @override
  void onWindowBlur() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowMoved() {}

  @override
  void onWindowResized() {}

  @override
  void onWindowEvent(String eventName) {}

  @override
  void onWindowDocked() {}

  @override
  void onWindowUndocked() {}
}
