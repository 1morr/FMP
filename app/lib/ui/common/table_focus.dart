import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:fmp/ui/common/focus_ring.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面表格（佇列、搜尋結果）的鍵盤焦點：整張表是一個 Tab 停點，選取的那列
/// 就是焦點所在（同系統的清單）：↑／↓ 移動選取，焦點外框畫在選取的列外面，
/// Shift+F10 或選單鍵打開那列的選單（Windows 與多數桌面 App 的慣例）。

/// 開選單的鍵：選單鍵，或 Shift+F10。
bool isMenuKey(KeyEvent event) =>
    event.logicalKey == LogicalKeyboardKey.contextMenu ||
    (event.logicalKey == LogicalKeyboardKey.f10 &&
        HardwareKeyboard.instance.isShiftPressed);

/// [node] 有焦點、而且最後一下輸入是鍵盤（`:focus-visible` 的語意）時為真：
/// 按下滑鼠或手指就不算，即使焦點是點出來的。框架的 highlight mode 在滑鼠
/// 之後仍是 traditional，所以自己看最後一下輸入。
class KeyboardFocus extends ValueNotifier<bool> {
  KeyboardFocus(this.node) : super(false) {
    node.addListener(_update);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  final FocusNode node;
  bool _lastInputWasKey = false;

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent && _lastInputWasKey) {
      _lastInputWasKey = false;
      _update();
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && !_lastInputWasKey) {
      _lastInputWasKey = true;
      _update();
    }
    return false;
  }

  void _update() => value = node.hasPrimaryFocus && _lastInputWasKey;

  @override
  void dispose() {
    node.removeListener(_update);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }
}

/// 表格的一列在 [focused] 時畫焦點外框，剛變成焦點時捲進看得到的地方；
/// [anchorKey] 標在列的左下角，鍵盤開選單時從那裡長出來。
class FocusableTableRow extends StatefulWidget {
  const FocusableTableRow({
    super.key,
    required this.focused,
    required this.radius,
    required this.child,
    required this.onActivate,
    this.anchorKey,
  });

  final bool focused;

  /// 螢幕閱讀器點這列（雙擊或 ↩ 的同一件事，例如播放）。列自己不是一個
  /// Tab 停點，但對螢幕閱讀器是表格裡可聚焦的一項，[focused] 時是焦點。
  final VoidCallback onActivate;
  final double radius;
  final GlobalKey? anchorKey;
  final Widget child;

  @override
  State<FocusableTableRow> createState() => _FocusableTableRowState();
}

class _FocusableTableRowState extends State<FocusableTableRow> {
  @override
  void didUpdateWidget(FocusableTableRow old) {
    super.didUpdateWidget(old);
    if (widget.focused && !old.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final policy in [
          ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ]) {
          Scrollable.ensureVisible(context, alignmentPolicy: policy);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Semantics(
        focusable: true,
        focused: widget.focused,
        onTap: widget.onActivate,
        child: FocusRing(
          visible: widget.focused,
          radius: widget.radius,
          child: widget.child,
        ),
      ),
      if (widget.anchorKey case final key?)
        Positioned(left: 0, bottom: 0, child: SizedBox.shrink(key: key)),
    ],
  );
}

/// [key] 標的那一點的螢幕座標（[FocusableTableRow.anchorKey]）。
Offset? menuAnchorOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached) return null;
  return box.localToGlobal(Offset.zero);
}
