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
  close([_Part('M6.5 6.5l11 11M17.5 6.5l-11 11')]),
  minus([_Part('M5 12h14')]),
  // Windows 的最大化鈕（設計系統頁的〈Windows 視窗按鈕〉）：
  // rect x=6 y=6 w=12 h=12 rx=1.5
  windowMaximize([
    _Part(
      'M7.5 6h9a1.5 1.5 0 0 1 1.5 1.5v9a1.5 1.5 0 0 1 -1.5 1.5h-9a1.5 1.5 0 0 1 -1.5 -1.5v-9a1.5 1.5 0 0 1 1.5 -1.5z',
    ),
  ]),
  // 還原：稿沒畫，照 Windows 的慣例是疊在一起的兩個方框，和最大化同大。
  // 前面 rect x=6 y=8.5 w=9.5 h=9.5 rx=1.5，後面只畫露出來的上緣與右緣。
  windowRestore([
    _Part(
      'M7.5 8.5h6.5a1.5 1.5 0 0 1 1.5 1.5v6.5a1.5 1.5 0 0 1 -1.5 1.5h-6.5a1.5 1.5 0 0 1 -1.5 -1.5v-6.5a1.5 1.5 0 0 1 1.5 -1.5z',
    ),
    _Part('M8.5 6h8a1.5 1.5 0 0 1 1.5 1.5v8'),
  ]),
  play([
    _Part(
      'M8 5.2v13.6c0 .6.7 1 1.2.7l10.6-6.8c.5-.3.5-1 0-1.4L9.2 4.5C8.7 4.2 8 4.6 8 5.2z',
      fill: true,
      stroke: false,
    ),
  ]),
  // rect x=6.2 y=4.8 w=4.2 h=14.4 rx=1.3，與 x=13.6 的同一個。
  pause([
    _Part(
      'M7.5 4.8h1.6a1.3 1.3 0 0 1 1.3 1.3v11.8a1.3 1.3 0 0 1 -1.3 1.3h-1.6a1.3 1.3 0 0 1 -1.3 -1.3v-11.8a1.3 1.3 0 0 1 1.3 -1.3z'
      'M14.9 4.8h1.6a1.3 1.3 0 0 1 1.3 1.3v11.8a1.3 1.3 0 0 1 -1.3 1.3h-1.6a1.3 1.3 0 0 1 -1.3 -1.3v-11.8a1.3 1.3 0 0 1 1.3 -1.3z',
      fill: true,
      stroke: false,
    ),
  ]),
  warn([
    _Part(
      'M10.6 4.7 3.3 17.6c-.6 1.1.2 2.4 1.4 2.4h14.6c1.2 0 2-1.3 1.4-2.4L13.4 4.7c-.6-1.1-2.2-1.1-2.8 0z',
    ),
    _Part('M12 10v4'),
    _Part('M11 16.9a1 1 0 1 0 2 0a1 1 0 1 0 -2 0', fill: true, stroke: false),
  ]),
  wifi([
    _Part(
      'M4.5 10a11 11 0 0 1 15 0M7.5 13.2a6.6 6.6 0 0 1 9 0',
      strokeWidth: 2.2,
    ),
    _Part(
      'M10.4 16.8a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0 -3.2 0',
      fill: true,
      stroke: false,
    ),
  ]),
  shield([
    _Part('M12 3.5 19 6.3v5.3c0 4.2-2.9 7.6-7 8.9-4.1-1.3-7-4.7-7-8.9V6.3z'),
    _Part('m9 12 2.1 2.1L15.2 10'),
  ]),
  next([
    _Part(
      'M4.5 6.6v10.8c0 .6.6.9 1.1.6l7.8-5.4c.4-.3.4-.9 0-1.2L5.6 6c-.5-.3-1.1 0-1.1.6z'
      'M12.5 6.6v10.8c0 .6.6.9 1.1.6l7.8-5.4c.4-.3.4-.9 0-1.2L13.6 6c-.5-.3-1.1 0-1.1.6z',
      fill: true,
      stroke: false,
    ),
  ]),
  prev([
    _Part(
      'M19.5 6.6v10.8c0 .6-.6.9-1.1.6l-7.8-5.4a.7.7 0 0 1 0-1.2L18.4 6c.5-.3 1.1 0 1.1.6z'
      'M11.5 6.6v10.8c0 .6-.6.9-1.1.6l-7.8-5.4a.7.7 0 0 1 0-1.2L10.4 6c.5-.3 1.1 0 1.1.6z',
      fill: true,
      stroke: false,
    ),
  ]),
  nextUp([
    _Part('M4 6.5h10M4 11.5h10M4 16.5h6'),
    _Part('M16.5 13v7l4.5-3.5z', fill: true, strokeWidth: 1.2),
  ]),
  // circle 5.5/12/18.5, r 1.7
  more([
    _Part(
      'M3.8 12a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0'
      'M10.3 12a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0'
      'M16.8 12a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0',
      fill: true,
      stroke: false,
    ),
  ]),
  drag([_Part('M5 8.5h14M5 12h14M5 15.5h14')]),
  history([
    _Part('M4.5 12a7.5 7.5 0 1 0 2.2-5.3'),
    _Part('M4.2 4.5v4.6h4.6'),
    _Part('M12 8v4.2l2.8 1.6'),
  ]),
  chevD([_Part('m5 9 7 7 7-7')]),
  shuffle([
    _Part('M3 7h3.2c2 0 3.2 1 4.3 2.6l2.6 4C14.2 15.2 15.5 16.5 17.6 16.5H21'),
    _Part('M3 16.5h3.2c1.5 0 2.5-.6 3.4-1.6M14 8.7c.9-1 2-1.7 3.6-1.7H21'),
    _Part('M18.6 4.6 21 7l-2.4 2.4M18.6 14.1 21 16.5l-2.4 2.4'),
  ]),
  repeat([
    _Part('M4 11.5V9.8A3.3 3.3 0 0 1 7.3 6.5H19.5'),
    _Part('M17 4 19.5 6.5 17 9'),
    _Part('M20 12.5v1.7a3.3 3.3 0 0 1-3.3 3.3H4.5'),
    _Part('M7 20 4.5 17.5 7 15'),
  ]),
  repeat1([
    _Part('M4 11.5V9.8A3.3 3.3 0 0 1 7.3 6.5H19.5'),
    _Part('M17 4 19.5 6.5 17 9'),
    _Part('M20 12.5v1.7a3.3 3.3 0 0 1-3.3 3.3H4.5'),
    _Part('M7 20 4.5 17.5 7 15'),
    _Part('M11.2 10.6 12.6 9.8v4.6', strokeWidth: 1.6),
  ]),
  trash([
    _Part('M4.5 7h15M9.5 7V5.2c0-.7.5-1.2 1.2-1.2h2.6c.7 0 1.2.5 1.2 1.2V7'),
    _Part(
      'm6.5 7 1 12.2c.1.8.7 1.3 1.5 1.3h6c.8 0 1.4-.5 1.5-1.3l1-12.2M10 11v6M14 11v6',
    ),
  ]);

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
  const _Part(
    this.d, {
    this.fill = false,
    this.stroke = true,
    this.strokeWidth,
  });

  final String d;
  final bool fill;

  /// 稿上 `stroke="none"` 的實心形狀不描邊。
  final bool stroke;
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
      _cache[icon] ??= [for (final part in icon._all) svgPath(part.d)];

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
      if (part.stroke) canvas.drawPath(paths[i], stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}

/// SVG 路徑字串 [d] 轉成 [Path]；圖示與插件宣告的音源標識都用它。
Path svgPath(String d) {
  final proxy = _PathProxy();
  writeSvgPathDataToPath(d, proxy);
  return proxy.path;
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
