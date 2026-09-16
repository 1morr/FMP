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
  group('plainTextReleaseNotes soft line breaks', () {
    // v1.10.2 的真實 body，逐字取自 `gh release view v1.10.2`。它以約 76 欄
    // 硬換行寫成 —— 逐行原樣輸出時手機會再折一次，就是 issue #145 的參差縮排。
    const body = '''
## FMP v1.10.2

Six days after v1.10.1. Anonymous Bilibili playback works again, covers are
sharp on every screen, and the account page finally tells an expired login
apart from no login. Two new settings ship with defaults that change
behaviour — read **Upgrading** below.

## What's Changed

### Features

- add an expired state to the platform card (633e1680)
- mark expired sessions instead of logging out (f936f5d5)
- check for updates once a day at startup (5ab060be)
- cap play history at a configurable row count (8b5eec17)

### Fixes

- warn portable builds about the startup path (be491609)
- show a failure screen when runApp never runs (ad01c84d)
- keep the once-a-second position poll out of the log (e1bf1712)
- stop retrying playback after an output device failure (e8cc8d8b)
- key lyrics auto-match on the resolved track (d994bd72)
- size cover tiers by physical source height (59b21879)
- rebuild nav labels when the locale loads after the first frame (9aab6282)
- query cid through wbi/view for anonymous playback (565ceb89)

### Dependencies

- bump audio_session from 0.1.25 to 0.2.4 (8ae84da2)
- bump slang in the pub-minor-and-patch group (8c643019)
- bump actions/setup-java in the github-actions group (3ebac654)

### Upgrading

- **Play history is now capped at 10,000 entries by default.** The first
  playback after upgrading deletes the oldest entries beyond the cap, and this
  cannot be undone. Raise the cap in Settings › Playback (up to 50,000) before
  playing if you want to keep more.
- FMP now checks for updates once a day, a few seconds after startup. Turn it
  off in Settings › About if you prefer manual checks.
- Cover thumbnails are fetched at new sizes, so covers are downloaded again
  once.
- Settings storage moved to schema v3 and the backup format to v5. Older
  builds ignore the new fields; a v5 backup file is rejected by older builds
  before the preview step, by design.

**Full Changelog**: https://github.com/1morr/FMP/compare/v1.10.1...v1.10.2


''';

    test('joins a wrapped list item into one line', () {
      final text = plainTextReleaseNotes(body);

      expect(
        text,
        contains(
          '• Play history is now capped at 10,000 entries by default. The first '
          'playback after upgrading deletes the oldest entries beyond the cap, '
          'and this cannot be undone. Raise the cap in Settings › Playback '
          '(up to 50,000) before playing if you want to keep more.',
        ),
      );
      // 續行接起來時只補一個空白，不是把原本的縮排留在句子中間。
      expect(text, isNot(contains('  ')));
    });

    test('joins a wrapped paragraph into one line', () {
      final lines = plainTextReleaseNotes(body).split('\n');

      expect(
        lines,
        contains(
          'Six days after v1.10.1. Anonymous Bilibili playback works again, '
          'covers are sharp on every screen, and the account page finally tells '
          'an expired login apart from no login. Two new settings ship with '
          'defaults that change behaviour — read Upgrading below.',
        ),
      );
    });

    test('keeps every heading on a line of its own', () {
      final lines = plainTextReleaseNotes(body).split('\n');

      // 整行相等才算「自成一行」—— 跟後面的段落或條列黏起來就對不上。
      expect(lines, contains('FMP v1.10.2'));
      expect(lines, contains("What's Changed"));
      expect(lines, contains('Features'));
      expect(lines, contains('Upgrading'));
    });

    test('leaves no markdown markers on screen', () {
      for (final line in plainTextReleaseNotes(body).split('\n')) {
        expect(line, isNot(contains('##')));
        expect(line, isNot(contains('**')));
        expect(line, isNot(contains('`')));
      }
    });

    test('separates consecutive list items by exactly one newline', () {
      final text = plainTextReleaseNotes(body);

      expect(
        text,
        contains(
          '• add an expired state to the platform card (633e1680)\n'
          '• mark expired sessions instead of logging out (f936f5d5)',
        ),
      );
      final lines = text.split('\n');
      for (var i = 1; i < lines.length - 1; i++) {
        if (lines[i].isNotEmpty) continue;
        expect(
          lines[i - 1].startsWith('• ') && lines[i + 1].startsWith('• '),
          isFalse,
          reason: 'a blank line split one list into two blocks at line $i',
        );
      }
    });

    test('does not join a heading with the paragraph after it', () {
      expect(plainTextReleaseNotes('## A\nbody text'), 'A\n\nbody text');
    });

    test('joins the lines of one paragraph with a single space', () {
      expect(
        plainTextReleaseNotes('one two\nthree   \n   four'),
        'one two three four',
      );
    });

    test('starts a new item on each bullet and folds its continuation', () {
      expect(
        plainTextReleaseNotes('- first item\n  wrapped on\n- second item'),
        '• first item wrapped on\n• second item',
      );
    });
  });
}
