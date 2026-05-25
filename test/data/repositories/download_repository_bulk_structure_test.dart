import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadRepository bulk update structure', () {
    late String source;

    setUpAll(() {
      source = File('lib/data/repositories/download_repository.dart')
          .readAsStringSync();
    });

    test('bulk status methods write changed tasks with putAll', () {
      for (final methodName in [
        'resetDownloadingToPaused',
        'pauseAllTasks',
        'resumeAllTasks',
      ]) {
        final body = _methodBody(source, methodName);

        expect(
          body,
          contains('putAll(tasks)'),
          reason: '$methodName should batch persisted task updates.',
        );
        expect(
          body,
          isNot(contains('put(task)')),
          reason: '$methodName should not put each task inside the loop.',
        );
      }
    });
  });
}

String _methodBody(String source, String methodName) {
  final signature = 'Future<void> $methodName() async {';
  final start = source.indexOf(signature);
  if (start < 0) {
    throw StateError('Cannot find method $methodName');
  }

  var depth = 0;
  for (var i = start; i < source.length; i++) {
    final char = source.codeUnitAt(i);
    if (char == 123) {
      depth++;
    } else if (char == 125) {
      depth--;
      if (depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }

  throw StateError('Cannot find end of method $methodName');
}
