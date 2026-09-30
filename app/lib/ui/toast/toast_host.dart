import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 視窗底部被外殼佔住的高度（dp，從視窗底邊算起，含系統的安全區），例如手機
/// 的迷你播放列加底部導覽列、桌面的播放列（ADR 0023 §決定 2）。
///
/// 外殼在自己的版面改變時寫入；沒有外殼（全螢幕頁、M1 的身分頁）時是 0，提示
/// 貼著底部安全區。
final toastBottomInsetProvider = NotifierProvider<ToastBottomInset, double>(
  ToastBottomInset.new,
);

final class ToastBottomInset extends Notifier<double> {
  @override
  double build() => 0;

  /// 外殼發佈目前佔住的高度。
  void set(double height) => state = height;
}

/// 顯示 [Toaster] 送來的提示（ADR 0023 §決定 2、3）。
///
/// 放在 `MaterialApp.builder`，以自己的 `ScaffoldMessenger` 與透明的 `Scaffold`
/// 包住 Navigator：提示畫在所有路由之上，全螢幕頁、對話框、底部面板開著時都
/// 看得到。頁面自己的 `Scaffold` 是它的子孫，所以提示只出現在這一層。
///
/// - 一次一則：新的立刻取代目前的（不排隊）。
/// - 時長依 [ToastKind.duration]；系統開了無障礙導覽（TalkBack 等）時停留到
///   使用者關閉，並顯示關閉鈕。
/// - App 在背景（hidden／paused）時不顯示；錯誤已由 [Toaster] 寫進錯誤歷史。
class ToastHost extends ConsumerStatefulWidget {
  const ToastHost({super.key, required this.child});

  /// `MaterialApp.builder` 給的 Navigator。
  final Widget child;

  @override
  ConsumerState<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends ConsumerState<ToastHost> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<Toast>? _subscription;

  @override
  void initState() {
    super.initState();
    ref.listenManual(toasterProvider, (_, toaster) {
      unawaited(_subscription?.cancel());
      _subscription = toaster.toasts.listen(_show);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  bool get _inForeground => switch (SchedulerBinding.instance.lifecycleState) {
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
    // 桌面視窗沒有焦點時是 inactive，仍在畫面上。
    AppLifecycleState.resumed || AppLifecycleState.inactive || null => true,
  };

  void _show(Toast toast) {
    final messenger = _messengerKey.currentState;
    if (messenger == null || !mounted || !_inForeground) return;
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(_snackBarFor(toast));
  }

  SnackBar _snackBarFor(Toast toast) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final media = MediaQuery.of(context);
    final (background, foreground, icon) = switch (toast.kind) {
      // 資訊用 M3 snackbar 的預設配色。
      ToastKind.info => (
        theme.colorScheme.inverseSurface,
        theme.colorScheme.onInverseSurface,
        Icons.info_outline,
      ),
      ToastKind.success => (
        tokens.success.container,
        tokens.success.onContainer,
        Icons.check_circle_outline,
      ),
      ToastKind.warning => (
        tokens.warning.container,
        tokens.warning.onContainer,
        Icons.warning_amber_outlined,
      ),
      ToastKind.error => (
        theme.colorScheme.errorContainer,
        theme.colorScheme.onErrorContainer,
        Icons.error_outline,
      ),
    };
    final accessible = media.accessibleNavigation;
    return SnackBar(
      content: Row(
        children: [
          Icon(icon, color: foreground),
          SizedBox(width: tokens.spacing.x3),
          Expanded(
            child: Text(
              toast.message,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
      margin: _margin(media, tokens.spacing),
      duration: toast.kind.duration,
      // SnackBar 帶動作時預設不消失；ADR 0023 要照時長消失，只有無障礙導覽
      // 開著時才停留。
      persist: accessible,
      showCloseIcon: accessible,
      closeIconColor: foreground,
      action: switch (toast.action) {
        final action? => SnackBarAction(
          label: action.label,
          textColor: foreground,
          onPressed: action.onPressed,
        ),
        null => null,
      },
    );
  }

  /// 桌面置中、最寬 [AppLayout.toastMaxWidth]；底部避開外殼發佈的高度與鍵盤。
  ///
  /// `Scaffold` 已經把 floating 的 SnackBar 放在底部安全區之上，所以只補超出
  /// 安全區的部分。
  EdgeInsets _margin(MediaQueryData media, AppSpacing spacing) {
    final occupied = math.max(
      ref.read(toastBottomInsetProvider),
      media.viewInsets.bottom,
    );
    final side = math.max(
      spacing.x4,
      (media.size.width - AppLayout.toastMaxWidth) / 2,
    );
    return EdgeInsets.fromLTRB(
      side,
      0,
      side,
      spacing.x4 + math.max(0.0, occupied - media.viewPadding.bottom),
    );
  }

  // 最外層的 Overlay 給提示自己的 tooltip（無障礙導覽時的關閉鈕）用：宿主在
  // Navigator 之上，Navigator 的 Overlay 在它下面，找不到。
  @override
  Widget build(BuildContext context) => Overlay.wrap(
    child: ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        // 宿主本身不畫東西，頁面由 Navigator 裡的路由自己畫。
        // ignore: fmp_lints/fmp_design_tokens — 透明是「不畫」，不是設計值。
        backgroundColor: Colors.transparent,
        // 鍵盤由頁面自己的 Scaffold 處理；宿主縮了會把整個 Navigator 一起縮。
        resizeToAvoidBottomInset: false,
        body: widget.child,
      ),
    ),
  );
}
