import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log_record.dart';

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
}
