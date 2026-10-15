// 接線哨兵（ADR 0015 §決定 2）：證明 fmp_lints 真的接上了 app/。
//
// 暫放違反每條規則的檔案，跑 `dart analyze --fatal-infos`，斷言分析失敗、
// 而且暫放檔的診斷含 analysis_options.yaml 開啟的每一條 fmp_ 規則；結束時
// （含失敗、Ctrl-C）刪除暫放檔。插件沒載入、編譯失敗或規則沒開時，
// `dart analyze` 可能照樣通過，只有這支會紅。
//
// 在 app/ 執行：dart run tool/lint_sentinel.dart
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// 暫放檔：相對 app/ 的路徑 → 內容。`fmp_test_waits` 只管 `test/`，
/// `fmp_design_tokens` 只管 `lib/ui/`，所以放兩個位置。
const _violations = {
  'lib/ui/lint_sentinel_violations.dart': r'''
// tool/lint_sentinel.dart 暫放的違規檔，結束時刪除。
import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:audio_session/audio_session.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:fmp/core/network/fixture/fixture.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:material_ui/material_ui.dart' as m;
import 'package:pub_semver/pub_semver.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class Dio {
  Dio();
}

int resetForTesting() => 0;

// ignore: fmp_lints/fmp_url_literal
const harmless = 0;

void violations(m.BuildContext context) {
  try {
    print('x');
  } catch (_) {}
  const id = 'bilibili';
  const url = 'https://example.com';
  Dio();
  Timer.periodic(const Duration(seconds: 1), (_) {});
  Platform.isAndroid;
  m.ScaffoldMessenger.of(context);
  const m.EdgeInsets.all(8);
}
''',
  // forbiddenLayerImports：排程器、電台與音樂庫不 import 介面；core 不 import 排程器與音樂庫。
  'lib/scheduler/lint_sentinel_violations.dart': r'''
// tool/lint_sentinel.dart 暫放的違規檔，結束時刪除。
import 'package:fmp/ui/toast/toast.dart';
''',
  'lib/radio/lint_sentinel_violations.dart': r'''
// tool/lint_sentinel.dart 暫放的違規檔，結束時刪除。
import 'package:fmp/ui/toast/toast.dart';
''',
  'lib/library/lint_sentinel_violations.dart': r'''
// tool/lint_sentinel.dart 暫放的違規檔，結束時刪除。
import 'package:fmp/ui/toast/toast.dart';
''',
  'lib/core/lint_sentinel_violations.dart': r'''
// tool/lint_sentinel.dart 暫放的違規檔，結束時刪除。
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/scheduler/background_scheduler.dart';
''',
  'test/lint_sentinel_violations.dart': r'''
// tool/lint_sentinel.dart 暫放的違規檔，結束時刪除。
Future<void> wait() => pumpEventQueue();
''',
};

/// 規則名之外還要在暫放檔的診斷裡看到的訊息：同一條規則有好幾張表時，規則名
/// 已經由別的行報出（`fmp_layer_imports` 由 `drift`），新表那一行只有訊息分得
/// 出來。
const _expectedMessages = [
  // restrictedImports（`package:fmp/playback/backends/audio_backend.dart`）
  'lib/playback/backends/audio_backend.dart is only imported from',
  // restrictedImports（`package:fmp/platform/cache_directory/…`）
  'lib/platform/cache_directory is only imported from',
  // restrictedImports（`package:fmp/core/network/fixture/…`）
  'lib/core/network/fixture is only imported from',
  // externalPackageOwners 的兩個圖片快取套件
  'package:flutter_cache_manager* is only allowed in lib/data/cache/',
  'package:cached_network_image* is only allowed in lib/ui/artwork/',
  // externalPackageOwners 的 audio_session（Android 的音訊中斷）
  'package:audio_session* is only allowed in lib/playback/backends/',
  // externalPackageOwners 的 pub_semver（插件庫的版本比較）
  'package:pub_semver* is only allowed in lib/plugins/repository/',
  // externalPackageOwners 的 qr_flutter（QR 登入畫面）
  'package:qr_flutter* is only allowed in lib/ui/accounts/',
  // externalPackageOwners 的 archive（診斷包的 zip）
  'package:archive* is only allowed in lib/app/diagnostics/',
  // forbiddenLayerImports 的 scheduler／radio／library／core
  'lib/scheduler/ must not import lib/ui/',
  'lib/radio/ must not import lib/ui/',
  'lib/library/ must not import lib/ui/',
  'lib/core/ must not import lib/scheduler/',
  'lib/core/ must not import lib/library/',
  // platformPackages 的 share_plus（分享診斷包）
  'package:share_plus* is only allowed in lib/platform/',
];

Future<void> main() async {
  final appRoot = p.dirname(p.dirname(p.fromUri(Platform.script)));
  final expected = _enabledRules(
    File(p.join(appRoot, 'analysis_options.yaml')).readAsStringSync(),
  );
  if (expected.isEmpty) {
    _fail('analysis_options.yaml enables no fmp_lints rules.');
  }

  final files = [
    for (final relative in _violations.keys)
      File(p.join(appRoot, p.joinAll(relative.split('/')))),
  ];
  // 暫放檔的目錄可能還不存在（例如還沒有 lib/ui/）；自己建的也自己刪。
  final createdDirectories = <Directory>[];
  void cleanUp() {
    for (final file in files) {
      if (file.existsSync()) file.deleteSync();
    }
    for (final directory in createdDirectories.reversed) {
      if (directory.existsSync()) directory.deleteSync();
    }
  }

  final interrupted = ProcessSignal.sigint.watch().listen((_) {
    cleanUp();
    exit(130);
  });

  ProcessResult result;
  try {
    for (final (index, file) in files.indexed) {
      if (!file.parent.existsSync()) {
        createdDirectories.add(file.parent..createSync());
      }
      file.writeAsStringSync(_violations.values.elementAt(index));
    }
    stdout.writeln('Running dart analyze --fatal-infos with violation files…');
    result = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '--fatal-infos',
    ], workingDirectory: appRoot);
  } finally {
    cleanUp();
    await interrupted.cancel();
  }

  final output = '${result.stdout}\n${result.stderr}';
  final violationLines = [
    for (final line in output.split(RegExp(r'\r?\n')))
      if (_violations.keys.any((path) => line.contains(p.basename(path)))) line,
  ];
  final found = <String>{
    for (final line in violationLines)
      if (RegExp(r' - (fmp_\w+)\s*$').firstMatch(line) case final match?)
        match.group(1)!,
  };
  stdout.writeln(
    'fmp rules reported on the violation files (${found.length}):',
  );
  for (final name in found.toList()..sort()) {
    stdout.writeln('  $name');
  }

  final missing = expected.where((name) => !found.contains(name)).toList();
  final missingMessages = [
    for (final message in _expectedMessages)
      if (!violationLines.any((line) => line.contains(message))) message,
  ];
  if (result.exitCode == 0) {
    _fail('dart analyze passed with the violation files in place.', output);
  }
  if (missing.isNotEmpty) {
    _fail(
      'Enabled rules not reported: ${missing.join(', ')}. Either the plugin '
      'is not wired, or a violation for the rule is missing in '
      'tool/lint_sentinel.dart.',
      output,
    );
  }
  if (missingMessages.isNotEmpty) {
    _fail(
      'Expected diagnostics not reported: ${missingMessages.join('; ')}. '
      'The running plugin lacks that table, or its violation is missing in '
      'tool/lint_sentinel.dart.',
      output,
    );
  }
  stdout.writeln(
    'OK: dart analyze failed (exit ${result.exitCode}) and reported all '
    '${expected.length} enabled fmp rules.',
  );
}

/// `plugins: fmp_lints: diagnostics:` 裡設成 `true` 的規則名。
List<String> _enabledRules(String analysisOptions) {
  final yaml = loadYaml(analysisOptions) as YamlMap;
  final plugin = (yaml['plugins'] as YamlMap?)?['fmp_lints'] as YamlMap?;
  final diagnostics = plugin?['diagnostics'] as YamlMap?;
  return [
    for (final MapEntry(:key, :value) in (diagnostics ?? YamlMap()).entries)
      if (value == true) key as String,
  ];
}

Never _fail(String message, [String? output]) {
  if (output != null) stderr.writeln(output);
  stderr.writeln('lint_sentinel FAILED: $message');
  exit(1);
}
