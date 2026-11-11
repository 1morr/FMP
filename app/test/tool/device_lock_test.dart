import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/device_lock.dart';

/// 共用裝置鎖（plan §4）。兩個 worktree 的閘門是兩個行程，所以這裡用子行程
/// （`dart test/tool/support/*.dart`）模擬另一個 worktree。
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('fmp_lock_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('two worktrees running the full gate at the same time do not '
      'overwrite each other on the shared devices', () async {
    final shared = Directory('${tmp.path}/devices')..createSync();
    final a = await _Child.start('concurrent_gate.dart', [shared.path, 'wt-a']);
    final b = await _Child.start('concurrent_gate.dart', [shared.path, 'wt-b']);
    await Future.wait([a.waitFor('ready'), b.waitFor('ready')]);
    a.send('go');
    b.send('go');

    final codes = await Future.wait([a.exitCode, b.exitCode]);

    expect(codes, [0, 0], reason: '${a.output}\n---\n${b.output}');
    // 兩個真的撞在一起過：其中一個等了另一個。
    expect('${a.output}${b.output}', contains('Waiting for the shared-device'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  group('DeviceLock', () {
    late File lockFile;
    late DeviceLock lock;
    late StringBuffer out;

    setUp(() {
      lockFile = File('${tmp.path}/${DeviceLock.fileName}');
      lock = DeviceLock(lockFile, worktree: '/work/this-ticket');
      out = StringBuffer();
    });
    tearDown(() => lock.release());

    test('a free lock is taken at once', () async {
      await lock.acquire(out);

      expect(lock.isHeld, isTrue);
      expect(out.toString(), isNot(contains('Waiting')));
    });

    test('while another worktree holds it, acquire prints the holder '
        '(worktree, pid, start time) and waits until it is released', () async {
      final holder = await _Child.start('hold_device_lock.dart', [
        lockFile.path,
        '/work/other-ticket',
      ]);
      await holder.waitFor('held');

      var acquired = false;
      final acquiring = lock.acquire(out).then((_) => acquired = true);
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(acquired, isFalse);
      expect(
        out.toString(),
        allOf(
          contains('worktree /work/other-ticket'),
          contains('pid ${holder.pid}'),
          matches(RegExp(r'since \d{4}-\d\d-\d\dT\d\d:\d\d')),
        ),
      );

      holder.send('release');
      await acquiring.timeout(const Duration(seconds: 10));
      expect(lock.isHeld, isTrue);
      expect(await holder.exitCode, 0);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('a holder that dies without releasing (kill -9) does not block '
        'the lock forever', () async {
      final holder = await _Child.start('hold_device_lock.dart', [
        lockFile.path,
        '/work/crashed-ticket',
      ]);
      await holder.waitFor('held');

      holder.kill();
      await holder.exitCode;
      await lock.acquire(out).timeout(const Duration(seconds: 10));

      expect(lock.isHeld, isTrue);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('released by this process, the lock is free for the next '
        'worktree', () async {
      await lock.acquire(out);
      await lock.release();

      final next = await _Child.start('hold_device_lock.dart', [
        lockFile.path,
        '/work/next-ticket',
      ]);
      await next.waitFor('held');
      expect(next.output, isNot(contains('Waiting')));
      next.send('release');
      expect(await next.exitCode, 0);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}

/// 跑 `test/tool/support/<script>` 的子行程，收集它的輸出。
class _Child {
  _Child._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    _process.stderr.transform(utf8.decoder).listen(_output.write);
  }

  static Future<_Child> start(String script, List<String> args) async =>
      _Child._(
        await Process.start('dart', ['test/tool/support/$script', ...args]),
      );

  final Process _process;
  final _output = StringBuffer();
  final _waiters = <(String, Completer<void>)>[];

  String get output => _output.toString();
  int get pid => _process.pid;
  Future<int> get exitCode => _process.exitCode;
  void kill() => _process.kill(ProcessSignal.sigkill);

  void _onLine(String line) {
    _output.writeln(line);
    for (final (text, done) in [..._waiters]) {
      if (line.contains(text)) {
        _waiters.remove((text, done));
        done.complete();
      }
    }
  }

  /// 等到輸出出現 [text]（含已經印過的）。
  Future<void> waitFor(String text) {
    if (output.contains(text)) return Future.value();
    final done = Completer<void>();
    _waiters.add((text, done));
    return done.future.timeout(const Duration(seconds: 30));
  }

  void send(String line) => _process.stdin.writeln(line);
}
