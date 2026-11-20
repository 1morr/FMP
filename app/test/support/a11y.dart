import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/common/focus_ring.dart';
import 'package:material_ui/material_ui.dart';

/// 無障礙的共用檢查（`docs/design/DESIGN.md`〈無障礙〉）：點擊區大小、語意
/// 標籤用框架的 [meetsGuideline]，這裡補框架沒有的兩條。

/// 桌面滑鼠目標 ≥ 28（觸控的 44 用框架的 [iOSTapTargetGuideline]）。
const pointerTapTargetGuideline = MinimumTapTargetGuideline(
  size: Size(28, 28),
  link: 'docs/design/DESIGN.md〈無障礙〉',
);

/// 能點的就能用鍵盤選到：每個沒停用、有點擊動作的語意節點都要可聚焦。
const focusableTapTargetGuideline = _FocusableTapTargetGuideline();

class _FocusableTapTargetGuideline extends AccessibilityGuideline {
  const _FocusableTapTargetGuideline();

  @override
  String get description => 'Tappable nodes should be keyboard focusable';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      result += _traverse(view.owner!.semanticsOwner!.rootSemanticsNode!);
    }
    return result;
  }

  Evaluation _traverse(SemanticsNode node) {
    var result = const Evaluation.pass();
    node.visitChildren((child) {
      result += _traverse(child);
      return true;
    });
    if (node.isMergedIntoParent || node.isInvisible) return result;
    final data = node.getSemanticsData();
    final flags = data.flagsCollection;
    if (flags.isHidden ||
        flags.isTextField ||
        flags.isEnabled == ui.Tristate.isFalse ||
        !data.hasAction(ui.SemanticsAction.tap)) {
      return result;
    }
    if (flags.isFocused == ui.Tristate.none) {
      result += Evaluation.fail(
        '$node: expected tappable node "${data.label}${data.tooltip}" to be '
        'keyboard focusable.',
      );
    }
    return result;
  }
}

/// 按 Tab 走 [steps] 步，每一步都要畫出剛好一個焦點外框（輸入框除外，它有
/// 自己的游標與外框）：停在看不到外框的地方（例如空的頁面本身）就失敗。回傳
/// 每一步有焦點的語意標籤，給測試對到期望的控制。
Future<List<String>> tabThrough(WidgetTester tester, int steps) async {
  final visited = <String>[];
  for (var i = 0; i < steps; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (focus == null || context == null) continue;
    final editing =
        context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
    final rings = find
        .byWidgetPredicate(
          (w) => w is FocusRing && w.visible,
          skipOffstage: false,
        )
        .evaluate()
        .length;
    expect(
      rings,
      editing ? 0 : 1,
      reason: 'Tab #${i + 1} focused ${_labelOf(context)}',
    );
    visited.add(_labelOf(context));
  }
  return visited;
}

/// 畫面上看得到的焦點外框有幾個。
int visibleFocusRings() => find
    .byWidgetPredicate((w) => w is FocusRing && w.visible)
    .evaluate()
    .length;

/// [context] 所在語意節點的標籤（含合併進來的字）。
String _labelOf(BuildContext context) {
  var render = context.findRenderObject();
  while (render != null) {
    final node = render.debugSemantics;
    if (node != null) {
      final data = node.getSemanticsData();
      if (data.label.isNotEmpty) return data.label;
      if (data.tooltip.isNotEmpty) return data.tooltip;
    }
    render = render.parent;
  }
  return '';
}

/// 把三條準則一次跑完，失敗時列出全部；[touch] 時點擊區 44，否則 28。
Future<void> expectAccessible(
  WidgetTester tester, {
  required bool touch,
}) async {
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(focusableTapTargetGuideline));
  await expectLater(
    tester,
    meetsGuideline(touch ? iOSTapTargetGuideline : pointerTapTargetGuideline),
  );
}
