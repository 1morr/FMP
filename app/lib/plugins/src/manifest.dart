import 'dart:convert';

/// 插件能力（`GLOSSARY.md`）：插件在 manifest 宣告做得到的事。新增能力時在
/// 這裡加一個值，[wireName] 是 manifest 裡的字串；宿主不認得的字串略過，
/// 舊版宿主讀得了新版插件的 manifest。
enum PluginCapability {
  search('search');

  const PluginCapability(this.wireName);

  final String wireName;
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
///   "domains": ["api.example.com", "*.cdn.example.com"]
/// }
/// ```
class PluginManifest {
  PluginManifest._({
    required this.id,
    required this.name,
    required this.version,
    required this.capabilities,
    required this.domains,
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
    return PluginManifest._(
      id: id,
      name: field<String>('name'),
      version: field<String>('version'),
      capabilities: {
        for (final c in PluginCapability.values)
          if (declared.contains(c.wireName)) c,
      },
      domains: List.unmodifiable(domains),
    );
  }

  /// 小寫英數、`_`、`-`；也是曲目的 `Track.source`。
  final String id;
  final String name;
  final String version;
  final Set<PluginCapability> capabilities;

  /// 插件可以連的主機。`*.example.com` 涵蓋 `example.com` 的子網域，不含
  /// `example.com` 本身。
  final List<String> domains;

  /// [host] 是否在 [domains] 裡（不分大小寫）。
  bool allowsHost(String host) {
    final h = host.toLowerCase();
    return domains.any(
      (d) => d.startsWith('*.') ? h.endsWith(d.substring(1)) : h == d,
    );
  }
}

final _id = RegExp(r'^[a-z0-9_-]+$');

/// 主機名稱，或 `*.` 加主機名稱；萬用字元只能在開頭，不帶連接埠。
final _domain = RegExp(r'^(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)+$');
