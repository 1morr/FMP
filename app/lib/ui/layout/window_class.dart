import 'package:flutter/widgets.dart';

/// 寬度等級（ADR 0024 §決定 3），與 M3 window size class 同值：
/// compact < 600 ≤ medium < 840 ≤ expanded < 1200 ≤ large < 1600 ≤ extraLarge。
///
/// 看的是內容區的寬度，不是螢幕：由 [WindowClassScope] 量它所在的位置，子樹以
/// [WindowClass.of] 讀。
enum WindowClass {
  compact,
  medium,
  expanded,
  large,
  extraLarge;

  /// [width]（dp）屬於哪一級；下限含在該級內（600 是 medium）。
  static WindowClass forWidth(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    if (width < 1200) return expanded;
    if (width < 1600) return large;
    return extraLarge;
  }

  /// 最近的 [WindowClassScope] 量到的等級；只在等級改變時重建。
  static WindowClass of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_WindowClassInherited>();
    assert(scope != null, 'No WindowClassScope above this context');
    return scope!.windowClass;
  }
}

/// 以自己拿到的寬度決定 [WindowClass]，提供給子樹。
///
/// App 根（`MaterialApp.builder`）放一個，量的是整個視窗；外殼在內容區再放
/// 一個，頁面讀到的就是內容區的等級。
class WindowClassScope extends StatelessWidget {
  const WindowClassScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _WindowClassInherited(
      windowClass: WindowClass.forWidth(constraints.maxWidth),
      child: child,
    ),
  );
}

class _WindowClassInherited extends InheritedWidget {
  const _WindowClassInherited({
    required this.windowClass,
    required super.child,
  });

  final WindowClass windowClass;

  @override
  bool updateShouldNotify(_WindowClassInherited oldWidget) =>
      oldWidget.windowClass != windowClass;
}
