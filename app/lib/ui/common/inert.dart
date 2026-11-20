import 'package:material_ui/material_ui.dart';

/// [inert] 時 [child] 像不在畫面上一樣：點不到、Tab 不到、螢幕閱讀器讀不到，
/// 但照樣畫出來（例如淡出中、或過場裡還被蓋著的元件）。
class Inert extends StatelessWidget {
  const Inert({super.key, required this.inert, required this.child});

  final bool inert;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: inert,
    child: ExcludeFocus(
      excluding: inert,
      child: ExcludeSemantics(excluding: inert, child: child),
    ),
  );
}
