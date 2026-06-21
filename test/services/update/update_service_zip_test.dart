import 'dart:io';

import 'package:crypto/crypto.dart';
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

  group('UpdateService asset integrity', () {
    test('parses sha256 manifest by release asset filename', () {
      final checksums = UpdateService.parseSha256ManifestForTest('''
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  fmp-v1.2.0-android-arm64-v8a.apk
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb *fmp-v1.2.0-windows.zip
not-a-valid-line
''');

      expect(
        checksums['fmp-v1.2.0-android-arm64-v8a.apk'],
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(
        checksums['fmp-v1.2.0-windows.zip'],
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      expect(checksums, hasLength(2));
    });

    test('validates downloaded asset size and sha256 before install', () async {
      final tempDir = await Directory.systemTemp.createTemp('fmp_update_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File('${tempDir.path}/asset.bin');
      final bytes = [1, 2, 3, 4, 5];
      await file.writeAsBytes(bytes);
      final digest = sha256.convert(bytes).toString();

      await UpdateService.validateDownloadedAssetForTest(
        file.path,
        expectedSize: bytes.length,
        expectedSha256: digest,
      );

      expect(
        () => UpdateService.validateDownloadedAssetForTest(
          file.path,
          expectedSize: bytes.length,
          expectedSha256:
              '0000000000000000000000000000000000000000000000000000000000000000',
        ),
        throwsA(isA<UpdateIntegrityException>()),
      );
    });

    test('rejects existing downloaded assets with a stale size', () async {
      final tempDir = await Directory.systemTemp.createTemp('fmp_update_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File('${tempDir.path}/asset.bin');
      await file.writeAsBytes([1, 2, 3]);

      expect(
        () => UpdateService.validateDownloadedAssetForTest(
          file.path,
          expectedSize: 4,
        ),
        throwsA(isA<UpdateIntegrityException>()),
      );
    });
  });

  group('UpdateService portable updater script', () {
    test('waits for the app process, backs up files, and avoids xcopy', () {
      final script = UpdateService.buildPortableUpdaterBatchForTest(
        extractDir: r'C:\Temp\fmp_update',
        appDir: r'C:\Apps\FMP',
        exeName: 'fmp.exe',
        vbsPath: r'C:\Temp\fmp_updater.vbs',
        appPid: 1234,
      );

      expect(script, contains('PID eq 1234'));
      expect(script, contains('fmp_update_backup'));
      expect(script, contains('robocopy'));
      expect(script.toLowerCase(), isNot(contains('xcopy')));
    });
  });
}
