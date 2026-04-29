import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account management platform cards do not request auth playback buttons',
      () async {
    final source = await File(
      'lib/ui/pages/settings/account_management_page.dart',
    ).readAsString();
    final cardBlocks = RegExp(
      r'_PlatformCard\([\s\S]*?\n          \)',
      multiLine: true,
    )
        .allMatches(source)
        .map((match) => match.group(0)!)
        .where((block) => block.contains('platformName:'))
        .toList();

    expect(cardBlocks, hasLength(3));
    expect(source, isNot(contains('t.account.useAuth')));
    for (final block in cardBlocks) {
      expect(block, isNot(contains('useAuthForPlay')));
      expect(block, isNot(contains('authInteractive')));
      expect(block, isNot(contains('authTooltip')));
    }
  });
}
