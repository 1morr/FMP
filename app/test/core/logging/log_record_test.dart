import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';

void main() {
  final record = LogRecord(
    time: DateTime.utc(2026, 9, 29, 1, 2, 3, 456),
    level: LogLevel.warning,
    tag: 'app',
    message: 'Something happened',
    error: 'StateError: bad',
    stackTrace: '#0 main (file.dart:1)',
    fields: const {
      'count': 2,
      'nested': {
        'list': [1, 'a', null],
      },
    },
  );

  group('stored format', () {
    // log 檔的格式（ADR 0025 §決定 3）：Debug 頁在 M3 讀之前的檔案。
    test('is pinned', () {
      expect(
        record.toJsonLine(),
        '{"time":"2026-09-29T01:02:03.456Z","level":"warning","tag":"app",'
        '"message":"Something happened","error":"StateError: bad",'
        '"stackTrace":"#0 main (file.dart:1)",'
        '"fields":{"count":2,"nested":{"list":[1,"a",null]}}}',
      );
    });

    test('leaves out an empty error, stack trace and fields', () {
      final minimal = LogRecord(
        time: DateTime.utc(2026),
        level: LogLevel.debug,
        tag: 't',
        message: 'm',
      );
      expect(
        minimal.toJsonLine(),
        '{"time":"2026-01-01T00:00:00.000Z","level":"debug","tag":"t",'
        '"message":"m"}',
      );
    });

    test('every level has its own wire name', () {
      expect(LogLevel.values.map((level) => level.wireName), [
        'debug',
        'info',
        'warning',
        'error',
      ]);
    });
  });

  test('a written line reads back with the same fields', () {
    final parsed = LogRecord.tryParseJsonLine(record.toJsonLine())!;

    expect(parsed.time, record.time);
    expect(parsed.time.isUtc, isTrue);
    expect(parsed.level, record.level);
    expect(parsed.tag, record.tag);
    expect(parsed.message, record.message);
    expect(parsed.error, record.error);
    expect(parsed.stackTrace, record.stackTrace);
    expect(parsed.fields, record.fields);
  });

  test('parseLogLines skips bad lines without stopping', () {
    final good = record.toJsonLine();
    final content = [
      good,
      '{"time":"2026-09-29T01:02:03.456Z","level":"warn',
      'not json at all',
      '[1, 2]',
      '{"time":"yesterday","level":"info","tag":"t","message":"m"}',
      '{"time":"2026-09-29T01:02:03Z","level":"fatal","tag":"t","message":"m"}',
      '{"time":"2026-09-29T01:02:03Z","level":"info","tag":"t","message":1}',
      '',
      good,
    ].join('\r\n');

    final records = parseLogLines(content);

    expect(records, hasLength(2));
    expect(records.map((r) => r.toJsonLine()), [good, good]);
  });

  group('redactLogLines', () {
    // 家目錄與憑證都是明顯的假值，不得換成真實值。
    const home = r'C:\Users\FAKE_USER';
    const secret = 'FAKE_SESSDATA_123';

    /// 登記之前寫進檔案的一行：原值都還在。
    String before() => LogRecord(
      time: DateTime.utc(2026, 10, 1),
      level: LogLevel.info,
      tag: 'app',
      message: 'App started at $home\\AppData\\fmp',
      error: 'token $secret',
      stackTrace: '#0 main ($home/fmp/lib/main.dart:1)',
      fields: {
        'dataDirectory': '$home\\AppData\\fmp',
        'nested': [
          {'path': '$home\\logs', 'value': secret},
        ],
      },
    ).toJsonLine();

    test('masks values registered after the line was written', () {
      final redactor = Redactor()
        ..registerHomeDirectory(home)
        ..registerSecret(secret);
      final raw = before();
      // 登記之前寫的行：JSON 裡反斜線是兩個，使用者名稱還在。
      expect(raw, contains(r'C:\\Users\\FAKE_USER'));

      final output = redactLogLines('$raw\n', redactor);

      expect(output, isNot(contains('FAKE_USER')));
      expect(output, isNot(contains(secret)));
      final record = LogRecord.tryParseJsonLine(output.trim())!;
      expect(record.message, r'App started at ~\AppData\fmp');
      expect(record.stackTrace, '#0 main (~/fmp/lib/main.dart:1)');
      expect(record.fields['dataDirectory'], r'~\AppData\fmp');
      expect(record.fields['nested'], [
        {'path': r'~\logs', 'value': '***'},
      ]);
    });

    test('keeps JSON Lines: one record per line, bad lines masked', () {
      final redactor = Redactor()..registerHomeDirectory(home);
      final content = [
        before(),
        '',
        // 寫到一半被截斷的行：不是 JSON，整行遮蔽後照樣留著。
        r'{"time":"2026-10-01T00:00:00.000Z","message":"C:\\Users\\FAKE_USER\\x',
        before(),
      ].join('\n');

      final lines = redactLogLines(content, redactor).split('\n');

      expect(lines, hasLength(4));
      expect(lines.last, isEmpty);
      expect(LogRecord.tryParseJsonLine(lines[0]), isNotNull);
      expect(lines[1], r'{"time":"2026-10-01T00:00:00.000Z","message":"~\\x');
      expect(LogRecord.tryParseJsonLine(lines[2]), isNotNull);
    });

    test('an already masked line comes out unchanged', () {
      final redactor = Redactor()
        ..registerHomeDirectory(home)
        ..registerSecret(secret);
      final masked = redactLogLines(before(), redactor);

      expect(redactLogLines(masked, redactor), masked);
    });
  });
}
