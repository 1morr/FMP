import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/runtime/plugin_host.dart';
import 'package:fmp/plugins/runtime/plugin_runtime.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 由 JS 腳本實作的 [SourcePlugin]：DTO 轉成 JSON 交給 [PluginRuntime]，回傳值
/// 驗證後轉回 DTO，形狀不對是 [ParseError]。
final class ScriptSourcePlugin implements SourcePlugin {
  ScriptSourcePlugin._(this.manifest, this._runtime)
    : _allowedHosts = AllowedHosts(manifest.allowedHosts);

  @override
  final PluginManifest manifest;
  final PluginRuntime _runtime;
  final AllowedHosts _allowedHosts;

  @override
  PluginHealth get health => _runtime.health;

  @override
  Future<void> get whenUnresponsive => _runtime.whenUnresponsive;

  @override
  Future<SearchPage> search(SearchQuery query) async {
    final json = await _invoke(PluginCapability.search, query.toJson());
    return _decode(
      () => SearchPage.fromJson(
        json,
        sourceTypeId: manifest.id,
        allowedHosts: _allowedHosts,
      ),
    );
  }

  @override
  Future<StreamResult> resolveStream(StreamRequest request) async {
    final json = await _invoke(
      PluginCapability.resolveStream,
      request.toJson(),
    );
    return _decode(
      () => StreamResult.fromJson(json, allowedHosts: _allowedHosts),
    );
  }

  @override
  void close() => _runtime.dispose();

  Future<Object?> _invoke(PluginCapability capability, Object? argument) {
    if (!manifest.capabilities.contains(capability)) {
      throw Unsupported(
        pluginId: manifest.id,
        cause: StateError('${capability.wireName} is not declared'),
        stackTrace: StackTrace.current,
      );
    }
    return _runtime.invoke(capability.wireName, argument);
  }

  T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on FormatException catch (error, stackTrace) {
      throw ParseError(
        pluginId: manifest.id,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// 把安裝檔變成可用的 [ScriptSourcePlugin]：建網路 client 與宿主 API、在
/// runtime 載入腳本、檢查匯出與能力一致。
///
/// App 共用的東西（log、遮蔽函式、HTTP client 工廠、storage）在這裡給一次。
final class ScriptPluginLoader {
  ScriptPluginLoader({
    required this._log,
    required this._redactor,
    required this._httpClients,
    required this._storage,
    required this._credentials,
    this._callTimeout = defaultPluginCallTimeout,
    this._livenessGrace = defaultLivenessGrace,
  });

  final Log _log;
  final Redactor _redactor;
  final SourceHttpClientFactory _httpClients;
  final PluginStorageRepository _storage;
  final CredentialStore _credentials;
  final Duration _callTimeout;
  final Duration _livenessGrace;

  /// 載入 [file]。
  ///
  /// manifest 宣告的能力沒有同名的匯出函式，或匯出了能力名稱的函式卻沒宣告：
  /// [Unsupported]（ADR 0014 §如何確認）。腳本本身的錯誤見
  /// [PluginRuntime.start]。
  Future<ScriptSourcePlugin> load(PluginFile file) async {
    final manifest = file.manifest;
    // header 與鍵名只增不減：插件更新或載入失敗都不收回（多遮的代價小於漏遮）。
    // 媒體 CDN 以插件 id 為鍵取代，更新時不累加。
    _redactor
      ..addRules(
        headerNames: manifest.redaction.headerNames,
        keyNames: manifest.redaction.keyNames,
      )
      ..setMediaCdns(manifest.id, manifest.redaction.mediaCdns);
    final host = PluginHost(
      pluginId: manifest.id,
      http: _httpClients.create(
        pluginId: manifest.id,
        allowedHosts: manifest.allowedHosts,
        retryPolicy: manifest.retryPolicy ?? const RetryPolicy(),
        rateLimitPolicy: manifest.rateLimitPolicy,
      ),
      storage: _storage,
      log: _log,
      credentials: _credentials,
      redactor: _redactor,
    );
    final PluginRuntime runtime;
    try {
      runtime = await PluginRuntime.start(
        pluginId: manifest.id,
        script: file.source,
        host: host,
        log: _log,
        callTimeout: _callTimeout,
        livenessGrace: _livenessGrace,
      );
    } on Object {
      host.close();
      rethrow;
    }
    final mismatch = _exportMismatch(manifest.capabilities, runtime.exports);
    if (mismatch != null) {
      runtime.dispose();
      throw Unsupported(
        pluginId: manifest.id,
        cause: StateError(mismatch),
        stackTrace: StackTrace.current,
      );
    }
    return ScriptSourcePlugin._(manifest, runtime);
  }

  static String? _exportMismatch(
    Set<PluginCapability> declared,
    Set<String> exports,
  ) {
    final missing = [
      for (final capability in declared)
        if (!exports.contains(capability.wireName)) capability.wireName,
    ];
    final undeclared = [
      for (final name in exports)
        if (PluginCapability.fromWireName(name) case final capability?
            when !declared.contains(capability))
          name,
    ];
    if (missing.isEmpty && undeclared.isEmpty) return null;
    return [
      if (missing.isNotEmpty)
        'declared but not exported: ${missing.join(', ')}',
      if (undeclared.isNotEmpty)
        'exported but not declared: ${undeclared.join(', ')}',
    ].join('; ');
  }
}
