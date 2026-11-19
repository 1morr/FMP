import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
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

/// 音源 chip（`.src-chip`）：符號 14 加全名，膠囊底。[background] 換掉預設的
/// `--fill`（玻璃上用字色 8%，`.pl-kv .src-chip`）。
class SourceChip extends ConsumerWidget {
  const SourceChip({
    super.key,
    required this.pluginId,
    this.background,
    this.foreground,
    this.large = false,
  });

  final String pluginId;
  final Color? background;
  final Color? foreground;

  /// 平板的詳情面板：高 26、字 14。
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.fmpColors;
    final name = ref.watch(pluginManifestProvider(pluginId))?.name ?? pluginId;
    return Container(
      height: large ? 26 : 22,
      padding: const EdgeInsets.only(left: 6, right: 8),
      decoration: BoxDecoration(
        color: background ?? colors.fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: SourceMarkIcon(pluginId: pluginId, size: 14)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: large ? 14 : 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: foreground ?? colors.label,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
