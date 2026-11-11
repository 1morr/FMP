import 'dart:async';

import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:fjs/fjs.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/src/host_network.dart';
import 'package:fmp/plugins/src/js_engine.dart';
import 'package:fmp/plugins/src/manifest.dart';
import 'package:fmp/plugins/src/plugin_error.dart';

/// 一個插件的原始檔：`manifest.json` 與 esbuild 打包的 `dist/plugin.js`。
class PluginBundle {
  const PluginBundle({required this.manifest, required this.code});

  final String manifest;
  final String code;
}

/// 插件宿主：載入插件、替插件連網、把插件的錯誤轉成錯誤分類。
///
/// manifest 不合格的插件略過並寫 log。每個插件一個 JS 引擎，第一次呼叫時
/// 才建；呼叫超過 `callTimeout` 就關掉引擎（中斷卡住的 JS，brief 事實
/// K11），下一次呼叫重建（plan §1.1）。
class PluginHost {
  PluginHost({
    required List<PluginBundle> bundles,
    required Log log,
    HttpClientAdapter? httpAdapter,
    Duration callTimeout = const Duration(seconds: 30),
  }) : _network = HostNetwork(log: log, adapter: httpAdapter) {
    final plugins = <Plugin>[];
    for (final bundle in bundles) {
      try {
        final manifest = PluginManifest.parse(bundle.manifest);
        if (plugins.any((p) => p.manifest.id == manifest.id)) {
          throw FormatException('duplicate plugin id "${manifest.id}"');
        }
        plugins.add(
          Plugin._(manifest, bundle.code, _network, log, callTimeout),
        );
      } on FormatException catch (e) {
        log.error('Skipped a plugin with a bad manifest: ${e.message}');
      }
    }
    this.plugins = List.unmodifiable(plugins);
  }

  final HostNetwork _network;

  /// 載入成功的插件，順序同傳入的 bundles。
  late final List<Plugin> plugins;

  /// 關掉所有引擎與網路。之後不能再用。
  Future<void> close() async {
    for (final plugin in plugins) {
      await plugin._closeEngine();
    }
    _network.close();
  }
}

/// 一個載入的插件。插件能力的方法在插件沒宣告該能力時丟 [Unsupported]；
/// 失敗一律丟 [AppError]。
class Plugin {
  Plugin._(this.manifest, this._code, this._network, this._log, this._timeout);

  final PluginManifest manifest;
  final String _code;
  final HostNetwork _network;
  final Log _log;
  final Duration _timeout;
  Future<JsEngine>? _engine;

  /// 插件能力 `search`：用 [query] 搜尋曲目。
  Future<List<Track>> search(String query) async {
    final result = await _invoke(PluginCapability.search, {'query': query});
    try {
      final tracks = (result as Map)['tracks'] as List;
      return [for (final t in tracks) _track(t as Map)];
    } on TypeError catch (e) {
      _log.warning('plugin ${manifest.id}: search returned a bad shape: $e');
      throw const ParseFailure();
    }
  }

  Track _track(Map<dynamic, dynamic> json) {
    final ms = json['durationMs'];
    return Track(
      source: manifest.id,
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      duration: ms == null ? null : Duration(milliseconds: (ms as num).round()),
    );
  }

  /// 呼叫插件匯出的 [capability] 函式，回傳它 resolve 的值。
  Future<Object?> _invoke(
    PluginCapability capability,
    Map<String, Object?> args,
  ) async {
    final method = capability.wireName;
    if (!manifest.capabilities.contains(capability)) {
      throw const Unsupported();
    }
    final JsValue value;
    try {
      final engine = await (_engine ??= createPluginEngine(
        code: _code,
        bridge: _bridge,
      ));
      value = await engine
          .call(
            module: invokeModule,
            method: 'invoke',
            params: [JsValue.string(method), JsValue.from(args)],
          )
          .timeout(_timeout);
    } on TimeoutException {
      _log.warning(
        'plugin ${manifest.id}: $method timed out after '
        '${_timeout.inMilliseconds}ms; restarting its engine',
      );
      await _closeEngine();
      throw const NetworkError();
    } on JsError catch (e) {
      _log.error('plugin ${manifest.id}: $method failed in the engine: $e');
      await _closeEngine();
      throw const ParseFailure();
    }
    final result = value.value;
    if (result is Map && result['error'] is Map) {
      final error = result['error'] as Map;
      final code = PluginErrorCode.fromWire(error['code']);
      _log.warning(
        'plugin ${manifest.id}: $method failed with ${code.wire}: '
        '${error['message']}',
      );
      throw code.toAppError();
    }
    return (result as Map)['ok'];
  }

  /// 宿主 API 的單一入口（`fjs.bridge_call`）：依 `op` 分派。失敗交回
  /// `{error: {code, message}}`，JS 端變成 `PluginError`。
  Future<JsResult> _bridge(JsValue value) async {
    final request = value.value;
    try {
      if (request is Map && request['op'] == 'http.request') {
        final headers = request['headers'];
        final response = await _network.get(
          manifest,
          '${request['url']}',
          headers: {
            if (headers is Map)
              for (final MapEntry(:key, :value) in headers.entries)
                '$key': '$value',
          },
        );
        return JsResult.ok(
          JsValue.from({'status': response.status, 'body': response.body}),
        );
      }
      throw PluginFailure(
        PluginErrorCode.unsupported,
        'unknown host call ${request is Map ? request['op'] : request}',
      );
    } on PluginFailure catch (e) {
      return JsResult.ok(
        JsValue.from({
          'error': {'code': e.code.wire, 'message': e.message},
        }),
      );
    }
  }

  Future<void> _closeEngine() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    try {
      await (await engine).close();
    } catch (e) {
      // 中斷卡住的呼叫時，close() 會把被中斷的背景錯誤丟出來（事實 K11）。
      _log.debug('plugin ${manifest.id}: engine closed with: $e');
    }
  }
}
