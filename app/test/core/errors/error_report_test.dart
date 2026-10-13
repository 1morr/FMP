import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/errors/error_report.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/redaction/redactor.dart';

// 所有憑證都是明顯的假值（FAKE_…），不得換成真實值。
const _fakeValues = [
  'FAKE_SESSDATA_123',
  'FAKE_ACCESS_KEY_123',
  'FAKE_UPSIG_123',
  'FAKE_E_PAYLOAD_123',
  'FAKE_REGISTERED_SECRET_123',
  'FAKE_BEARER_123',
];

const _signedUrl =
    'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/x.m4s'
    '?e=FAKE_E_PAYLOAD_123&deadline=1700000000&upsig=FAKE_UPSIG_123';

void main() {
  late Log log;
  late Redactor redactor;
  setUp(() {
    redactor = Redactor()..registerSecret('FAKE_REGISTERED_SECRET_123');
    log = Log(redactor: redactor, minimumLevel: LogLevel.debug);
  });

  void writeRequest({
    int id = 7,
    String pluginId = 'alpha',
  }) => writeNetworkRecord(
    log,
    client: NetworkClient.source,
    id: id,
    pluginId: pluginId,
    method: 'GET',
    uri: Uri.parse(
      'https://api.example.test/search?q=song&access_key=FAKE_ACCESS_KEY_123',
    ),
    failed: true,
    credentials: false,
    retry: 1,
    status: 412,
    ms: 830,
    error: 'RateLimited',
  );

  ErrorReport reportOf(
    LogRecord? record, {
    List<LogRecord>? networkHistory,
    String? pluginVersion = '1.2.0',
  }) => ErrorReport.fromRecord(
    record!,
    redactor: redactor,
    appVersion: '2.0.0',
    flavor: 'dev',
    platform: 'Windows',
    osVersion: 'Windows 11 (test)',
    pluginVersion: pluginVersion,
    networkHistory: networkHistory ?? log.history,
  );

  LogRecord? reportParseError({int? networkRecordId = 7}) => log.report(
    'Search failed',
    ParseError(
      pluginId: 'alpha',
      networkRecordId: networkRecordId,
      cause: StateError('bad payload'),
      stackTrace: StackTrace.fromString('#0      parse (package:alpha/x.js:1)'),
    ),
    tag: 'search',
  );

  group('fields', () {
    test('come from the error history record', () {
      writeRequest();
      final report = reportOf(reportParseError());

      expect(report.type, 'ParseError');
      expect(report.operation, 'Search failed');
      expect(report.tag, 'search');
      expect(report.pluginId, 'alpha');
      expect(report.pluginVersion, '1.2.0');
      expect(report.cause, contains('bad payload'));
      expect(report.stackTrace, contains('package:alpha/x.js:1'));
      expect(report.appVersion, '2.0.0');
      expect(report.flavor, 'dev');
      expect(report.platform, 'Windows');
      expect(report.osVersion, 'Windows 11 (test)');
      expect(report.time.isUtc, isTrue);
      expect(report.timestamp, endsWith('Z'));
      expect(DateTime.parse(report.timestamp), report.time);
    });

    test('carry the matching network record as the request summary', () {
      writeRequest();
      final request = reportOf(reportParseError()).request;

      expect(request, isNotNull);
      expect(request!.method, 'GET');
      expect(request.url, startsWith('api.example.test/search?'));
      expect(request.url, contains('q=song'));
      expect(request.status, 412);
      expect(request.ms, 830);
      expect(request.error, 'RateLimited');
    });

    test('have no request when the network record is not in the history', () {
      expect(reportOf(reportParseError()).request, isNull);
      writeRequest(id: 99);
      expect(reportOf(reportParseError()).request, isNull);
    });

    test('have no request when the error carries no record id', () {
      writeRequest();
      expect(reportOf(reportParseError(networkRecordId: null)).request, isNull);
    });

    test('have no request for a previous run (empty history is given)', () {
      writeRequest();
      expect(
        reportOf(reportParseError(), networkHistory: const []).request,
        isNull,
      );
    });

    test('ignore a record with the same id from another source', () {
      writeRequest(pluginId: 'beta');
      expect(reportOf(reportParseError()).request, isNull);
    });

    test('ignore a network record newer than the error', () {
      final error = LogRecord(
        time: DateTime.utc(2026, 10, 14, 12),
        level: LogLevel.error,
        tag: 'search',
        message: 'Search failed',
        fields: const {'type': 'ParseError', 'networkRecordId': 7},
      );
      LogRecord request(DateTime time) => LogRecord(
        time: time,
        level: LogLevel.info,
        tag: networkLogTag,
        message: 'HTTP request',
        fields: const {
          'id': 7,
          'method': 'GET',
          'host': 'api.example.test',
          'path': '/search',
        },
      );

      expect(
        reportOf(
          error,
          networkHistory: [request(DateTime.utc(2026, 10, 14, 12, 0, 1))],
        ).request,
        isNull,
      );
      expect(
        reportOf(
          error,
          networkHistory: [request(DateTime.utc(2026, 10, 14, 11, 59, 59))],
        ).request,
        isNotNull,
      );
    });

    test('work without a plugin or a plugin version', () {
      final record = log.report('Load failed', UnexpectedError(), tag: 'app');
      final report = reportOf(record, pluginVersion: null);

      expect(report.pluginId, isNull);
      expect(report.pluginVersion, isNull);
      expect(report.type, 'UnexpectedError');
      final markdown = report.toMarkdown();
      expect(markdown, isNot(contains('Source')));
      expect(markdown, isNot(contains('null')));
    });
  });

  group('markdown', () {
    test('has a heading, a field list and code blocks', () {
      writeRequest();
      final markdown = reportOf(reportParseError()).toMarkdown();

      expect(markdown, startsWith('## ParseError: Search failed\n'));
      expect(markdown, contains('- **Type**: ParseError'));
      expect(markdown, contains('- **Source**: alpha 1.2.0'));
      expect(markdown, contains('- **Action**: Search failed'));
      expect(markdown, contains('- **Request**: GET api.example.test/search?'));
      expect(markdown, contains('- **Status**: 412'));
      expect(markdown, contains('- **Duration**: 830 ms'));
      expect(markdown, contains('- **App**: 2.0.0 (dev)'));
      expect(markdown, contains('- **System**: Windows, Windows 11 (test)'));
      expect(markdown, contains('### Cause\n\n~~~\n'));
      expect(
        markdown,
        contains(
          '### Stack trace\n\n~~~\n#0      parse (package:alpha/x.js:1)',
        ),
      );
    });

    // `bug_report.yml` 的 `render: markdown` 把整個欄位包進反引號的 code block：裡面的 fence
    // 用 `~`，才不會提早結束外層；反引號照原樣留在內容裡。
    test('code blocks use tilde fences, so backticks cannot end them', () {
      final record = log.report(
        'Load failed',
        UnexpectedError(
          cause: StateError('has ``` ticks'),
          stackTrace: StackTrace.fromString('#0 x'),
        ),
        tag: 'app',
      );
      final markdown = reportOf(record).toMarkdown();

      expect(markdown, contains('~~~\nBad state: has ``` ticks\n~~~'));
      expect(
        markdown.split('\n').where((line) => line.startsWith('```')),
        isEmpty,
      );
    });

    test('a fence longer than any tilde run in the content', () {
      final record = log.report(
        'Load failed',
        UnexpectedError(
          cause: StateError('has ~~~~ four tildes'),
          stackTrace: StackTrace.fromString('#0 x'),
        ),
        tag: 'app',
      );
      final markdown = reportOf(record).toMarkdown();

      expect(
        markdown,
        contains('~~~~~\nBad state: has ~~~~ four tildes\n~~~~~'),
      );
    });
  });

  group('redaction', () {
    // 假值從四個入口進來：原因、stack trace、請求的 query、版本字串。
    test('no fake credential survives into the markdown', () {
      writeNetworkRecord(
        log,
        client: NetworkClient.source,
        id: 7,
        pluginId: 'alpha',
        method: 'GET',
        uri: Uri.parse(
          'https://api.example.test/search?q=song&access_key=FAKE_ACCESS_KEY_123'
          '&SESSDATA=FAKE_SESSDATA_123',
        ),
        failed: true,
        credentials: true,
        retry: 0,
        status: 401,
        ms: 10,
      );
      final record = log.report(
        'Stream failed for FAKE_REGISTERED_SECRET_123',
        ParseError(
          pluginId: 'alpha',
          networkRecordId: 7,
          cause: _FakeRequestError(),
          stackTrace: StackTrace.fromString(
            '#0      fetch (package:fmp/x.dart:1)\n'
            '#1      <fn> ($_signedUrl&access_key=FAKE_ACCESS_KEY_123)',
          ),
        ),
        tag: 'playback',
      );
      final report = ErrorReport.fromRecord(
        record!,
        redactor: redactor,
        appVersion: '2.0.0',
        flavor: 'dev',
        platform: 'Windows',
        // 外來欄位（版本字串）也過遮蔽函式。
        osVersion: 'Windows 11 Authorization: Bearer FAKE_BEARER_123',
        pluginVersion: '1.0 token=FAKE_SESSDATA_123',
        networkHistory: log.history,
      );

      // 前提：請求摘要真的接上了，遮蔽測的不是空欄位。
      expect(report.request, isNotNull);
      final markdown = report.toMarkdown();
      for (final value in _fakeValues) {
        expect(markdown, isNot(contains(value)), reason: value);
      }
      expect(markdown, isNot(contains('deadline=1700000000&upsig')));
      for (final field in [
        report.cause,
        report.stackTrace,
        report.request!.url,
        report.osVersion,
        report.pluginVersion,
        report.operation,
      ]) {
        for (final value in _fakeValues) {
          expect(field, isNot(contains(value)), reason: value);
        }
      }
    });

    // 即使紀錄本身沒遮乾淨（例如遮蔽名單之後才登記的值），Markdown 的最後一道也會擋住。
    test('the markdown is redacted again as a whole', () {
      final record = LogRecord(
        time: DateTime.utc(2026, 10, 14),
        level: LogLevel.error,
        tag: 'search',
        message: 'Search failed',
        error: 'late secret FAKE_LATE_SECRET_123 leaked',
        fields: const {'type': 'ParseError'},
      );
      final late = Redactor()..registerSecret('FAKE_LATE_SECRET_123');
      final markdown = ErrorReport.fromRecord(
        record,
        redactor: late,
        appVersion: '2.0.0',
        flavor: 'dev',
        platform: 'Windows',
        osVersion: 'x',
      ).toMarkdown();

      expect(markdown, isNot(contains('FAKE_LATE_SECRET_123')));
      expect(markdown, contains('late secret'));
    });

    // 頁面顯示的是欄位，不是 Markdown：欄位在組報告時就再遮一次，顯示與複製是同一份。
    test('every field is redacted again when the report is assembled', () {
      const secret = 'FAKE_LATE_SECRET_123';
      final record = LogRecord(
        time: DateTime.utc(2026, 10, 14),
        level: LogLevel.error,
        tag: 'search $secret',
        message: 'Search failed $secret',
        error: 'cause $secret',
        stackTrace: '#0 x ($secret)',
        fields: const {
          'type': 'ParseError',
          'pluginId': 'alpha',
          'networkRecordId': 7,
        },
      );
      final request = LogRecord(
        time: DateTime.utc(2026, 10, 13),
        level: LogLevel.info,
        tag: networkLogTag,
        message: 'HTTP request',
        fields: const {
          'id': 7,
          'pluginId': 'alpha',
          'method': 'GET',
          'host': 'api.example.test',
          'path': '/search/$secret',
          'query': 'q=$secret',
          'error': 'ParseError $secret',
        },
      );
      final report = ErrorReport.fromRecord(
        record,
        redactor: Redactor()..registerSecret(secret),
        appVersion: '2.0.0',
        flavor: 'dev',
        platform: 'Windows',
        osVersion: 'x',
        networkHistory: [request],
      );

      expect(report.request, isNotNull);
      for (final field in [
        report.operation,
        report.tag,
        report.cause,
        report.stackTrace,
        report.request!.url,
        report.request!.error,
      ]) {
        expect(field, isNot(contains(secret)));
        expect(field, contains('***'));
      }
    });
  });
}

final class _FakeRequestError implements Exception {
  @override
  String toString() =>
      'Request failed: Cookie: SESSDATA=FAKE_SESSDATA_123; '
      'Authorization: Bearer FAKE_BEARER_123 for $_signedUrl '
      'and FAKE_REGISTERED_SECRET_123';
}
