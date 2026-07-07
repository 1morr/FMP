import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart' show DragToMoveArea;

/// 全螢幕播放器的沉浸式版面骨架，音樂/電台播放器共用。
///
/// 統一「模糊封面背板 + 兩層 overlay 色調 + 浮動透明 AppBar（含 Windows 拖曳
/// 區）+ 內容定位 Stack」這組原本在兩頁逐字重複的 chrome。各頁只需提供
/// [backdrop]（TrackBlurredBackdrop / RadioBlurredBackdrop）、[appBarActions]
/// 與 [body]，即可獲得一致的沉浸式外觀，避免未來漂移。
///
/// 背景圖由全頁 Stack 統一繪製，AppBar 透明且置於同一 Stack 內（不使用
/// Scaffold.appBar），以免路由轉場露出 Scaffold 的繪製區。
class ImmersivePlayerScaffold extends StatelessWidget {
  final Widget backdrop;
  final List<Widget> appBarActions;
  final Widget body;
  final ColorScheme colorScheme;

  const ImmersivePlayerScaffold({
    super.key,
    required this.backdrop,
    required this.appBarActions,
    required this.body,
    required this.colorScheme,
  });

  static const double _appBarHeight = kToolbarHeight;
  static const double _bodyBackdropSurfaceOverlayAlpha = 0.60;
  static const double _bodyBackdropContainerOverlayAlpha = 0.08;
  static const double _appBarBackdropSurfaceOverlayAlpha = 0.50;
  static const double _appBarBackdropContainerOverlayAlpha = 0.06;

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      primary: false,
      toolbarHeight: _appBarHeight,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.keyboard_arrow_down),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: _buildAppBarOverlay(colorScheme),
      actions: appBarActions,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        backdrop,
        _buildBodyBackdropOverlays(colorScheme),
        Positioned.fill(
          top: _appBarHeight,
          child: body,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _appBarHeight,
          child: appBar,
        ),
      ],
    );
  }

  /// AppBar 覆蓋層：背景圖由全頁 Stack 統一繪製，避免路由轉場不同步。
  Widget _buildAppBarOverlay(ColorScheme colorScheme) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackdropOverlay(
          colorScheme: colorScheme,
          surfaceOverlayAlpha: _appBarBackdropSurfaceOverlayAlpha,
          surfaceContainerOverlayAlpha: _appBarBackdropContainerOverlayAlpha,
        ),
        if (Platform.isWindows) const DragToMoveArea(child: SizedBox.expand()),
      ],
    );
  }

  Widget _buildBodyBackdropOverlays(ColorScheme colorScheme) {
    return Positioned.fill(
      top: _appBarHeight,
      child: _buildBackdropOverlay(
        colorScheme: colorScheme,
        surfaceOverlayAlpha: _bodyBackdropSurfaceOverlayAlpha,
        surfaceContainerOverlayAlpha: _bodyBackdropContainerOverlayAlpha,
      ),
    );
  }

  Widget _buildBackdropOverlay({
    required ColorScheme colorScheme,
    required double surfaceOverlayAlpha,
    required double surfaceContainerOverlayAlpha,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: colorScheme.surface.withValues(alpha: surfaceOverlayAlpha),
        ),
        ColoredBox(
          color: colorScheme.surfaceContainerHighest
              .withValues(alpha: surfaceContainerOverlayAlpha),
        ),
      ],
    );
  }
}
