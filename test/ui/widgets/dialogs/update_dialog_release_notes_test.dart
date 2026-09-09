import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/dialogs/update_dialog.dart';

void main() {
  group('plainTextReleaseNotes', () {
    // release.yml 產的形狀。這裡故意用整份 body 而不是逐條 case，
    // 因為要擋的是「使用者看到字面記號」，那是整份讀起來才看得出來的。
    const body = '''
## What's Changed

### Fixes

- put settings back in the navigation bar (72f3b6e1)
- make a concurrent `initialize` wait for the in-flight one (#81) (35c0e8f4)

### Dependencies

- bump just_audio from 0.9.46 to 0.10.6 (8ab8e693)

**Full Changelog**: https://github.com/1morr/FMP/compare/v1.10.0...v1.10.1
''';

    test('leaves no markdown markers on screen', () {
      final text = plainTextReleaseNotes(body);

      // `(#81)` 是 PR 編號不是標題記號，所以逐行看行首。
      for (final line in text.split('\n')) {
        expect(line, isNot(startsWith('#')));
        expect(line, isNot(startsWith('- ')));
      }
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('`')));
    });

    test('keeps every line of content', () {
      final text = plainTextReleaseNotes(body);

      expect(text, startsWith("What's Changed"));
      expect(text, contains('Fixes'));
      expect(text, contains('• put settings back in the navigation bar'));
      expect(text, contains('• make a concurrent initialize wait'));
      expect(text, contains('Dependencies'));
      expect(
        text,
        contains(
          'Full Changelog: https://github.com/1morr/FMP/compare/v1.10.0...v1.10.1',
        ),
      );
    });

    test('strips bold that opens on one line and closes on the next', () {
      // v1.10.0 的 Upgrading 段就是這個形狀，實機上 `**` 會留在畫面上。
      const wrapped =
          '- Because of that, **downgrading to v1.9.1 will\n'
          '  require signing in again.**';

      expect(plainTextReleaseNotes(wrapped), isNot(contains('*')));
    });

    test('collapses runs of blank lines and trims the tail', () {
      final text = plainTextReleaseNotes('a\n\n\n\nb\n\n\n');

      expect(text, 'a\n\nb');
    });

    test('handles CRLF and an empty body', () {
      expect(plainTextReleaseNotes('## A\r\n\r\n- b\r\n'), 'A\n\n• b');
      expect(plainTextReleaseNotes(''), '');
    });

    test('leaves a hyphen inside a sentence alone', () {
      expect(
        plainTextReleaseNotes('- fix a-b and c - d'),
        '• fix a-b and c - d',
      );
    });
  });
}
