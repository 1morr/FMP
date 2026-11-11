import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/device_lock.dart';

/// 包裝指令 `tool/device_lock.dart` 與 `tool/winpc/lock_guard.sh`（plan §2、
/// §4）。都在暫存的 git repo 裡跑，用那個 repo 自己的鎖，不碰開發機上真的
/// 共用裝置鎖。
void main() {
  final tool = File('tool/device_lock.dart').absolute.path;
  final guard = File('tool/winpc/lock_guard.sh').absolute.path;
  final holdScript = File('test/tool/support/hold_device_lock.dart')
      .absolute
      .path;
  late String repo;
  late DeviceLock lock;

  setUp(() {
    repo = Directory.systemTemp
        .createTempSync('fmp_lock_cli_')
        .resolveSymbolicLinksSync();
    final init = Process.runSync('git', ['init', '-q'], workingDirectory: repo);
    expect(init.exitCode, 0);
    lock = DeviceLock.forRepo(Directory(repo));
  });
  tearDown(() async {
    await lock.release();
    Directory(repo).deleteSync(recursive: true);
  });

  /// 在 [repo] 裡開一個子行程。
  Future<_Child> start(String executable, List<String> args) async =>
      _Child(await Process.start(executable, args, workingDirectory: repo));

  /// 另一個 worktree 的閘門持有 [repo] 的鎖。
  Future<_Child> holdElsewhere() async {
    final holder = await start('dart', [
      holdScript,
      lock.file.path,
      '/work/other-ticket',
    ]);
    await holder.waitFor('held');
    return holder;
  }

  /// 照 `sync.sh` 的寫法：一開頭 source lock_guard.sh 的腳本。
  String guardedScript() {
    final script = File('$repo/guarded.sh')
      ..writeAsStringSync(
        '#!/bin/bash\n'
        'source "$guard"\n'
        r'echo "guarded args=$*"'
        '\n',
      );
    Process.runSync('chmod', ['+x', script.path]);
    return script.path;
  }

  group('dart run tool/device_lock.dart -- <command>', () {
    test('runs the command while holding the lock, then releases it and '
        'returns the exit code', () async {
      final child = await start('dart', [
        tool,
        '--',
        'sh',
        '-c',
        r'cat "$0"; exit 3',
        lock.holderFile.path,
      ]);

      expect(await child.exitCode, 3, reason: child.output);
      expect(child.output, contains('"worktree":"$repo"'));
      expect(lock.holderFile.existsSync(), isFalse);
      final out = StringBuffer();
      await lock.acquire(out);
      expect(out.toString(), isNot(contains('Waiting')));
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('the command starts any adb server with mDNS off (ADB_MDNS=0, '
        'brief fact K15)', () async {
      final child = await start('dart', [
        tool,
        '--',
        'sh',
        '-c',
        r'echo "ADB_MDNS=$ADB_MDNS"',
      ]);

      expect(await child.exitCode, 0);
      expect(child.output, contains('ADB_MDNS=0\n'));
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('while another worktree holds the lock, prints the holder and runs '
        'the command only after it is released', () async {
      final holder = await holdElsewhere();
      final child = await start('dart', [tool, '--', 'echo', 'ran']);
      await child.waitFor('Waiting');
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(child.output, contains('pid ${holder.pid}'));
      expect(child.output, isNot(contains('ran\n')));

      holder.send('release');
      expect(await child.exitCode, 0);
      expect(child.output, contains('ran\n'));
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('nested inside a command it already guards, it runs at once '
        'instead of waiting for itself', () async {
      final child = await start('dart', [
        tool,
        '--',
        'dart',
        tool,
        '--',
        'echo',
        'inner',
      ]);

      expect(
        await child.exitCode.timeout(const Duration(seconds: 30)),
        0,
        reason: child.output,
      );
      expect(child.output, contains('inner'));
      expect(child.output, isNot(contains('Waiting')));
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('--held is true only under the holder', () async {
      Future<int> held(List<String> wrap) async =>
          (await start('dart', [...wrap, tool, '--held'])).exitCode;

      expect(await held([]), 1, reason: 'nobody holds the lock');
      expect(await held([tool, '--', 'dart']), 0, reason: 'under the wrapper');

      final holder = await holdElsewhere();
      expect(await held([]), 1, reason: 'held by an unrelated process');
      holder.send('release');
      await holder.exitCode;
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('lock_guard.sh', () {
    test('a guarded script started without the lock takes it first: it '
        'waits for another worktree and only then does its work', () async {
      final holder = await holdElsewhere();
      final script = await start(guardedScript(), ['a', 'b']);
      await script.waitFor('Waiting');
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(script.output, isNot(contains('guarded')));

      holder.send('release');
      expect(await script.exitCode, 0, reason: script.output);
      expect(script.output, contains('guarded args=a b'));
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('called by a process that holds the lock (the full gate), a guarded '
        'script runs at once instead of waiting for its caller', () async {
      await lock.acquire(StringBuffer());

      final script = await start(guardedScript(), ['x']);

      expect(
        await script.exitCode.timeout(const Duration(seconds: 30)),
        0,
        reason: script.output,
      );
      expect(script.output, contains('guarded args=x'));
      expect(script.output, isNot(contains('Waiting')));
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('every winpc script sources lock_guard.sh before reaching winpc', () {
    final scripts = [
      for (final file in Directory('tool/winpc').listSync())
        if (file is File &&
            file.path.endsWith('.sh') &&
            !file.path.endsWith('lock_guard.sh'))
          file,
    ];

    test('in the repo', () {
      expect(
        scripts.map((f) => f.path.split('/').last),
        containsAll(['sync.sh', 'run_task.sh']),
      );
      for (final script in scripts) {
        expect(
          _guardViolation(script.readAsStringSync()),
          isNull,
          reason: script.path,
        );
      }
    });

    final sync = File('tool/winpc/sync.sh').readAsStringSync();
    final guardLine = sync
        .split('\n')
        .firstWhere(
          (l) => l.contains('lock_guard.sh') && l.startsWith('source'),
        );

    test('mutation: turns red without the guard, with it commented out, or '
        'with it after the first ssh/scp', () {
      final firstRemote = sync
          .split('\n')
          .firstWhere((l) => l.startsWith('ssh ') || l.startsWith('scp '));
      for (final mutated in [
        sync.replaceFirst('$guardLine\n', ''),
        sync.replaceFirst(guardLine, '# $guardLine'),
        sync
            .replaceFirst('$guardLine\n', '')
            .replaceFirst(firstRemote, '$firstRemote\n$guardLine'),
      ]) {
        expect(_guardViolation(mutated), isNotNull, reason: mutated);
      }
    });

    test('mutation: stays green on unrelated edits (comments, blank lines, '
        'renamed variables, other commands before the guard)', () {
      for (final mutated in [
        sync.replaceFirst('#!/bin/bash\n', '#!/bin/bash\n# note\n\n'),
        sync.replaceAll(r'$tmp', r'$scratch').replaceAll('tmp=', 'scratch='),
        sync.replaceFirst(guardLine, 'echo start\n$guardLine'),
        sync.replaceFirst(guardLine, '  $guardLine'),
      ]) {
        expect(_guardViolation(mutated), isNull, reason: mutated);
      }
    });
  });
}

/// 腳本的問題：沒有 source lock_guard.sh，或在那之前就 `ssh`／`scp` 到
/// winpc。沒問題時回 null。註解不算。
String? _guardViolation(String script) {
  final lines = [
    for (final line in script.split('\n'))
      if (!line.trimLeft().startsWith('#')) line.trim(),
  ];
  final guard = lines.indexWhere(
    (l) => RegExp(r'^(source|\.)\s.*lock_guard\.sh').hasMatch(l),
  );
  final remote = lines.indexWhere(
    (l) => RegExp(r'(^|[\s;(|&$])(ssh|scp)\s').hasMatch(l),
  );
  if (guard < 0) return 'does not source lock_guard.sh';
  if (remote >= 0 && remote < guard) {
    return 'reaches winpc before sourcing lock_guard.sh';
  }
  return null;
}

/// 子行程，收集它的 stdout 與 stderr。
class _Child {
  _Child(this._process) {
    for (final stream in [_process.stdout, _process.stderr]) {
      stream.transform(utf8.decoder).listen(_onData);
    }
  }

  final Process _process;
  final _output = StringBuffer();
  final _waiters = <(String, Completer<void>)>[];

  String get output => _output.toString();
  int get pid => _process.pid;
  Future<int> get exitCode => _process.exitCode;

  void _onData(String data) {
    _output.write(data);
    for (final (text, done) in [..._waiters]) {
      if (output.contains(text)) {
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
