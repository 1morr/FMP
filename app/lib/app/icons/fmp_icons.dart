import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:path_parsing/path_parsing.dart';

/// 設計稿的圖示（`docs/design/assets/kit.js` 的 `FMP.icon`）：同一組線條，
/// 24 格、圓頭圓角。路徑照稿搬過來，用到哪個搬哪個；`circle`、`rect` 改寫
/// 成等價的路徑。
enum FmpIcons {
  search([
    _Part('M4.5 10.8a6.3 6.3 0 1 0 12.6 0a6.3 6.3 0 1 0 -12.6 0'),
    _Part('M15.6 15.6 20 20'),
  ]),
  home([
    _Part('M3.8 11 12 4.2l8.2 6.8'),
    _Part('M6 9.4v9.1c0 .8.7 1.5 1.5 1.5h9c.8 0 1.5-.7 1.5-1.5V9.4'),
    _Part('M10 20v-4.6c0-.6.4-1 1-1h2c.6 0 1 .4 1 1V20'),
  ]),
  library([
    // rect x=3.5 y=7.5 w=13 h=13 rx=3
    _Part(
      'M6.5 7.5h7a3 3 0 0 1 3 3v7a3 3 0 0 1 -3 3h-7a3 3 0 0 1 -3 -3v-7a3 3 0 0 1 3 -3z',
    ),
    _Part('M8 3.5h9.5a3 3 0 0 1 3 3V16'),
    _Part('M6.9 16.6a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0'),
    _Part('M10.3 16.6v-5.2l3.2-.9'),
  ]),
  queue([
    _Part('M4 6.5h16M4 12h10M4 17.5h7'),
    _Part('M15.5 14.6v6l4.9-3z', fill: true, strokeWidth: 1.2),
  ]),
  settings(null),
  sidebarR([
    // rect x=3.5 y=5 w=17 h=14 rx=2.8
    _Part(
      'M6.3 5h11.4a2.8 2.8 0 0 1 2.8 2.8v8.4a2.8 2.8 0 0 1 -2.8 2.8h-11.4a2.8 2.8 0 0 1 -2.8 -2.8v-8.4a2.8 2.8 0 0 1 2.8 -2.8z',
    ),
    _Part('M14.5 5v14'),
  ]),
  close([_Part('M6.5 6.5l11 11M17.5 6.5l-11 11')]);

  const FmpIcons(this._parts);

  final List<_Part>? _parts;

  List<_Part> get _all => _parts ?? _gearParts;

  /// 設定的齒輪由 kit.js 的 gearPath() 算出來，只算一次。
  static final _gearParts = [
    _Part(_gearPath()),
    const _Part('M9.2 12a2.8 2.8 0 1 0 5.6 0a2.8 2.8 0 1 0 -5.6 0'),
  ];
}

/// 圖示的一筆：預設只描邊；[fill] 時填滿並用 [strokeWidth] 描邊。
class _Part {
  const _Part(this.d, {this.fill = false, this.strokeWidth});

  final String d;
  final bool fill;
  final double? strokeWidth;
}

String _gearPath() {
  const cx = 12.0, cy = 12.0, ro = 9.0, ri = 6.9, n = 8;
  String p(double r, double a) =>
      '${(cx + r * math.cos(a)).toStringAsFixed(2)} '
      '${(cy + r * math.sin(a)).toStringAsFixed(2)}';
  final d = StringBuffer();
  for (var i = 0; i < n; i++) {
    final a0 = i / n * math.pi * 2;
    const step = math.pi * 2 / n;
    d
      ..write(i == 0 ? 'M' : 'L')
      ..write(p(ri, a0))
      ..write('L${p(ro, a0 + step * .22)}')
      ..write('L${p(ro, a0 + step * .5)}')
      ..write('L${p(ri, a0 + step * .72)}');
  }
  return '${d}Z';
}

/// 畫一個 [FmpIcons]。顏色與大小沒給時照 [IconTheme]，像內建的 `Icon`。
/// 線寬是 24 格裡的寬度（稿的預設 1.8，導覽 1.7），跟著大小縮放。
class FmpIcon extends StatelessWidget {
  const FmpIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.strokeWidth = 1.8,
    this.semanticLabel,
  });

  final FmpIcons icon;
  final double? size;
  final Color? color;
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 22;
    final paint = SizedBox.square(
      dimension: side,
      child: CustomPaint(
        painter: _IconPainter(
          icon,
          color ?? theme.color ?? const Color(0xFF000000),
          strokeWidth,
        ),
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: paint)
        : Semantics(label: semanticLabel, child: paint);
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color, this.strokeWidth);

  final FmpIcons icon;
  final Color color;
  final double strokeWidth;

  static final _cache = <FmpIcons, List<Path>>{};

  static List<Path> _paths(FmpIcons icon) =>
      _cache[icon] ??= [for (final part in icon._all) _parse(part.d)];

  static Path _parse(String d) {
    final proxy = _PathProxy();
    writeSvgPathDataToPath(d, proxy);
    return proxy.path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas
      ..save()
      ..scale(scale);
    final paths = _paths(icon);
    for (var i = 0; i < paths.length; i++) {
      final part = icon._all[i];
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = part.strokeWidth ?? strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color
        ..isAntiAlias = true;
      if (part.fill) {
        canvas.drawPath(
          paths[i],
          Paint()
            ..color = color
            ..isAntiAlias = true,
        );
      }
      canvas.drawPath(paths[i], stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}

class _PathProxy extends PathProxy {
  final path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}
