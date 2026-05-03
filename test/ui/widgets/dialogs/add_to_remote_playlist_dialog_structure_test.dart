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

  test(
      'source remote playlist dialogs delegate submit orchestration to controller',
      () {
    for (final path in [
      'lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart',
      'lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart',
      'lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('remote_playlist_sync_provider.dart'));
      expect(source, contains('remotePlaylistEditControllerProvider'));
      final submitBody = _methodBody(source, '_submit');
      expect(submitBody, contains('.submitSelectionEdit('));
      expect(submitBody, isNot(contains('updateVideoFavorites(')));
      expect(submitBody, isNot(contains('addToPlaylist(')));
      expect(submitBody, isNot(contains('removeFromPlaylist(')));
      expect(submitBody, isNot(contains('addTracksToPlaylist(')));
      expect(submitBody, isNot(contains('removeTracksFromPlaylist(')));
    }
  });
}

String _methodBody(String source, String methodName) {
  final methodIndex = source.indexOf(' $methodName(');
  if (methodIndex == -1) {
    throw StateError('Method $methodName not found');
  }

  final openBrace = source.indexOf('{', methodIndex);
  if (openBrace == -1) {
    throw StateError('Method $methodName has no body');
  }

  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) {
      return source.substring(openBrace + 1, i);
    }
  }

  throw StateError('Method $methodName body is not closed');
}
