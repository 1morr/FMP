import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:path/path.dart' as p;

// 所有憑證都是明顯的假值（FAKE_…），不得換成真實值。
const _fakeValues = ['FAKE_SESSDATA_123', 'FAKE_ACCESS_KEY_123'];

void main() {
  late Directory temp;
  late Log log;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fmp_report_error_test');
    addTearDown(() => temp.delete(recursive: true));
    log = Log(
      redactor: Redactor(),
      minimumLevel: LogLevel.debug,
      file: LogFile(Directory(p.join(temp.path, logDirectoryName))),
    );
  });

  test('expected errors are warnings, bugs are errors', () {
    log
      ..report('Search failed', NetworkError(), tag: 'search')
      ..report('Search failed', ParseError(), tag: 'search');

    expect(log.history.map((r) => r.level), [LogLevel.warning, LogLevel.error]);
  });

  test('an explicit level (uncaught errors only) overrides expected', () {
    log.report(
      'Uncaught error',
      NetworkError(),
      tag: 'platform',
      level: LogLevel.error,
    );

    expect(log.history.single.level, LogLevel.error);
  });

  test('writes the structured fields', () {
    log.report(
      'Stream failed',
      Unavailable(
        reason: UnavailableReason.region,
        pluginId: 'bilibili',
        networkRecordId: 12,
        retryAfter: const Duration(seconds: 3),
      ),
      tag: 'playback',
    );

    final [record] = log.history;
    expect(record.tag, 'playback');
    expect(record.message, 'Stream failed');
    expect(record.fields, {
      'type': 'Unavailable',
      'pluginId': 'bilibili',
      'reason': 'region',
      'networkRecordId': 12,
      'retryable': false,
      'retryAfterMs': 3000,
    });
  });

  test('leaves out fields that have no value', () {
    log.report('Failed', AuthRequired(), tag: 'library');

    expect(log.history.single.fields, {
      'type': 'AuthRequired',
      'retryable': false,
    });
  });

  test(
    'the cause and its stack trace reach the log through redaction',
    () async {
      final error = AppError.wrap(
        const HttpException(
          '412 for https://api.example.com/x?access_key=FAKE_ACCESS_KEY_123 '
          '(Cookie: SESSDATA=FAKE_SESSDATA_123)',
        ),
        StackTrace.fromString(
          '#0 fetch (package:fmp/x.dart:1)\n'
          '#1 <fn> (Cookie: SESSDATA=FAKE_SESSDATA_123)',
        ),
        pluginId: 'bilibili',
      );

      log.report('Search failed', error, tag: 'search');

      final [record] = log.history;
      expect(record.level, LogLevel.error);
      expect(record.error, contains('HttpException: 412'));
      expect(record.stackTrace, contains('#0 fetch'));
      await log.file!.flush();
      final file = await log.file!.currentFile.readAsString();
      final history = record.toJsonLine();
      for (final value in _fakeValues) {
        expect(history, isNot(contains(value)), reason: 'history');
        expect(file, isNot(contains(value)), reason: 'log file');
      }
      expect(history, contains(redactedValue));
      expect(file, contains(redactedValue));
    },
  );

  test('an error without a cause has no error or stack trace', () {
    log.report('Not found', NotFound(pluginId: 'youtube'), tag: 'library');

    final [record] = log.history;
    expect(record.error, isNull);
    expect(record.stackTrace, isNull);
  });
}
