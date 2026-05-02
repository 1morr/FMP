import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaylistService transaction boundaries', () {
    final source =
        File('lib/services/library/playlist_service.dart').readAsStringSync();

    test('removeTrackFromPlaylist delegates to mutation service', () {
      final body = _methodBody(source, 'removeTrackFromPlaylist');

      expect(body, contains('_mutationService.removeTrack('));
      expect(body, isNot(contains('_isar.writeTxn')));
      expect(body, isNot(contains('_playlistRepository.removeTrack(')));
    });

    test('removeTracksFromPlaylist delegates to mutation service', () {
      final body = _methodBody(source, 'removeTracksFromPlaylist');

      expect(body, contains('_mutationService.removeTracks('));
      expect(body, isNot(contains('_isar.writeTxn')));
      expect(body, isNot(contains('_playlistRepository.removeTracks(')));
    });

    test('reorderPlaylistTracks delegates to mutation service', () {
      final body = _methodBody(source, 'reorderPlaylistTracks');

      expect(body, contains('_mutationService.reorderTracks('));
      expect(body, isNot(contains('_isar.writeTxn')));
    });

    test('duplicatePlaylist delegates to mutation service', () {
      final body = _methodBody(source, 'duplicatePlaylist');

      expect(body, contains('_mutationService.duplicatePlaylist('));
      expect(body, isNot(contains('_isar.writeTxn')));
    });
  });
}

String _methodBody(String source, String name) {
  final start = source.indexOf(RegExp('Future<[^>]+> $name'));
  expect(start, isNonNegative, reason: 'method $name should exist');
  final firstBrace = source.indexOf('{', start);
  var depth = 0;
  for (var i = firstBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) return source.substring(firstBrace, i + 1);
  }
  fail('method $name body did not close');
}
