import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/platform/window_chrome/window_chrome.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 平台宣告了自繪標題列（`PlatformCapabilities.customTitleBar`）時的視窗動作；否則 `null`。
/// 標題列與拖曳區都問它：UI 不判斷平台。
final activeWindowChromeProvider = Provider<WindowChrome?>(
  (ref) => ref.watch(platformCapabilitiesProvider).customTitleBar
      ? ref.watch(windowChromeProvider)
      : null,
);

/// 可以按住拖曳視窗、雙擊切換最大化的區域（`window_manager` 的 `DragToMoveArea` 同款）。
/// 沒有自繪標題列的平台直接回傳 [child]（沒給就是空的）。
///
/// 放在其他控制項的後面：點擊落在控制項上不會拖動視窗，只有空白處會（`translucent`）。
class WindowDragArea extends ConsumerWidget {
  const WindowDragArea({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chrome = ref.watch(activeWindowChromeProvider);
    if (chrome == null) return child ?? const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => unawaited(chrome.startDragging()),
      onDoubleTap: () => unawaited(chrome.toggleMaximize()),
      child: child ?? const SizedBox.expand(),
    );
  }
}

/// 自繪標題列（ADR 0035 §決定 6，舊版 `CustomTitleBar`）：36dp、主題的 `surface` 色。依
/// [WindowChrome.captionButtons] 排兩種版型：
///
/// - [CaptionButtons.drawn]（Windows）：左邊是 App 名稱（拖曳區，雙擊切換最大化），右邊最小化、
///   最大化（最大化中是還原）、關閉。
/// - [CaptionButtons.systemLeading]（macOS，ADR 0036 §決定 6）：系統的紅綠燈在左邊，App 不畫鈕；
///   「FMP」在整條的正中間（設計稿 APL-2 A）。拖曳與雙擊由系統的標題區處理。高度是系統標題區的高度
///   （[WindowChrome.titleBarHeight]），紅綠燈因此在列的正中間。
///
/// 沒有自繪標題列的平台不放這個 widget（外殼先看 [activeWindowChromeProvider]）。
///
/// 不在 Tab 的順序裡：系統標題列的按鈕本來就不在，鍵盤用 Win＋方向鍵與 Alt＋F4（macOS 是 ⌘M、⌘W）。
class WindowTitleBar extends ConsumerWidget {
  const WindowTitleBar({super.key, required this.chrome});

  final WindowChrome chrome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).shell;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = AppTokens.of(context).spacing;
    // App 名稱不翻譯（同側欄與舊版）。
    final name = Text(
      'FMP',
      style: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    );
    if (chrome.captionButtons == CaptionButtons.systemLeading) {
      return ExcludeFocus(
        child: Material(
          color: scheme.surface,
          child: SizedBox(
            height: chrome.titleBarHeight ?? AppLayout.titleBarHeight,
            // 不包 WindowDragArea：這一條正好在系統（透明）的標題區底下，拖曳與雙擊由系統處理，
            // 雙擊照使用者在系統設定選的動作（縮放或填滿）。Flutter 再處理一次雙擊會切換兩次。
            child: Center(child: name),
          ),
        ),
      );
    }
    return ExcludeFocus(
      child: Material(
        color: scheme.surface,
        child: SizedBox(
          height: AppLayout.titleBarHeight,
          child: Row(
            children: [
              Expanded(
                child: WindowDragArea(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(start: spacing.x4),
                      child: name,
                    ),
                  ),
                ),
              ),
              _CaptionButton(
                icon: Icons.remove,
                tooltip: t.minimizeTooltip,
                onPressed: chrome.minimize,
              ),
              ValueListenableBuilder<bool>(
                valueListenable: chrome.maximized,
                builder: (context, maximized, _) => _CaptionButton(
                  icon: maximized ? Icons.filter_none : Icons.crop_square,
                  tooltip: maximized ? t.restoreTooltip : t.maximizeTooltip,
                  onPressed: chrome.toggleMaximize,
                ),
              ),
              _CaptionButton(
                icon: Icons.close,
                tooltip: t.closeWindowTooltip,
                onPressed: chrome.close,
                isClose: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 標題列右邊的視窗鈕：46×36 的方鈕，滑過時淡底色，關閉鈕滑過時是 error 色。
class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: AppLayout.titleBarIcon),
      onPressed: () => unawaited(onPressed()),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(
          Size(AppLayout.titleBarButtonWidth, AppLayout.titleBarHeight),
        ),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => isClose && states.contains(WidgetState.hovered)
              ? scheme.onError
              : scheme.onSurfaceVariant,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => isClose && states.contains(WidgetState.hovered)
              ? scheme.error
              : null,
        ),
      ),
    );
  }
}

/// 根 Navigator 外面的框（ADR 0035 §決定 6，同舊版 `app.dart` 的 `AppContentWrapper`）：平台宣告自繪標題列
/// （[activeWindowChromeProvider] 有值）時，最上面一條 [WindowTitleBar]，下面是 [child]。標題列在所有 route
/// 之上，所以 Debug 頁、網頁登入、錯誤詳細、播放頁與對話框開著時視窗鈕都在。
///
/// - 放在 `ToastHost` 裡面：宿主的 `Overlay.wrap` 就是標題列 tooltip 要的 Overlay，提示的位置只看視窗寬度與
///   底部，不受頂端這一條影響。
/// - [child] 自己一個語意容器：每個 route 的 `ModalBarrier` 帶 `BlockSemantics`，不包的話對話框或全螢幕頁
///   開著時標題列的按鈕會從語意樹消失。
class WindowFrame extends ConsumerWidget {
  const WindowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chrome = ref.watch(activeWindowChromeProvider);
    if (chrome == null) return child;
    return Column(
      children: [
        WindowTitleBar(chrome: chrome),
        Expanded(child: Semantics(container: true, child: child)),
      ],
    );
  }
}
