import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/media_http_client.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/network/network_status.dart';

/// 插件 index 的大小上限（ADR 0030 §決定 5，design §7.1）。
const indexMaxBytes = 1024 * 1024;

/// 插件安裝檔的大小上限。
const pluginFileMaxBytes = 8 * 1024 * 1024;

/// `checks.json` 的大小上限。
const checksMaxBytes = 256 * 1024;

/// 宿主自己的請求：讀插件 index、下載插件檔與 `checks.json`（ADR 0030
/// §決定 5）。
///
/// 以媒體 client 的規則為底（不帶憑證、沒有 cookie jar、只准 `https`、不准
/// user info、轉址每跳檢查、三種逾時、不重試），差別只有兩個：允許網域是
/// 「該網址自己的 host」且不含子網域，轉址不得換 host；網路紀錄的 `client` 是
/// `host`、`pluginId` 為空。丟出的錯誤都是 `AppError`（取消不會發生：沒有
/// abortTrigger）。
final class HostFetch {
  HostFetch({
    required Log log,
    RequestOutcomeSink reportOutcome = _ignoreOutcome,
    NetworkRecordIds? recordIds,
    HttpClientAdapter Function() createAdapter = IOHttpClientAdapter.new,
  }) : _factory = MediaHttpClientFactory(
         log: log,
         reportOutcome: reportOutcome,
         recordIds: recordIds,
         createAdapter: createAdapter,
       );

  final MediaHttpClientFactory _factory;

  /// 讀 [url] 的內容，最多 [maxBytes] 位元組。
  Future<Uint8List> fetch(Uri url, {required int maxBytes}) async {
    final client = _factory.create(
      pluginId: null,
      allowedHosts: [url.host],
      client: NetworkClient.host,
      exactHosts: true,
    );
    // 媒體 client 下載到檔案：放在每次不同的暫存目錄，讀完就刪。
    final directory = await Directory.systemTemp.createTemp('fmp_host_fetch');
    try {
      final file = File('${directory.path}${Platform.pathSeparator}body');
      await client.download(url, destination: file, maxBytes: maxBytes);
      return await file.readAsBytes();
    } finally {
      client.close();
      await directory.delete(recursive: true);
    }
  }
}

void _ignoreOutcome(RequestOutcome outcome) {}
