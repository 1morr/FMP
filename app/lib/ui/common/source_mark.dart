import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:material_ui/material_ui.dart';

/// 音源標識的符號（`.src`，`docs/design/DESIGN.md`〈音源標識〉）：照插件
/// [pluginId] 的 manifest 宣告的路徑畫，螢幕閱讀器讀音源名稱。插件沒宣告
/// 標識時什麼都不畫。
class SourceMarkIcon extends ConsumerWidget {
  const SourceMarkIcon({super.key, required this.pluginId, required this.size});

  final String pluginId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifest = ref.watch(pluginManifestProvider(pluginId));
    final mark = manifest?.mark;
    if (manifest == null || mark == null) return const SizedBox.shrink();
    return Semantics(
      label: manifest.name,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MarkPainter(mark)),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.mark);

  final SourceMark mark;

  static final _cache = Expando<List<Path>>();

  List<Path> get _paths =>
      _cache[mark] ??= [for (final p in mark.paths) svgPath(p.pathData)];

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.shortestSide / 16);
    final paths = _paths;
    for (final (i, part) in mark.paths.indexed) {
      if (part.fillColor case final fill?) {
        canvas.drawPath(paths[i], Paint()..color = Color(fill));
      }
      if (part.strokeColor case final stroke?) {
        canvas.drawPath(
          paths[i],
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Color(stroke)
            ..strokeWidth = part.strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.mark != mark;
}
