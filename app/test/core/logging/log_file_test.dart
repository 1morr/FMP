import 'dart:io';

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
}
