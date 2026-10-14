import 'dart:convert';
import 'dart:io';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/fixture/fixture.dart';
import 'package:fmp/core/network/fixture/fixture_adapters.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/dev/describe_error.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:path/path.dart' as p;

// 插件目錄的格式（ADR 0015 §決定 6），命令列契約執行器與 App 內開發工具共用：
//
//   <目錄>/<任意名稱>.js           安裝檔（只能有一個）
//   <目錄>/checks.json             檢查案例（lib/plugins/health/checks.dart）
//   <目錄>/fixtures/<能力>/*.json  該案例依序的請求與回應（fixture.dart）

/// 插件目錄的清單：[root] 本身有 `.js` 檔就是一個插件目錄，否則是它底下有
/// `.js` 檔的子目錄（依名稱排序）。
List<Directory> pluginDirectories(Directory root) {
  if (_scripts(root).isNotEmpty) return [root];
  return [
    for (final entry
        in root.listSync()..sort((a, b) => a.path.compareTo(b.path)))
      if (entry is Directory && _scripts(entry).isNotEmpty) entry,
  ];
}

List<File> _scripts(Directory directory) => [
  for (final entry in directory.listSync())
    if (entry is File && entry.path.endsWith('.js')) entry,
];

/// 讀好的插件目錄：只檢查格式（一個 .js、manifest、checks.json、
/// fixtures/<能力>/*.json）。讀的時候發現的問題在 [problems]，其他部分盡量讀。
final class PluginFolder {
  PluginFolder._(this.directory);

  /// 讀 [directory]。[inspectFixture] 在每個能力的 fixture 都讀好之後，對該能力的
  /// 每個 fixture 依序呼叫（契約執行器以它加網域與憑證掃描）；它發現的問題加進
  /// 傳入的 `problems`，接在格式問題之後。
  factory PluginFolder.read(
    Directory directory, {
    void Function(
      PluginManifest manifest,
      String name,
      HttpFixture fixture,
      List<String> problems,
    )?
    inspectFixture,
  }) {
    final folder = PluginFolder._(directory);
    final scripts = _scripts(directory);
    if (scripts.length != 1) {
      folder.problems.add(
        'expected one .js install file, found ${scripts.length}',
      );
      return folder;
    }
    try {
      folder.file = PluginFile.parse(scripts.single.readAsStringSync());
    } on AppError catch (error) {
      folder.problems.add(
        'install file: ${describeError(
          error,
          Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
          tag: 'plugins',
        )}',
      );
      return folder;
    }
    folder
      .._readChecks()
      .._readFixtures(inspectFixture);
    return folder;
  }

  final Directory directory;
  PluginFile? file;
  final checks = <PluginCheck>[];

  /// 依能力名稱（`fixtures/` 底下的目錄名），依檔名排序。
  final fixtures = <String, List<NamedFixture>>{};
  final problems = <String>[];

  PluginManifest get manifest => file!.manifest;

  /// 測試名稱用。
  String get label => switch (file) {
    null => p.basename(directory.path),
    final file => '${file.manifest.id} (${p.basename(directory.path)})',
  };

  void _readChecks() {
    final checksFile = File(p.join(directory.path, 'checks.json'));
    if (!checksFile.existsSync()) {
      problems.add('checks.json is missing');
      return;
    }
    try {
      checks.addAll(parseChecks(checksFile.readAsStringSync()));
    } on FormatException catch (error) {
      problems.add('checks.json: ${error.message}');
      return;
    }
    for (final check in checks) {
      if (!manifest.capabilities.contains(check.capability)) {
        problems.add(
          'checks.json: ${check.capability.wireName} is not a declared '
          'capability',
        );
      }
    }
  }

  void _readFixtures(
    void Function(
      PluginManifest manifest,
      String name,
      HttpFixture fixture,
      List<String> problems,
    )?
    inspectFixture,
  ) {
    final root = Directory(p.join(directory.path, 'fixtures'));
    if (!root.existsSync()) return;
    final checked = {for (final check in checks) check.capability.wireName};
    for (final entry in root.listSync()) {
      final name = p.basename(entry.path);
      if (entry is! Directory) {
        problems.add('fixtures/$name: fixtures go in fixtures/<capability>/');
        continue;
      }
      if (!checked.contains(name)) {
        problems.add('fixtures/$name: checks.json has no $name check');
      }
      final files = [
        for (final file in entry.listSync())
          if (file is File && file.path.endsWith('.json')) file,
      ]..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      fixtures[name] = [
        for (final file in files)
          if (_readFixture(file, 'fixtures/$name/${p.basename(file.path)}')
              case final fixture?)
            (name: 'fixtures/$name/${p.basename(file.path)}', fixture: fixture),
      ];
      if (inspectFixture == null) continue;
      for (final (:name, :fixture) in fixtures[name]!) {
        inspectFixture(manifest, name, fixture, problems);
      }
    }
  }

  HttpFixture? _readFixture(File file, String name) {
    try {
      return HttpFixture.fromJson(jsonDecode(file.readAsStringSync()));
    } on FormatException catch (error) {
      problems.add('$name: ${error.message}');
      return null;
    }
  }
}

/// 寫進 [target]（`fixtures/<能力>/`）：先刪原有的 .json，依序寫 001.json…；沒有
/// fixture 時連空目錄一起刪。命令列錄製與 App 內錄製共用（經 `recordCase`）。
void writeFixtures(Directory target, List<HttpFixture> fixtures) {
  if (target.existsSync()) {
    for (final entry in target.listSync()) {
      if (entry is File && entry.path.endsWith('.json')) entry.deleteSync();
    }
  }
  if (fixtures.isEmpty) {
    if (target.existsSync() && target.listSync().isEmpty) target.deleteSync();
    return;
  }
  target.createSync(recursive: true);
  for (final (index, fixture) in fixtures.indexed) {
    File(p.join(target.path, '${'${index + 1}'.padLeft(3, '0')}.json'))
        .writeAsStringSync(fixture.encode());
  }
}
