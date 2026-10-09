import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/runtime/plugin_host.dart';
import 'package:fmp/plugins/runtime/plugin_runtime.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 由 JS 腳本實作的 [SourcePlugin]：DTO 轉成 JSON 交給 [PluginRuntime]，回傳值
/// 驗證後轉回 DTO，形狀不對是 [ParseError]。
///
/// `login*` 匯出執行期間，這個插件的 API client 不把回應的 `Set-Cookie` 存進 cookie
/// jar（ADR 0029 §決定 2）：登入回應設的 cookie 是憑證，只經 `CredentialStore` 與
/// 注入送出。插件照樣讀得到回應的 header。
final class ScriptSourcePlugin implements SourcePlugin {
  ScriptSourcePlugin._(this.manifest, this._runtime, this._http, this._redactor)
    : _allowedHosts = AllowedHosts(manifest.allowedHosts);

  @override
  final PluginManifest manifest;
  final PluginRuntime _runtime;
  final SourceHttpClient _http;
  final Redactor _redactor;
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
  Future<LoginQrCode> loginQrStart() async {
    final json = await _login(LoginExports.qrStart, null);
    return _decode(() => LoginQrCode.fromJson(json));
  }

  @override
  Future<LoginQrPoll> loginQrPoll(String token) async {
    final json = await _login(LoginExports.qrPoll, token);
    return _decode(() => LoginQrPoll.fromJson(json));
  }

  @override
  Future<LoginAccount> loginVerify(LoginCredentials credentials) async {
    final json = await _login(
      LoginExports.verify,
      credentials.toJson(),
      secrets: credentials,
    );
    return _decode(
      () => LoginAccount.fromJson(json, allowedHosts: _allowedHosts),
    );
  }

  @override
  Future<LoginCredentials?> loginRefresh(LoginCredentials credentials) async {
    final json = await _login(
      LoginExports.refresh,
      credentials.toJson(),
      secrets: credentials,
    );
    if (json == null) return null;
    final refreshed = _decode(() => LoginCredentials.fromJson(json));
    // 新的憑證在寫入之前就可能出現在 log（插件自己的 log、錯誤原因）。
    refreshed.registerWith(_redactor);
    return refreshed;
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

  /// 呼叫 `login*` 匯出 [function]：manifest 沒宣告它（沒有 `login`、methods 沒有
  /// `qr`、沒宣告 `refresh`）是 [Unsupported]。[secrets] 的值在呼叫前登記到遮蔽
  /// 函式，之後不取消（值本來就是秘密）。執行期間 cookie jar 不存回應的 cookie。
  Future<Object?> _login(
    String function,
    Object? argument, {
    LoginCredentials? secrets,
  }) {
    if (!manifest.requiredExports.contains(function)) {
      throw Unsupported(
        pluginId: manifest.id,
        cause: StateError('$function is not declared'),
        stackTrace: StackTrace.current,
      );
    }
    secrets?.registerWith(_redactor);
    return _http.withoutSavingCookies(
      () => _runtime.invoke(function, argument),
    );
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
  /// manifest 要求的匯出函式（[PluginManifest.requiredExports]：能力的同名函式、
  /// `login` 的那幾個）沒有匯出，或匯出了宿主認得的名稱卻沒宣告：[Unsupported]
  /// （ADR 0014 §如何確認）。腳本本身的錯誤見
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
    final http = _httpClients.create(
      pluginId: manifest.id,
      allowedHosts: manifest.allowedHosts,
      retryPolicy: manifest.retryPolicy ?? const RetryPolicy(),
      rateLimitPolicy: manifest.rateLimitPolicy,
    );
    final host = PluginHost(
      pluginId: manifest.id,
      http: http,
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
    final mismatch = _exportMismatch(manifest, runtime.exports);
    if (mismatch != null) {
      runtime.dispose();
      throw Unsupported(
        pluginId: manifest.id,
        cause: StateError(mismatch),
        stackTrace: StackTrace.current,
      );
    }
    // 「以登入身分瀏覽與播放」沒設定過時的值跟著載入成功的這一版走。
    _credentials.setBrowseAsLoggedInDefault(
      manifest.id,
      manifest.login?.browseAsLoggedInDefault ?? true,
    );
    return ScriptSourcePlugin._(manifest, runtime, http, _redactor);
  }

  /// manifest 要求的匯出（[PluginManifest.requiredExports]）與實際匯出不一致之處；
  /// 一致是 `null`。宿主認得、卻不是 manifest 要求的匯出也算。
  static String? _exportMismatch(PluginManifest manifest, Set<String> exports) {
    final required = manifest.requiredExports;
    final missing = [
      for (final name in required)
        if (!exports.contains(name)) name,
    ];
    final undeclared = [
      for (final name in exports)
        if (PluginManifest.knownExports.contains(name) &&
            !required.contains(name))
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
