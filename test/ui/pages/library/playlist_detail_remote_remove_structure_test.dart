import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'imported playlist remote removals surface partial success before failure',
      () {
    final source = File('lib/ui/pages/library/playlist_detail_page.dart')
        .readAsStringSync();

    for (final methodName in [
      '_confirmAndBatchRemoveFromRemote',
      '_confirmAndRemoveFromRemote',
    ]) {
      final methodBody = _methodBody(source, methodName);
      final partialIndex =
          methodBody.indexOf('if (result.changedRemote && result.hasFailures)');
      final failureIndex = methodBody.indexOf('if (result.hasFailures)');

      expect(partialIndex, isNot(-1), reason: methodName);
      expect(failureIndex, isNot(-1), reason: methodName);
      expect(partialIndex, lessThan(failureIndex), reason: methodName);
      expect(methodBody, contains('ToastService.warning'), reason: methodName);
      expect(methodBody, contains('removedRemoteLocalSyncFailed'),
          reason: methodName);
    }
  });

  test('batch imported playlist partial removal exits selection mode', () {
    final source = File('lib/ui/pages/library/playlist_detail_page.dart')
        .readAsStringSync();
    final methodBody = _methodBody(source, '_confirmAndBatchRemoveFromRemote');
    final partialBranch =
        _ifBody(methodBody, 'if (result.changedRemote && result.hasFailures)');

    expect(partialBranch, contains('notifier.exitSelectionMode()'));
  });
}

String _methodBody(String source, String methodName) {
  final declaration = RegExp(
    r'Future<void>\s+' + RegExp.escape(methodName) + r'\s*\(',
  ).firstMatch(source);
  if (declaration == null) {
    throw StateError('Method $methodName not found');
  }

  final openBrace = source.indexOf('{', declaration.start);
  if (openBrace == -1) {
    throw StateError('Method $methodName has no body');
  }

  return _bodyFromOpenBrace(source, openBrace);
}

String _ifBody(String source, String condition) {
  final conditionIndex = source.indexOf(condition);
  if (conditionIndex == -1) {
    throw StateError('Condition $condition not found');
  }

  final openBrace = source.indexOf('{', conditionIndex);
  if (openBrace == -1) {
    throw StateError('Condition $condition has no body');
  }

  return _bodyFromOpenBrace(source, openBrace);
}

String _bodyFromOpenBrace(String source, int openBrace) {
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) {
      return source.substring(openBrace, i + 1);
    }
  }

  throw StateError('Body did not close');
}
