import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/common/motion.dart';
import 'package:material_ui/material_ui.dart';

/// 展開、收起的那幾列（首頁榜展開到 10 名、搜尋頁的分 P）：平常高度跟著變
/// （morph，不彈跳）；系統開「減少動態效果」時只淡入淡出
/// （`docs/design/DESIGN.md`〈狀態變化對照〉的展開／收合）。
class ExpandingRows extends StatelessWidget {
  const ExpandingRows({super.key, required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shown = expanded ? child : const SizedBox(width: double.infinity);
    if (FmpMotion.reduced(context)) {
      return PreservedSwitcher(
        key: const Key('expanding-rows-fade'),
        child: KeyedSubtree(key: ValueKey(expanded), child: shown),
      );
    }
    return ClipRect(
      key: const Key('expanding-rows-size'),
      child: AnimatedSize(
        duration: FmpMotion.morph,
        curve: FmpMotion.morphCurve,
        alignment: Alignment.topCenter,
        child: shown,
      ),
    );
  }
}
