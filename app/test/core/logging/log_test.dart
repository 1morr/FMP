import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:path/path.dart' as p;

// 所有憑證都是明顯的假值（FAKE_…），不得換成真實值。
const _fakeValues = [
  'FAKE_SESSDATA_123',
  'FAKE_BILI_JCT_123',
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
  late Directory temp;
  late Redactor redactor;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fmp_log_test');
    addTearDown(() => temp.delete(recursive: true));
    redactor = Redactor()..registerSecret('FAKE_REGISTERED_SECRET_123');
  });

  Log newLog({LogLevel minimumLevel = LogLevel.debug, LogFile? file}) => Log(
    redactor: redactor,
    minimumLevel: minimumLevel,
    file: file ?? LogFile(Directory(p.join(temp.path, logDirectoryName))),
  );

  Future<String> fileContent(Log log) async {
    await log.file!.flush();
    return log.file!.currentFile.readAsString();
  }

  group('no fake credential survives into the history or the log file', () {
    final cases = <String, void Function(Log log)>{
      'message': (log) => log.info(
        'Cookie: SESSDATA=FAKE_SESSDATA_123 then $_signedUrl and '
        'FAKE_REGISTERED_SECRET_123',
        tag: 'test',
      ),
      'error toString': (log) =>
          log.error('Request failed', tag: 'test', error: _FakeRequestError()),
      'stack trace only': (log) => log.error(
        'Request failed',
        tag: 'test',
        stackTrace: StackTrace.fromString(
          '#0      fetch (package:fmp/x.dart:1)\n'
          '#1      <fn> ($_signedUrl&access_key=FAKE_ACCESS_KEY_123)',
        ),
      ),
      'deep structured fields': (log) => log.warning(
        'Slow request',
        tag: 'test',
        fields: {
          'request': {
            'headers': {
              'Cookie': 'SESSDATA=FAKE_SESSDATA_123',
              'Authorization': 'Bearer FAKE_BEARER_123',
            },
            'attempts': [
              {'url': _signedUrl},
              {'body': 'bili_jct=FAKE_BILI_JCT_123&x=1'},
              ['nested', 'FAKE_REGISTERED_SECRET_123'],
            ],
          },
        },
      ),
    };

    for (final MapEntry(key: name, value: write) in cases.entries) {
      test(name, () async {
        final log = newLog();

        write(log);

        final history = log.history.map((r) => r.toJsonLine()).join('\n');
        final file = await fileContent(log);
        expect(history, isNotEmpty);
        expect(file, isNotEmpty);
        for (final value in _fakeValues) {
          expect(history, isNot(contains(value)), reason: 'history');
          expect(file, isNot(contains(value)), reason: 'log file');
        }
        expect('$history$file', contains(redactedValue));
      });
    }
  });

  test('keeps the unredacted parts of a record', () async {
    final log = newLog();

    log.warning(
      'Slow request',
      tag: 'network',
      error: StateError('timeout'),
      stackTrace: StackTrace.fromString('#0 main (a.dart:1)'),
      fields: {'ms': 1200},
    );

    final [record] = log.history;
    expect(record.level, LogLevel.warning);
    expect(record.tag, 'network');
    expect(record.message, 'Slow request');
    expect(record.error, 'Bad state: timeout');
    expect(record.stackTrace, '#0 main (a.dart:1)');
    expect(record.fields, {'ms': 1200});
    expect(record.time.isUtc, isTrue);
    expect(
      parseLogLines(await fileContent(log)).single.toJsonLine(),
      record.toJsonLine(),
    );
  });

  test('drops records below the minimum level everywhere', () async {
    final log = newLog(minimumLevel: LogLevel.info);

    log
      ..debug('hidden', tag: 't')
      ..info('shown', tag: 't');

    expect(log.history.map((r) => r.message), ['shown']);
    expect(parseLogLines(await fileContent(log)).map((r) => r.message), [
      'shown',
    ]);
  });

  test('the memory history keeps the latest ${Log.historyLimit}', () {
    final log = Log(redactor: redactor, minimumLevel: LogLevel.debug);

    for (var i = 0; i < Log.historyLimit + 5; i++) {
      log.debug('$i', tag: 't');
    }

    expect(log.history, hasLength(Log.historyLimit));
    expect(log.history.first.message, '5');
    expect(log.history.last.message, '${Log.historyLimit + 4}');
  });

  test(
    'a record that cannot be redacted is dropped, not written raw',
    () async {
      final log = newLog();

      log.error(
        'Cookie: SESSDATA=FAKE_SESSDATA_123',
        tag: 'test',
        error: _FakeRequestError(),
        fields: {'items': _ThrowingIterable()},
      );

      final [record] = log.history;
      expect(record.level, LogLevel.error);
      expect(record.message, 'Redaction failed; record dropped');
      final file = await fileContent(log);
      for (final value in _fakeValues) {
        expect(record.toJsonLine(), isNot(contains(value)));
        expect(file, isNot(contains(value)));
      }
    },
  );

  test('a log file that cannot be written does not affect logging', () async {
    final blocker = File(p.join(temp.path, 'blocked'))..writeAsStringSync('');
    final log = newLog(file: LogFile(Directory(blocker.path)));

    log.error('still recorded', tag: 't');
    await log.file!.flush();

    expect(log.history.single.message, 'still recorded');
    expect(log.file!.failureCount, 1);
  });
}

/// 錯誤訊息帶著憑證的例外（例如把請求整個印出來的 HTTP 例外）。
final class _FakeRequestError implements Exception {
  @override
  String toString() =>
      'HttpException: 412 for $_signedUrl&access_key=FAKE_ACCESS_KEY_123 '
      '(Cookie: SESSDATA=FAKE_SESSDATA_123; bili_jct=FAKE_BILI_JCT_123)';
}

/// 遍歷時拋錯的 Iterable：遮蔽函式走到它就失敗。
final class _ThrowingIterable extends Iterable<Object?> {
  @override
  Iterator<Object?> get iterator => throw StateError('FAKE_SESSDATA_123');
}
