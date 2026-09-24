import 'package:flutter/material.dart';

/// 自帶一層 Overlay 的 [Slider]。FMP 裡所有 Slider 都走這裡。
///
/// Material `Slider` 為了數值指示器，一建立就在最近的 Overlay 放一個
/// `OverlayPortal` 子節點。這個子節點的語意節點實體上掛在 Overlay 底下，走訪
/// 順序卻嫁接回 Slider。只要它落在 Navigator 的 Overlay，Windows 的
/// `AccessibilityBridge` 就更新失敗（log 是 `Failed to update ui::AXTree ... will
/// not be in the tree`，flutter/flutter#182444）。而且一旦失敗，整棵路由子樹就再
/// 也送不進去，Narrator 只讀得到標題列上的舊標籤。
/// 實測（Flutter 3.47.1）：迷你播放列的音量 Slider 讓啟動就壞掉，播放頁的
/// 兩個 Slider 讓打開播放頁就壞掉；包上本地 Overlay 之後，錯誤是 0 行，節點
/// 從 7 個回到 120 多個。
///
/// 用 [Clip.none] 是因為有 `divisions` 與 `label` 的 Slider（歌詞樣式對話框）
/// 拖曳時要把指示器畫在自己的範圍外面。
class ScopedSlider extends StatelessWidget {
  const ScopedSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.label,
    this.onChangeStart,
    this.onChangeEnd,
    this.semanticFormatterCallback,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final SemanticFormatterCallback? semanticFormatterCallback;

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(
      clipBehavior: Clip.none,
      child: Slider(
        value: value,
        onChanged: onChanged,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        semanticFormatterCallback: semanticFormatterCallback,
      ),
    );
  }
}
