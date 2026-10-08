import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';

/// 網路紀錄的 log tag。
const networkLogTag = 'network';

/// 發出請求的 client，網路紀錄的 `client` 欄位。值寫死，是 log 檔的持久化
/// 格式。
enum NetworkClient {
  /// `SourceHttpClient`：插件的 API 請求。
  source('source'),

  /// `MediaHttpClient`：抓圖片與檔案，不帶憑證。
  media('media'),

  /// `HostFetch`：宿主自己的請求（插件 index、插件檔、checks.json），不屬於任何
  /// 插件，`pluginId` 為空（ADR 0030 §決定 5）。
  host('host');

  const NetworkClient(this.wireName);

  final String wireName;
}

/// 網路紀錄的 id。兩種 client 的工廠共用一個：同一次執行裡 id 不重複，
/// `AppError.networkRecordId` 才只對得到一筆。
final class NetworkRecordIds {
  int _last = 0;

  int next() => ++_last;
}

/// 寫一筆網路紀錄（ADR 0011 §決定 4）：每次送出一筆摘要，經 log 門面寫入，
/// 不記 body。query 原樣交給門面，由遮蔽函式處理。
///
/// [failed]：產生了錯誤，或狀態碼 ≥ 400。失敗用 `warning`，release 的預設
/// 層級（info）也看得到；其餘用 `debug`。
void writeNetworkRecord(
  Log log, {
  required NetworkClient client,
  required int id,
  required String pluginId,
  required String method,
  required Uri uri,
  required bool failed,
  required bool credentials,
  required int retry,
  int? status,
  int? ms,
  int? bytes,
  String? error,
}) => log.write(
  failed ? LogLevel.warning : LogLevel.debug,
  failed ? 'HTTP request failed' : 'HTTP request',
  tag: networkLogTag,
  fields: {
    'id': id,
    'pluginId': pluginId,
    'client': client.wireName,
    'method': method,
    'host': uri.host,
    'path': uri.path,
    if (uri.hasQuery) 'query': uri.query,
    'status': ?status,
    'ms': ?ms,
    'bytes': ?bytes,
    'error': ?error,
    'credentials': credentials,
    'retry': retry,
  },
);
