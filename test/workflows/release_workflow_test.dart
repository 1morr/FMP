import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('release gate', () {
    test('the release publishes only what the verify job checked', () {
      final workflow = File('.github/workflows/release.yml').readAsStringSync();
      expect(releaseGateProblems(workflow), isEmpty);
    });

    // 下面用最小的 workflow 證明這條規則擋得住繞過 verify 的寫法，也不會被
    // needs 的寫法差異擋下。
    test('accepts any YAML spelling of needs', () {
      expect(releaseGateProblems(_gatedWorkflow()), isEmpty);
      expect(
        releaseGateProblems(
          _gatedWorkflow(
            verifyNeeds: '\n      - prepare\n      - build-a\n      - build-b',
            releaseNeeds: ' verify',
          ),
        ),
        isEmpty,
      );
    });

    test('rejects a release that skips the verify job', () {
      expect(
        releaseGateProblems(
          _gatedWorkflow(releaseNeeds: ' [prepare, build-a, build-b]'),
        ),
        ['release does not need verify'],
      );
    });

    test('rejects a verify job that runs before a build finishes', () {
      expect(
        releaseGateProblems(_gatedWorkflow(verifyNeeds: ' [prepare, build-a]')),
        ['verify does not need build-b'],
      );
    });

    test('rejects a release that uploads anything but the checked copy', () {
      expect(releaseGateProblems(_gatedWorkflow(files: 'artifacts/**/*')), [
        'release uploads artifacts/**/*, not release-assets/*',
      ]);
      expect(
        releaseGateProblems(
          _gatedWorkflow(downloaded: 'android-apk-universal'),
        ),
        ['release downloads android-apk-universal, not release-assets'],
      );
    });

    test('rejects a verify job that does not run the checks', () {
      expect(
        releaseGateProblems(_gatedWorkflow(verifyRun: 'ls release-assets')),
        ['verify does not run $_verifier'],
      );
    });
  });

  group('release workflow', () {
    test(
      'uses a generated multiline output delimiter for the release body',
      () {
        final workflow = File(
          '.github/workflows/release.yml',
        ).readAsStringSync();

        // 一個字面 EOF 分隔符會被 body 裡剛好等於 EOF 的一行截斷。
        expect(workflow, isNot(contains('<<EOF')));
        expect(workflow, contains('output_delimiter='));
        expect(workflow, contains(r'body<<$output_delimiter'));
      },
    );

    test('writes the body delimiter on its own line', () {
      final workflow = File('.github/workflows/release.yml').readAsStringSync();

      expect(workflow, contains(r'''printf '\n%s\n' "$output_delimiter"'''));
    });

    test('groups the generated body by conventional commit prefix', () {
      final workflow = File('.github/workflows/release.yml').readAsStringSync();

      // 沒有手寫檔那條路了 —— body 一定是從 commit 範圍算出來的。
      expect(workflow, isNot(contains('docs/release-notes/')));
      for (final section in const [
        "section 'Features'",
        "section 'Fixes'",
        "section 'Performance'",
        "section 'Dependencies'",
      ]) {
        expect(workflow, contains(section));
      }
      // 分組全空時要退回列出全部，否則純重構的版本會發出一份空 body。
      expect(workflow, contains(r'if [ "$matched" = 0 ]'));
      // grep 沒命中會回 1，而 GitHub 的 bash step 帶 -eo pipefail。
      expect(
        workflow,
        contains(r'{ grep -E "$pattern" commits.txt || true; }'),
      );
      // 合併 commit 的標題不是變更，列出來只會洗掉真正的條目。
      expect(workflow, contains('git log --no-merges'));
      // body 由 changelog step 完全擁有，標題不能再由 Create Release 前綴。
      expect(workflow, contains(r'body: ${{ steps.changelog.outputs.body }}'));
      expect(
        workflow,
        isNot(contains(r'${{ steps.changelog.outputs.commits }}')),
      );
    });

    test('derives app build number from semantic release tag', () {
      final workflow = File('.github/workflows/release.yml').readAsStringSync();

      expect(workflow, isNot(contains(r'+${{ github.run_number }}')));
      expect(workflow, contains(r'version_code=$((major * 1000000'));
      expect(
        workflow,
        contains(r'version_with_code="${version}+${version_code}"'),
      );
      expect(workflow, contains('version_with_code'));
    });
  });
}

const _verifier = 'tool/release/verify_release_assets.dart';

/// Release 對外之前的閘門（docs/adr/0006）：`verify` 等所有 build job 完成才跑
/// 檢查腳本，`release` 等 `verify` 通過才跑，而且只上傳 `verify` 檢查過、打包成
/// `release-assets` 的那一份。回傳違反的條目。
List<String> releaseGateProblems(String workflowYaml) {
  final jobs = (loadYaml(workflowYaml) as YamlMap)['jobs'] as YamlMap;
  YamlMap job(String name) => jobs[name] as YamlMap? ?? YamlMap();
  List<String> needs(String name) => switch (job(name)['needs']) {
    final String single => [single],
    final YamlList list => list.cast<String>(),
    _ => const [],
  };
  List<YamlMap> steps(String name) =>
      (job(name)['steps'] as YamlList? ?? YamlList()).cast<YamlMap>();
  YamlMap? stepUsing(String name, String action) => steps(
    name,
  ).where((step) => '${step['uses']}'.startsWith(action)).firstOrNull;
  Object? input(YamlMap? step, String key) => (step?['with'] as YamlMap?)?[key];

  final problems = <String>[];
  final builds = jobs.keys.cast<String>().where((j) => j.startsWith('build-'));
  for (final build in builds) {
    if (!needs('verify').contains(build)) {
      problems.add('verify does not need $build');
    }
  }
  if (!steps('verify').any((step) => '${step['run']}'.contains(_verifier))) {
    problems.add('verify does not run $_verifier');
  }
  final uploaded = input(
    stepUsing('verify', 'actions/upload-artifact'),
    'name',
  );
  if (uploaded != 'release-assets') {
    problems.add('verify uploads $uploaded, not release-assets');
  }

  if (!needs('release').contains('verify')) {
    problems.add('release does not need verify');
  }
  final downloaded = input(
    stepUsing('release', 'actions/download-artifact'),
    'name',
  );
  if (downloaded != 'release-assets') {
    problems.add('release downloads $downloaded, not release-assets');
  }
  final files =
      '${input(stepUsing('release', 'softprops/action-gh-release'), 'files')}'
          .trim();
  if (files != 'release-assets/*') {
    problems.add('release uploads $files, not release-assets/*');
  }
  return problems;
}

String _gatedWorkflow({
  String verifyNeeds = ' [prepare, build-a, build-b]',
  String verifyRun = 'dart run $_verifier release-assets v1.0.0 1000000',
  String releaseNeeds = ' [prepare, verify]',
  String downloaded = 'release-assets',
  String files = 'release-assets/*',
}) =>
    '''
jobs:
  prepare:
    runs-on: ubuntu-latest
  build-a:
    needs: prepare
  build-b:
    needs: [prepare]
  verify:
    needs:$verifyNeeds
    steps:
      - run: $verifyRun
      - uses: actions/upload-artifact@0000 # v7
        with:
          name: release-assets
  release:
    needs:$releaseNeeds
    steps:
      - uses: actions/download-artifact@0000 # v8
        with:
          name: $downloaded
      - uses: softprops/action-gh-release@0000 # v3
        with:
          files: $files
''';
