import 'package:dio/dio.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/plugins/src/manifest.dart';
import 'package:fmp/plugins/src/plugin_error.dart';

/// 插件唯一的連網方式（宿主 API `host.http.request`）。
///
/// - 只放行 https，且主機要在插件 manifest 的 `domains` 裡；轉址由這裡逐跳
///   跟（最多 [maxRedirects] 次），每一跳都檢查，不讓 dio 自己跟到別的網域。
/// - 任何狀態碼都照實交回插件，由插件判斷（例如音源的限流碼）；連不上、
///   逾時才算失敗，丟 [PluginFailure]（代碼 `network`）。
/// - 每個請求與失敗都經 [Log] 寫 log，log 門面負責遮蔽（brief §13）。
class HostNetwork {
  HostNetwork({required this._log, HttpClientAdapter? adapter})
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          followRedirects: false,
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ),
      ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  static const maxRedirects = 5;

  final Log _log;
  final Dio _dio;

  /// 替 [plugin] 發 GET。回傳最後一跳的狀態碼與內文。
  Future<({int status, String body})> get(
    PluginManifest plugin,
    String url, {
    Map<String, String> headers = const {},
  }) async {
    var uri = Uri.tryParse(url);
    for (var hop = 0; ; hop++) {
      _checkAllowed(plugin, uri);
      final watch = Stopwatch()..start();
      final Response<String> response;
      try {
        response = await _dio.getUri<String>(
          uri!,
          options: Options(headers: headers),
        );
      } on DioException catch (e) {
        _log.warning('plugin ${plugin.id}: GET $uri failed: ${e.type.name}');
        throw PluginFailure(PluginErrorCode.network, e.type.name);
      }
      final status = response.statusCode ?? 0;
      _log.debug(
        'plugin ${plugin.id}: GET $uri -> $status '
        'in ${watch.elapsedMilliseconds}ms',
      );
      final location = response.headers.value('location');
      if (!_redirects.contains(status) || location == null) {
        return (status: status, body: response.data ?? '');
      }
      if (hop == maxRedirects) {
        _log.warning('plugin ${plugin.id}: too many redirects from $url');
        throw const PluginFailure(
          PluginErrorCode.network,
          'too many redirects',
        );
      }
      uri = uri.resolve(location);
    }
  }

  void _checkAllowed(PluginManifest plugin, Uri? uri) {
    if (uri != null && uri.scheme == 'https' && plugin.allowsHost(uri.host)) {
      return;
    }
    final target = uri == null
        ? 'an invalid URL'
        : '${uri.scheme}://${uri.host}';
    _log.warning('plugin ${plugin.id}: blocked a request to $target');
    throw PluginFailure(
      PluginErrorCode.domainNotAllowed,
      '$target is not https on a domain in the manifest',
    );
  }

  void close() => _dio.close(force: true);
}

const _redirects = {301, 302, 303, 307, 308};
