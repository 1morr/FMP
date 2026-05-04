import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('download path sync resolves scanned track identities in one batch', () {
    final source = File(
      'lib/services/download/download_path_sync_service.dart',
    ).readAsStringSync();
    final syncBody = _methodBody(source, 'syncLocalFiles');
    final scanBody = _methodBody(source, '_scanAndMatchFolder');

    expect(syncBody, contains('getBySourceIdentities('));
    expect(syncBody, contains('saveAll('));
    expect(scanBody, isNot(contains('_findMatchingTrack(')));
    expect(source, isNot(contains('Future<Track?> _findMatchingTrack')));
  });
}

String _methodBody(String source, String methodName) {
  final methodIndex = source.indexOf(' $methodName(');
  if (methodIndex == -1) {
    throw StateError('Method $methodName not found');
  }
  final bodyStart = source.indexOf(' async', methodIndex);
  final openBrace =
      source.indexOf('{', bodyStart == -1 ? methodIndex : bodyStart);
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) return source.substring(openBrace + 1, i);
  }
  throw StateError('Method $methodName body is not closed');
}
