import 'dart:async';
import 'dart:convert';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/plugins/json_shape.dart';

/// 宿主 API 的 JSON 形狀，鍵是 `fmp-plugin.d.ts` 裡的 interface 名稱。
const hostApiShapes = <String, JsonShape>{
  'HttpRequest': {
    'url': true,
    'method': false,
    'headers': false,
    'body': false,
    'auth': false,
    'idempotent': false,
  },
  'HttpResponse': {'status': true, 'url': true, 'headers': true, 'body': true},
};

/// 一個插件的宿主 API v1（ADR 0014 §決定 5）在主 isolate 的那一半：網路、
/// storage、憑證、log。插件腳本能碰到的外界只有這些，加上背景 isolate 自己算
/// 的 `crypto`（`plugin_worker.dart`）。
///
/// 每個實例綁定一個插件：`pluginId` 在建構時固定，腳本沒有辦法指定別的插件，
/// 所以讀不到其他插件的 storage 與憑證。參數與回傳值是已解碼的 JSON；參數
/// 不對拋 [ArgumentError] 或 [FormatException]（腳本收到 `TypeError`），其他
/// 失敗拋 `AppError`。
final class PluginHost {
  PluginHost({
    required this.pluginId,
    required this._http,
    required this._storage,
    required this._log,
  });

  final String pluginId;
  final SourceHttpClient _http;
  final PluginStorageRepository _storage;
  final Log _log;

  /// [close] 時完成：取消還在進行的請求。
  final _closed = Completer<void>();

  /// 非同步的宿主函式（網路、storage、憑證）。
  Future<Object?> callAsync(String op, Object? args) => switch (op) {
    'http.request' => _request(args),
    'storage.get' => _storage.read(pluginId, _key(args)),
    'storage.set' => _storageSet(args),
    'storage.delete' => _storage.delete(pluginId, _key(args)),
    // M1 沒有登入，一律「沒有憑證」；CredentialStore 在 M3（ADR 0012 §決定 3）。
    'credentials.get' => Future.value(),
    _ => throw ArgumentError.value(op, 'op', 'unknown host function'),
  };

  /// 腳本的 log（背景 isolate 已檢查過形狀）：經門面寫入，tag 固定是插件
  /// id，腳本改不了。
  void writeLog(String level, String message, Map<String, Object?> fields) {
    _log.write(
      switch (level) {
        'debug' => LogLevel.debug,
        'info' => LogLevel.info,
        'warn' => LogLevel.warning,
        'error' => LogLevel.error,
        _ => throw ArgumentError.value(level, 'level'),
      },
      message,
      tag: pluginId,
      fields: fields,
    );
  }

  /// 取消進行中的請求並關閉連線。之後的呼叫結果不再交給腳本。
  void close() {
    if (_closed.isCompleted) return;
    _closed.complete();
    _http.close();
  }

  Future<Map<String, Object?>> _request(Object? args) async {
    final fields = JsonFields(
      args,
      hostApiShapes['HttpRequest']!,
      path: 'fmp.http.request',
    );
    final response = await _http.send(
      SourceRequest(
        Uri.parse(fields.string('url')),
        method: fields.optionalString('method') ?? 'GET',
        headers: fields.optionalStringMap('headers') ?? const {},
        body: fields.optionalString('body'),
        auth: _auth(fields.optionalString('auth')),
        idempotent: fields.optionalBool('idempotent'),
      ),
      abortTrigger: _closed.future,
    );
    return {
      'status': response.statusCode,
      'url': response.url.toString(),
      'headers': response.headers,
      'body': utf8.decode(response.body, allowMalformed: true),
    };
  }

  Future<void> _storageSet(Object? args) {
    final fields = JsonFields(args, const {
      'key': true,
      'value': true,
    }, path: 'fmp.storage.set');
    return _storage.write(pluginId, _key(args), fields.string('value'));
  }

  static String _key(Object? args) {
    final key = switch (args) {
      {'key': final String key} => key,
      _ => throw ArgumentError('storage key must be a string'),
    };
    if (key.isEmpty) throw ArgumentError('storage key must not be empty');
    return key;
  }

  /// 預設 `never`（ADR 0012 §決定 2）。名稱是插件的介面，與 enum 分開寫死。
  static AuthRequirement _auth(String? name) => switch (name) {
    null || 'never' => AuthRequirement.never,
    'userPreference' => AuthRequirement.userPreference,
    'required' => AuthRequirement.required,
    _ => throw ArgumentError.value(name, 'auth'),
  };
}
