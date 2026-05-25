import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/update/update_service.dart';

void main() {
  group('UpdateService ZIP extraction path safety', () {
    test('allows normal nested relative entries', () {
      final path = UpdateService.safeZipEntryDestinationForTest(
        r'C:\Temp\fmp_update',
        'FMP/data/app.dll',
      );

      expect(path.replaceAll('\\', '/'), endsWith('/FMP/data/app.dll'));
    });

    test('rejects parent traversal entries', () {
      expect(
        () => UpdateService.safeZipEntryDestinationForTest(
          r'C:\Temp\fmp_update',
          '../evil.txt',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects absolute slash entries', () {
      expect(
        () => UpdateService.safeZipEntryDestinationForTest(
          r'C:\Temp\fmp_update',
          '/evil.txt',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects Windows drive entries', () {
      expect(
        () => UpdateService.safeZipEntryDestinationForTest(
          r'C:\Temp\fmp_update',
          r'C:\evil.txt',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('portable ZIP extraction streams in a worker isolate', () {
      final source =
          File('lib/services/update/update_service.dart').readAsStringSync();

      expect(source, contains('Isolate.run('));
      expect(source, contains('InputFileStream(zipPath)'));
      expect(source, contains('ZipDecoder().decodeStream('));
      expect(source, contains('OutputFileStream(filePath)'));
      expect(source, contains('file.writeContent(output)'));
      expect(source, isNot(contains('readAsBytesSync()')));
      expect(source, isNot(contains('writeAsBytesSync(file.content')));
    });
  });
}
