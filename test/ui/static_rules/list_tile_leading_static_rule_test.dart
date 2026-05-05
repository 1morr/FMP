import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ListTile leading static rules', () {
    test('runtime UI ListTile leading values do not directly use Row', () {
      final offenders = <String>[];

      for (final entity in Directory('lib/ui').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }

        final source = entity.readAsStringSync();
        final matches = RegExp(r'ListTile\s*\([\s\S]*?leading:\s*Row\s*\(')
            .allMatches(source);
        if (matches.isNotEmpty) {
          offenders.add(entity.path);
        }
      }

      expect(offenders, isEmpty);
    });
  });
}
