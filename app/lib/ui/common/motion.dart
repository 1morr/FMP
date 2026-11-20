import 'dart:math' as math;

import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/common/inert.dart';
import 'package:material_ui/material_ui.dart';

// 「減少動態效果」時仍要動的動畫（`docs/design/DESIGN.md`〈狀態變化對照〉的
// 最後一欄：淡入淡出、交叉淡出、圖片淡入、spinner 放慢）。系統開這個設定時，
// Flutter 預設的 AnimationController（含 AnimatedOpacity、AnimatedSwitcher、
// showGeneralDialog 的過場）把時長縮成 5%，等於直接跳過（事實 K35）；這裡的
// 元件都用 `AnimationBehavior.preserve`，照原本的時長動。要不要動、怎麼退化
// 由呼叫的地方經 `FmpMotion.reduced` 決定。

/// 淡入淡出到 [opacity]（AnimatedOpacity 的用法），減少動態效果時照樣淡。
class PreservedFade extends StatefulWidget {
  const PreservedFade({
    super.key,
    required this.opacity,
    required this.child,
    this.duration = FmpMotion.mid,
    this.curve = FmpMotion.outCurve,
  });

  final double opacity;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<PreservedFade> createState() => _PreservedFadeState();
}

class _PreservedFadeState extends State<PreservedFade>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: widget.opacity,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didUpdateWidget(PreservedFade old) {
    super.didUpdateWidget(old);
    if (widget.opacity != old.opacity) {
      _controller.animateTo(
        widget.opacity,
        duration: widget.duration,
        curve: widget.curve,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _controller, child: widget.child);
}

/// [PreservedSwitcher] 的過場：拿到這個 child 的進度（0 → 1 是進來）。
typedef SwitcherTransition = Widget Function(
  Widget child,
  Animation<double> animation,
);

/// 換 child 時的過場（AnimatedSwitcher 的用法：child 的型別或 key 不同才算
/// 換），減少動態效果時照樣動。預設是交叉淡出、疊在一起靠上置中。
class PreservedSwitcher extends StatefulWidget {
  const PreservedSwitcher({
    super.key,
    required this.child,
    this.duration = FmpMotion.mid,
    this.curve = FmpMotion.outCurve,
    this.transition = fadeTransition,
    this.alignment = Alignment.topCenter,
    this.fit = StackFit.loose,
  });

  final Widget? child;
  final Duration duration;
  final Curve curve;
  final SwitcherTransition transition;

  /// 新舊疊在一起時怎麼對齊（[Stack.alignment]）、要不要撐滿（[Stack.fit]）。
  final AlignmentGeometry alignment;
  final StackFit fit;

  static Widget fadeTransition(Widget child, Animation<double> animation) =>
      FadeTransition(opacity: animation, child: child);

  @override
  State<PreservedSwitcher> createState() => _PreservedSwitcherState();
}

class _Entry {
  _Entry(this.widget, this.controller, this.animation);

  Widget? widget;
  final AnimationController controller;
  final CurvedAnimation animation;

  void dispose() {
    animation.dispose();
    controller.dispose();
  }
}

class _PreservedSwitcherState extends State<PreservedSwitcher>
    with TickerProviderStateMixin {
  late _Entry _current = _entry(widget.child, value: 1);
  final _previous = <_Entry>[];

  _Entry _entry(Widget? child, {required double value}) {
    final controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: value,
      animationBehavior: AnimationBehavior.preserve,
    );
    return _Entry(
      child,
      controller,
      CurvedAnimation(parent: controller, curve: widget.curve),
    );
  }

  @override
  void didUpdateWidget(PreservedSwitcher old) {
    super.didUpdateWidget(old);
    final next = widget.child;
    final now = _current.widget;
    final same = next != null && now != null
        ? Widget.canUpdate(now, next)
        : next == null && now == null;
    if (same) {
      _current.widget = next;
      return;
    }
    final leaving = _current;
    _previous.add(leaving);
    leaving.controller.duration = widget.duration;
    leaving.controller.reverse().whenCompleteOrCancel(() {
      if (!mounted) return;
      setState(() => _previous.remove(leaving));
      leaving.dispose();
    });
    _current = _entry(next, value: 0)..controller.forward();
  }

  @override
  void dispose() {
    _current.dispose();
    for (final entry in _previous) {
      entry.dispose();
    }
    super.dispose();
  }

  /// 正在離開的點不到、Tab 不到、螢幕閱讀器讀不到；Inert 一直包著，換成
  /// 離開時才不會重建。
  Widget? _build(_Entry entry) => switch (entry.widget) {
    null => null,
    final child => KeyedSubtree(
      key: ObjectKey(entry),
      child: Inert(
        inert: !identical(entry, _current),
        child: widget.transition(child, entry.animation),
      ),
    ),
  };

  @override
  Widget build(BuildContext context) => Stack(
    alignment: widget.alignment,
    fit: widget.fit,
    children: [
      for (final entry in _previous) ?_build(entry),
      ?_build(_current),
    ],
  );
}

/// 小元件出現與消失（迷你播放器、播放膠囊、提示、多選動作列）：out 280，
/// 淡入並從下方 [rise]（不超過 20）滑上來；減少動態效果時只淡入淡出
/// （`DESIGN.md`〈狀態變化對照〉）。[child] 為 null 是不在。
class AppearSwitcher extends StatelessWidget {
  const AppearSwitcher({
    super.key,
    required this.child,
    this.rise = 20,
    this.alignment = Alignment.bottomCenter,
  });

  final Widget? child;
  final double rise;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final rise = FmpMotion.reduced(context) ? 0.0 : this.rise;
    return PreservedSwitcher(
      transition: (child, animation) => FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, (1 - animation.value) * rise),
            child: child,
          ),
          child: child,
        ),
      ),
      alignment: alignment,
      child: child,
    );
  }
}

/// 載入中的轉圈（`.spinner`）：18 見方、2 寬的環，上面四分之一較深，900ms
/// 等速一圈；減少動態效果時 3 秒一圈。
class Spinner extends StatefulWidget {
  const Spinner({
    super.key,
    this.size = 18,
    this.strokeWidth = 2,
    this.color,
    this.trackColor,
  });

  final double size;
  final double strokeWidth;

  /// 較深的那段；預設 `--label-2`。
  final Color? color;

  /// 其他部分；預設 `--label-4`。
  final Color? trackColor;

  /// 一圈多久。
  static const period = Duration(milliseconds: 900);
  static const reducedPeriod = Duration(seconds: 3);

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  // 預設的 controller 在減少動態效果時會轉快 20 倍。
  late final _controller = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final period = FmpMotion.reduced(context)
        ? Spinner.reducedPeriod
        : Spinner.period;
    if (_controller.duration != period) {
      _controller
        ..duration = period
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Semantics(
      container: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: RotationTransition(
          key: const Key('spinner-turns'),
          turns: _controller,
          child: CustomPaint(
            painter: _SpinnerPainter(
              color: widget.color ?? colors.label2,
              track: widget.trackColor ?? colors.label4,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawOval(rect, paint..color = track);
    // CSS 圓的 border-top：以正上方為中心的四分之一圈。
    canvas.drawArc(
      rect,
      -math.pi * 3 / 4,
      math.pi / 2,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.color != color ||
      old.track != track ||
      old.strokeWidth != strokeWidth;
}

/// 路由過場的 controller 用 `AnimationBehavior.preserve`：減少動態效果時的
/// 淡入淡出才真的有時長（預設的 controller 縮成 5%，事實 K35）。
mixin PreservedRouteTransition<T> on TransitionRoute<T> {
  @override
  AnimationController createAnimationController() => AnimationController(
    duration: transitionDuration,
    reverseDuration: reverseTransitionDuration,
    debugLabel: debugLabel,
    vsync: navigator!,
    animationBehavior: AnimationBehavior.preserve,
  );
}

/// 從邊緣升起的浮層（sheet、對話框）的路由（showGeneralDialog 的路由加上
/// [PreservedRouteTransition]）。
class PreservedDialogRoute<T> extends RawDialogRoute<T>
    with PreservedRouteTransition<T> {
  PreservedDialogRoute({
    required super.pageBuilder,
    required super.transitionBuilder,
    required super.transitionDuration,
    super.barrierDismissible,
    super.barrierLabel,
    super.barrierColor,
  });
}

/// 手機從底部升起的 sheet（曲目 ⋮、曲目資訊）：morph 520 從底邊滑入；減少
/// 動態效果時只淡入淡出（`DESIGN.md`〈狀態變化對照〉的浮層）。
Future<T?> showBottomSheetRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final reduced = FmpMotion.reduced(context);
  return Navigator.of(context, rootNavigator: true).push(
    PreservedDialogRoute<T>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: context.fmpColors.scrim,
      transitionDuration: FmpMotion.morph,
      transitionBuilder: (context, animation, _, child) {
        if (reduced) {
          return FadeTransition(
            key: const Key('sheet-fade'),
            opacity: CurvedAnimation(
              parent: animation,
              curve: FmpMotion.outCurve,
            ),
            child: child,
          );
        }
        return SlideTransition(
          key: const Key('sheet-slide'),
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(
              parent: animation,
              curve: FmpMotion.morphCurve,
              reverseCurve: FmpMotion.morphCurve.flipped,
            ),
          ),
          child: child,
        );
      },
      pageBuilder: (context, _, _) =>
          Align(alignment: Alignment.bottomCenter, child: builder(context)),
    ),
  );
}

/// 按下時縮到 [scale]（按鈕 0.96、圖示鈕 0.92），放開回 1：out 160，減少
/// 動態效果時照樣（`DESIGN.md`〈狀態變化對照〉的按下）。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.pressed,
    required this.scale,
    required this.child,
  });

  final bool pressed;
  final double scale;
  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: FmpMotion.fast,
    value: widget.pressed ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final _scale = Tween(
    begin: 1.0,
    end: widget.scale,
  ).animate(CurvedAnimation(parent: _controller, curve: FmpMotion.outCurve));

  @override
  void didUpdateWidget(PressScale old) {
    super.didUpdateWidget(old);
    if (widget.pressed != old.pressed) {
      widget.pressed ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    key: const Key('press-scale'),
    scale: _scale,
    child: widget.child,
  );
}

/// 值變了就從現在的值動到新的值（TweenAnimationBuilder 的用法），減少動態
/// 效果時照樣動：顏色過渡、選取時 out 280 的位置。[lerp] 算兩個值之間。
class PreservedTweenBuilder<T> extends StatefulWidget {
  const PreservedTweenBuilder({
    super.key,
    required this.value,
    required this.lerp,
    required this.builder,
    this.duration = FmpMotion.mid,
    this.curve = FmpMotion.outCurve,
    this.child,
  });

  final T value;
  final T Function(T a, T b, double t) lerp;
  final Duration duration;
  final Curve curve;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;

  @override
  State<PreservedTweenBuilder<T>> createState() =>
      _PreservedTweenBuilderState<T>();
}

class _PreservedTweenBuilderState<T> extends State<PreservedTweenBuilder<T>>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  late T _from = widget.value;
  late T _to = widget.value;

  T get _current =>
      widget.lerp(_from, _to, widget.curve.transform(_controller.value));

  @override
  void didUpdateWidget(PreservedTweenBuilder<T> old) {
    super.didUpdateWidget(old);
    if (widget.value != _to) {
      _from = _current;
      _to = widget.value;
      _controller
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => widget.builder(context, _current, child),
    child: widget.child,
  );
}

/// 清單裡的一列在骨架換成內容時交叉淡出：[fade] 從 0 動到 1 的途中，
/// [child] 淡入、壓在它上面的 [skeleton]（同一個位置原本的骨架列）淡出；動完
/// 只剩 [child]。[child] 一直在同一個位置，不會因為過場重建。
class SkeletonCrossFade extends StatefulWidget {
  const SkeletonCrossFade({
    super.key,
    required this.fade,
    required this.child,
    this.skeleton,
  });

  final Animation<double> fade;
  final Widget? skeleton;
  final Widget child;

  @override
  State<SkeletonCrossFade> createState() => _SkeletonCrossFadeState();
}

class _SkeletonCrossFadeState extends State<SkeletonCrossFade> {
  late bool _fading = widget.fade.isAnimating;

  @override
  void initState() {
    super.initState();
    widget.fade.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(SkeletonCrossFade old) {
    super.didUpdateWidget(old);
    if (old.fade != widget.fade) {
      old.fade.removeStatusListener(_onStatus);
      widget.fade.addStatusListener(_onStatus);
      _fading = widget.fade.isAnimating;
    }
  }

  @override
  void dispose() {
    widget.fade.removeStatusListener(_onStatus);
    super.dispose();
  }

  void _onStatus(AnimationStatus _) {
    if (_fading != widget.fade.isAnimating) {
      setState(() => _fading = widget.fade.isAnimating);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      FadeTransition(opacity: widget.fade, child: widget.child),
      if (_fading && widget.skeleton != null)
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: FadeTransition(
                opacity: ReverseAnimation(widget.fade),
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: double.infinity,
                  child: widget.skeleton,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
