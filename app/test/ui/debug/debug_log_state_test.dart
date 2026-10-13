import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/ui/debug/debug_log_state.dart';
import 'package:path/path.dart' as p;

LogRecord _record(
  int second,
  String message, {
  LogLevel level = LogLevel.info,
  String tag = 'app',
  Map<String, Object?> fields = const {},
  String? error,
  String? stackTrace,
}) => LogRecord(
  time: DateTime.utc(2026, 10, 13, 12, 0, second),
  level: level,
  tag: tag,
  message: message,
  fields: fields,
  error: error,
  stackTrace: stackTrace,
);

List<String> _messages(List<LogRecord> records) => [
  for (final record in records) record.message,
];

void main() {
  group('mergeLogRecords', () {
    test('orders by time and drops a record that is in both lists', () {
      final shared = _record(3, 'shared', fields: {'k': 1});
      final stored = [_record(1, 'old'), shared, _record(5, 'last stored')];
      // 同一筆從檔案讀回來是另一個物件，內容相同。
      final sameFromMemory = LogRecord.tryParseJsonLine(shared.toJsonLine())!;
      final memory = [sameFromMemory, _record(4, 'new')];

      expect(_messages(mergeLogRecords(stored, memory)), [
        'old',
        'shared',
        'new',
        'last stored',
      ]);
    });

    // 錯誤詳細頁靠物件身分判斷「這次執行的紀錄」（才對網路紀錄）：重複的那筆要是記憶體的。
    test('a record in both lists is the memory instance', () {
      final shared = _record(3, 'shared', fields: {'k': 1});
      final fromFile = LogRecord.tryParseJsonLine(shared.toJsonLine())!;

      final merged = mergeLogRecords([fromFile], [shared]);

      expect(merged, hasLength(1));
      expect(merged.single, same(shared));
    });

    test('keeps records that only differ in a field or in the time', () {
      final a = _record(1, 'x', fields: {'n': 1});
      final b = _record(1, 'x', fields: {'n': 2});
      final c = LogRecord(
        time: DateTime.utc(2026, 10, 13, 12, 0, 1, 0, 1),
        level: LogLevel.info,
        tag: 'app',
        message: 'x',
        fields: {'n': 1},
      );

      expect(mergeLogRecords([a], [b, c]), hasLength(3));
    });

    test('equal times keep the order: stored first, then memory', () {
      final merged = mergeLogRecords(
        [_record(1, 'stored a'), _record(1, 'stored b')],
        [_record(1, 'memory')],
      );

      expect(_messages(merged), ['stored a', 'stored b', 'memory']);
    });

    // 整條路：這次執行寫的每一筆同時在記憶體和 log 檔，合併後不重複；下次啟動再合併，
    // 上次的在前、這次的在後。
    test('a run and the next run, through a real log file', () async {
      final temp = await Directory.systemTemp.createTemp('fmp_merge_test');
      addTearDown(() => temp.delete(recursive: true));
      Log newLog() => Log(
        redactor: Redactor(),
        minimumLevel: LogLevel.debug,
        file: LogFile(Directory(p.join(temp.path, 'logs'))),
      );

      final first = newLog()..info('run 1 a', tag: 't', fields: {'n': 1});
      first.warning('run 1 b', tag: 't', error: 'boom');
      final firstMerged = mergeLogRecords(
        await first.file!.readStored(),
        first.history,
      );
      expect(_messages(firstMerged), ['run 1 a', 'run 1 b']);

      final second = newLog()..info('run 2', tag: 't');
      final secondMerged = mergeLogRecords(
        await second.file!.readStored(),
        second.history,
      );
      expect(_messages(secondMerged), ['run 1 a', 'run 1 b', 'run 2']);
    });
  });

  group('LogFilter', () {
    final records = [
      _record(1, 'alpha', level: LogLevel.debug, tag: 'net'),
      _record(2, 'Beta thing', tag: 'app'),
      _record(3, 'gamma', level: LogLevel.warning, tag: 'net'),
      _record(
        4,
        'delta',
        level: LogLevel.error,
        tag: 'app',
        fields: {'type': 'ParseError'},
      ),
    ];

    List<String> apply(LogFilter filter) => _messages([
      for (final r in records)
        if (filter.matches(r)) r,
    ]);

    test('shows everything by default', () {
      expect(apply(const LogFilter()), [
        'alpha',
        'Beta thing',
        'gamma',
        'delta',
      ]);
    });

    test('the level is a minimum', () {
      expect(apply(const LogFilter(level: LogLevel.info)), [
        'Beta thing',
        'gamma',
        'delta',
      ]);
      expect(apply(const LogFilter(level: LogLevel.error)), ['delta']);
    });

    test('errors only is the warning and error history', () {
      expect(apply(const LogFilter(errorsOnly: true)), ['gamma', 'delta']);
    });

    test('the tag is exact', () {
      expect(apply(const LogFilter(tag: 'net')), ['alpha', 'gamma']);
      expect(apply(const LogFilter(tag: 'ne')), isEmpty);
    });

    test('the text ignores case and also looks at the fields', () {
      expect(apply(const LogFilter(text: 'BETA')), ['Beta thing']);
      expect(apply(const LogFilter(text: 'parseerror')), ['delta']);
      expect(apply(const LogFilter(text: 'nothing')), isEmpty);
    });

    test('the filters combine', () {
      expect(apply(const LogFilter(tag: 'app', level: LogLevel.warning)), [
        'delta',
      ]);
    });
  });

  group('formatLogRecord', () {
    test('one line without details', () {
      expect(
        formatLogRecord(_record(1, 'hello', tag: 'app')),
        '2026-10-13T12:00:01.000Z info [app] hello',
      );
    });

    test('details follow on indented lines', () {
      final text = formatLogRecord(
        _record(
          1,
          'failed',
          level: LogLevel.error,
          fields: {'n': 1},
          error: 'boom',
          stackTrace: '#0 main',
        ),
      );

      expect(text.split('\n'), [
        '2026-10-13T12:00:01.000Z error [app] failed',
        '  fields: {"n":1}',
        '  error: boom',
        '  stackTrace:',
        '#0 main',
      ]);
    });
  });
}
