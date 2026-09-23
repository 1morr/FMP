import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
    },
  );

  test(
    'source remote playlist dialogs surface partial success before success',
    () {
      final sharedSource = File(
        'lib/ui/widgets/dialogs/remote_playlist_dialog_widgets.dart',
      ).readAsStringSync();
      final reportBody = _functionBody(
        sharedSource,
        'void reportRemotePlaylistEditResult(',
      );
      final partialIndex = reportBody.indexOf(
        'result.changedRemote && result.hasFailures',
      );
      final successIndex = reportBody.indexOf('result.changedRemote)');

      expect(partialIndex, isNot(-1));
      expect(successIndex, isNot(-1));
      expect(partialIndex, lessThan(successIndex));
      expect(reportBody, contains('ToastService.warning'));
      expect(reportBody, contains('partiallyCompleted'));

      for (final path in [
        'lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart',
        'lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart',
        'lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart',
      ]) {
        final submitBody = _methodBody(
          File(path).readAsStringSync(),
          '_submit',
        );
        expect(
          submitBody,
          contains('reportRemotePlaylistEditResult('),
          reason: path,
        );
      }
    },
  );
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

/// 以宣告前綴定位頂層函式並取出本體；與 [_methodBody] 不同，
/// 會跳過參數列表中的 named-parameter 大括號。
String _functionBody(String source, String declarationPrefix) {
  final declIndex = source.indexOf(declarationPrefix);
  if (declIndex == -1) {
    throw StateError('Function $declarationPrefix not found');
  }

  final signatureEnd = source.indexOf(') {', declIndex);
  if (signatureEnd == -1) {
    throw StateError('Function $declarationPrefix has no body');
  }
  final openBrace = signatureEnd + 2;

  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) {
      return source.substring(openBrace + 1, i);
    }
  }

  throw StateError('Function $declarationPrefix body is not closed');
}
