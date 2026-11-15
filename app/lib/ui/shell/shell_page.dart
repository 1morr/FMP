import 'package:fmp/app/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

/// 外殼告訴頁面內容要留的邊距：上面到大標題，下面讓出 dock 或播放膠囊。
/// 內容照樣從玻璃底下捲過去，所以是捲動的 padding，不是裁切。
class ShellInsets extends InheritedWidget {
  const ShellInsets({super.key, required this.padding, required super.child});

  final EdgeInsets padding;

  /// 不在外殼裡（例如單獨測一頁）時用頁面邊距。
  static EdgeInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellInsets>()?.padding ??
      EdgeInsets.all(context.fmpMetrics.pagePadding);

  @override
  bool updateShouldNotify(ShellInsets old) => old.padding != padding;
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
