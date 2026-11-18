import 'dart:math' as math;

import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:material_ui/material_ui.dart';

/// 選單的一列或一條分隔線。
sealed class GlassMenuEntry<T> {
  const GlassMenuEntry();
}

/// 選單的一個項目（`.gmenu .mi`）。
class GlassMenuItem<T> extends GlassMenuEntry<T> {
  const GlassMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.shortcut,
    this.destructive = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final FmpIcons? icon;

  /// 桌面列尾的鍵盤提示（`.k`）。
  final String? shortcut;

  /// 會刪掉東西的動作：`--danger` 字色。
  final bool destructive;

  /// 停用時 40% 透明、點不了。
  final bool enabled;
}

/// 分隔線（`.ms`）；[thick] 是區隔會動到資料的動作的粗分隔（`.ms.thick`）。
class GlassMenuDivider<T> extends GlassMenuEntry<T> {
  const GlassMenuDivider({this.thick = false});

  final bool thick;
}

/// 在 [at]（全域座標）打開玻璃選單（`.gmenu`，`docs/design/DESIGN.md`
/// 〈選單〉）：厚玻璃、跟主題走；觸控與滑鼠兩種密度照 `platform/` 的密度。
/// 選了回傳那個項目的值，點外面或按 Esc 回傳 null。方向鍵移動、↩ 選取。
/// [header] 是頂端的摘要（`.mh`：動作作用在哪首曲目），下面接一條細分隔。
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required Offset at,
  required List<GlassMenuEntry<T>> entries,
  Widget? header,
}) {
  final touch = FormFactor.of(context).density == Density.touch;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x00000000),
    transitionDuration: FmpMotion.fast,
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, _, _) => CustomSingleChildLayout(
      delegate: _MenuPosition(at),
      child: _GlassMenu<T>(entries: entries, touch: touch, header: header),
    ),
  );
}

/// 選單左上角放在 [at]，超出畫面時往左、往上翻，離邊緣至少 8。
class _MenuPosition extends SingleChildLayoutDelegate {
  _MenuPosition(this.at);

  final Offset at;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = at.dx;
    var y = at.dy;
    if (x + child.width > size.width - _margin) x = at.dx - child.width;
    if (y + child.height > size.height - _margin) y = at.dy - child.height;
    return Offset(
      x.clamp(_margin, math.max(_margin, size.width - child.width - _margin)),
      y.clamp(_margin, math.max(_margin, size.height - child.height - _margin)),
    );
  }

  @override
  bool shouldRelayout(_MenuPosition old) => old.at != at;
}

class _GlassMenu<T> extends StatelessWidget {
  const _GlassMenu({required this.entries, required this.touch, this.header});

  final List<GlassMenuEntry<T>> entries;
  final bool touch;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    // 第一個可選的項目先拿到焦點：鍵盤直接上下選；桌面稿也標亮它（`.hl`）。
    final focused = entries.indexWhere(
      (e) => e is GlassMenuItem<T> && e.enabled,
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: SizedBox(
        width: touch ? 252 : 236,
        child: Glass(
          variant: GlassVariant.thick,
          radius: touch ? 22 : 14,
          // 對話框路由裡沒有 Material：補上預設字型樣式，字才不帶除錯底線。
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: touch
                  ? const EdgeInsets.symmetric(vertical: 6)
                  : const EdgeInsets.all(5),
              child: FocusTraversalGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (header case final header?) ...[
                      Padding(
                        padding: touch
                            ? const EdgeInsets.fromLTRB(14, 6, 14, 10)
                            : const EdgeInsets.fromLTRB(8, 5, 8, 8),
                        child: header,
                      ),
                      Container(
                        height: 0.5,
                        margin: EdgeInsets.only(
                          bottom: touch ? 5 : 4,
                          left: touch ? 0 : 8,
                          right: touch ? 0 : 8,
                        ),
                        color: colors.glassInk.withValues(alpha: 0.14),
                      ),
                    ],
                    for (final (i, entry) in entries.indexed)
                      switch (entry) {
                        GlassMenuItem<T>() => _Item<T>(
                          item: entry,
                          touch: touch,
                          autofocus: i == focused,
                        ),
                        GlassMenuDivider<T>(:final thick) => Container(
                          height: thick ? 7 : 0.5,
                          margin: thick
                              ? const EdgeInsets.symmetric(vertical: 4)
                              : EdgeInsets.symmetric(
                                  vertical: touch ? 5 : 4,
                                  horizontal: touch ? 0 : 8,
                                ),
                          color: colors.glassInk.withValues(
                            alpha: thick ? 0.06 : 0.14,
                          ),
                        ),
                      },
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

class _Item<T> extends StatefulWidget {
  const _Item({
    required this.item,
    required this.touch,
    required this.autofocus,
  });

  final GlassMenuItem<T> item;
  final bool touch;
  final bool autofocus;

  @override
  State<_Item<T>> createState() => _ItemState<T>();
}

class _ItemState<T> extends State<_Item<T>> {
  bool _highlighted = false;

  void _choose() => Navigator.of(context).pop(widget.item.value);

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final touch = widget.touch;
    final colors = context.fmpColors;
    final lit = _highlighted && item.enabled;
    // 桌面滑過是強調色實心底；觸控是 `--glass-press`。
    final ink = lit && !touch
        ? colors.accentInk
        : item.destructive
        ? colors.danger
        : colors.glassInk;
    final ink2 = lit && !touch ? colors.accentInk : colors.glassInk2;
    final icon = item.icon == null
        ? null
        : FmpIcon(
            item.icon!,
            size: touch ? 20 : 15,
            color: item.destructive && !(lit && !touch) ? colors.danger : ink2,
          );
    final label = Expanded(
      child: Text(
        item.label,
        style: context.fmpText.body.copyWith(
          fontSize: touch ? 16 : 13,
          height: touch ? 21 / 16 : 17 / 13,
          letterSpacing: 0,
          color: ink,
        ),
      ),
    );
    final row = Row(
      children: [
        if (!touch && icon != null) ...[icon, const SizedBox(width: 9)],
        label,
        if (item.shortcut case final shortcut? when !touch)
          Text(
            shortcut,
            style: context.fmpText.cap
                .copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: ink2,
                )
                .tabular,
          ),
        if (touch && icon != null) ...[const SizedBox(width: 12), icon],
      ],
    );
    return Opacity(
      opacity: item.enabled ? 1 : 0.4,
      child: FocusableActionDetector(
        enabled: item.enabled,
        autofocus: widget.autofocus,
        mouseCursor: item.enabled
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onShowHoverHighlight: (value) => setState(() => _highlighted = value),
        onShowFocusHighlight: (value) => setState(() => _highlighted = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _choose();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          enabled: item.enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: item.enabled ? _choose : null,
            child: Container(
              constraints: BoxConstraints(minHeight: touch ? 44 : 28),
              padding: EdgeInsets.symmetric(horizontal: touch ? 16 : 9),
              decoration: BoxDecoration(
                color: !lit
                    ? null
                    : touch
                    ? colors.glassPress
                    : colors.accentFill,
                borderRadius: BorderRadius.circular(touch ? 0 : 8),
              ),
              alignment: Alignment.centerLeft,
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}
