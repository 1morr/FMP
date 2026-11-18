import 'dart:io';

import 'device_lock.dart';
import 'devices.dart';
import 'steps.dart';

/// 完整版閘門在 quick 之後的平台步驟（docs/development.md〈平台〉〈開發環境與閘門〉）：先建置四個平台，再在
/// 四個平台跑 [integrationTests]。步驟名稱帶平台，失敗時看得出是哪個平台、
/// 哪一步。
///
/// - 碰共用裝置的步驟（`winpc` 的同步與建置、macOS 的原生測試、四平台的
///   integration_test）夾在 `lock shared devices` 與 `unlock shared devices` 之間，持有
///   [deviceLock] 時才跑；沒拿到鎖就判失敗、不執行。Mac 上的建置（三個平台與 macOS 的原生
///   測試）只寫這個 worktree 的 `build/`，在鎖外先做，縮短持鎖時間。
/// - 一次只給 `flutter test` 一個 integration_test 檔（docs/development.md〈平台〉 的怪癖）。
/// - 每個 integration_test 都帶 `FMP_SCRATCH_DATA=`[integrationTestScratchData]：
///   開真的 App 的測試把資料放在裝置的系統暫存目錄、先清空，不寫擁有者 dev 版的
///   資料庫與 log（`test/support/scratch_data.dart`）。
/// - iOS、Android 只挑模擬器，不碰連著的實機；加 `--no-uninstall`，跑完
///   不刪模擬器上的 App 與資料。iOS 只用 iPhone，沒開著就開一台
///   （[ensureBootedIPhone]）；Android 先 `adb start-server`。
/// - Windows 經 SSH 在 `winpc` 的桌面工作階段跑（docs/development.md〈平台〉〈Windows〉），
///   log 取回 [winpcLogs] 並印到 [out]。
List<CheckStep> platformSteps({
  required Directory app,
  required Shell shell,
  required List<String> integrationTests,
  required StringSink out,
  required Directory winpcLogs,
  required DeviceLock deviceLock,
}) {
  const scratch = '--dart-define=FMP_SCRATCH_DATA=$integrationTestScratchData';

  CheckStep flutter(String name, List<String> args) =>
      commandStep(name, shell, 'flutter', args, workingDirectory: app);

  // 模擬器上的 integration_test：跑完不刪 App 與資料（docs/development.md〈平台〉）。
  Future<bool> testOnEmulator(String file, String device) async =>
      await shell.run('flutter', [
        'test',
        file,
        '-d',
        device,
        '--no-uninstall',
        scratch,
      ], workingDirectory: app) ==
      0;

  CheckStep locked(CheckStep step) => CheckStep(step.name, () async {
    if (!deviceLock.isHeld) {
      out.writeln('Skipped: the shared-device lock is not held.');
      return false;
    }
    return step.run();
  });

  // 和 `flutter build macos` 共用 build/macos，build-for-testing 只補建測試目標。
  const macosNativeTests = [
    '-workspace',
    'macos/Runner.xcworkspace',
    '-scheme',
    'Runner',
    '-destination',
    'platform=macOS',
    '-derivedDataPath',
    'build/macos',
  ];
  final windows = Winpc(app, shell, out, winpcLogs);
  final sharedDeviceSteps = [
    CheckStep('build windows', windows.build),
    // macos/RunnerTests 跑在 Mac 的 App 裡，讀真的視窗（紅綠燈的位置，事實 M13）；
    // 建置在鎖外（[macosNativeTests] 的 build-for-testing）。
    commandStep('native tests macos', shell, 'xcodebuild', [
      'test-without-building',
      ...macosNativeTests,
      '-only-testing:RunnerTests',
    ], workingDirectory: app),
    for (final file in integrationTests)
      flutter('integration_test macos: $file', [
        'test',
        file,
        '-d',
        'macos',
        scratch,
      ]),
    for (final file in integrationTests)
      CheckStep('integration_test ios: $file', () async {
        // 每個檔都重查：模擬器可能在兩個檔之間被關掉。
        final device = await ensureBootedIPhone(shell, app, out);
        return testOnEmulator(file, device);
      }),
    for (final file in integrationTests)
      CheckStep('integration_test android: $file', () async {
        // adb server 不在時以 ADB_MDNS=0 叫起來（brief 事實 K15），在跑時
        // 什麼都不做；先叫起來，`flutter devices` 才看得到模擬器。
        await shell.run('adb', ['start-server'], workingDirectory: app);
        return testOnEmulator(file, await androidEmulator(shell, app));
      }),
    for (final file in integrationTests)
      CheckStep(
        'integration_test windows: $file',
        () => windows.integrationTest(
          file,
          extra: ['-ScratchData', integrationTestScratchData],
        ),
      ),
  ];

  return [
    flutter('build macos', ['build', 'macos', '--debug']),
    commandStep('build macos native tests', shell, 'xcodebuild', [
      'build-for-testing',
      ...macosNativeTests,
    ], workingDirectory: app),
    flutter('build ios', ['build', 'ios', '--simulator', '--debug']),
    flutter('build android', ['build', 'apk', '--debug']),
    CheckStep('lock shared devices', () async {
      await deviceLock.acquire(out);
      return true;
    }),
    ...sharedDeviceSteps.map(locked),
    CheckStep('unlock shared devices', () async {
      await deviceLock.release();
      return true;
    }),
  ];
}

/// 閘門的 integration_test 用的隔離資料目錄名（`FMP_SCRATCH_DATA`），和實跑的
/// 分開。
const integrationTestScratchData = 'fmp-integration-test';

/// `integration_test/` 底下的 `*_test.dart`（含子目錄），相對於 [app]、排序。
List<String> integrationTestFiles(Directory app) {
  final dir = Directory('${app.path}/integration_test');
  if (!dir.existsSync()) return [];
  return [
    for (final file in dir.listSync(recursive: true))
      if (file is File && file.path.endsWith('_test.dart'))
        file.path.substring(app.path.length + 1).replaceAll(r'\', '/'),
  ]..sort();
}
