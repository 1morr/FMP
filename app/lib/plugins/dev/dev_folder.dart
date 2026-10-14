import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/dev/plugin_folder.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/settings/developer_settings.dart';

// 插件開發資料夾（M3 PR 16b，ADR 0025 §決定 7）：哪個資料夾生效，以及掃描出來的狀態型別。

/// 生效的插件開發資料夾：平台宣告 `pluginDevTools`、開發者模式開著、`plugin_dev_folder`
/// 有值時是那個目錄，否則 `null`。
final pluginDevFolderProvider = FutureProvider<Directory?>((ref) async {
  if (!ref.watch(platformCapabilitiesProvider).pluginDevTools) return null;
  final developer = await ref.watch(developerProvider.future);
  final path = developer.stored.pluginDevFolder;
  if (!developer.developerMode || path == null) return null;
  return Directory(path);
});

enum DevLoad { loaded, failed }

/// 資料夾裡的一個插件目錄。
@immutable
final class DevPlugin {
  const DevPlugin({
    required this.id,
    required this.directory,
    required this.load,
    this.problem,
    this.manifest,
    this.replacedVersion,
    this.cases = const [],
    this.changedId,
  });

  /// manifest 的 id；讀不出 manifest 時是目錄名。
  final String id;
  final Directory directory;
  final DevLoad load;

  /// 載入失敗的原因，或 checks.json 讀不懂的原因；已遮蔽。
  final String? problem;

  /// 載入成功時是開發版的 manifest。
  final PluginManifest? manifest;

  /// 取代的已安裝版本；沒有已安裝的列是 `null`。
  final String? replacedVersion;

  /// checks.json 的能力；讀不懂是空的（原因在 [problem]）。
  final List<PluginCapability> cases;

  /// 重新載入時 manifest 的 id 變成了它（載入失敗，要重新掃描資料夾）；畫面以翻譯過的
  /// 字串顯示，所以不放進 [problem]。
  final String? changedId;

  @override
  bool operator ==(Object other) =>
      other is DevPlugin &&
      other.id == id &&
      other.directory.path == directory.path &&
      other.load == load &&
      other.problem == problem &&
      other.manifest?.version == manifest?.version &&
      other.replacedVersion == replacedVersion &&
      other.changedId == changedId &&
      listEquals(other.cases, cases);

  @override
  int get hashCode => Object.hash(
    id,
    directory.path,
    load,
    problem,
    manifest?.version,
    replacedVersion,
    changedId,
    Object.hashAll(cases),
  );
}

@immutable
final class DevFolderState {
  const DevFolderState({
    required this.folder,
    this.plugins = const [],
    this.problems = const [],
    this.busy = false,
  });

  final Directory folder;

  /// 依目錄名。
  final List<DevPlugin> plugins;

  /// 資料夾層級的問題（不存在、沒有插件目錄、id 重複）。
  final List<DevFolderProblem> problems;

  /// 套用或重新載入中。
  final bool busy;

  DevFolderState copyWith({
    List<DevPlugin>? plugins,
    List<DevFolderProblem>? problems,
    bool? busy,
  }) => DevFolderState(
    folder: folder,
    plugins: plugins ?? this.plugins,
    problems: problems ?? this.problems,
    busy: busy ?? this.busy,
  );

  @override
  bool operator ==(Object other) =>
      other is DevFolderState &&
      other.folder.path == folder.path &&
      other.busy == busy &&
      listEquals(other.plugins, plugins) &&
      listEquals(other.problems, problems);

  @override
  int get hashCode => Object.hash(
    folder.path,
    busy,
    Object.hashAll(plugins),
    Object.hashAll(problems),
  );
}

/// 資料夾層級的問題（design §3.6）。畫面依種類顯示翻譯過的字串；目錄名與 id 照原樣
/// 顯示（資料夾的路徑另外經遮蔽顯示）。
sealed class DevFolderProblem {
  const DevFolderProblem();
}

/// 資料夾不存在。
final class DevFolderMissing extends DevFolderProblem {
  const DevFolderMissing();

  @override
  bool operator ==(Object other) => other is DevFolderMissing;

  @override
  int get hashCode => (DevFolderMissing).hashCode;
}

/// 資料夾本身與子目錄都沒有 .js（沒有插件目錄）。
final class DevFolderEmpty extends DevFolderProblem {
  const DevFolderEmpty();

  @override
  bool operator ==(Object other) => other is DevFolderEmpty;

  @override
  int get hashCode => (DevFolderEmpty).hashCode;
}

/// 目錄 [second] 與 [first] 的 manifest id 都是 [id]：只載入 [first]（依目錄名排序在前）。
final class DevFolderDuplicateId extends DevFolderProblem {
  const DevFolderDuplicateId({
    required this.id,
    required this.first,
    required this.second,
  });

  final String id;
  final String first;
  final String second;

  @override
  bool operator ==(Object other) =>
      other is DevFolderDuplicateId &&
      other.id == id &&
      other.first == first &&
      other.second == second;

  @override
  int get hashCode => Object.hash(id, first, second);
}

/// 掃描出來的一個插件目錄（還沒載入）。訊息未遮蔽，只在 isolate 與掃描者之間傳。
final class ScannedPlugin {
  const ScannedPlugin({
    required this.id,
    required this.directory,
    this.file,
    this.problem,
    this.cases = const [],
  });

  final String id;
  final Directory directory;

  /// 讀不出安裝檔（不是剛好一個 .js、標頭或 manifest 有問題）時是 `null`。
  final PluginFile? file;
  final String? problem;
  final List<PluginCapability> cases;
}

final class DevScan {
  const DevScan({this.plugins = const [], this.problems = const []});

  final List<ScannedPlugin> plugins;
  final List<DevFolderProblem> problems;
}

/// 讀一個插件目錄成 [ScannedPlugin]。
ScannedPlugin scanPluginDirectory(Directory directory) {
  final folder = PluginFolder.read(directory);
  final file = folder.file;
  final name = p.basename(directory.path);
  if (file == null) {
    return ScannedPlugin(
      id: name,
      directory: directory,
      problem: folder.problems.join('; '),
    );
  }
  return ScannedPlugin(
    id: file.manifest.id,
    directory: directory,
    file: file,
    // 只有 checks.json 的問題會讓案例讀不出來；fixture 格式的問題在跑案例時才看。
    problem: [
      for (final problem in folder.problems)
        if (problem.startsWith('checks.json')) problem,
    ].firstOrNull,
    cases: [for (final check in folder.checks) check.capability],
  );
}

/// 掃描 [root]：每個插件目錄一筆（依目錄名）。同 id 的兩個目錄第一個留下，後面的記進
/// [DevScan.problems]。純函式，可在 isolate 裡跑。
DevScan scanDevFolder(Directory root) {
  if (!root.existsSync()) {
    return const DevScan(problems: [DevFolderMissing()]);
  }
  final directories = pluginDirectories(root);
  if (directories.isEmpty) {
    return const DevScan(problems: [DevFolderEmpty()]);
  }
  final plugins = <ScannedPlugin>[];
  final problems = <DevFolderProblem>[];
  final owners = <String, String>{};
  for (final directory in directories) {
    final scanned = scanPluginDirectory(directory);
    final name = p.basename(directory.path);
    if (scanned.file != null && owners.containsKey(scanned.id)) {
      problems.add(
        DevFolderDuplicateId(
          id: scanned.id,
          first: owners[scanned.id]!,
          second: name,
        ),
      );
      continue;
    }
    if (scanned.file != null) owners[scanned.id] = name;
    plugins.add(scanned);
  }
  return DevScan(plugins: plugins, problems: problems);
}
