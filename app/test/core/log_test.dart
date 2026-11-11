import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fmp_log_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  File current() => File('${dir.path}/${Log.fileName}');

  test('writes each record as a line in fmp.log', () async {
    final log = await Log.open(dir, minimumLevel: LogLevel.debug);
    log.info('App started');
    log.warning('Search failed', error: const RateLimited());
    await log.close();

    final lines = current().readAsLinesSync();
    expect(lines, hasLength(2));
    expect(
      lines[0],
      matches(
        RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+Z INFO App started$'),
      ),
    );
    expect(lines[1], endsWith('WARNING Search failed | RateLimited'));
  });

  test('appends to the file left by an earlier run', () async {
    final first = await Log.open(dir, minimumLevel: LogLevel.debug);
    first.info('first run');
    await first.close();
    final second = await Log.open(dir, minimumLevel: LogLevel.debug);
    second.info('second run');
    await second.close();

    final text = current().readAsStringSync();
    expect(text, contains('first run'));
    expect(text, contains('second run'));
  });

  test(
    'redacts the message, the error and the stack trace before writing',
    () async {
      final log = await Log.open(dir, minimumLevel: LogLevel.debug);
      log.error(
        'GET https://cdn.example.com/a.m4s?upsig=FAKE_SIG failed',
        error: 'DioException: Cookie: SESSDATA=FAKE_SESS',
        stackTrace: StackTrace.fromString('#0 send (token=FAKE_TOKEN)'),
      );
      await log.close();

      final text = current().readAsStringSync();
      expect(text, isNot(contains('FAKE')));
      expect(text, contains('Cookie: ***'));
      expect(text, contains('upsig=***'));
      expect(text, contains('#0 send (token=***)'));
    },
  );

  test('the console copy is redacted too', () async {
    final printed = <String>[];
    await runZoned(
      () async {
        final log = await Log.open(
          dir,
          minimumLevel: LogLevel.debug,
          console: true,
        );
        log.info('Authorization: Bearer FAKE_TOKEN_1');
        await log.close();
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );

    expect(printed.join('\n'), contains('Authorization: ***'));
    expect(printed.join('\n'), isNot(contains('FAKE')));
  });

  group('minimum level', () {
    test('release builds keep info and above', () async {
      expect(minimumLogLevel(release: true), LogLevel.info);
      expect(minimumLogLevel(release: false), LogLevel.debug);

      final log = await Log.open(dir, minimumLevel: LogLevel.info);
      log.debug('cache hit');
      log.info('App started');
      log.error('Playback failed');
      await log.close();

      final text = current().readAsStringSync();
      expect(text, isNot(contains('cache hit')));
      expect(text, contains('App started'));
      expect(text, contains('Playback failed'));
    });
  });

  group('rotation keeps at most three files', () {
    List<File> logFiles() =>
        dir.listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('defaults to 2 MB × 3', () {
      expect(Log.defaultMaxFileKB, 2048);
      expect(Log.defaultKeptFiles, 3);
    });

    test('an oversized fmp.log is rotated when the log opens', () async {
      current().writeAsStringSync('old run\n' * 300); // 約 2.4 KB

      final log = await Log.open(
        dir,
        minimumLevel: LogLevel.debug,
        maxFileKB: 2,
      );
      log.info('new run');
      await log.close();

      expect(current().readAsStringSync(), isNot(contains('old run')));
      expect(current().readAsStringSync(), contains('new run'));
      final rotated = logFiles().where((f) => f.path != current().path);
      expect(rotated, hasLength(1));
      expect(rotated.single.readAsStringSync(), startsWith('old run'));
    });

    test('the oldest rotated file is deleted beyond the limit', () async {
      final now = DateTime.now();
      for (final (i, name) in ['a.log', 'b.log'].indexed) {
        File('${dir.path}/$name')
          ..writeAsStringSync('rotated $name')
          ..setLastModifiedSync(now.subtract(Duration(hours: 10 - i)));
      }
      current().writeAsStringSync('x' * 3000);

      final log = await Log.open(
        dir,
        minimumLevel: LogLevel.debug,
        maxFileKB: 2,
      );
      await log.close();

      final names = logFiles().map((f) => f.uri.pathSegments.last).toList();
      expect(names, hasLength(3));
      expect(names, contains('fmp.log'));
      expect(names, isNot(contains('a.log')), reason: 'a.log is the oldest');
      expect(names, contains('b.log'));
    });

    test('a file that grows past the limit while running is rotated', () async {
      final log = await Log.open(
        dir,
        minimumLevel: LogLevel.debug,
        maxFileKB: 1,
        rotationCheck: const Duration(milliseconds: 20),
      );
      // 每一批都超過 1 KB；等它被輪進某個舊檔、不在 fmp.log 裡，再寫下一批。
      bool rotatedAway(String text) => logFiles().any((f) {
        if (f.path == current().path) return false;
        try {
          return f.readAsStringSync().contains(text);
        } on FileSystemException {
          return false; // 剛好在列出之後被輪替刪掉
        }
      });
      for (var batch = 0; batch < 4; batch++) {
        log.info('batch $batch ${'x' * 1100}');
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!rotatedAway('batch $batch')) {
          if (DateTime.now().isAfter(deadline)) {
            fail('batch $batch not rotated');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      await log.close();

      final text = logFiles().map((f) => f.readAsStringSync()).join();
      expect(logFiles(), hasLength(3));
      expect(text, isNot(contains('batch 0')));
      expect(text, contains('batch 3'));
    });
  });
}
