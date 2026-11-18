import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/device_lock.dart';
import '../../tool/src/full_gate.dart';
import '../../tool/src/steps.dart';

/// 每個 integration_test 都帶的隔離資料（不寫擁有者 dev 版的資料）。
const _scratch = '--dart-define=FMP_SCRATCH_DATA=fmp-integration-test';

/// 完整版閘門（docs/development.md〈開發環境與閘門〉）的平台步驟。外部指令經 [Shell]，這裡換成假的：
/// 記下跑過的指令，依前綴決定結果與輸出。
void main() {
  final app = Directory('/repo/app');
  final out = StringBuffer();
  late _FakeShell shell;
  late Directory logs;
  late DeviceLock lock;

  setUp(() {
    out.clear();
    logs = Directory.systemTemp.createTempSync('fmp_gate_');
    lock = DeviceLock(
      File('${logs.path}/${DeviceLock.fileName}'),
      worktree: '/repo',
    );
    shell = _FakeShell(lock);
  });
  tearDown(() async {
    await lock.release();
    logs.deleteSync(recursive: true);
  });

  List<CheckStep> steps({
    List<String> tests = const ['integration_test/app_test.dart'],
    bool skipWindows = false,
  }) => platformSteps(
    app: app,
    shell: shell,
    integrationTests: tests,
    out: out,
    winpcLogs: logs,
    deviceLock: lock,
    skipWindows: skipWindows,
  );

  Future<int> runGate({
    List<String> tests = const ['integration_test/app_test.dart'],
    bool skipWindows = false,
  }) => runSteps(steps(tests: tests, skipWindows: skipWindows), out);

  test('builds all four platforms, then runs integration tests on all four, '
      'one file per invocation', () async {
    final code = await runGate(
      tests: ['integration_test/a_test.dart', 'integration_test/b_test.dart'],
    );

    expect(code, 0);
    expect(shell.ran.where((c) => c.startsWith('flutter build')), [
      'flutter build macos --debug',
      'flutter build ios --simulator --debug',
      'flutter build apk --debug',
    ]);
    expect(shell.ran.where((c) => c.startsWith('flutter test')), [
      'flutter test integration_test/a_test.dart -d macos $_scratch',
      'flutter test integration_test/b_test.dart -d macos $_scratch',
      'flutter test integration_test/a_test.dart -d SIM-UDID --no-uninstall $_scratch',
      'flutter test integration_test/b_test.dart -d SIM-UDID --no-uninstall $_scratch',
      'flutter test integration_test/a_test.dart -d emulator-5554 --no-uninstall $_scratch',
      'flutter test integration_test/b_test.dart -d emulator-5554 --no-uninstall $_scratch',
    ]);
    expect(
      out.toString(),
      allOf(
        contains('ok   build macos'),
        contains('ok   build windows'),
        contains('ok   integration_test android: integration_test/b_test.dart'),
        contains('ok   integration_test windows: integration_test/a_test.dart'),
      ),
    );
    // 建置全部做完才開始跑 integration_test。
    final lastBuild = shell.ran.lastIndexWhere((c) => c.contains(' build '));
    final firstTest = shell.ran.indexWhere((c) => c.startsWith('flutter test'));
    expect(lastBuild, lessThan(firstTest));
  });

  test('integration tests on all four platforms keep their data apart from '
      "the owner's dev app", () async {
    expect(await runGate(), 0);

    final runs = shell.ran.where(
      (c) => c.startsWith('flutter test') || c.contains('fmptest'),
    );
    expect(runs, hasLength(4));
    for (final run in runs) {
      expect(
        run,
        anyOf(
          endsWith(' --dart-define=FMP_SCRATCH_DATA=fmp-integration-test'),
          endsWith(' -ScratchData fmp-integration-test'),
        ),
      );
    }
  });

  test('builds the macOS native tests (RunnerTests) outside the lock, after '
      'the macOS build, and runs them inside the Mac app holding the '
      'lock', () async {
    expect(await runGate(), 0);

    const xcode =
        '-workspace macos/Runner.xcworkspace -scheme Runner '
        '-destination platform=macOS -derivedDataPath build/macos';
    const build = 'xcodebuild build-for-testing $xcode';
    const run =
        'xcodebuild test-without-building $xcode '
        '-only-testing:RunnerTests';
    expect(
      shell.ranWithLock,
      containsAllInOrder([(build, false), (run, true)]),
    );
    expect(
      shell.ran.indexOf(build),
      greaterThan(shell.ran.indexOf('flutter build macos --debug')),
    );
    expect(
      out.toString(),
      allOf(
        contains('ok   build macos native tests'),
        contains('ok   native tests macos'),
      ),
    );
  });

  group('shared-device lock', () {
    /// 違規：碰共用裝置、卻不在持鎖時跑的指令；一個共用裝置的指令都沒跑也
    /// 算（鎖沒拿到時步驟不執行，不能因此放過）。
    List<String> violations(List<(String, bool)> ran) => [
      for (final (command, held) in ran)
        if (_touchesSharedDevice(command) && !held) command,
      if (!ran.any((r) => _touchesSharedDevice(r.$1))) 'no shared-device step',
    ];

    test('every command that touches winpc, the simulators or the Mac app '
        'runs while holding the lock, and the gate releases it at the '
        'end', () async {
      expect(await runGate(), 0);

      expect(violations(shell.ranWithLock), isEmpty);
      expect(
        shell.ranWithLock,
        containsAll([
          ('tool/winpc/sync.sh', true),
          (
            'tool/winpc/run_task.sh fmpbuild C:/fmp-wt/build.ps1 -Mode debug',
            true,
          ),
          (
            'flutter test integration_test/app_test.dart -d macos $_scratch',
            true,
          ),
          (
            'flutter test integration_test/app_test.dart -d SIM-UDID '
                '--no-uninstall $_scratch',
            true,
          ),
          ('adb start-server', true),
          (
            'flutter test integration_test/app_test.dart -d emulator-5554 '
                '--no-uninstall $_scratch',
            true,
          ),
          (
            'tool/winpc/run_task.sh fmptest C:/fmp-wt/test.ps1 '
                '-File integration_test/app_test.dart -ScratchData fmp-integration-test',
            true,
          ),
        ]),
      );
      expect(lock.isHeld, isFalse);
      expect(out.toString(), contains('ok   unlock shared devices'));
    });

    test('mutation: without the lock step, the check goes red', () async {
      final noLock = [
        for (final step in steps())
          if (step.name != 'lock shared devices') step,
      ];

      expect(await runSteps(noLock, out), isNot(0));
      expect(violations(shell.ranWithLock), isNotEmpty);
    });

    test('mutation: unrelated changes (renamed tests, extra local steps, '
        'reordered Mac builds) stay green', () async {
      final mutated = steps(tests: ['integration_test/z_renamed_test.dart'])
          .toList();
      final macBuilds = mutated.take(3).toList().reversed;
      final rest = mutated.skip(3);
      final code = await runSteps([
        CheckStep('unrelated local step', () async => true),
        ...macBuilds,
        ...rest,
      ], out);

      expect(code, 0);
      expect(violations(shell.ranWithLock), isEmpty);
    });

    group('the check itself, on a recorded run', () {
      late List<(String, bool)> recorded;

      setUp(() async {
        await runGate();
        recorded = [...shell.ranWithLock];
      });

      List<(String, bool)> unlockedAt(bool Function(String) which) => [
        for (final (command, held) in recorded)
          (command, which(command) ? false : held),
      ];

      test('turns red on any shared-device command run without the '
          'lock', () {
        for (final command in [
          'tool/winpc/sync.sh',
          'flutter test integration_test/app_test.dart -d macos $_scratch',
          'flutter test integration_test/app_test.dart -d emulator-5554 '
              '--no-uninstall $_scratch',
          'ssh winpc Get-Content -Raw C:\\fmp-wt\\test.log',
        ]) {
          expect(violations(unlockedAt((c) => c == command)), [
            command,
          ], reason: command);
        }
      });

      test('stays green when only the Mac builds or the device listing run '
          'without the lock', () {
        final mutated = unlockedAt(
          (c) =>
              c.startsWith('flutter build') || c.startsWith('flutter devices'),
        );

        expect(mutated, isNot(recorded));
        expect(violations(mutated), isEmpty);
      });
    });
  });

  test('before looking for the Android emulator, the gate makes sure an adb '
      'server runs (started with mDNS off, see gateShell)', () async {
    await runGate();

    final start = shell.ran.indexOf('adb start-server');
    final androidLookup = shell.ran.indexOf('flutter devices --machine');
    expect(start, isNonNegative);
    expect(start, lessThan(androidLookup));
    expect(
      start,
      greaterThan(shell.ran.indexOf('xcrun simctl list devices --json')),
      reason: 'only for Android, after the iOS lookup',
    );
  });

  test('a failing platform step exits non-zero and names the platform and '
      'the step', () async {
    shell.failing.add('flutter build ios');

    final code = await runGate();

    expect(code, isNot(0));
    expect(out.toString(), contains('FAIL build ios'));
    expect(out.toString(), contains('ok   build android'));
  });

  group('iOS simulator', () {
    test('runs on the booted iPhone simulator, never the physical iPhone or '
        'a booted iPad', () async {
      shell.outputs['xcrun simctl list devices --json'] = _simctlJson(
        booted: {'IPAD-UDID', 'SIM-UDID'},
      );

      expect(await runGate(), 0);

      expect(
        shell.ran.where(
          (c) => c.contains('--no-uninstall') && c.contains('SIM'),
        ),
        [
          'flutter test integration_test/app_test.dart -d SIM-UDID --no-uninstall $_scratch',
        ],
      );
      expect(shell.ran, isNot(contains(contains('IPAD-UDID'))));
      expect(shell.ran, isNot(contains(startsWith('xcrun simctl bootstatus'))));
    });

    test('without a booted iPhone simulator (Orca shuts the previous one down '
        'when its pane switches devices), the gate boots the most recently '
        'used iPhone, says why, and runs on it', () async {
      shell.outputs['xcrun simctl list devices --json'] = _simctlJson(
        booted: {'IPAD-UDID'},
      );

      expect(await runGate(), 0);

      final boot = shell.ranWithLock.indexWhere(
        (r) => r.$1 == 'xcrun simctl bootstatus RECENT-UDID -b',
      );
      expect(boot, isNonNegative);
      expect(
        shell.ranWithLock[boot].$2,
        isTrue,
        reason: 'boots under the lock',
      );
      final run = shell.ran.indexOf(
        'flutter test integration_test/app_test.dart -d RECENT-UDID '
        '--no-uninstall $_scratch',
      );
      expect(run, greaterThan(boot));
      expect(
        out.toString(),
        allOf(
          contains('No booted iPhone simulator'),
          contains('booting iPhone Recent (RECENT-UDID)'),
        ),
      );
    });

    test('each iOS test file looks for the iPhone again, so one shut down '
        'between two files is booted again', () async {
      shell.outputs['xcrun simctl list devices --json'] = _simctlJson(
        booted: {},
      );

      expect(
        await runGate(
          tests: [
            'integration_test/a_test.dart',
            'integration_test/b_test.dart',
          ],
        ),
        0,
      );

      expect(
        shell.ran.where(
          (c) =>
              c.startsWith('xcrun simctl bootstatus') ||
              c.contains('RECENT-UDID --no-uninstall $_scratch'),
        ),
        [
          'xcrun simctl bootstatus RECENT-UDID -b',
          'flutter test integration_test/a_test.dart -d RECENT-UDID '
              '--no-uninstall $_scratch',
          'xcrun simctl bootstatus RECENT-UDID -b',
          'flutter test integration_test/b_test.dart -d RECENT-UDID '
              '--no-uninstall $_scratch',
        ],
      );
    });

    test('when booting the iPhone fails, the iOS integration test fails '
        'without running', () async {
      shell.outputs['xcrun simctl list devices --json'] = _simctlJson(
        booted: {},
      );
      shell.failing.add('xcrun simctl bootstatus');

      expect(await runGate(), isNot(0));

      expect(
        out.toString(),
        contains('FAIL integration_test ios: integration_test/app_test.dart'),
      );
      expect(
        shell.ran,
        isNot(contains(contains('RECENT-UDID --no-uninstall $_scratch'))),
      );
    });

    test('without any available iPhone simulator the iOS integration test '
        'fails and says so', () async {
      shell.outputs['xcrun simctl list devices --json'] = _simctlJson(
        booted: {},
        iPhones: false,
      );

      expect(await runGate(), isNot(0));

      expect(
        out.toString(),
        allOf(
          contains('No available iPhone simulator'),
          contains('FAIL integration_test ios: integration_test/app_test.dart'),
        ),
      );
      expect(shell.ran, isNot(contains(startsWith('xcrun simctl bootstatus'))));
      expect(shell.ran, isNot(contains(contains('IPAD-UDID'))));
    });
  });

  group('Windows', () {
    test('runs on winpc and keeps the fetched log on the Mac', () async {
      final code = await runGate();

      expect(code, 0);
      expect(
        shell.ran.indexOf('tool/winpc/sync.sh'),
        allOf(
          isNonNegative,
          lessThan(shell.ran.indexWhere((c) => c.contains('fmpbuild'))),
        ),
      );
      expect(
        shell.ran,
        containsAll([
          'tool/winpc/run_task.sh fmpbuild C:/fmp-wt/build.ps1 -Mode debug',
          'tool/winpc/run_task.sh fmptest C:/fmp-wt/test.ps1 '
              '-File integration_test/app_test.dart -ScratchData fmp-integration-test',
        ]),
      );
      expect(
        File('${logs.path}/build.log').readAsStringSync(),
        contains('exit build=0'),
      );
      expect(File('${logs.path}/test-app_test.log').existsSync(), isTrue);
    });

    test('a non-zero stage in the remote log fails the Windows step', () async {
      shell.outputs['ssh winpc Get-Content'] =
          'exit pubget=0\nexit build=1\n=== done\n';

      expect(await runGate(), isNot(0));
      expect(out.toString(), contains('FAIL build windows'));
    });

    test(
      'a remote log that never reached the end fails the Windows step',
      () async {
        shell.outputs['ssh winpc Get-Content'] = 'exit pubget=0\n';

        expect(await runGate(), isNot(0));
        expect(out.toString(), contains('FAIL build windows'));
      },
    );

    test('--skip-windows never touches winpc, lists the Windows steps as '
        'SKIP with the reason, and passes when the rest is green', () async {
      final code = await runGate(
        tests: ['integration_test/a_test.dart', 'integration_test/b_test.dart'],
        skipWindows: true,
      );

      expect(code, 0);
      expect(
        shell.ran.where(
          (c) =>
              c.startsWith('tool/winpc/') ||
              c.startsWith('ssh ') ||
              c.startsWith('scp '),
        ),
        isEmpty,
      );
      expect(
        out.toString(),
        allOf(
          contains('SKIP build windows (--skip-windows: '),
          contains(
            'SKIP integration_test windows: integration_test/a_test.dart',
          ),
          contains(
            'SKIP integration_test windows: integration_test/b_test.dart',
          ),
          contains(
            'ok   integration_test android: integration_test/b_test.dart',
          ),
          contains('ok   native tests macos'),
        ),
      );
      expect(out.toString(), isNot(contains('ok   build windows')));
      expect(
        shell.ran.where((c) => c.startsWith('flutter test')),
        hasLength(6),
        reason: 'macOS, iOS and Android still run both files',
      );
    });

    test('--skip-windows still fails the gate when another platform '
        'fails', () async {
      shell.failing.add('flutter build apk');

      expect(await runGate(skipWindows: true), isNot(0));
      expect(out.toString(), contains('FAIL build android'));
    });

    test('a failed sync fails the Windows build without running it', () async {
      shell.failing.add('tool/winpc/sync.sh');

      expect(await runGate(), isNot(0));
      expect(out.toString(), contains('FAIL build windows'));
      expect(
        shell.ran,
        isNot(contains(startsWith('tool/winpc/run_task.sh fmpbuild'))),
      );
    });
  });

  test('integration tests are the *_test.dart files under integration_test/, '
      'in a stable order; real-run scenarios (*_run.dart) are left out', () {
    final root = Directory.systemTemp.createTempSync('fmp_app_');
    addTearDown(() => root.deleteSync(recursive: true));
    for (final path in [
      'integration_test/search_test.dart',
      'integration_test/app_test.dart',
      'integration_test/support/robot.dart',
      'integration_test/real_run/search_and_play_run.dart',
      'test/ui/page_test.dart',
    ]) {
      File('${root.path}/$path').createSync(recursive: true);
    }

    expect(integrationTestFiles(root), [
      'integration_test/app_test.dart',
      'integration_test/search_test.dart',
    ]);
  });
}

/// 碰共用裝置的指令：`winpc` 的同步、排程工作、SSH、scp，adb，開模擬器，以及
/// 指定裝置的 `flutter test`（macOS 上的 App、模擬器）。Mac 上的建置與查裝置
/// 清單不算。
bool _touchesSharedDevice(String command) =>
    command.startsWith('tool/winpc/') ||
    command.startsWith('adb ') ||
    command.startsWith('ssh ') ||
    command.startsWith('scp ') ||
    command.startsWith('xcrun simctl bootstatus ') ||
    command.startsWith('xcodebuild test-without-building ') ||
    (command.startsWith('flutter test ') && command.contains(' -d '));

class _FakeShell implements Shell {
  _FakeShell(this.lock);

  final DeviceLock lock;
  final ran = <String>[];

  /// 每個指令跑的時候是否持有 [lock]。
  final ranWithLock = <(String, bool)>[];

  /// 指令以這些前綴開頭時回傳非零。
  final failing = <String>{};

  /// `capture` 的輸出，依前綴比對。
  final outputs = <String, String>{
    'flutter devices --machine': _devicesJson,
    'xcrun simctl list devices --json': _simctlJson(booted: {'SIM-UDID'}),
    'ssh winpc Get-Content': 'exit pubget=0\nexit build=0\n=== done\n',
  };

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    final command = [executable, ...arguments].join(' ');
    ran.add(command);
    ranWithLock.add((command, lock.isHeld));
    return failing.any(command.startsWith) ? 1 : 0;
  }

  @override
  Future<String> capture(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    final command = [executable, ...arguments].join(' ');
    ran.add(command);
    ranWithLock.add((command, lock.isHeld));
    for (final MapEntry(:key, :value) in outputs.entries) {
      if (command.startsWith(key)) return value;
    }
    return '';
  }
}

/// `flutter devices --machine` 的形狀（2026-11-11，Flutter 3.47.5），名稱與
/// id 改成假的。實體 iPhone 與 Android 實機不能被選到。
const _devicesJson = '''
[
  {"name": "phone", "id": "emulator-5554", "isSupported": true,
   "targetPlatform": "android-arm64", "emulator": true, "sdk": "Android 17 (API 37)"},
  {"name": "real phone", "id": "REAL-ANDROID", "isSupported": true,
   "targetPlatform": "android-arm64", "emulator": false, "sdk": "Android 16"},
  {"name": "my iPhone", "id": "REAL-IPHONE", "isSupported": true,
   "targetPlatform": "ios", "emulator": false, "sdk": "iOS 27.2"},
  {"name": "iPhone Sim", "id": "SIM-UDID", "isSupported": true,
   "targetPlatform": "ios", "emulator": true, "sdk": "iOS 27.1"},
  {"name": "macOS", "id": "macos", "isSupported": true,
   "targetPlatform": "darwin", "emulator": false, "sdk": "macOS 27.0.1"}
]
''';

/// `xcrun simctl list devices --json` 的形狀（2026-11-15，Xcode 27.2），只留
/// 閘門讀的欄位，名稱與 udid 改成假的。[booted] 裡的 udid 是開著的。iPad 與
/// 不可用的 iPhone 最近用過，不能被選到；沒用過的裝置沒有 `lastUsedAt`。
String _simctlJson({required Set<String> booted, bool iPhones = true}) {
  String device(
    String name,
    String udid,
    String type, {
    String? lastUsedAt,
    bool available = true,
  }) =>
      '{"name": "$name", "udid": "$udid", "isAvailable": $available, '
      '"deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.$type", '
      '"state": "${booted.contains(udid) ? 'Booted' : 'Shutdown'}"'
      '${lastUsedAt == null ? '' : ', "lastUsedAt": "$lastUsedAt"'}}';

  final iPhoneDevices = [
    if (iPhones) ...[
      device(
        'iPhone Old',
        'OLD-UDID',
        'iPhone-17',
        lastUsedAt: '2026-10-01T08:00:00Z',
      ),
      device(
        'iPhone Sim',
        'SIM-UDID',
        'iPhone-18-Pro',
        lastUsedAt: '2026-11-14T08:00:00Z',
      ),
      device(
        'iPhone Recent',
        'RECENT-UDID',
        'iPhone-17e',
        lastUsedAt: '2026-11-15T09:00:00Z',
      ),
      device('iPhone Never', 'NEVER-UDID', 'iPhone-Air'),
      device(
        'iPhone Gone',
        'GONE-UDID',
        'iPhone-17',
        lastUsedAt: '2026-11-15T11:00:00Z',
        available: false,
      ),
    ],
  ];
  final iPad = device(
    'iPad Air',
    'IPAD-UDID',
    'iPad-Air-11-inch-M4',
    lastUsedAt: '2026-11-15T10:00:00Z',
  );
  return '{"devices": {'
      '"com.apple.CoreSimulator.SimRuntime.iOS-27-1": [$iPad], '
      '"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [${iPhoneDevices.join(', ')}], '
      '"com.apple.CoreSimulator.SimRuntime.watchOS-12-0": []'
      '}}';
}
