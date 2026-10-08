import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/json_shape.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';

/// 宿主讀得懂的 `index.json` 版本（ADR 0030 §決定 1）。
const supportedIndexVersion = 1;

/// 為什麼拒絕一個 index 或安裝檔。UI 依它顯示 ADR 0030 規定的提示。
enum PluginRejection {
  /// 下載到的檔案與 index 的 SHA-256 不符：插件庫剛更新，請稍後再試。
  hashMismatch,

  /// 下載到的 `.js` 標頭 manifest 與 index 那一筆的 id、版本、能力或網域不同。
  manifestMismatch,

  /// `indexVersion` 或插件的 `apiVersion` 宿主不支援：需要更新 FMP。
  appUpdateRequired,
}

/// 插件庫流程裡「預期內」的拒絕：資料有問題或太新，不是 bug。其他失敗
/// （網路、解析、載入）仍是 [AppError]。
final class PluginRejected implements Exception {
  const PluginRejected(this.reason, {this.pluginId});

  final PluginRejection reason;

  /// 被拒的插件 id；index 本身被拒時為 `null`。
  final String? pluginId;

  @override
  String toString() =>
      'PluginRejected(${reason.name}${pluginId == null ? '' : ', $pluginId'})';
}

const indexShape = <String, bool>{'indexVersion': true, 'plugins': true};

const indexEntryShape = <String, bool>{
  'id': true,
  'name': true,
  'author': true,
  'description': true,
  'version': true,
  'apiVersion': true,
  'capabilities': true,
  'allowedHosts': true,
  'url': true,
  'sha256': true,
  'checksUrl': false,
  'checksSha256': false,
};

final _sha256 = RegExp(r'^[0-9a-f]{64}$');

/// index 裡的一個插件（ADR 0030 §決定 1）。
final class PluginIndexEntry {
  const PluginIndexEntry({
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.version,
    required this.apiVersion,
    required this.capabilities,
    required this.allowedHosts,
    required this.url,
    required this.sha256,
    this.checksUrl,
    this.checksSha256,
  });

  factory PluginIndexEntry.fromJson(Object? json, {required String path}) {
    final fields = JsonFields(json, indexEntryShape, path: path);
    final id = fields.string('id');
    if (!PluginManifest.isValidId(id)) {
      throw FormatException('$path.id: "$id" is not a valid plugin id');
    }
    final version = fields.nonEmptyString('version');
    try {
      Version.parse(version);
    } on FormatException {
      throw FormatException('$path.version: "$version" is not a semver');
    }
    final capabilities = <PluginCapability>{};
    for (final name in fields.stringList('capabilities')) {
      final capability = PluginCapability.fromWireName(name);
      if (capability == null || !capabilities.add(capability)) {
        throw FormatException('$path.capabilities: bad "$name"');
      }
    }
    final sha = fields.string('sha256');
    if (!_sha256.hasMatch(sha)) {
      throw FormatException('$path.sha256: expected 64 lowercase hex digits');
    }
    final checksUrl = fields.optionalString('checksUrl');
    final checksSha = fields.optionalString('checksSha256');
    if ((checksUrl == null) != (checksSha == null)) {
      throw FormatException('$path: checksUrl and checksSha256 come together');
    }
    if (checksSha != null && !_sha256.hasMatch(checksSha)) {
      throw FormatException(
        '$path.checksSha256: expected 64 lowercase hex digits',
      );
    }
    return PluginIndexEntry(
      id: id,
      name: fields.nonEmptyString('name'),
      author: fields.nonEmptyString('author'),
      description: fields.string('description'),
      version: version,
      apiVersion: fields.integer('apiVersion'),
      capabilities: Set.unmodifiable(capabilities),
      allowedHosts: List.unmodifiable(fields.stringList('allowedHosts')),
      url: _url(fields.string('url'), '$path.url'),
      sha256: sha,
      checksUrl: checksUrl == null ? null : _url(checksUrl, '$path.checksUrl'),
      checksSha256: checksSha,
    );
  }

  final String id;
  final String name;
  final String author;
  final String description;
  final String version;
  final int apiVersion;
  final Set<PluginCapability> capabilities;
  final List<String> allowedHosts;

  /// `.js` 安裝檔的網址與它的 SHA-256（小寫十六進位）。
  final Uri url;
  final String sha256;

  /// `checks.json` 的網址與 SHA-256；兩者同時有或同時沒有。
  final Uri? checksUrl;
  final String? checksSha256;

  /// 宿主 API 版本相容。
  bool get isCompatible => apiVersion == hostApiVersion;

  static Uri _url(String text, String path) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw FormatException('$path: expected an https URL');
    }
    return uri;
  }
}

/// 一份 index（ADR 0030 §決定 1）。
final class PluginIndex {
  const PluginIndex(this.plugins);

  /// 解析 index 原文。欄位封閉：不認得的欄位整個拒收（[ParseError]）；
  /// `indexVersion` 不是 [supportedIndexVersion] 是 [PluginRejected]
  /// （[PluginRejection.appUpdateRequired]），不去讀其餘欄位。
  factory PluginIndex.parse(String text) {
    try {
      final json = jsonDecode(text);
      final version = json is Map<String, Object?>
          ? json['indexVersion']
          : null;
      if (version is int && version != supportedIndexVersion) {
        throw const PluginRejected(PluginRejection.appUpdateRequired);
      }
      final fields = JsonFields(json, indexShape, path: 'index');
      final entries = [
        for (final (i, item) in fields.list('plugins').indexed)
          PluginIndexEntry.fromJson(item, path: 'index.plugins[$i]'),
      ];
      if (fields.integer('indexVersion') != supportedIndexVersion) {
        throw const PluginRejected(PluginRejection.appUpdateRequired);
      }
      final ids = <String>{};
      for (final entry in entries) {
        if (!ids.add(entry.id)) {
          throw FormatException('index: "${entry.id}" is listed twice');
        }
      }
      return PluginIndex(List.unmodifiable(entries));
    } on FormatException catch (error, stackTrace) {
      throw ParseError(cause: error, stackTrace: stackTrace);
    }
  }

  final List<PluginIndexEntry> plugins;
}
