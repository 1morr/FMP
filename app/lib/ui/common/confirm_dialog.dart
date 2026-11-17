import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:material_ui/material_ui.dart';

/// 警示框（`.alert`，`docs/design/DESIGN.md`〈對話框〉）：置中的厚玻璃，兩顆等寬
/// 按鈕，取消在左、確定在右。破壞性動作用 [destructive]（danger 色）。
/// 預設沒有焦點在確定鍵上，所以 ↩ 不會直接確定；Esc、點背後的暗層＝取消。
/// 回傳使用者是否確定。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final colors = context.fmpColors;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: colors.scrim,
    builder: (context) => _ConfirmDialog(
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
  return confirmed ?? false;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final touch = FormFactor.of(context).density == Density.touch;
    final buttonHeight = touch ? 46.0 : 32.0;
    return Center(
      child: SizedBox(
        width: touch ? 300 : 340,
        child: Glass(
          variant: GlassVariant.thick,
          radius: context.fmpMetrics.radii.dialog,
          child: Material(
            type: MaterialType.transparency,
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: title,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: touch ? 17 : 14,
                        height: touch ? 22 / 17 : 18 / 14,
                        fontWeight: FontWeight.w600,
                        color: colors.glassInk,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: touch ? 14 : 12.5,
                        height: touch ? 19 / 14 : 17 / 12.5,
                        color: colors.glassInk2,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: FmpButton(
                            label: cancelLabel,
                            height: buttonHeight,
                            onTap: () => Navigator.of(context).pop(false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FmpButton(
                            label: confirmLabel,
                            height: buttonHeight,
                            variant: destructive
                                ? FmpButtonVariant.danger
                                : FmpButtonVariant.primary,
                            onTap: () => Navigator.of(context).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
