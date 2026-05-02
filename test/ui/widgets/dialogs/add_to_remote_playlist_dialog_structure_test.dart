import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bilibili remote playlist dialog is split into its own file', () {
    final routerFile = File(
      'lib/ui/widgets/dialogs/add_to_remote_playlist_dialog.dart',
    );
    final bilibiliFile = File(
      'lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart',
    );

    expect(bilibiliFile.existsSync(), isTrue);

    final routerSource = routerFile.readAsStringSync();
    final bilibiliSource = bilibiliFile.readAsStringSync();

    expect(
      routerSource,
      contains("import 'add_to_bilibili_playlist_dialog.dart';"),
    );
    expect(routerSource, isNot(contains('class _BilibiliRemoteFavSheet')));
    expect(
      routerSource,
      contains('showAddToBilibiliPlaylistDialog('),
    );

    expect(
      bilibiliSource,
      contains('Future<bool> showAddToBilibiliPlaylistDialog'),
    );
    expect(bilibiliSource, contains('class _BilibiliRemoteFavSheet'));
  });
}
