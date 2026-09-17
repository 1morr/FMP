import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dependabot 依版號位置分類，所以對 0.x 套件它把 `0.9 -> 0.10` 叫作 *minor*。
/// pub 不是這樣算的：`^0.9.40` 不接受 0.10，那是破壞性變更。
///
/// PR #59 就是這樣把五個破壞性升級包進一個叫「minor-and-patch」的 PR：
/// just_audio、audio_session、tray_manager、window_manager、inno_bundle ——
/// 音訊後端、系統匣、視窗管理與安裝檔打包。
///
/// `.github/dependabot.yml` 因此逐一排除仍在 0.x 的直接依賴。清單會隨著套件
/// 各自走到 1.0 而漂移，所以由這條規則守著：**新增一個 0.x 依賴卻忘了排除**
/// 會紅，而**排除了一個已經離開 0.x 的套件**也會紅。
///
/// 同一份設定還有一條 `ignore`：`flutter_secure_storage` 的大版本不交給
/// dependabot。11.x 拿掉了 10.x 從 9.x 遷移時用的舊 cipher，跳過 10.x 的安裝
/// 一升上去就丟登入（`lib/services/AGENTS.md`）。這裡守的是那條 ignore 還在。
void main() {
  group('dependabot grouping', () {
    late Set<String> zeroVersion;
    late Set<String> excluded;
    late Map<String, Set<String>> ignored;

    setUp(() {
      final config = File('.github/dependabot.yml').readAsStringSync();
      zeroVersion = zeroVersionDirectDependencies(
        File('pubspec.yaml').readAsStringSync(),
      );
      excluded = groupExcludePatterns(config);
      ignored = ignoredUpdateTypes(config);
    });

    test('flutter_secure_storage majors are kept away from dependabot', () {
      expect(
        ignored['flutter_secure_storage'],
        contains('version-update:semver-major'),
        reason:
            'a bump to flutter_secure_storage 11.x signs out every install '
            'that never ran a 10.x build; it is a release decision, not a PR '
            'dependabot may open',
      );
    });

    test('every 0.x direct dependency is excluded from the group', () {
      // 解析本身要有作用 —— 格式一變，兩個集合都會是空的。
      expect(zeroVersion, isNotEmpty);
      expect(
        zeroVersion.difference(excluded),
        isEmpty,
        reason:
            'a 0.x dependency would be grouped as minor; add it to '
            'exclude-patterns so its bump arrives as its own PR',
      );
    });

    test('no exclusion names a dependency that left 0.x', () {
      expect(
        excluded.difference(zeroVersion),
        isEmpty,
        reason:
            'this dependency is no longer 0.x (or no longer a dependency); '
            'drop it from exclude-patterns',
      );
    });

    test('the pubspec parser reads versions, not sdk or hosted entries', () {
      const pubspec = '''
environment:
  sdk: ^3.9.0

dependencies:
  flutter:
    sdk: flutter
  dio: ^5.9.2
  just_audio: ^0.9.40             # Android 音频后端
  isar_community:
    hosted: https://example.test

dev_dependencies:
  inno_bundle: ^0.11.2

flutter:
  uses-material-design: true
''';
      expect(zeroVersionDirectDependencies(pubspec), {
        'just_audio',
        'inno_bundle',
      });
    });

    test('the dependabot parser stops at the end of the list', () {
      const config = '''
    groups:
      pub-minor-and-patch:
        patterns: ['*']
        exclude-patterns:
          - 'just_audio'
          - 'tray_manager'
        update-types: ['minor', 'patch']
''';
      expect(groupExcludePatterns(config), {'just_audio', 'tray_manager'});
    });

    test('the ignore parser pairs each dependency with its update types', () {
      const config = '''
        update-types: ['minor', 'patch']
    # a comment mentioning dependency-name: 'not_this_one'
    ignore:
      - dependency-name: 'flutter_secure_storage'
        update-types: ['version-update:semver-major']
      - dependency-name: 'other'
        update-types: ['version-update:semver-major', 'version-update:semver-minor']
''';
      expect(ignoredUpdateTypes(config), {
        'flutter_secure_storage': {'version-update:semver-major'},
        'other': {'version-update:semver-major', 'version-update:semver-minor'},
      });
      expect(ignoredUpdateTypes('groups:\n  x:\n'), isEmpty);
    });
  });
}

/// `pubspec.yaml` 的 `dependencies:` / `dev_dependencies:` 裡版本仍在 0.x 的項目。
Set<String> zeroVersionDirectDependencies(String pubspec) {
  final names = <String>{};
  var inDependencies = false;

  for (final line in const LineSplitter().convert(pubspec)) {
    if (!line.startsWith(' ') && line.trim().isNotEmpty) {
      inDependencies =
          line.startsWith('dependencies:') ||
          line.startsWith('dev_dependencies:');
      continue;
    }
    if (!inDependencies) continue;

    final match = RegExp(r"^  ([a-z0-9_]+):\s*\^?(0\.\S*)").firstMatch(line);
    if (match != null) names.add(match.group(1)!);
  }
  return names;
}

/// `.github/dependabot.yml` 的 `exclude-patterns:` 清單。
Set<String> groupExcludePatterns(String config) {
  final names = <String>{};
  var inList = false;

  for (final line in const LineSplitter().convert(config)) {
    if (line.trimRight().endsWith('exclude-patterns:')) {
      inList = true;
      continue;
    }
    if (!inList) continue;

    final match = RegExp(r"^\s+- '([^']+)'\s*$").firstMatch(line);
    if (match == null) break;
    names.add(match.group(1)!);
  }
  return names;
}

/// `.github/dependabot.yml` 的 `ignore:` 清單：每個 `dependency-name` 對應的
/// `update-types`。註解行不算。
Map<String, Set<String>> ignoredUpdateTypes(String config) {
  final result = <String, Set<String>>{};
  String? current;

  for (final rawLine in const LineSplitter().convert(config)) {
    final line = rawLine.trim();
    if (line.startsWith('#')) continue;
    final name = RegExp(r"^- dependency-name:\s*'([^']+)'").firstMatch(line);
    if (name != null) {
      current = name.group(1)!;
      result.putIfAbsent(current, () => <String>{});
      continue;
    }
    final types = RegExp(r"^update-types:\s*\[(.*)\]").firstMatch(line);
    if (types != null && current != null) {
      result[current]!.addAll(
        RegExp(
          r"'([^']+)'",
        ).allMatches(types.group(1)!).map((m) => m.group(1)!),
      );
    }
  }
  return result;
}
