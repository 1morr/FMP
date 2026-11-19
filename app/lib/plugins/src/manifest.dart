import 'dart:convert';

import 'package:path_parsing/path_parsing.dart';

/// 插件能力（`GLOSSARY.md`）：插件在 manifest 宣告做得到的事。新增能力時在
/// 這裡加一個值，值的名稱就是 manifest 裡的字串，也是插件匯出的函式名；
/// 宿主不認得的字串略過，舊版宿主讀得了新版插件的 manifest。
enum PluginCapability { search, resolveStream, listParts, trackInfo, charts }

/// 搜尋的排序（ADR 0039）：值的名稱就是 manifest 與插件參數裡的字串，名字照
/// YouTube Data API search.list 的 `order`。宿主不認得的字串略過。
enum SearchSort {
  /// 綜合排序。
  relevance,

  /// 最多播放。
  viewCount,

  /// 最新發布。
  date,
}

/// 插件的 manifest（`app/plugins/<id>/manifest.json`）。
///
/// 格式參考 Spotube 的 `plugin.json`（能力與權限分開宣告，ADR 0038）與
/// Chrome 擴充的 `host_permissions`（網域可用 `*.` 開頭涵蓋子網域）：
///
/// ```json
/// {
///   "id": "example",
///   "name": "Example",
///   "version": "1.0.0",
///   "capabilities": ["search"],
///   "searchSorts": ["relevance", "viewCount", "date"],
///   "chartTitle": {"en": "Music chart", "zh-TW": "音樂區排行榜"},
///   "domains": ["api.example.com", "*.cdn.example.com"],
///   "mark": {
///     "short": "Ex",
///     "color": "#FB7299",
///     "paths": [{"pathData": "M1 1h14v14H1z", "fillColor": "#FB7299"}]
///   }
/// }
/// ```
///
/// `mark` 是選填的音源標識（[SourceMark]，ADR 0039）。`searchSorts` 也是選填：
/// 插件支援的搜尋排序，第一個是它的預設，沒宣告就不能排序。`chartTitle` 是
/// 排行榜的榜名，宣告 `charts` 時必填（[chartTitle]）。
class PluginManifest {
  PluginManifest._({
    required this.id,
    required this.name,
    required this.version,
    required this.capabilities,
    required this.domains,
    required this.mark,
    required this.searchSorts,
    required this.chartTitles,
  });

  /// 解析 manifest；缺欄位、型別不對或格式不合時丟 [FormatException]。
  factory PluginManifest.parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('manifest must be a JSON object');
    }
    T field<T>(String name) {
      final value = json[name];
      if (value is! T) throw FormatException('manifest "$name" is missing');
      return value;
    }

    List<String> strings(String name) {
      final list = field<List<dynamic>>(name);
      if (list.any((e) => e is! String)) {
        throw FormatException('manifest "$name" must list strings');
      }
      return list.cast<String>();
    }

    final id = field<String>('id');
    if (!_id.hasMatch(id)) throw FormatException('bad plugin id "$id"');
    final domains = strings('domains').map((d) => d.toLowerCase()).toList();
    for (final domain in domains) {
      if (!_domain.hasMatch(domain)) {
        throw FormatException('bad domain "$domain"');
      }
    }
    final declared = strings('capabilities').toSet();
    // 依宣告的順序、去重、略過不認得的字串。
    final searchSorts = <SearchSort>{
      if (json.containsKey('searchSorts'))
        for (final name in strings('searchSorts'))
          for (final sort in SearchSort.values)
            if (sort.name == name) sort,
    };
    final capabilities = {
      for (final c in PluginCapability.values)
        if (declared.contains(c.name)) c,
    };
    return PluginManifest._(
      id: id,
      name: field<String>('name'),
      version: field<String>('version'),
      capabilities: capabilities,
      chartTitles: capabilities.contains(PluginCapability.charts)
          ? _parseChartTitles(json['chartTitle'])
          : const {},
      domains: List.unmodifiable(domains),
      searchSorts: List.unmodifiable(searchSorts),
      mark: switch (json['mark']) {
        null => null,
        final Map<String, dynamic> mark => SourceMark._parse(mark),
        _ => throw const FormatException('manifest "mark" must be an object'),
      },
    );
  }

  /// 小寫英數、`_`、`-`；也是曲目的 `TrackRef.pluginId`。
  final String id;
  final String name;
  final String version;
  final Set<PluginCapability> capabilities;

  /// 插件可以連的主機。`*.example.com` 涵蓋 `example.com` 的子網域，不含
  /// `example.com` 本身。
  final List<String> domains;

  /// 插件支援的搜尋排序，第一個是它的預設；沒宣告是空的，就不能排序。
  final List<SearchSort> searchSorts;

  /// 音源標識；插件沒宣告時是 null，畫面就不畫。
  final SourceMark? mark;

  /// 排行榜的榜名，語言標籤（BCP 47，例如 `zh-TW`）對榜名；沒宣告 `charts`
  /// 時是空的。畫面用 [chartTitle] 挑。
  final Map<String, String> chartTitles;

  /// 排行榜的榜名，照 [languageTag] 挑，沒有這個語言就用 `en`（照 Chrome
  /// 擴充的 `default_locale` 退回，ADR 0039）。沒宣告 `charts` 時是 null。
  String? chartTitle(String languageTag) =>
      chartTitles[languageTag] ?? chartTitles['en'];

  /// [host] 是否在 [domains] 裡（不分大小寫）。
  bool allowsHost(String host) {
    final h = host.toLowerCase();
    return domains.any(
      (d) => d.startsWith('*.') ? h.endsWith(d.substring(1)) : h == d,
    );
  }
}

final _id = RegExp(r'^[a-z0-9_-]+$');

/// `chartTitle`：語言標籤對不是空的榜名，要有 `en`。
Map<String, String> _parseChartTitles(Object? json) {
  if (json is! Map<String, dynamic>) {
    throw const FormatException('manifest "chartTitle" must be an object');
  }
  final titles = <String, String>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('manifest "chartTitle" for "$key" must be text');
    }
    titles[key] = value;
  }
  if (!titles.containsKey('en')) {
    throw const FormatException('manifest "chartTitle" needs an "en" title');
  }
  return Map.unmodifiable(titles);
}

/// 主機名稱，或 `*.` 加主機名稱；萬用字元只能在開頭，不帶連接埠。
final _domain = RegExp(r'^(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)+$');

/// 音源標識（`docs/design/DESIGN.md`〈音源標識〉）：插件在 manifest 宣告，宿主只負責
/// 畫，Dart 端沒有音源分支。符號是 16×16 畫布上的一串路徑，欄位名照 Android
/// VectorDrawable（`pathData`、`fillColor`、`strokeColor`、`strokeWidth`），
/// 線頭與轉角一律圓角；顏色是 `#RRGGBB`，存成不透明的 ARGB 整數。
class SourceMark {
  SourceMark._({required this.short, required this.color, required this.paths});

  factory SourceMark._parse(Map<String, dynamic> json) {
    final short = json['short'];
    if (short is! String || short.isEmpty) {
      throw const FormatException('mark "short" is missing');
    }
    final paths = json['paths'];
    if (paths is! List || paths.isEmpty) {
      throw const FormatException('mark "paths" must list at least one path');
    }
    return SourceMark._(
      short: short,
      color: _color(json['color'], 'color')!,
      paths: List.unmodifiable([
        for (final path in paths)
          if (path is Map<String, dynamic>)
            MarkPath._parse(path)
          else
            throw const FormatException('mark path must be an object'),
      ]),
    );
  }

  /// 簡稱，例如「B站」；全名是 manifest 的 `name`。
  final String short;

  /// 音源色（ARGB）。
  final int color;

  /// 由下往上畫。
  final List<MarkPath> paths;
}

/// [SourceMark] 的一條路徑：填色、描邊，或兩者都有。
class MarkPath {
  MarkPath._({
    required this.pathData,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  });

  factory MarkPath._parse(Map<String, dynamic> json) {
    final pathData = json['pathData'];
    if (pathData is! String) {
      throw const FormatException('mark path "pathData" is missing');
    }
    try {
      writeSvgPathDataToPath(pathData, _NoPath());
    } on StateError catch (e) {
      throw FormatException('bad mark "pathData": ${e.message}');
    }
    final fill = _color(json['fillColor'], 'fillColor', optional: true);
    final stroke = _color(json['strokeColor'], 'strokeColor', optional: true);
    if (fill == null && stroke == null) {
      throw const FormatException('mark path needs a fill or a stroke');
    }
    final width = json['strokeWidth'];
    if (stroke != null && (width is! num || width <= 0)) {
      throw const FormatException('mark stroke needs a positive "strokeWidth"');
    }
    return MarkPath._(
      pathData: pathData,
      fillColor: fill,
      strokeColor: stroke,
      strokeWidth: stroke == null ? 0 : (width as num).toDouble(),
    );
  }

  /// SVG 路徑字串，座標在 16×16 的畫布上。
  final String pathData;

  /// 填色（ARGB）；不填是 null。
  final int? fillColor;

  /// 描邊色（ARGB）；不描邊是 null。
  final int? strokeColor;

  /// 描邊寬度；不描邊是 0。
  final double strokeWidth;
}

int? _color(Object? value, String name, {bool optional = false}) {
  if (value == null && optional) return null;
  if (value is! String || !_hexColor.hasMatch(value)) {
    throw FormatException('mark "$name" must be #RRGGBB');
  }
  return 0xFF000000 | int.parse(value.substring(1), radix: 16);
}

final _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

/// 只用來檢查路徑字串解析得了。
class _NoPath extends PathProxy {
  @override
  void moveTo(double x, double y) {}

  @override
  void lineTo(double x, double y) {}

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {}

  @override
  void close() {}
}
