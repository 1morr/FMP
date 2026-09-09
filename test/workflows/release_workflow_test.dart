import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
      // 產物與 body 都要人看過才對外，所以 release 建成草稿。
      expect(workflow, contains('draft: true'));
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
