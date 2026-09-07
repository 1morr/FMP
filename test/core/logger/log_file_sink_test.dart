import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log_file_sink.dart';
import 'package:fmp/core/logger.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fmp_log_sink_test_');
    AppLogger.clearLogs();
    AppLogger.detachFileSink();
  });

  tearDown(() async {
    AppLogger.detachFileSink();
    AppLogger.clearLogs();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  LogFileSink sinkWith({int maxBytes = 2 * 1024 * 1024, int keptFiles = 3}) {
    return LogFileSink(
      directory: Directory('${tempDir.path}/logs'),
      maxBytes: maxBytes,
      keptFiles: keptFiles,
    );
  }

  group('LogFileSink', () {
    test('creates the directory and appends lines', () async {
      final sink = sinkWith();
      await sink.open();
      sink
        ..write('first')
        ..write('second');
      await sink.flush();

      expect(await sink.readAll(), 'first\nsecond\n');
    });

    test('rotates once the current file would exceed the size cap', () async {
      final sink = sinkWith(maxBytes: 40);
      await sink.open();
      for (var i = 0; i < 6; i++) {
        sink.write('0123456789012345678'); // 20 bytes with the newline
      }
      await sink.flush();

      final files = await sink.filesOldestFirst();
      expect(files, hasLength(3));
      expect(files.last.path, endsWith('fmp.log'));
      expect(files.first.path, endsWith('fmp.2.log'));
    });

    test('keeps at most keptFiles files and drops the oldest', () async {
      final sink = sinkWith(maxBytes: 20, keptFiles: 2);
      await sink.open();
      for (var i = 0; i < 8; i++) {
        sink.write('line $i padded out');
      }
      await sink.flush();

      final files = await sink.filesOldestFirst();
      expect(files, hasLength(2));
      expect(
        await File('${tempDir.path}/logs/fmp.2.log').exists(),
        isFalse,
        reason: 'keptFiles = 2 must not leave a third generation behind',
      );
    });

    test('readAll returns rotated content oldest first', () async {
      final sink = sinkWith(maxBytes: 20);
      await sink.open();
      sink
        ..write('oldest entry here')
        ..write('newest entry here');
      await sink.flush();

      expect(await sink.readAll(), 'oldest entry here\nnewest entry here\n');
    });

    test('write is a no-op when the sink never opened', () async {
      final sink = LogFileSink(directory: Directory('${tempDir.path}/logs'));
      sink.write('dropped');
      await sink.flush();

      expect(await Directory('${tempDir.path}/logs').exists(), isFalse);
    });
  });

  group('AppLogger file sink', () {
    test('backfills the in-memory buffer when the sink is attached', () async {
      AppLogger.info('before the sink existed', 'Startup');

      final sink = sinkWith();
      await AppLogger.attachFileSink(sink);
      await sink.flush();

      expect(await sink.readAll(), contains('before the sink existed'));
    });

    test('writes new entries through to disk', () async {
      final sink = sinkWith();
      await AppLogger.attachFileSink(sink);
      AppLogger.warning('after attaching', 'Test');
      await sink.flush();

      final contents = await sink.readAll();
      expect(contents, contains('after attaching'));
      expect(contents, contains('[W]'));
    });

    test('what lands on disk is redacted', () async {
      final sink = sinkWith();
      await AppLogger.attachFileSink(sink);
      AppLogger.info(
        'Cookie: SESSDATA=abc123secret; bili_jct=deadbeef',
        'Test',
      );
      AppLogger.error(
        'request failed',
        'Authorization: Bearer tok_should_not_survive',
        null,
        'Test',
      );
      await sink.flush();

      final contents = await sink.readAll();
      expect(contents, contains('[REDACTED]'));
      expect(contents, isNot(contains('abc123secret')));
      expect(contents, isNot(contains('deadbeef')));
      expect(contents, isNot(contains('tok_should_not_survive')));
    });

    test(
      'error and stack trace reach the file, unlike the on-screen line',
      () async {
        final sink = sinkWith();
        await AppLogger.attachFileSink(sink);
        AppLogger.error(
          'boom',
          StateError('inner cause'),
          StackTrace.fromString('#0 someFrame'),
          'Test',
        );
        await sink.flush();

        final contents = await sink.readAll();
        expect(contents, contains('inner cause'));
        expect(contents, contains('someFrame'));
      },
    );
  });
}
