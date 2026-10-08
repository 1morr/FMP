import 'dart:convert';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/redaction/redaction_lists.dart';
import 'package:fmp/plugins/json_shape.dart';

/// 宿主支援的插件 API 版本（ADR 0014 §決定 5）。manifest 的 `apiVersion` 必須
/// 等於它；宿主 API 或 DTO 有不相容的改動時加一。
const hostApiVersion = 1;

/// 插件能力（ADR 0014 §決定 4）。
///
/// 每個能力對應腳本裡一個同名的匯出函式（[wireName]）：manifest 宣告的能力都要
/// 匯出，匯出了能力名稱的函式也都要宣告，否則拒絕載入。M1 只有 [search] 與
/// [resolveStream] 有宿主端的方法（`SourcePlugin`），其他能力認得、檢查匯出，
/// 但還沒有人呼叫。
enum PluginCapability {
  search,
  resolveStream,
  trackDetail,
  multiPart,
  importPlaylist,
  libraryRead,
  libraryWrite,
  charts,
  live,
  mix,
  lyrics,
  login;

  /// manifest 與匯出函式用的名稱。這是插件的介面，與 [name] 分開寫死，改
  /// enum 的名稱不會改到它。
  String get wireName => switch (this) {
    search => 'search',
    resolveStream => 'resolveStream',
    trackDetail => 'trackDetail',
    multiPart => 'multiPart',
    importPlaylist => 'importPlaylist',
    libraryRead => 'libraryRead',
    libraryWrite => 'libraryWrite',
    charts => 'charts',
    live => 'live',
    mix => 'mix',
    lyrics => 'lyrics',
    login => 'login',
  };

  /// 不認得的名稱回 `null`。
  static PluginCapability? fromWireName(String name) {
    for (final capability in values) {
      if (capability.wireName == name) return capability;
    }
    return null;
  }
}

/// manifest 追加的遮蔽名單（交給 `Redactor.addRules`、`Redactor.setMediaCdns`，
/// ADR 0011 §決定 3）。
final class PluginRedaction {
  const PluginRedaction({
    this.headerNames = const [],
    this.keyNames = const [],
    this.mediaCdns = const [],
  });

  final List<String> headerNames;
  final List<String> keyNames;
  final List<MediaCdn> mediaCdns;
}

/// 插件的 manifest（ADR 0014 §決定 3）。由 [PluginManifest.parse] 從安裝檔的
/// 標頭讀出；欄位與格式見 `lib/plugins/types/fmp-plugin.d.ts` 的
/// `FmpPluginManifest`。
final class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.capabilities,
    required this.allowedHosts,
    this.retryPolicy,
    this.rateLimitPolicy,
    this.redaction = const PluginRedaction(),
    this.defaults = const {},
    this.icon,
    this.description = '',
  });

  /// 解析 manifest 的 JSON 文字。
  ///
  /// - 不是 JSON、欄位缺少或型別不對、格式不合：[ParseError]；
  /// - `apiVersion` 不是 [hostApiVersion]、有不認得的能力、`login` 不是空值（M1
  ///   還沒有登入）：[Unsupported]。
  ///
  /// 原因只在 `cause`（進 log）；使用者訊息用子類的預設 key。
  static PluginManifest parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error, stackTrace) {
      throw ParseError(cause: error, stackTrace: stackTrace);
    }
    // 先看版本：別的版本的欄位本來就可能不同，不拿 v1 的形狀去判它。
    if (decoded case {'apiVersion': final int version}
        when version != hostApiVersion) {
      throw Unsupported(
        pluginId: _idOrNull(decoded),
        cause: FormatException(
          'apiVersion $version is not supported (host supports '
          '$hostApiVersion)',
        ),
        stackTrace: StackTrace.current,
      );
    }
    try {
      return _fromJson(decoded);
    } on _UnsupportedManifest catch (error, stackTrace) {
      throw Unsupported(
        pluginId: _idOrNull(decoded),
        cause: FormatException(error.message),
        stackTrace: stackTrace,
      );
    } on FormatException catch (error, stackTrace) {
      throw ParseError(
        pluginId: _idOrNull(decoded),
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 音源 id：小寫英數與 `-`，見 [isValidId]。
  final String id;
  final String name;
  final String version;
  final String author;
  final Set<PluginCapability> capabilities;

  /// 可以連的網域（ADR 0014 §決定 5）：只有 host，小寫。網路請求、串流與封面
  /// 網址、圖示網址都只能在這些網域或它們的子網域。
  final List<String> allowedHosts;

  /// 沒宣告就是 `null`（用 `const RetryPolicy()`）。
  final RetryPolicy? retryPolicy;

  /// 沒宣告就是 `null`（不限流）。
  final RateLimitPolicy? rateLimitPolicy;
  final PluginRedaction redaction;

  /// 插件設定的預設值；M1 只保存，還沒有設定頁讀它。
  final Map<String, Object?> defaults;

  /// `https` 網址（網域在 [allowedHosts] 內）或 `data:image/…;base64,` 網址。
  final Uri? icon;

  /// 一句描述（插件頁與 index 顯示）；沒寫就是空字串，最多 [maxDescriptionLength] 字元。
  final String description;

  /// id 的格式：1–[maxIdLength] 個小寫英數與 `-`，不以 `-` 開頭或結尾。它是
  /// 曲目鍵的第一段（`TrackKey`），所以不能有 `:`。
  static bool isValidId(String id) => _idPattern.hasMatch(id);

  static const maxIdLength = 32;

  static const maxDescriptionLength = 200;
}

final _idPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$');

/// 一段 DNS label；host 至少兩段，最後一段不是純數字（排除 IPv4）。
final _hostLabel = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
final _digits = RegExp(r'^[0-9]+$');

/// 圖示的 data 網址：只接受這幾種圖片、base64 編碼。
final _dataIcon = RegExp(
  r'^data:image/(?:png|jpeg|webp|gif|svg\+xml);base64,([A-Za-z0-9+/=]+)$',
);

/// data 圖示解碼後的上限。
const _maxIconBytes = 64 * 1024;

/// 重試次數的上限：插件不能把一個失敗放大成大量請求。
const _maxRetries = 5;

const manifestShape = <String, bool>{
  'id': true,
  'name': true,
  'version': true,
  'author': true,
  'apiVersion': true,
  'capabilities': true,
  'allowedHosts': true,
  'login': false,
  'retry': false,
  'rateLimit': false,
  'redaction': false,
  'defaults': false,
  'icon': false,
  'description': false,
};
const retryShape = <String, bool>{
  'maxRetries': false,
  'baseDelayMs': false,
  'maxDelayMs': false,
  'maxRetryAfterMs': false,
};
const rateLimitShape = <String, bool>{
  'maxConcurrentRequests': true,
  'minRequestIntervalMs': true,
};
const redactionShape = <String, bool>{
  'headerNames': false,
  'keyNames': false,
  'mediaCdns': false,
};
const mediaCdnShape = <String, bool>{
  'host': true,
  'signedQueryParameters': false,
  'signedPath': false,
};

/// manifest 的欄位表，鍵是 `fmp-plugin.d.ts` 裡的 interface 名稱。
const manifestShapes = <String, JsonShape>{
  'FmpPluginManifest': manifestShape,
  'FmpRetryPolicy': retryShape,
  'FmpRateLimitPolicy': rateLimitShape,
  'FmpRedaction': redactionShape,
  'FmpMediaCdn': mediaCdnShape,
};

/// 格式合法但這個版本不支援（轉成 [Unsupported]）。
final class _UnsupportedManifest implements Exception {
  const _UnsupportedManifest(this.message);

  final String message;
}

String? _idOrNull(Object? json) => switch (json) {
  {'id': final String id} when PluginManifest.isValidId(id) => id,
  _ => null,
};

PluginManifest _fromJson(Object? json) {
  final fields = JsonFields(json, manifestShape, path: 'manifest');
  final id = fields.string('id');
  if (!PluginManifest.isValidId(id)) {
    throw FormatException(
      'manifest.id: "$id" must be 1-${PluginManifest.maxIdLength} lowercase '
      'letters, digits or "-", not starting or ending with "-"',
    );
  }
  // 版本在 parse 開頭已經比對過；這裡只確認它是整數。
  fields.integer('apiVersion');
  if (fields.raw('login') != null) {
    throw const _UnsupportedManifest('manifest.login: login is not supported');
  }
  final allowedHosts = [
    for (final (index, host) in fields.stringList('allowedHosts').indexed)
      _host(host, 'manifest.allowedHosts[$index]'),
  ];
  return PluginManifest(
    id: id,
    name: fields.nonEmptyString('name'),
    version: fields.nonEmptyString('version'),
    author: fields.nonEmptyString('author'),
    capabilities: _capabilities(fields.stringList('capabilities')),
    allowedHosts: List.unmodifiable(allowedHosts),
    retryPolicy: _retry(fields.optionalObject('retry')),
    rateLimitPolicy: _rateLimit(fields.optionalObject('rateLimit')),
    redaction: _redaction(fields.optionalObject('redaction')),
    defaults: Map.unmodifiable(fields.optionalObject('defaults') ?? const {}),
    icon: _icon(fields.optionalString('icon'), allowedHosts),
    description: _description(fields.optionalString('description')),
  );
}

String _description(String? value) {
  if (value == null) return '';
  if (value.runes.length > PluginManifest.maxDescriptionLength) {
    throw const FormatException(
      'manifest.description: must be at most '
      '${PluginManifest.maxDescriptionLength} characters',
    );
  }
  return value;
}

Set<PluginCapability> _capabilities(List<String> names) {
  if (names.isEmpty) {
    throw const FormatException('manifest.capabilities: must not be empty');
  }
  final capabilities = <PluginCapability>{};
  for (final name in names) {
    final capability = PluginCapability.fromWireName(name);
    if (capability == null) {
      throw _UnsupportedManifest('manifest.capabilities: unknown "$name"');
    }
    if (!capabilities.add(capability)) {
      throw FormatException('manifest.capabilities: "$name" is listed twice');
    }
  }
  return Set.unmodifiable(capabilities);
}

/// 只接受小寫的 host：沒有 scheme、port、路徑、萬用字元。
String _host(String host, String path) {
  final labels = host.split('.');
  final valid =
      host.length <= 253 &&
      labels.length >= 2 &&
      labels.every(_hostLabel.hasMatch) &&
      !_digits.hasMatch(labels.last);
  if (!valid) {
    throw FormatException(
      '$path: "$host" is not a lowercase host name (no scheme, port, path or '
      'wildcard)',
    );
  }
  return host;
}

RetryPolicy? _retry(Map<String, Object?>? json) {
  if (json == null) return null;
  final fields = JsonFields(json, retryShape, path: 'manifest.retry');
  const defaults = RetryPolicy();
  final maxRetries = fields.optionalInteger('maxRetries');
  if (maxRetries != null && maxRetries > _maxRetries) {
    throw const FormatException(
      'manifest.retry.maxRetries: must be at most $_maxRetries',
    );
  }
  Duration? millis(String key) => switch (fields.optionalInteger(key)) {
    null => null,
    final value => Duration(milliseconds: value),
  };
  return RetryPolicy(
    maxRetries: maxRetries ?? defaults.maxRetries,
    baseDelay: millis('baseDelayMs') ?? defaults.baseDelay,
    maxDelay: millis('maxDelayMs') ?? defaults.maxDelay,
    maxRetryAfter: millis('maxRetryAfterMs') ?? defaults.maxRetryAfter,
  );
}

RateLimitPolicy? _rateLimit(Map<String, Object?>? json) {
  if (json == null) return null;
  final fields = JsonFields(json, rateLimitShape, path: 'manifest.rateLimit');
  return RateLimitPolicy(
    maxConcurrentRequests: fields.integer('maxConcurrentRequests', min: 1),
    minRequestInterval: Duration(
      milliseconds: fields.integer('minRequestIntervalMs'),
    ),
  );
}

PluginRedaction _redaction(Map<String, Object?>? json) {
  if (json == null) return const PluginRedaction();
  final fields = JsonFields(json, redactionShape, path: 'manifest.redaction');
  return PluginRedaction(
    headerNames: List.unmodifiable(
      fields.optionalStringList('headerNames') ?? const <String>[],
    ),
    keyNames: List.unmodifiable(
      fields.optionalStringList('keyNames') ?? const <String>[],
    ),
    mediaCdns: List.unmodifiable([
      for (final (index, item)
          in (fields.optionalList('mediaCdns') ?? []).indexed)
        _mediaCdn(item, 'manifest.redaction.mediaCdns[$index]'),
    ]),
  );
}

MediaCdn _mediaCdn(Object? json, String path) {
  final fields = JsonFields(json, mediaCdnShape, path: path);
  return MediaCdn(
    host: _host(fields.string('host'), '$path.host'),
    signedQueryParameters: {
      ...?fields.optionalStringList('signedQueryParameters'),
    },
    signedPath: fields.optionalBool('signedPath') ?? false,
  );
}

Uri? _icon(String? value, List<String> allowedHosts) {
  if (value == null) return null;
  if (_dataIcon.firstMatch(value) case final match?) {
    final List<int> bytes;
    try {
      bytes = base64.decode(match[1]!);
    } on FormatException {
      throw const FormatException('manifest.icon: invalid base64');
    }
    if (bytes.length > _maxIconBytes) {
      throw const FormatException(
        'manifest.icon: data icon is larger than $_maxIconBytes bytes',
      );
    }
    return Uri.parse(value);
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !AllowedHosts(allowedHosts).allows(uri)) {
    throw const FormatException(
      'manifest.icon: must be an https URL on an allowed host, or a '
      'data:image/...;base64, URL',
    );
  }
  return uri;
}
