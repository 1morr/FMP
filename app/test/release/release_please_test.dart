import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// release-please 的設定（repo 根的 `release-please-config.json`、
/// `.release-please-manifest.json`）與 `pubspec.yaml` 的版本（app/AGENTS.md
/// § 發版）。舊專案的 `pubspec_version_test` 比的是 tag；新 App 的版本只由
/// 發版 PR 同時改 pubspec 與 manifest，所以改成兩者相等（ADR 0022 §決定 1）。
void main() {
  final config = File('../release-please-config.json').readAsStringSync();
  final manifest = File('../.release-please-manifest.json').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('the committed files agree', () {
    expect(releaseConfigProblems(config, manifest, pubspec), isEmpty);
  });

  group('mutations', () {
    List<String> problems({String? c, String? m, String? p}) =>
        releaseConfigProblems(c ?? config, m ?? manifest, p ?? pubspec);

    String replaced(String source, Pattern from, String to) {
      final mutated = source.replaceFirst(from, to);
      expect(mutated, isNot(source), reason: 'the mutation did not apply');
      return mutated;
    }

    final versionLine = RegExp(r'^version: .*$', multiLine: true);

    test('a pubspec version that differs from the manifest', () {
      expect(problems(p: replaced(pubspec, versionLine, 'version: 9.9.9')), [
        'pubspec.yaml says 9.9.9, .release-please-manifest.json says '
            '${_manifestVersion(manifest)}',
      ]);
    });

    test('a build number or a comment on the version line', () {
      final version = _manifestVersion(manifest);
      for (final line in ['version: $version+1', 'version: $version # x']) {
        expect(problems(p: replaced(pubspec, versionLine, line)), [
          'pubspec.yaml: the version line must be exactly '
              '"version: MAJOR.MINOR.PATCH"',
        ], reason: line);
      }
    });

    test('unrelated pubspec edits do not matter', () {
      final edited = replaced(
        pubspec,
        'publish_to:',
        '# another comment\ndescription2: x\npublish_to:',
      );
      expect(problems(p: edited), isEmpty);
    });

    Map<String, Object?> json(String source) =>
        jsonDecode(source) as Map<String, Object?>;
    Map<String, Object?> appPackage(Map<String, Object?> c) =>
        (c['packages'] as Map<String, Object?>)['app'] as Map<String, Object?>;

    test('a release-as that is not above the manifest version', () {
      final c = json(config);
      appPackage(c)['release-as'] = _manifestVersion(manifest);
      expect(problems(c: jsonEncode(c)), [
        'release-as ${_manifestVersion(manifest)} is not above the manifest '
            'version ${_manifestVersion(manifest)}; remove it after the '
            'release it named',
      ]);
    });

    test('tags with a component, a non-draft release or another type', () {
      final c = json(config)
        ..['include-component-in-tag'] = true
        ..['draft'] = false;
      appPackage(c)['release-type'] = 'simple';
      expect(problems(c: jsonEncode(c)), [
        'include-component-in-tag must be false: tags are v{version}',
        'draft must be true: assets are uploaded before the release goes out',
        'packages.app.release-type must be dart',
      ]);
    });

    test('a draft without its tag or a tag without the v', () {
      final c = json(config)..['force-tag-creation'] = false;
      appPackage(c)['include-v-in-tag'] = false;
      expect(problems(c: jsonEncode(c)), [
        'include-v-in-tag must not be false: tags are v{version}',
        'force-tag-creation must be true: drafts get their tag now',
      ]);
    });

    test('another package path', () {
      final c = json(config);
      final packages = c['packages'] as Map<String, Object?>;
      packages['.'] = packages.remove('app');
      expect(problems(c: jsonEncode(c)), [
        'release-please must manage exactly the package app',
      ]);
    });

    test('key order and indentation do not matter', () {
      final c = json(config);
      final reordered = {
        for (final key in c.keys.toList().reversed) key: c[key],
      };
      expect(
        problems(
          c: const JsonEncoder.withIndent('    ').convert(reordered),
          m: jsonEncode(json(manifest)),
        ),
        isEmpty,
      );
    });
  });
}

String _manifestVersion(String manifest) =>
    (jsonDecode(manifest) as Map<String, Object?>)['app']! as String;

/// 回傳違反的條目。
List<String> releaseConfigProblems(
  String configJson,
  String manifestJson,
  String pubspecYaml,
) {
  final problems = <String>[];
  final config = jsonDecode(configJson) as Map<String, Object?>;
  final packages = config['packages'] as Map<String, Object?>? ?? const {};
  if (packages.length != 1 || !packages.containsKey('app')) {
    return ['release-please must manage exactly the package app'];
  }
  final app = packages['app']! as Map<String, Object?>;
  Object? option(String key) => app[key] ?? config[key];

  // 舊版更新器與 asset 檔名都假設 tag 是 v{版本}（ADR 0022 §決定 3、4）。
  if (option('include-component-in-tag') != false) {
    problems.add('include-component-in-tag must be false: tags are v{version}');
  }
  if (option('include-v-in-tag') == false) {
    problems.add('include-v-in-tag must not be false: tags are v{version}');
  }
  // 先建草稿、上傳完才轉正式（ADR 0022 §決定 1）；草稿的 tag 要馬上建，
  // release-please 下一次才找得到上一版。
  if (option('draft') != true) {
    problems.add(
      'draft must be true: assets are uploaded before the release goes out',
    );
  }
  if (option('force-tag-creation') != true) {
    problems.add('force-tag-creation must be true: drafts get their tag now');
  }
  if (app['release-type'] != 'dart') {
    problems.add('packages.app.release-type must be dart');
  }

  final manifest = jsonDecode(manifestJson) as Map<String, Object?>;
  final released = manifest['app'];
  if (released is! String || _parse(released) == null) {
    problems.add(
      '.release-please-manifest.json has no MAJOR.MINOR.PATCH for app',
    );
    return problems;
  }

  // release-please 的 PubspecYaml 以 `^version: ([0-9.]+)\+?(.*$)` 讀、整行改寫：
  // 數字的 build number 會被加 1（和 versionCode 的公式對不上），同一行的註解
  // 會變成 build number。
  final line = RegExp(
    r'^version:([^\r\n]*)',
    multiLine: true,
  ).firstMatch(pubspecYaml);
  final version = RegExp(r'^ (\d+\.\d+\.\d+)$')
      .firstMatch(line?.group(1) ?? '');
  if (version == null) {
    problems.add(
      'pubspec.yaml: the version line must be exactly '
      '"version: MAJOR.MINOR.PATCH"',
    );
  } else if (version.group(1) != released) {
    problems.add(
      'pubspec.yaml says ${version.group(1)}, .release-please-manifest.json '
      'says $released',
    );
  }

  // release-as 在它指定的版本發出之後還留著，下一個發版 PR 會再提同一個版本。
  final releaseAs = option('release-as');
  if (releaseAs is String && releaseAs.isNotEmpty) {
    final target = _parse(releaseAs);
    if (target == null || _compare(target, _parse(released)!) <= 0) {
      problems.add(
        'release-as $releaseAs is not above the manifest version $released; '
        'remove it after the release it named',
      );
    }
  }
  return problems;
}

List<int>? _parse(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}
