import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fmp_log_file_test');
    addTearDown(() => temp.delete(recursive: true));
  });

  List<String> logFileNames(Directory directory) =>
      directory.listSync().map((entity) => p.basename(entity.path)).toList()
        ..sort();

  test('creates the directory and appends one line per write', () async {
    final file = LogFile(Directory(p.join(temp.path, 'logs')));

    file
      ..write('{"n":1}')
      ..write('{"n":2}');
    await file.flush();
    file.write('{"n":3}');
    await file.flush();

    expect(p.basename(file.currentFile.path), 'fmp.jsonl');
    expect(await file.currentFile.readAsLines(), [
      '{"n":1}',
      '{"n":2}',
      '{"n":3}',
    ]);
    expect(file.failureCount, 0);
  });

  test('rotates past 2MB and keeps at most 3 files', () async {
    final directory = Directory(p.join(temp.path, 'logs'));
    final file = LogFile(directory);
    // 每行 1KB（含換行），寫約 7MB：會輪替三次以上。
    final line = 'x' * 1023;
    for (var i = 0; i < 7 * 1024; i++) {
      file.write(line);
      if (i % 512 == 0) await file.flush();
    }
    await file.flush();

    expect(logFileNames(directory), [
      'fmp.1.jsonl',
      'fmp.2.jsonl',
      'fmp.jsonl',
    ]);
    for (final entity in directory.listSync().whereType<File>()) {
      expect(entity.lengthSync(), lessThanOrEqualTo(2 * 1024 * 1024));
    }
    expect(
      directory.listSync().whereType<File>().fold<int>(
        0,
        (sum, f) => sum + f.lengthSync(),
      ),
      greaterThan(4 * 1024 * 1024),
    );
    expect(file.failureCount, 0);
  });

  test('the size limit counts UTF-8 bytes, not characters', () async {
    final directory = Directory(p.join(temp.path, 'logs'));
    // 「中文字」是 3 個字元、9 個位元組；加換行 10 個位元組，正好到上限。
    final file = LogFile(directory, maxBytes: 10);

    file
      ..write('中文字')
      ..write('a');
    await file.flush();

    expect(logFileNames(directory), ['fmp.1.jsonl', 'fmp.jsonl']);
    expect(await File(p.join(directory.path, 'fmp.1.jsonl')).readAsLines(), [
      '中文字',
    ]);
    expect(await file.currentFile.readAsLines(), ['a']);
  });

  test('keeps counting from an existing file after a restart', () async {
    final directory = Directory(p.join(temp.path, 'logs'));
    final first = LogFile(directory, maxBytes: 10);
    first.write('12345678');
    await first.flush();

    final second = LogFile(directory, maxBytes: 10);
    second.write('abc');
    await second.flush();

    expect(logFileNames(directory), ['fmp.1.jsonl', 'fmp.jsonl']);
    expect(await second.currentFile.readAsLines(), ['abc']);
  });

  test('a failed write does not throw and is counted', () async {
    // 目錄的位置已經是一個檔案：建不了目錄，也寫不進去。
    final blocker = File(p.join(temp.path, 'logs'))..writeAsStringSync('');
    final file = LogFile(Directory(blocker.path));

    file.write('{"n":1}');
    await file.flush();
    file.write('{"n":2}');
    await file.flush();

    expect(file.failureCount, 2);
    expect(file.lastFailure, isA<FileSystemException>());
  });

  // ADR 0025 §決定 3：最後修改超過 7 天的輪替檔刪掉，與大小輪替並存。
  group('retention', () {
    final now = DateTime.utc(2026, 10, 2, 12);
    late Directory logs;
    late LogFile file;
    setUp(() {
      logs = Directory(p.join(temp.path, 'logs'))..createSync();
      file = LogFile(logs, maxBytes: 100, keptFiles: 3);
    });

    File make(String name, Duration age, {Directory? in_}) =>
        File(p.join((in_ ?? logs).path, name))
          ..writeAsStringSync('{}\n')
          ..setLastModifiedSync(now.subtract(age));

    Future<int> run() =>
        withClock(Clock.fixed(now), () => file.deleteExpired());

    test(
      'deletes rotated files older than 7 days and keeps newer ones',
      () async {
        final old = make('fmp.2.jsonl', const Duration(days: 7, minutes: 1));
        final recent = make('fmp.1.jsonl', const Duration(days: 6, hours: 23));
        // 比 keptFiles 多的編號（以前留下的）也算輪替檔。
        final stray = make('fmp.7.jsonl', const Duration(days: 8));

        expect(await run(), 2);
        expect(old.existsSync(), isFalse);
        expect(stray.existsSync(), isFalse);
        expect(recent.existsSync(), isTrue);
      },
    );

    test('never deletes the file being written', () async {
      final current = make('fmp.jsonl', const Duration(days: 30));
      expect(await run(), 0);
      expect(current.existsSync(), isTrue);
    });

    test('leaves other files and other directories alone', () async {
      const age = Duration(days: 30);
      final others = [
        make('notes.txt', age),
        make('fmp.jsonl.bak', age),
        make('other.1.jsonl', age),
        make('fmp-extra.jsonl', age),
        make('fmp.1.jsonl', age, in_: temp),
      ];
      final nestedDirectory = Directory(p.join(logs.path, 'nested'))
        ..createSync();
      final nested = make('fmp.1.jsonl', age, in_: nestedDirectory);

      expect(await run(), 0);
      for (final other in [...others, nested]) {
        expect(other.existsSync(), isTrue, reason: other.path);
      }
    });

    test('a missing directory is a no-op', () async {
      logs.deleteSync(recursive: true);
      expect(await run(), 0);
    });

    test('works together with size rotation', () async {
      for (var i = 0; i < 12; i++) {
        file.write('x' * 60);
      }
      await file.flush();
      expect(logFileNames(logs), ['fmp.1.jsonl', 'fmp.2.jsonl', 'fmp.jsonl']);
      // 大小輪替先限制到 3 個；天數再把過期的舊檔刪掉。
      File(p.join(logs.path, 'fmp.2.jsonl'))
          .setLastModifiedSync(now.subtract(const Duration(days: 8)));
      File(p.join(logs.path, 'fmp.1.jsonl')).setLastModifiedSync(now);
      file.currentFile.setLastModifiedSync(now);

      expect(await run(), 1);
      expect(logFileNames(logs), ['fmp.1.jsonl', 'fmp.jsonl']);
    });

    test('waits for a rotation that is already queued', () async {
      make('fmp.1.jsonl', const Duration(days: 10));
      file.currentFile
        ..writeAsStringSync('${'x' * 89}\n')
        ..setLastModifiedSync(now.subtract(const Duration(days: 9)));
      // 這一行一寫就輪替：fmp.1 → fmp.2、fmp.jsonl → fmp.1。保留期限要排在
      // 輪替之後，否則會和改名交錯（刪到剛改名進來的檔，或檔案半途不見）。
      file.write('y' * 20);

      expect(await run(), 2);
      await file.flush();
      expect(logFileNames(logs), ['fmp.jsonl']);
    });

    test('a failure reaches the caller and later writes still run', () async {
      final broken = LogFile(_UnlistableDirectory(logs.path));

      await expectLater(
        broken.deleteExpired(),
        throwsA(isA<FileSystemException>()),
      );
      // 佇列沒有卡在那個錯誤上：下一批照常處理（這個假目錄建不了，記一次失敗）。
      broken.write('{"n":1}');
      await broken.flush();
      expect(broken.failureCount, 1);
    });
  });
}

/// 存在但列不出內容的目錄；其他操作都丟 [NoSuchMethodError]。
final class _UnlistableDirectory implements Directory {
  _UnlistableDirectory(this.path);

  @override
  final String path;

  @override
  Future<bool> exists() async => true;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream.error(const FileSystemException('denied'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
