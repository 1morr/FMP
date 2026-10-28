import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/app_restart/app_restart_android.dart';
import 'package:fmp/platform/app_restart/app_restart_macos.dart';
import 'package:fmp/platform/app_restart/app_restart_windows.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';

// 結束並重啟 App 的平台實作（M3 PR 14b，M3 design §12.2）。

final class _FakeMediaControls implements SystemMediaControls {
  _FakeMediaControls(this.events);

  final List<String> events;

  @override
  Stream<MediaCommand> get commands => const Stream.empty();

  @override
  Future<void> publish(NowPlaying nowPlaying) async =>
      events.add(nowPlaying.hasTrack ? 'publish track' : 'publish nothing');

  @override
  Future<void> dispose() async => events.add('dispose');
}

void main() {
  group('Windows', () {
    test('starts the same executable with the old pid, then exits', () async {
      final events = <String>[];
      final restarter = WindowsAppRestarter(
        executable: r'C:\FMP\fmp.exe',
        pid: 4242,
        launch: (executable, arguments) async =>
            events.add('launch $executable $arguments'),
        exitProcess: (code) => events.add('exit $code'),
      );

      await restarter.restart();

      // 只帶舊 pid，不沿用原本的命令列參數（例如 --fmp-dev-plugin）。
      expect(events, [
        r'launch C:\FMP\fmp.exe [--fmp-restarted-from=4242]',
        'exit 0',
      ]);
    });

    test('does not exit when the new process cannot be started', () async {
      var exited = false;
      final restarter = WindowsAppRestarter(
        executable: r'C:\FMP\fmp.exe',
        pid: 1,
        launch: (_, _) async => throw StateError('cannot start'),
        exitProcess: (_) => exited = true,
      );

      await expectLater(restarter.restart(), throwsStateError);

      expect(exited, isFalse);
    });

    test('the argument prefix matches what main.cpp parses', () {
      // windows/runner/main.cpp 的 kRestartedFromArgument 寫的是同一個字串。
      expect(restartedFromArgumentPrefix, '--fmp-restarted-from=');
    });
  });

  group('Android', () {
    test('stops the media session before ending the process', () async {
      final events = <String>[];
      final restarter = AndroidAppRestarter.forMediaControls(
        _FakeMediaControls(events),
        exitProcess: (code) => events.add('exit $code'),
      );

      await restarter.restart();

      expect(events, ['publish nothing', 'dispose', 'exit 0']);
    });

    test('still ends the process when stopping the session fails', () async {
      final events = <String>[];
      final restarter = AndroidAppRestarter(
        stopMediaSession: () async => throw StateError('service is gone'),
        exitProcess: (code) => events.add('exit $code'),
      );

      await expectLater(restarter.restart(), throwsStateError);

      expect(events, ['exit 0']);
    });

    test('works without system media controls', () async {
      final events = <String>[];
      final restarter = AndroidAppRestarter.forMediaControls(
        null,
        exitProcess: (code) => events.add('exit $code'),
      );

      await restarter.restart();

      expect(events, ['exit 0']);
    });
  });

  group('macOS', () {
    const executable = '/Applications/My Apps/fmp.app/Contents/MacOS/fmp';

    test('disposes media controls, starts a detached shell that waits for '
        'this pid and opens the bundle, then exits', () async {
      final events = <String>[];
      final restarter = MacosAppRestarter(
        executable: executable,
        pid: 4242,
        mediaControls: _FakeMediaControls(events),
        launch: (executable, arguments) async =>
            events.add('launch $executable $arguments'),
        exitProcess: (code) => events.add('exit $code'),
      );

      await restarter.restart();

      // pid 與 .app 路徑是位置參數（$0、$1），不拼進腳本字串。
      expect(events, [
        'dispose',
        'launch /bin/sh [-c, $macosRestartScript, 4242, '
            '/Applications/My Apps/fmp.app]',
        'exit 0',
      ]);
      expect(macosRestartScript, isNot(contains('4242')));
      expect(macosRestartScript, contains(r'kill -0 "$0"'));
      expect(macosRestartScript, contains(r'/usr/bin/open "$1"'));
    });

    test('works without system media controls', () async {
      final events = <String>[];
      final restarter = MacosAppRestarter(
        executable: executable,
        pid: 1,
        launch: (_, _) async => events.add('launch'),
        exitProcess: (code) => events.add('exit $code'),
      );

      await restarter.restart();

      expect(events, ['launch', 'exit 0']);
    });

    test('does not exit when the shell cannot be started', () async {
      var exited = false;
      final restarter = MacosAppRestarter(
        executable: executable,
        pid: 1,
        launch: (_, _) async => throw StateError('cannot start'),
        exitProcess: (_) => exited = true,
      );

      await expectLater(restarter.restart(), throwsStateError);

      expect(exited, isFalse);
    });
  });
}
