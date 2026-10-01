import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// `.github/workflows/app-release.yml` 的靜態規則（app/AGENTS.md § 發版）。
/// 每條規則先對真正的 workflow 跑，再以它的變異證明兩件事：造一個違規會紅，
/// 改一次無關的寫法不會紅。
void main() {
  final workflow = File('../.github/workflows/app-release.yml')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  String mutate(String from, String to) {
    expect(workflow, contains(from), reason: 'the mutation did not apply');
    return workflow.replaceFirst(from, to);
  }

  group('only workflow_dispatch triggers it', () {
    // 重寫期間不發版（M1 prd 擁有者決定 4）；M9 才加 push。
    test('the workflow', () {
      expect(triggerProblems(workflow), isEmpty);
    });

    test('red on another trigger', () {
      expect(
        triggerProblems(
          mutate(
            'on:\n  workflow_dispatch:\n',
            'on:\n  workflow_dispatch:\n  push:\n    branches: [main]\n',
          ),
        ),
        ['triggered by push'],
      );
      expect(
        triggerProblems(mutate('on:\n  workflow_dispatch:\n', 'on: [push]\n')),
        ['triggered by push', 'not triggered by workflow_dispatch'],
      );
    });

    test('not red on another spelling', () {
      for (final spelling in [
        'on: workflow_dispatch\n',
        'on: [workflow_dispatch]\n',
        'on:\n  workflow_dispatch: {}\n',
      ]) {
        expect(
          triggerProblems(mutate('on:\n  workflow_dispatch:\n', spelling)),
          isEmpty,
          reason: spelling,
        );
      }
    });
  });

  group('nothing runs without a new release', () {
    test('the workflow', () {
      expect(releaseGatedProblems(workflow), isEmpty);
    });

    const gate =
        "    if: needs.release-please.outputs.release_created == 'true'\n";

    test('red on a build job without the gate', () {
      expect(
        releaseGatedProblems(
          mutate('$gate    # 預裝 Inno Setup 6', '    # 預裝 Inno Setup 6'),
        ),
        ['build-windows can run without a new release'],
      );
    });

    test('red on a job that also runs when its needs were skipped', () {
      expect(
        releaseGatedProblems(
          mutate(
            '    name: Publish Release\n',
            '    name: Publish Release\n    if: always()\n',
          ),
        ),
        ['publish can run without a new release'],
      );
    });

    test('red on a gate that reads another output', () {
      expect(
        releaseGatedProblems(
          mutate(
            "    name: Build Android APKs\n    needs: release-please\n$gate",
            "    name: Build Android APKs\n    needs: release-please\n"
                "    if: needs.release-please.outputs.version != ''\n",
          ),
        ),
        ['build-android can run without a new release'],
      );
    });

    test('not red on another spelling of if and needs', () {
      final respelled =
          mutate(
            "    name: Build Android APKs\n    needs: release-please\n$gate",
            "    name: Build Android APKs\n    needs: [release-please]\n"
                "    if: \${{ needs.release-please.outputs.release_created=='true' }}\n",
          ).replaceFirst(
            '    needs: [release-please, verify]\n',
            '    needs:\n      - release-please\n      - verify\n',
          );
      expect(respelled, isNot(workflow));
      expect(releaseGatedProblems(respelled), isEmpty);
    });
  });

  group('every build is prod', () {
    test('the workflow', () {
      expect(flavorProblems(workflow), isEmpty);
    });

    test('red on a build without --flavor prod', () {
      expect(
        flavorProblems(
          mutate(
            'flutter build windows --flavor prod --release',
            'flutter build windows --release',
          ),
        ),
        [
          'flutter build windows --release --build-name \$env:VERSION '
              '--build-number \$env:VERSION_CODE does not use --flavor prod',
        ],
      );
      expect(
        flavorProblems(
          mutate(
            'flutter build apk --flavor prod --release',
            'flutter build apk --flavor dev --release',
          ),
        ),
        [
          'flutter build apk --flavor dev --release --build-name "\$VERSION" '
              '--build-number "\$VERSION_CODE" "\${platform[@]}" does not use '
              '--flavor prod',
        ],
      );
    });

    test('red when a platform is not built at all', () {
      expect(
        flavorProblems(
          mutate(
            'flutter build windows --flavor prod --release',
            'echo skipped',
          ),
        ),
        ['no flutter build windows'],
      );
    });

    test('not red on another spelling', () {
      final respelled =
          mutate(
                'flutter build windows --flavor prod --release',
                'flutter build windows --release --flavor=prod',
              )
              .replaceFirst(
                'flutter build apk --flavor prod --release \\\n              ',
                'flutter build apk --release ',
              )
              .replaceFirst(
                '"\${platform[@]}"\n',
                '"\${platform[@]}" --flavor prod\n',
              );
      expect(respelled, isNot(workflow));
      expect(flavorProblems(respelled), isEmpty);
    });
  });

  group('only verified assets are published', () {
    test('the workflow', () {
      expect(publishGateProblems(workflow), isEmpty);
    });

    test('red on a verify job that runs before a build finishes', () {
      expect(
        publishGateProblems(
          mutate(
            'needs: [release-please, build-android, build-windows]',
            'needs: [release-please, build-android]',
          ),
        ),
        ['verify does not need build-windows'],
      );
    });

    test('red on a publish job that skips verify', () {
      expect(
        publishGateProblems(
          mutate(
            '    needs: [release-please, verify]\n',
            '    needs: [release-please, build-android, build-windows]\n',
          ),
        ),
        ['publish does not need verify'],
      );
    });

    test('red on uploading anything but the verified copy', () {
      expect(
        publishGateProblems(
          mutate(
            'gh release upload "\$TAG" "\$RUNNER_TEMP"/release-assets/*',
            'gh release upload "\$TAG" "\$RUNNER_TEMP"/android-assets/*',
          ),
        ),
        ['publish does not upload the downloaded release-assets'],
      );
      expect(
        publishGateProblems(
          mutate(
            '          name: release-assets\n          path: \${{ runner.temp }}/release-assets\n',
            '          name: android\n          path: \${{ runner.temp }}/release-assets\n',
          ),
        ),
        ['publish downloads android, not release-assets'],
      );
    });

    test('red on a verify job that does not run the checks', () {
      expect(
        publishGateProblems(
          mutate('dart run tool/release/verify_release_assets.dart', 'ls'),
        ),
        ['verify does not run tool/release/verify_release_assets.dart'],
      );
    });

    test('red on another job that touches the release', () {
      expect(
        publishGateProblems(
          mutate(
            '            cp "fmp-\$TAG-\$suffix" "fmp-latest-\$suffix"\n',
            '            cp "fmp-\$TAG-\$suffix" "fmp-latest-\$suffix"\n'
                '            gh release upload "\$TAG" "fmp-latest-\$suffix"\n',
          ),
        ),
        ['verify runs gh release'],
      );
    });

    test('not red on another spelling', () {
      final respelled =
          mutate(
            'needs: [release-please, build-android, build-windows]',
            'needs:\n      - build-windows\n      - release-please\n'
                '      - build-android',
          ).replaceFirst(
            'gh release upload "\$TAG" "\$RUNNER_TEMP"/release-assets/* --clobber',
            'gh release upload --clobber "\$TAG" \${RUNNER_TEMP}/release-assets/*',
          );
      expect(respelled, isNot(workflow));
      expect(publishGateProblems(respelled), isEmpty);
    });
  });
}

YamlMap _jobs(String workflowYaml) =>
    (loadYaml(workflowYaml) as YamlMap)['jobs'] as YamlMap;

List<String> _needs(YamlMap job) => switch (job['needs']) {
  final String single => [single],
  final YamlList list => list.cast<String>(),
  _ => const [],
};

List<YamlMap> _steps(YamlMap job) =>
    (job['steps'] as YamlList? ?? YamlList()).cast<YamlMap>();

/// 觸發條件只能是 workflow_dispatch。
List<String> triggerProblems(String workflowYaml) {
  final on = (loadYaml(workflowYaml) as YamlMap)['on'];
  final events = switch (on) {
    final String single => [single],
    final YamlList list => list.cast<String>(),
    final YamlMap map => map.keys.cast<String>().toList(),
    _ => const <String>[],
  };
  return [
    for (final event in events)
      if (event != 'workflow_dispatch') 'triggered by $event',
    if (!events.contains('workflow_dispatch'))
      'not triggered by workflow_dispatch',
  ];
}

/// release-please 以外的每個 job，要嘛自己的 `if` 要求
/// `needs.release-please.outputs.release_created == 'true'`，要嘛依賴至少一個
/// 這樣的 job（依賴被跳過，自己也跳過）；而且 `if` 不以 `always()`、
/// `failure()`、`cancelled()` 蓋掉這條規則。
List<String> releaseGatedProblems(String workflowYaml) {
  final jobs = _jobs(workflowYaml);
  final gate = RegExp(
    r"needs\.release-please\.outputs\.release_created\s*==\s*'true'",
  );
  final statusOverride = RegExp(r'\b(always|failure|cancelled)\(\)');
  final gated = <String, bool>{};

  bool isGated(String name) {
    if (gated[name] case final known?) return known;
    gated[name] = false; // 依賴成環時不算
    final job = jobs[name] as YamlMap;
    final condition = '${job['if'] ?? ''}';
    final needs = _needs(job);
    final result =
        !statusOverride.hasMatch(condition) &&
        ((needs.contains('release-please') && gate.hasMatch(condition)) ||
            needs.any(isGated));
    return gated[name] = result;
  }

  return [
    for (final name in jobs.keys.cast<String>())
      if (name != 'release-please' && !isGated(name))
        '$name can run without a new release',
  ];
}

/// 每一個 `flutter build` 都帶 `--flavor prod`（ADR 0015 §決定 8），而且 apk 與
/// windows 都有建。
List<String> flavorProblems(String workflowYaml) {
  final problems = <String>[];
  final built = <String>{};
  for (final job in _jobs(workflowYaml).values.cast<YamlMap>()) {
    for (final step in _steps(job)) {
      final script = '${step['run'] ?? ''}'.replaceAll('\\\n', ' ');
      for (final match in RegExp(
        r'flutter build (\S+)[^\n;&|]*',
      ).allMatches(script)) {
        final command = match.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim();
        built.add(match.group(1)!);
        if (!RegExp(r'--flavor(=| )prod\b').hasMatch(command)) {
          problems.add('$command does not use --flavor prod');
        }
      }
    }
  }
  for (final target in ['apk', 'windows']) {
    if (!built.contains(target)) problems.add('no flutter build $target');
  }
  return problems;
}

const _verifier = 'tool/release/verify_release_assets.dart';

/// 草稿轉正式之前的閘門：`verify` 等所有 build job 完成才跑檢查腳本並上傳
/// `release-assets`；`publish` 等 `verify` 通過，只上傳下載到的
/// `release-assets`；其他 job 不碰 release（`gh release`）。
List<String> publishGateProblems(String workflowYaml) {
  final jobs = _jobs(workflowYaml);
  YamlMap job(String name) => jobs[name] as YamlMap? ?? YamlMap();
  YamlMap? stepUsing(String name, String action) =>
      _steps(job(name))
          .where((step) => '${step['uses']}'.startsWith(action))
          .firstOrNull;
  Object? input(YamlMap? step, String key) => (step?['with'] as YamlMap?)?[key];
  String scripts(String name) =>
      _steps(job(name)).map((step) => '${step['run'] ?? ''}').join('\n');

  final problems = <String>[];
  for (final build in jobs.keys.cast<String>().where(
    (name) => name.startsWith('build-'),
  )) {
    if (!_needs(job('verify')).contains(build)) {
      problems.add('verify does not need $build');
    }
  }
  if (!scripts('verify').contains(_verifier)) {
    problems.add('verify does not run $_verifier');
  }
  final uploaded = input(
    stepUsing('verify', 'actions/upload-artifact'),
    'name',
  );
  if (uploaded != 'release-assets') {
    problems.add('verify uploads $uploaded, not release-assets');
  }

  if (!_needs(job('publish')).contains('verify')) {
    problems.add('publish does not need verify');
  }
  final download = stepUsing('publish', 'actions/download-artifact');
  final downloaded = input(download, 'name');
  if (downloaded != 'release-assets') {
    problems.add('publish downloads $downloaded, not release-assets');
  }
  // 下載目錄 `${{ runner.temp }}/x` 在 shell 裡是 `$RUNNER_TEMP/x`。
  final directory = '${input(download, 'path')}'
      .replaceAll(RegExp(r'\$\{\{\s*runner\.temp\s*\}\}'), '')
      .replaceAll(RegExp(r'^/+'), '');
  final upload = RegExp(r'gh release upload\b[^\n]*')
      .firstMatch(scripts('publish'));
  final uploadsDownloaded =
      upload != null &&
      RegExp(
        r'''(\$\{?RUNNER_TEMP\}?"?)/''' + RegExp.escape(directory) + r'/\*',
      ).hasMatch(upload.group(0)!);
  if (!uploadsDownloaded) {
    problems.add('publish does not upload the downloaded release-assets');
  }
  for (final name in jobs.keys.cast<String>()) {
    if (name != 'publish' && scripts(name).contains('gh release')) {
      problems.add('$name runs gh release');
    }
  }
  return problems;
}
