import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/toast/playback_toast.dart';
import 'package:fmp/ui/toast/toast.dart';
import 'package:material_ui/material_ui.dart';

/// 外殼裡畫提示的那一層（`.toast`，`docs/design/DESIGN.md`〈對話框、sheet、
/// 警示框、提示〉）：浮在迷你播放器或播放膠囊上方，厚玻璃，最小高 52（滑鼠
/// 44）。也在這裡把播放失敗（[playbackFailureProvider]）轉成提示。外殼用 [Positioned.fill] 放它，位置由
/// [bottom] 與 [stretch] 決定。
class ToastLayer extends ConsumerWidget {
  const ToastLayer({
    super.key,
    required this.bottom,
    required this.stretch,
    required this.touch,
    this.reportsFailures = true,
    this.left = 12,
    this.right = 12,
  });

  /// 提示底邊離這一層底邊的距離。
  final double bottom;

  /// 提示可以佔的左右範圍；桌面與中寬度是播放膠囊的左右，提示在內容欄
  /// 置中。
  final double left;
  final double right;

  /// 手機：左右各 12 撐滿；其他寬度置中、依文字長短，最寬 480。
  final bool stretch;

  /// 觸控密度的字級與圓角。
  final bool touch;

  /// 把播放失敗轉成提示。外殼的那一層一直掛著（被播放頁蓋住時也在），由它
  /// 轉；播放頁上的那一層只畫，免得同一次失敗轉兩次。
  final bool reportsFailures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(playbackFailureProvider, (_, failure) {
      if (failure == null || !reportsFailures) return;
      final track = failure.state.track;
      final manifest = ref.read(pluginManifestProvider(track.ref.pluginId));
      // 提示被點時這一層可能已經換掉，先抓好 router。
      final router = GoRouter.of(context);
      ref
          .read(toastProvider.notifier)
          .show(
            playbackFailedToast(
              context.t,
              failure,
              source: manifest?.name ?? track.ref.pluginId,
              retry: () => ref.read(playbackProvider.notifier).play(track),
              showQueue: () => router.go(Destination.queue.path),
            ),
          );
    });
    final message = ref.watch(toastProvider);
    return Stack(
      children: [
        Positioned(
          left: left,
          right: right,
          bottom: bottom,
          child: AnimatedSwitcher(
            duration: FmpMotion.mid,
            switchInCurve: FmpMotion.outCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, .3),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: message == null
                ? const SizedBox.shrink()
                : Align(
                    key: ObjectKey(message),
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: stretch ? double.infinity : 480,
                      ),
                      child: _Toast(
                        message: message,
                        stretch: stretch,
                        touch: touch,
                        onAction: () {
                          ref.read(toastProvider.notifier).dismiss();
                          message.action?.onTap();
                        },
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({
    required this.message,
    required this.stretch,
    required this.touch,
    required this.onAction,
  });

  final ToastMessage message;
  final bool stretch;
  final bool touch;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final action = message.action;
    final text = Text(
      message.text,
      style: context.fmpText.sub.copyWith(
        fontSize: touch ? 13.5 : 13,
        height: 18 / 13.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: colors.glassInk,
      ),
    );
    final body = Row(
      mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (message.icon case final icon?) ...[
          FmpIcon(icon, size: 18, color: colors.glassInk),
          const SizedBox(width: 8),
        ],
        if (stretch) Expanded(child: text) else Flexible(child: text),
        if (action != null) ...[
          const SizedBox(width: 10),
          ShellButton(
            onTap: onAction,
            builder: (context, _) => Container(
              height: 34,
              padding: EdgeInsets.symmetric(horizontal: touch ? 20 : 14),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: colors.accentSoft,
                shape: const StadiumBorder(),
              ),
              child: Text(
                action.label,
                style: context.fmpText.sub.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  color: colors.accent,
                ),
              ),
            ),
          ),
        ],
      ],
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: Glass(
        variant: GlassVariant.thick,
        radius: touch ? 26 : 22,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: touch ? 52 : 44),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, action == null ? 18 : 8, 8),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
