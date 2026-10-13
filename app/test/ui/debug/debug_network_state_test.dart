import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/ui/debug/debug_network_state.dart';

void main() {
  late Log log;
  setUp(() => log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug));

  /// 和網路層一樣經 `writeNetworkRecord` 寫：欄位名稱改了這裡會跟著紅。
  void request(
    int id, {
    String? pluginId = 'alpha',
    String method = 'GET',
    String host = 'api.example.test',
    String path = '/search',
    int? status = 200,
    int? ms = 80,
    int? bytes = 1200,
    String? error,
    Uri? uri,
  }) => writeNetworkRecord(
    log,
    client: pluginId == null ? NetworkClient.host : NetworkClient.source,
    id: id,
    pluginId: pluginId,
    method: method,
    uri: uri ?? Uri.https(host, path, {'q': 'song'}),
    failed: status == null || status >= 400,
    credentials: false,
    retry: 0,
    status: status,
    ms: ms,
    bytes: bytes,
    error: error,
  );

  List<NetworkEntry> entries() => networkEntries(log.history);

  group('NetworkEntry', () {
    test('reads what writeNetworkRecord writes', () {
      request(7);

      final entry = entries().single;
      expect(entry.id, 7);
      expect(entry.source, 'alpha');
      expect(entry.method, 'GET');
      expect(entry.host, 'api.example.test');
      expect(entry.path, '/search');
      expect(entry.query, 'q=song');
      expect(entry.status, 200);
      expect(entry.ms, 80);
      expect(entry.bytes, 1200);
      expect(entry.statusClass, StatusClass.success);
    });

    test('a request that never got a response has no status and failed', () {
      request(1, status: null, ms: null, bytes: null, error: 'NetworkError');

      final entry = entries().single;
      expect(entry.status, isNull);
      expect(entry.bytes, isNull);
      expect(entry.error, 'NetworkError');
      expect(entry.statusClass, StatusClass.failed);
    });

    test('only network records with the list fields count', () {
      log
        ..info('not a request', tag: 'app')
        ..info('half', tag: networkLogTag, fields: {'method': 'GET'});
      request(1);

      expect(entries(), hasLength(1));
    });

    test('status classes', () {
      expect(StatusClass.of(204), StatusClass.success);
      expect(StatusClass.of(302), StatusClass.redirect);
      expect(StatusClass.of(404), StatusClass.clientError);
      expect(StatusClass.of(503), StatusClass.serverError);
      expect(StatusClass.of(null), StatusClass.failed);
      expect(StatusClass.of(101), isNull);
    });
  });

  group('NetworkFilter', () {
    setUp(() {
      request(1, pluginId: 'alpha', status: 200);
      request(2, pluginId: 'alpha', status: 404, path: '/missing');
      request(3, pluginId: 'beta', status: 503);
      request(4, pluginId: 'beta', status: 302);
      request(5, pluginId: null, host: 'raw.example.test', status: 200);
      request(6, pluginId: 'beta', status: null, error: 'NetworkError');
    });

    List<int?> ids(NetworkFilter filter) => [
      for (final entry in entries())
        if (filter.matches(entry)) entry.id,
    ];

    test('no filter shows everything', () {
      expect(ids(const NetworkFilter()), [1, 2, 3, 4, 5, 6]);
    });

    test('by source; the empty source is the app itself', () {
      expect(ids(const NetworkFilter(source: 'alpha')), [1, 2]);
      expect(ids(const NetworkFilter(source: 'beta')), [3, 4, 6]);
      expect(ids(const NetworkFilter(source: '')), [5]);
    });

    test('by status class', () {
      expect(ids(const NetworkFilter(statusClass: StatusClass.success)), [
        1,
        5,
      ]);
      expect(ids(const NetworkFilter(statusClass: StatusClass.redirect)), [4]);
      expect(ids(const NetworkFilter(statusClass: StatusClass.clientError)), [
        2,
      ]);
      expect(ids(const NetworkFilter(statusClass: StatusClass.serverError)), [
        3,
      ]);
      expect(ids(const NetworkFilter(statusClass: StatusClass.failed)), [6]);
    });

    test('source and status class combine', () {
      expect(
        ids(
          const NetworkFilter(
            source: 'beta',
            statusClass: StatusClass.serverError,
          ),
        ),
        [3],
      );
    });

    test('the text looks at the method, host, path, source and status', () {
      expect(ids(const NetworkFilter(text: 'MISSING')), [2]);
      expect(ids(const NetworkFilter(text: 'raw.example')), [5]);
      expect(ids(const NetworkFilter(text: '503')), [3]);
      expect(ids(const NetworkFilter(text: 'nothing')), isEmpty);
    });
  });

  group('matchingErrors', () {
    test('finds the error records that carry the request id', () {
      request(7, status: 503);
      request(8);
      log.report(
        'Search failed',
        NetworkError(networkRecordId: 7),
        tag: 'search',
      );
      log.report(
        'Other failed',
        NetworkError(networkRecordId: 8),
        tag: 'search',
      );
      log.report('No request', NetworkError(), tag: 'search');
      // 不是錯誤（層級太低）的不算。
      log.info('Retrying', tag: 'search', fields: {'networkRecordId': 7});

      final matched = matchingErrors(
        entries().firstWhere((entry) => entry.id == 7),
        log.history,
      );

      expect(matched.map((record) => record.message), ['Search failed']);
    });

    test('a request without an id has none', () {
      log.write(
        LogLevel.warning,
        'HTTP request failed',
        tag: networkLogTag,
        fields: {'method': 'GET', 'host': 'h', 'path': '/'},
      );

      expect(matchingErrors(entries().single, log.history), isEmpty);
    });
  });
}
