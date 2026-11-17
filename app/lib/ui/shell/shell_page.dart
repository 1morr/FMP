import 'package:fmp/app/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

/// 頁面頂列（手機 `.ptop`、桌面與中寬度 `.wtop`）的位置，相對於內容區：
/// 離頂 [top]、高 [height]，左右各內縮 [left]、[right]；右邊已讓出外殼自己
/// 放在頂列的東西（詳情面板鈕、Windows 視窗鈕）。
class ShellTopBar {
  const ShellTopBar({
    required this.top,
    required this.height,
    required this.left,
    required this.right,
  });

  final double top;
  final double height;
  final double left;
  final double right;

  @override
  bool operator ==(Object other) =>
      other is ShellTopBar &&
      other.top == top &&
      other.height == height &&
      other.left == left &&
      other.right == right;

  @override
  int get hashCode => Object.hash(top, height, left, right);
}

/// 外殼告訴頁面內容要留的邊距：上面到大標題，下面讓出 dock 或播放膠囊。
/// 內容照樣從玻璃底下捲過去，所以是捲動的 padding，不是裁切。也告訴頁面
/// 自己的頂列放在哪裡（[ShellTopBar]）。
class ShellInsets extends InheritedWidget {
  const ShellInsets({
    super.key,
    required this.padding,
    required this.topBar,
    required super.child,
  });

  final EdgeInsets padding;
  final ShellTopBar topBar;

  static ShellInsets? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellInsets>();

  /// 不在外殼裡（例如單獨測一頁）時用頁面邊距。
  static EdgeInsets of(BuildContext context) =>
      _of(context)?.padding ?? EdgeInsets.all(context.fmpMetrics.pagePadding);

  /// 不在外殼裡時是頁面邊距內一條 50 高的列。
  static ShellTopBar topBarOf(BuildContext context) {
    if (_of(context)?.topBar case final bar?) return bar;
    final pad = context.fmpMetrics.pagePadding;
    return ShellTopBar(top: 0, height: 50, left: pad, right: pad);
  }

  @override
  bool updateShouldNotify(ShellInsets old) =>
      old.padding != padding || old.topBar != topBar;
}

/// 外殼裡的一頁：大標題，下面接著 [children]，整頁一起捲動。
class ShellPage extends StatelessWidget {
  const ShellPage({super.key, required this.title, this.children = const []});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: ShellInsets.of(context),
      children: [
        Semantics(
          header: true,
          child: Text(title, style: context.fmpText.large),
        ),
        const SizedBox(height: FmpSpace.s4),
        ...children,
      ],
    );
  }
}
