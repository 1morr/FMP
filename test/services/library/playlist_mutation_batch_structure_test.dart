import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playlist mutation bulk paths resolve identities once per batch', () {
    final source = File(
      'lib/services/library/playlist_mutation_service.dart',
    ).readAsStringSync();
    final addTracksBody = _methodBody(source, 'addTracks');
    final refreshBody = _methodBody(source, 'replaceTracksFromRemoteRefresh');

    expect(source, contains('_findTracksByIdentity('));
    expect(addTracksBody, contains('final existingByIdentity ='));
    expect(refreshBody, contains('final existingByIdentity ='));
    expect(addTracksBody, isNot(contains('await _findTrackByIdentity')));
    expect(refreshBody, isNot(contains('await _findTrackByIdentity')));
    expect(source, isNot(contains('Future<Track?> _findTrackByIdentity')));
  });
}

String _methodBody(String source, String methodName) {
  final methodIndex = source.indexOf(' $methodName(');
  if (methodIndex == -1) {
    throw StateError('Method $methodName not found');
  }
  final openBrace = source.indexOf('{', methodIndex);
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) return source.substring(openBrace + 1, i);
  }
  throw StateError('Method $methodName body is not closed');
}
