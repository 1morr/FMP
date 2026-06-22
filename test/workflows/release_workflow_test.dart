import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('release workflow', () {
    test('uses a generated multiline output delimiter for changelog output',
        () {
      final workflow = File('.github/workflows/release.yml').readAsStringSync();

      expect(workflow, isNot(contains('commits<<EOF')));
      expect(workflow, contains('output_delimiter='));
      expect(workflow, contains(r'commits<<$output_delimiter'));
    });

    test('writes the changelog delimiter on its own line', () {
      final workflow = File('.github/workflows/release.yml').readAsStringSync();

      expect(workflow, contains(r'''printf '\n%s\n' "$output_delimiter"'''));
    });

    test('derives app build number from semantic release tag', () {
      final workflow = File('.github/workflows/release.yml').readAsStringSync();

      expect(workflow, isNot(contains(r'+${{ github.run_number }}')));
      expect(workflow, contains(r'version_code=$((major * 1000000'));
      expect(workflow, contains(r'version_with_code="${version}+${version_code}"'));
      expect(workflow, contains('version_with_code'));
    });
  });
}
