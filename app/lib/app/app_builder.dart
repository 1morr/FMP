import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/shell/window_title_bar.dart';
import 'package:fmp/ui/toast/toast_host.dart';

/// `MaterialApp.builder`（`FmpApp` 與測試的 `ShellHarness` 共用）：視窗寬度等級、提示宿主，
/// 平台宣告自繪標題列時再加 [WindowFrame]。
Widget fmpAppBuilder(BuildContext context, Widget? navigator) =>
    WindowClassScope(
      child: ToastHost(child: WindowFrame(child: navigator!)),
    );
