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

    test('lets a hand-written notes file own the release body', () {
      final workflow = File('.github/workflows/release.yml').readAsStringSync();

      expect(
        workflow,
        contains(r'notes_file="docs/release-notes/${current_tag}.md"'),
      );
      expect(workflow, contains(r'if [ -f "$notes_file" ]'));
      // 手寫檔存在時它必須完全擁有 body，標題不能再由 Create Release 前綴。
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
