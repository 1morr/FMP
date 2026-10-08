import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/network/http_rules.dart';
import 'package:fmp/core/network/media_headers.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/network/source_http_client.dart' show RequestCancelled;

/// 連線沿用 API client 的 10 秒。
const _connectTimeout = Duration(seconds: 10);

/// 等回應標頭與兩次收到資料之間的上限（dio 的 `receiveTimeout`）。比 OkHttp
/// 預設的 10 秒寬，給慢的 CDN。
const _idleTimeout = Duration(seconds: 15);

/// 整個下載（含每一跳轉址與寫檔前的收資料）的上限。
const _totalTimeout = Duration(seconds: 30);

/// 寫到一半的檔案放在目的地旁邊，完成才改名。
const _partialSuffix = '.part';

/// 媒體 client 自己的 log tag（暫存檔清不掉之類），和每一跳的網路紀錄分開。
const mediaFilesLogTag = 'media-files';

/// 依插件建立 [MediaHttpClient]（ADR 0012 §決定 1：抓位元組的媒體 client）。
///
/// 和 `SourceHttpClientFactory` 一樣，[createAdapter] 換掉 dio 最底層的
/// adapter，[reportOutcome] 收每一跳的結果（網路狀態，ADR 0016 §決定 6），
/// [recordIds] 在 App 裡與 API client 共用。
final class MediaHttpClientFactory {
  MediaHttpClientFactory({
    required this._log,
    this._reportOutcome = _ignoreOutcome,
    NetworkRecordIds? recordIds,
    this._createAdapter = IOHttpClientAdapter.new,
  }) : _recordIds = recordIds ?? NetworkRecordIds();

  final Log _log;
  final RequestOutcomeSink _reportOutcome;
  final NetworkRecordIds _recordIds;
  final HttpClientAdapter Function() _createAdapter;

  /// [pluginId] 的媒體 client。[allowedHosts] 是 manifest 的允許網域，與同一個
  /// 插件的 API client 相同。
  ///
  /// [client] 是網路紀錄的 `client` 欄位；[exactHosts] 讓允許網域不含子網域
  /// （`HostFetch` 用，轉址不得換 host）。
  MediaHttpClient create({
    required String pluginId,
    required Iterable<String> allowedHosts,
    NetworkClient client = NetworkClient.media,
    bool exactHosts = false,
  }) {
    // 沒有認證與 cookie 攔截器，也沒有 cookie jar：請求上只有呼叫端給、經
    // mediaRequestHeaders 過濾的 header（ADR 0012 §決定 1）。
    final dio = Dio(
      BaseOptions(
        connectTimeout: _connectTimeout,
        receiveTimeout: _idleTimeout,
      ),
    )..httpClientAdapter = _createAdapter();
    return MediaHttpClient._(
      pluginId: pluginId,
      allowedHosts: AllowedHosts(allowedHosts, exact: exactHosts),
      client: client,
      dio: dio,
      log: _log,
      recordIds: _recordIds,
      reportOutcome: _reportOutcome,
    );
  }
}

void _ignoreOutcome(RequestOutcome outcome) {}

/// 一次下載的結果；內容已經在呼叫端給的檔案裡。
final class MediaDownload {
  const MediaDownload({
    required this.url,
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  /// 跟隨轉址後的最終網址。
  final Uri url;

  /// 2xx（帶 `Range` 時是 206）。
  final int statusCode;

  /// 回應標頭，名稱小寫（`Cache-Control`、`ETag`、`Content-Type` 給呼叫端）。
  final Map<String, List<String>> headers;

  /// 寫進檔案的位元組數。
  final int bytes;
}

/// 一個插件的媒體 client：抓圖片與檔案（封面快取，M6 起的下載），不帶憑證。
///
/// 每一跳只帶媒體 header，以和 API client 同一份規則（`http_rules.dart`）檢查
/// 網域與轉址；有大小上限與三種逾時；不重試。丟出的錯誤都是 [AppError]，
/// 取消例外（[RequestCancelled]）。
final class MediaHttpClient {
  MediaHttpClient._({
    required this.pluginId,
    required this._allowedHosts,
    required this._client,
    required this._dio,
    required this._log,
    required this._recordIds,
    required this._reportOutcome,
  });

  final String pluginId;
  final AllowedHosts _allowedHosts;
  final NetworkClient _client;
  final Dio _dio;
  final Log _log;
  final NetworkRecordIds _recordIds;
  final RequestOutcomeSink _reportOutcome;

  /// 把 [url] 的內容下載到 [destination]。
  ///
  /// - [headers] 先經 `mediaRequestHeaders`，只留 `Referer`、`User-Agent`、
  ///   `Origin`、`Range`；每一跳都只帶這些。
  /// - 內容先寫進 [destination] 旁的 `.part` 檔，完成才改名成 [destination]；
  ///   失敗時刪掉 `.part`，[destination] 原本的檔案不動。同一個 [destination]
  ///   不要同時下載兩次。
  /// - 超過 [maxBytes]（先看 `Content-Length`，再邊收邊數）就中止，丟
  ///   [Unsupported]。
  /// - 網址或轉址的下一跳不在允許網域、不是 `https`、帶 user info、超過 5 次
  ///   轉址：[Unsupported]，那一跳不發出。
  /// - 傳輸錯誤與逾時（連線 10 秒、收資料間隔 15 秒、整個下載 30 秒）：
  ///   [NetworkError]。429 與帶 `Retry-After` 的 503：[RateLimited]；404、410：
  ///   [NotFound]；其他非 2xx：[UnexpectedError]（狀態碼在網路紀錄）。
  /// - [abortTrigger] 完成時取消，丟 [RequestCancelled]。
  /// - 已經 [close]：[UnexpectedError]，那一跳不發出。
  Future<MediaDownload> download(
    Uri url, {
    required File destination,
    required int maxBytes,
    Map<String, String> headers = const {},
    Future<void>? abortTrigger,
  }) async {
    requireAllowedHost(_allowedHosts, url, pluginId: pluginId);
    _requireNoUserInfo(url);
    final requestHeaders = mediaRequestHeaders(headers);
    final stopper = _Stopper();
    // 觸發的 Future 以錯誤結束也算取消。
    abortTrigger
        ?.whenComplete(() => stopper.stop(_StopReason.cancelled))
        .ignore();
    final deadline = Timer(
      _totalTimeout,
      () => stopper.stop(_StopReason.timedOut),
    );
    try {
      var hopUrl = url;
      for (var redirects = 0; ; redirects++) {
        switch (await _hop(
          hopUrl,
          requestHeaders,
          stopper,
          destination: destination,
          maxBytes: maxBytes,
        )) {
          case _Downloaded(:final result):
            return result;
          case _Redirected(:final location, :final recordId):
            hopUrl = redirectTarget(
              from: hopUrl,
              location: location,
              redirects: redirects,
              allowedHosts: _allowedHosts,
              pluginId: pluginId,
              networkRecordId: recordId,
            );
            _requireNoUserInfo(hopUrl, networkRecordId: recordId);
        }
      }
    } finally {
      deadline.cancel();
      // 之後才觸發的 abortTrigger 不再碰已經結束的請求。
      stopper.detach();
    }
  }

  /// 已經 [close]：之後的每一跳都不發出。
  var _closed = false;

  /// 關閉底層的連線；進行中的那一跳以傳輸錯誤結束。
  void close() {
    _closed = true;
    _dio.close(force: true);
  }

  /// 一跳：送出、依狀態碼處理、收內容。不論結果都寫一筆網路紀錄、回報網路
  /// 狀態最多一次。
  Future<_HopResult> _hop(
    Uri url,
    Map<String, String> headers,
    _Stopper stopper, {
    required File destination,
    required int maxBytes,
  }) async {
    _throwIfStopped(stopper);
    _throwIfClosed();
    final recordId = _recordIds.next();
    final startedAt = clock.now();
    final cancelToken = stopper.track(CancelToken());
    Response<ResponseBody>? response;
    int? bytes;

    void finish({Object? failure}) {
      final status = response?.statusCode;
      final cancelled = failure is RequestCancelled;
      writeNetworkRecord(
        _log,
        client: _client,
        id: recordId,
        pluginId: pluginId,
        method: 'GET',
        uri: url,
        failed: (failure != null && !cancelled) || (status ?? 0) >= 400,
        credentials: false,
        retry: 0,
        status: status,
        ms: clock.now().difference(startedAt).inMilliseconds,
        bytes: bytes,
        error: switch (failure) {
          null => null,
          RequestCancelled() => 'Cancelled',
          final AppError error => error.typeName,
          _ => 'UnexpectedError',
        },
      );
      // 拿到回應不論狀態碼都是連得上；NetworkError（含收內容時中斷、逾時）
      // 是連不上；取消與沒送出的不算。
      final outcome = switch (failure) {
        NetworkError() => RequestOutcome.networkError,
        RequestCancelled() => null,
        _ when response != null => RequestOutcome.responded,
        _ => null,
      };
      if (outcome != null) _reportOutcome(outcome);
    }

    try {
      final received = response = await _dio.requestUri<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          method: 'GET',
          headers: {...headers},
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (_) => true,
        ),
      );
      final status = received.statusCode!;
      final responseHeaders = received.headers.map;
      if (redirectLocation(status, responseHeaders) case final location?) {
        // 不讀轉址的內容：取消才會關掉連線（dio 的回應串流沒有人聽時不會
        // 自己關）。
        cancelToken.cancel();
        finish();
        return _Redirected(location, recordId);
      }
      if (_statusError(status, responseHeaders, recordId) case final error?) {
        throw error;
      }
      final declared = int.tryParse(
        responseHeaders[HttpHeaders.contentLengthHeader]?.first ?? '',
      );
      if (declared != null && declared > maxBytes) {
        throw _tooLarge(maxBytes, recordId);
      }
      bytes = 0;
      final count = bytes = await _save(
        received.data!.stream,
        destination,
        maxBytes: maxBytes,
        recordId: recordId,
        onReceived: (count) => bytes = count,
      );
      finish();
      return _Downloaded(
        MediaDownload(
          url: url,
          statusCode: status,
          headers: responseHeaders,
          bytes: count,
        ),
      );
    } on Object catch (error, stackTrace) {
      // 不再讀這個回應：取消才會關掉連線。
      cancelToken.cancel();
      final failure = _classify(error, stackTrace, stopper, recordId);
      finish(failure: failure);
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  /// 收內容寫進 [destination] 旁的暫存檔，完成才改名，回傳位元組數；失敗時
  /// 刪掉暫存檔。暫存檔在收到第一塊資料時才建立。[onReceived] 讓失敗的那筆
  /// 網路紀錄也有收到的位元組數。
  Future<int> _save(
    Stream<Uint8List> body,
    File destination, {
    required int maxBytes,
    required int recordId,
    required void Function(int count) onReceived,
  }) async {
    final partial = File('${destination.path}$_partialSuffix');
    IOSink? sink;
    var closed = false;
    var received = 0;
    try {
      await for (final chunk in body) {
        received += chunk.length;
        onReceived(received);
        if (received > maxBytes) throw _tooLarge(maxBytes, recordId);
        (sink ??= partial.openWrite()).add(chunk);
      }
      final finished = sink ?? partial.openWrite();
      closed = true;
      await finished.close();
      await partial.rename(destination.path);
      return received;
    } on Object {
      await _discard(partial, sink, closed: closed);
      rethrow;
    }
  }

  /// 刪掉寫到一半的 [partial]。這裡的失敗只記下來：往上拋的是原本的錯誤。
  Future<void> _discard(
    File partial,
    IOSink? sink, {
    required bool closed,
  }) async {
    if (sink == null && !closed) return;
    try {
      if (sink != null && !closed) await sink.close();
    } on FileSystemException catch (error, stackTrace) {
      _log.warning(
        'Failed to close a partial media file',
        tag: mediaFilesLogTag,
        error: error,
        stackTrace: stackTrace,
      );
    }
    try {
      if (await partial.exists()) await partial.delete();
    } on FileSystemException catch (error, stackTrace) {
      _log.warning(
        'Failed to delete a partial media file',
        tag: mediaFilesLogTag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 非 2xx 的狀態碼對應的錯誤（ADR 0013 §決定 2）；2xx 回 `null`。
  AppError? _statusError(
    int status,
    Map<String, List<String>> headers,
    int recordId,
  ) {
    if (status >= 200 && status < 300) return null;
    final rateLimited = rateLimitedResponse(
      status,
      headers,
      now: clock.now(),
      pluginId: pluginId,
      networkRecordId: recordId,
    );
    if (rateLimited != null) return rateLimited;
    final cause = 'HTTP $status';
    return switch (status) {
      404 || 410 => NotFound(
        pluginId: pluginId,
        networkRecordId: recordId,
        cause: cause,
      ),
      _ => UnexpectedError(
        pluginId: pluginId,
        networkRecordId: recordId,
        cause: cause,
      ),
    };
  }

  Unsupported _tooLarge(int maxBytes, int recordId) => Unsupported(
    pluginId: pluginId,
    networkRecordId: recordId,
    cause: StateError('Media response is larger than $maxBytes bytes'),
    stackTrace: StackTrace.current,
  );

  /// 一跳失敗時丟出去的東西：[AppError] 或 [RequestCancelled]。
  Object _classify(
    Object error,
    StackTrace stackTrace,
    _Stopper stopper,
    int recordId,
  ) => switch (error) {
    AppError() || RequestCancelled() => error,
    DioException(type: DioExceptionType.cancel) => switch (stopper.reason) {
      _StopReason.timedOut => _timedOut(recordId),
      _StopReason.cancelled || null => const RequestCancelled(),
    },
    DioException() => transportError(
      error,
      pluginId: pluginId,
      networkRecordId: recordId,
    ),
    // 寫檔失敗（磁碟滿、沒有權限）不是網路的問題。
    FileSystemException() => UnexpectedError(
      pluginId: pluginId,
      networkRecordId: recordId,
      cause: error,
      stackTrace: stackTrace,
    ),
    // 收內容時連線中斷：dio 把 dart:io 的錯誤（HttpException 等）原樣交出。
    IOException() => NetworkError(
      pluginId: pluginId,
      networkRecordId: recordId,
      cause: error,
      stackTrace: stackTrace,
    ),
    _ => UnexpectedError(
      pluginId: pluginId,
      networkRecordId: recordId,
      cause: error,
      stackTrace: stackTrace,
    ),
  };

  NetworkError _timedOut(int? recordId) => NetworkError(
    pluginId: pluginId,
    networkRecordId: recordId,
    cause: TimeoutException('Media request took too long', _totalTimeout),
    stackTrace: StackTrace.current,
  );

  /// [url] 帶 user info（`https://user:pass@host/`）：丟 [Unsupported]，那一跳
  /// 不發出。dart:io 的 `HttpClient` 會把 user info 變成
  /// `Authorization: Basic …`，繞過 `mediaRequestHeaders`（ADR 0012 §決定 1：
  /// 媒體請求不帶憑證）。錯誤原因不寫 user info 本身。
  void _requireNoUserInfo(Uri url, {int? networkRecordId}) {
    if (url.userInfo.isEmpty) return;
    throw Unsupported(
      pluginId: pluginId,
      networkRecordId: networkRecordId,
      cause: StateError('Media URL carries user info: ${url.host}'),
      stackTrace: StackTrace.current,
    );
  }

  /// client 已關閉（插件更新後還拿著舊的）：那一跳不發出，不寫網路紀錄、不回報
  /// 網路狀態。不能交給 dio：關閉後的 dio 丟 `connectionError`，會被當成連不上。
  void _throwIfClosed() {
    if (!_closed) return;
    throw UnexpectedError(
      pluginId: pluginId,
      cause: StateError('Media client is closed'),
      stackTrace: StackTrace.current,
    );
  }

  /// 兩跳之間已經取消或逾時：下一跳不發出。
  void _throwIfStopped(_Stopper stopper) {
    switch (stopper.reason) {
      case null:
        return;
      case _StopReason.cancelled:
        throw const RequestCancelled();
      case _StopReason.timedOut:
        throw _timedOut(null);
    }
  }
}

sealed class _HopResult {}

final class _Downloaded implements _HopResult {
  _Downloaded(this.result);

  final MediaDownload result;
}

final class _Redirected implements _HopResult {
  _Redirected(this.location, this.recordId);

  final String location;
  final int recordId;
}

enum _StopReason { cancelled, timedOut }

/// 一次下載的停止：呼叫端取消或整個下載逾時，先到的算。停止時取消目前這一跳。
final class _Stopper {
  _StopReason? reason;
  CancelToken? _current;

  CancelToken track(CancelToken token) => _current = token;

  /// 下載結束：之後的停止都不取消任何東西。
  void detach() => _current = null;

  void stop(_StopReason why) {
    reason ??= why;
    _current?.cancel();
  }
}
