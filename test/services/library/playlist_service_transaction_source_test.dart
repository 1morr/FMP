import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaylistService transaction boundaries', () {
    final source =
        File('lib/services/library/playlist_service.dart').readAsStringSync();

    test('removeTrackFromPlaylist uses service-level Isar transaction', () {
      final body = _methodBody(source, 'removeTrackFromPlaylist');

      expect(body, contains('_isar.writeTxn'));
      expect(body, isNot(contains('_playlistRepository.removeTrack(')));
      expect(body, isNot(contains('_trackRepository.delete(')));
      expect(body, isNot(contains('_trackRepository.save(')));
    });

    test('removeTracksFromPlaylist uses service-level Isar transaction', () {
      final body = _methodBody(source, 'removeTracksFromPlaylist');

      expect(body, contains('_isar.writeTxn'));
      expect(body, isNot(contains('_playlistRepository.removeTracks(')));
      expect(body, isNot(contains('_trackRepository.deleteAll(')));
      expect(body, isNot(contains('_trackRepository.saveAll(')));
    });
  });
}

String _methodBody(String source, String name) {
  final start = source.indexOf('Future<void> $name');
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
