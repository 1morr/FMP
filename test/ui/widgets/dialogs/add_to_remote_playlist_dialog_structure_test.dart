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

  test('source remote playlist dialogs surface partial success before success',
      () {
    final sharedSource = File(
      'lib/ui/widgets/dialogs/remote_playlist_dialog_widgets.dart',
    ).readAsStringSync();
    final reportBody = _functionBody(
      sharedSource,
      'void reportRemotePlaylistEditResult(',
    );
    final partialIndex =
        reportBody.indexOf('result.changedRemote && result.hasFailures');
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
      final submitBody = _methodBody(File(path).readAsStringSync(), '_submit');
      expect(submitBody, contains('reportRemotePlaylistEditResult('),
          reason: path);
    }
  });

  test('source remote playlist dialogs reuse shared selection UI widgets', () {
    final sharedSource = File(
      'lib/ui/widgets/dialogs/remote_playlist_dialog_widgets.dart',
    ).readAsStringSync();

    expect(sharedSource, contains('class RemotePlaylistDialogHeader'));
    expect(sharedSource, contains('class RemotePlaylistTrackSummary'));
    expect(sharedSource, contains('class RemotePlaylistCreateTile'));
    expect(sharedSource, contains('class RemotePlaylistListTile'));
    expect(sharedSource, contains('class RemotePlaylistSelectionIndicator'));

    // The shared sheet shell composes the leaf widgets so individual dialogs
    // do not rebuild the header/summary/create-tile/list-tile scaffold.
    expect(sharedSource, contains('class RemotePlaylistSheetBody'));
    expect(sharedSource, contains('RemotePlaylistDialogHeader('));
    expect(sharedSource, contains('RemotePlaylistTrackSummary('));
    expect(sharedSource, contains('RemotePlaylistCreateTile('));
    expect(sharedSource, contains('class RemotePlaylistSelectionListView'));
    expect(sharedSource, contains('RemotePlaylistListTile('));

    for (final path in [
      'lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart',
      'lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart',
      'lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains("import 'remote_playlist_dialog_widgets.dart';"));
      expect(source, contains('RemotePlaylistSheetBody('), reason: path);
      expect(source, contains('RemotePlaylistSelectionListView<'), reason: path);
      expect(source, isNot(contains('ImageLoadingService.loadImage(')),
          reason: path);
      expect(source, isNot(contains('TrackThumbnail(')), reason: path);
    }
  });

  test('legacy remote action services are removed from providers and UI', () {
    final accountProvider =
        File('lib/providers/account/account_provider.dart').readAsStringSync();
    final syncProvider =
        File('lib/providers/library/remote_playlist_sync_provider.dart')
            .readAsStringSync();
    final detailPage = File('lib/ui/pages/library/playlist_detail_page.dart')
        .readAsStringSync();

    const actionsProvider = 'remotePlaylistActions' 'ServiceProvider';
    const removalSyncProvider = 'remotePlaylistRemoval' 'SyncServiceProvider';

    expect(accountProvider, isNot(contains(actionsProvider)));
    expect(syncProvider, isNot(contains(removalSyncProvider)));
    expect(detailPage, isNot(contains(actionsProvider)));
    expect(detailPage, isNot(contains(removalSyncProvider)));
    expect(
      File('lib/services/library/remote_playlist_actions_service.dart')
          .existsSync(),
      isFalse,
    );
    expect(
      File('lib/services/library/remote_playlist_removal_sync_service.dart')
          .existsSync(),
      isFalse,
    );
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
