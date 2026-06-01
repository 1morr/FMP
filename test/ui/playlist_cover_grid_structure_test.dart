import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'playlist grids use the shared cover map instead of per-card cover providers',
      () {
    final librarySource =
        File('lib/ui/pages/library/library_page.dart').readAsStringSync();
    final homeSource =
        File('lib/ui/pages/home/home_page.dart').readAsStringSync();
    final providerSource =
        File('lib/providers/library/playlist_provider.dart').readAsStringSync();

    expect(providerSource, contains('final playlistCoverMapProvider'));
    expect(librarySource, contains('playlistCoverMapProvider'));
    expect(homeSource, contains('playlistCoverMapProvider'));
    expect(_classBody(librarySource, '_PlaylistCard'),
        isNot(contains('playlistCoverProvider(')));
    expect(_classBody(librarySource, '_ReorderablePlaylistCard'),
        isNot(contains('playlistCoverProvider(')));
    expect(_classBody(homeSource, '_HomePlaylistCard'),
        isNot(contains('playlistCoverProvider(')));
  });
}

String _classBody(String source, String className) {
  final classIndex = source.indexOf('class $className');
  if (classIndex == -1) throw StateError('Class $className not found');
  final openBrace = source.indexOf('{', classIndex);
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) return source.substring(openBrace + 1, i);
  }
  throw StateError('Class $className body is not closed');
}
