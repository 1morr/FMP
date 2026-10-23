import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/startup_diagnostics.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:path/path.dart' as p;

import '../ui/support/plugin_page_harness.dart' show FakeFileDialogs;

// 啟動失敗時的「匯出診斷」（M5 design §3.1、§7.2）：一個 zip，有摘要與 log 檔，經遮蔽，
// 不含憑證與家目錄。值全是假的。

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fmp_startup_diagnostics');
    addTearDown(() => temp.delete(recursive: true));
  });

  Map<String, String> unzip(List<int> bytes) => {
    for (final file in ZipDecoder().decodeBytes(bytes))
      file.name: utf8.decode(file.content),
  };

  test(
    'exports the error, the step, the counts and the redacted log files',
    () async {
      final redactor = Redactor()..registerHomeDirectory(r'C:\Users\FAKE_USER');
      final logs = Directory(p.join(temp.path, 'logs'));
      final logFile = LogFile(logs)
        ..write('{"message":"opened C:\\\\Users\\\\FAKE_USER\\\\x"}');
      await logFile.flush();
      final dialogs = FakeFileDialogs();
      final diagnostics = StartupDiagnostics(
        flavor: AppFlavor.dev,
        redactor: redactor,
        logFile: logFile,
        fileDialogs: dialogs,
      );

      final saved = await withClock(
        Clock.fixed(DateTime(2026, 10, 23, 9, 8, 7)),
        () => diagnostics.export(
          kind: 'legacyImport',
          error: StateError(
            r'failed at C:\Users\FAKE_USER\fmp Cookie: SESSDATA=FAKE_SESSDATA_123',
          ),
          step: 'verify',
          details: summaryDiagnostics(
            const ImportSummary(
              collections: {
                'tracks': CollectionSummary(
                  read: 5,
                  written: 3,
                  skipped: {'danglingTrackId': 1, 'duplicateTrack': 1},
                ),
              },
            ),
          ),
        ),
      );

      expect(saved, isTrue);
      final save = dialogs.saves.single;
      expect(save.name, 'fmp-startup-diagnostics-20261023-090807.zip');
      expect(save.mimeType, 'application/zip');
      final files = unzip(save.bytes);
      expect(files.keys, containsAll(['diagnostics.txt', 'fmp.jsonl']));
      final text = files['diagnostics.txt']!;
      expect(text, contains('kind: legacyImport'));
      expect(text, contains('step: verify'));
      expect(text, contains('flavor: dev'));
      expect(text, contains('errorType: StateError'));
      expect(text, contains('  tracks:'));
      expect(text, contains('    read: 5'));
      expect(text, contains('    written: 3'));
      expect(text, contains('    skipped: 2'));
      for (final content in files.values) {
        expect(content, isNot(contains('FAKE_USER')));
        expect(content, isNot(contains('FAKE_SESSDATA_123')));
      }
    },
  );

  test(
    'a cancelled save reports false; no file dialogs means no export',
    () async {
      final dialogs = FakeFileDialogs()..saveResult = null;
      final diagnostics = StartupDiagnostics(
        flavor: AppFlavor.prod,
        redactor: Redactor(),
        logFile: null,
        fileDialogs: dialogs,
      );
      expect(diagnostics.canExport, isTrue);
      expect(
        await diagnostics.export(kind: 'databaseOpen', error: StateError('x')),
        isFalse,
      );
      // 沒有 log 檔也有摘要。
      expect(unzip(dialogs.saves.single.bytes).keys, ['diagnostics.txt']);

      expect(
        StartupDiagnostics(
          flavor: AppFlavor.prod,
          redactor: Redactor(),
          logFile: null,
          fileDialogs: null,
        ).canExport,
        isFalse,
      );
    },
  );
}
