import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/models/hotkey_config.dart';
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
  bool _hotkeysRegistered = false;
  HotkeyConfig? _hotkeyConfig;

  // 回调函数，由外部设置
  VoidCallback? onPlayPause;
  VoidCallback? onNext;
  VoidCallback? onPrevious;
  VoidCallback? onStop;
  VoidCallback? onVolumeUp;
  VoidCallback? onVolumeDown;
  VoidCallback? onMute;
  VoidCallback? onShowWindow;
  VoidCallback? onQuit;

  // 当前播放状态（用于更新托盘菜单）
  bool _isPlaying = false;
  Track? _currentTrack;

  /// 初始化 Windows 桌面特性
  ///
  /// [enableHotkeys] - 是否启用全局快捷键
  Future<void> initialize({bool enableHotkeys = true}) async {
    if (_isInitialized) return;
    if (!Platform.isWindows) return;

    await _initTray();
    if (enableHotkeys) {
      await registerHotkeys();
    }
    _initWindowListener();

    _isInitialized = true;
    debugPrint('[WindowsDesktopService] Initialized (hotkeys: $enableHotkeys)');
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
    // 设置托盘图标 - Windows API 需要绝对路径
    String? iconPath;
    
    // 获取可执行文件所在目录（适用于打包后的应用）
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    
    // 可能的图标路径（按优先级排序）
    final possiblePaths = [
      // 打包后：图标在可执行文件同级目录
      '$exeDir\\app_icon.ico',
      // 打包后：图标在 data 目录
      '$exeDir\\data\\app_icon.ico',
      // 开发模式：项目目录下
      '${Directory.current.path}\\windows\\runner\\resources\\app_icon.ico',
    ];
    
    for (final path in possiblePaths) {
      if (File(path).existsSync()) {
        iconPath = path;
        break;
      }
    }
    
    if (iconPath != null) {
      debugPrint('[WindowsDesktopService] Setting tray icon: $iconPath');
      await trayManager.setIcon(iconPath);
    } else {
      debugPrint('[WindowsDesktopService] Tray icon not found! Tried paths:');
      for (final path in possiblePaths) {
        debugPrint('  - $path');
      }
    }

    // 设置悬停提示
    await trayManager.setToolTip(t.tray.appName);

    // 设置右键菜单
    await _updateTrayMenu();

    // 注册托盘事件监听
    trayManager.addListener(this);
  }

  /// 更新托盘菜单
  Future<void> _updateTrayMenu() async {
    final trackInfo = _currentTrack != null
        ? '${_currentTrack!.title}\n${_currentTrack!.artist ?? t.tray.unknownArtist}'
        : t.tray.notPlaying;

    debugPrint('[WindowsDesktopService] Updating tray menu, isPlaying: $_isPlaying');

    final menu = Menu(
      items: [
        MenuItem(
          key: 'track_info',
          label: trackInfo,
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'play_pause',
          label: _isPlaying ? t.tray.pause : t.tray.play,
        ),
        MenuItem(
          key: 'previous',
          label: t.tray.previous,
        ),
        MenuItem(
          key: 'next',
          label: t.tray.next,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'show_window',
          label: t.tray.showWindow,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: t.tray.exit,
        ),
      ],
    );

    await trayManager.setContextMenu(menu);
    debugPrint('[WindowsDesktopService] Tray menu updated');
  }

  /// 更新托盘工具提示（显示当前歌曲）
  Future<void> updateTrayTooltip() async {
    if (!Platform.isWindows || !_isInitialized) return;

    String tooltip = t.tray.appName;
    if (_currentTrack != null) {
      final artist = _currentTrack!.artist ?? t.tray.unknownArtist;
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
    debugPrint('[WindowsDesktopService] Right mouse down on tray icon');
    // 右键点击：显示菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() {
    debugPrint('[WindowsDesktopService] Right mouse up on tray icon');
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    debugPrint('[WindowsDesktopService] Menu item clicked: ${menuItem.key}');
    switch (menuItem.key) {
      case 'play_pause':
        onPlayPause?.call();
        break;
      case 'previous':
        onPrevious?.call();
        break;
      case 'next':
        onNext?.call();
        break;
      case 'show_window':
        _showWindow();
        break;
      case 'quit':
        _handleQuit();
        break;
    }
  }

  // ============================================================
  // 全局快捷键
  // ============================================================

  /// 快捷键是否已注册
  bool get hotkeysRegistered => _hotkeysRegistered;

  /// 应用快捷键配置
  Future<void> applyHotkeyConfig(HotkeyConfig config) async {
    _hotkeyConfig = config;
    if (_hotkeysRegistered) {
      // 重新注册快捷键
      await unregisterHotkeys();
      await registerHotkeys();
    }
  }

  /// 注册全局快捷键
  Future<void> registerHotkeys() async {
    if (_hotkeysRegistered) return;
    if (!Platform.isWindows) return;

    try {
      final config = _hotkeyConfig ?? HotkeyConfig.defaults();

      // 注册所有配置的快捷键
      for (final action in HotkeyAction.values) {
        final binding = config.getBinding(action);
        if (binding == null || !binding.isConfigured) continue;

        final hotKey = binding.toHotKey();
        if (hotKey == null) continue;

        await hotKeyManager.register(
          hotKey,
          keyDownHandler: (key) => _handleHotkeyAction(action),
        );
      }

      _hotkeysRegistered = true;
      debugPrint('[WindowsDesktopService] Hotkeys registered');
    } catch (e) {
      debugPrint('[WindowsDesktopService] Failed to register hotkeys: $e');
    }
  }

  /// 处理快捷键动作
  void _handleHotkeyAction(HotkeyAction action) {
    debugPrint('[WindowsDesktopService] Hotkey: ${action.label}');
    switch (action) {
      case HotkeyAction.playPause:
        onPlayPause?.call();
        break;
      case HotkeyAction.next:
        onNext?.call();
        break;
      case HotkeyAction.previous:
        onPrevious?.call();
        break;
      case HotkeyAction.stop:
        onStop?.call();
        break;
      case HotkeyAction.volumeUp:
        onVolumeUp?.call();
        break;
      case HotkeyAction.volumeDown:
        onVolumeDown?.call();
        break;
      case HotkeyAction.mute:
        onMute?.call();
        break;
      case HotkeyAction.toggleWindow:
        _toggleWindow();
        break;
    }
  }

  /// 切换窗口显示/隐藏
  Future<void> _toggleWindow() async {
    if (_isMinimizedToTray) {
      await _showWindow();
    } else {
      await minimizeToTray();
    }
  }

  /// 注销全局快捷键
  Future<void> unregisterHotkeys() async {
    if (!_hotkeysRegistered) return;
    if (!Platform.isWindows) return;

    try {
      await hotKeyManager.unregisterAll();
      _hotkeysRegistered = false;
      debugPrint('[WindowsDesktopService] Hotkeys unregistered');
    } catch (e) {
      debugPrint('[WindowsDesktopService] Failed to unregister hotkeys: $e');
    }
  }

  /// 设置快捷键启用状态
  Future<void> setHotkeysEnabled(bool enabled) async {
    if (enabled) {
      await registerHotkeys();
    } else {
      await unregisterHotkeys();
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
