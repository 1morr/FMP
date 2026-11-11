import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// repo 是公開的，不寫 Apple Team ID（`AGENTS.md`〈公開 repo〉）。
/// `flutter create` 與 Xcode 會自動把本機的 Team ID 寫進專案檔，
/// 簽名設定要放 gitignore 的本機檔。
final _teamId = RegExp(r'DEVELOPMENT_TEAM\s*=\s*"?[A-Z0-9]{10}"?\s*;');

List<String> findTeamIds(Map<String, String> files) => [
  for (final MapEntry(key: path, value: text) in files.entries)
    for (final (i, line) in text.split('\n').indexed)
      if (_teamId.hasMatch(line)) '$path:${i + 1}',
];

void main() {
  test('Apple project files carry no Team ID', () {
    final files = {
      for (final dir in ['ios', 'macos'])
        for (final f in Directory(dir).listSync(recursive: true))
          if (f is File &&
              (f.path.endsWith('.pbxproj') || f.path.endsWith('.xcconfig')))
            f.path: f.readAsStringSync(),
    };
    expect(files, isNotEmpty);
    expect(findTeamIds(files), isEmpty);
  });

  test('turns red on a Team ID, quoted or not', () {
    expect(findTeamIds({'a': '\t\tDEVELOPMENT_TEAM = ABCDE12345;'}), ['a:1']);
    expect(findTeamIds({'b': 'x\nDEVELOPMENT_TEAM = "ABCDE12345";'}), ['b:2']);
  });

  test('stays green on an empty or variable team', () {
    expect(
      findTeamIds({
        'a': 'DEVELOPMENT_TEAM = "";\nDEVELOPMENT_TEAM = \$(FMP_TEAM);',
        'b': 'CODE_SIGN_STYLE = Automatic;',
      }),
      isEmpty,
    );
  });
}
