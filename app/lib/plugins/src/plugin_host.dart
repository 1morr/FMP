import 'dart:async';

import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:fjs/fjs.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/audio_stream.dart';
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
/// K11），下一次呼叫重建（plan §1.1）。`callTimeout` 要比宿主網路單次請求
/// 的上限（連線 15 秒加讀取 30 秒）長，慢的網路才會以 `network` 回到插件，
/// 不會被當成插件卡住。
class PluginHost {
  PluginHost({
    required List<PluginBundle> bundles,
    required Log log,
    HttpClientAdapter? httpAdapter,
    Duration callTimeout = const Duration(seconds: 60),
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
/// 插件或音源造成的失敗丟 [AppError]，宿主自己的程式錯誤（例如原生庫
/// 載入失敗）照原樣丟出。
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
    return _parse(PluginCapability.search, () {
      final tracks = (result as Map)['tracks'] as List;
      return [for (final t in tracks) _track(t as Map)];
    });
  }

  /// 插件能力 `resolveStream`：把 [trackId]（[Track.id]）解析成串流。
  Future<AudioStream> resolveStream(String trackId) async {
    final result = await _invoke(PluginCapability.resolveStream, {
      'trackId': trackId,
    });
    return _parse(PluginCapability.resolveStream, () {
      final json = result as Map;
      final url = Uri.parse(json['url'] as String);
      if (!url.isAbsolute || !const {'http', 'https'}.contains(url.scheme)) {
        throw const FormatException('url is not an absolute http(s) url');
      }
      final headers = json['headers'] as Map? ?? const {};
      final expiresAtMs = _whole(json['expiresAtMs'], 'expiresAtMs');
      return AudioStream(
        url: url,
        headers: {
          for (final MapEntry(:key, :value) in headers.entries)
            key as String: value as String,
        },
        expiresAt: expiresAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiresAtMs, isUtc: true),
        codec: json['codec'] as String?,
        bitrate: _whole(json['bitrate'], 'bitrate'),
      );
    });
  }

  /// 把插件能力的回傳值轉成 Dart 的型別。形狀不對（型別、格式、數字或時間
  /// 超出範圍）時寫 log、丟 [ParseFailure]。FormatException 只記訊息：
  /// `Uri.parse` 的例外會帶整個（簽名過的）網址。
  T _parse<T>(PluginCapability capability, T Function() parse) {
    Never badShape(Object why) {
      _log.warning(
        'plugin ${manifest.id}: ${capability.name} returned a bad shape: $why',
      );
      throw const ParseFailure();
    }

    try {
      return parse();
    } on TypeError catch (e) {
      badShape(e);
    } on FormatException catch (e) {
      badShape(e.message);
    } on ArgumentError catch (e) {
      badShape(e);
    }
  }

  /// 選填的數字欄位，四捨五入成整數；NaN 與無限大不算數字。
  static int? _whole(Object? value, String name) => switch (value) {
    null => null,
    num n when n.isFinite => n.round(),
    _ => throw FormatException('$name is not a finite number'),
  };

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
    final method = capability.name;
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
      throw const ParseFailure();
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
